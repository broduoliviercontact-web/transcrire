// Moteur de Transcrire : lance mlx_whisper, suit sa progression, découpe le résultat en phrases.
import AVFoundation
import Observation

struct Phrase: Identifiable, Hashable {
    let id: Int
    let debut: Double
    let fin: Double
    let texte: String
}

/// Fichier JSON écrit par mlx_whisper avec --word-timestamps True.
struct ResultatWhisper: Decodable {
    struct Segment: Decodable { let text: String; let start: Double; let end: Double; let words: [Mot]? }
    struct Mot: Decodable { let word: String; let start: Double; let end: Double }
    let segments: [Segment]
}

/// Whisper découpe en gros blocs : on regroupe ses mots horodatés phrase par phrase.
func regrouperEnPhrases(_ segments: [ResultatWhisper.Segment]) -> [Phrase] {
    var phrases: [Phrase] = []
    var mots: [ResultatWhisper.Mot] = []
    func clore() {
        let texte = mots.map(\.word).joined().trimmingCharacters(in: .whitespaces)
        if let premier = mots.first, let dernier = mots.last, !texte.isEmpty {
            phrases.append(Phrase(id: phrases.count, debut: premier.start, fin: dernier.end, texte: texte))
        }
        mots = []
    }
    for segment in segments {
        for mot in segment.words ?? [.init(word: segment.text, start: segment.start, end: segment.end)] {
            mots.append(mot)
            // ponytail: coupe à chaque . ? ! … — se trompe sur « M. Dupont », suffisant en pratique
            let nu = mot.word.trimmingCharacters(in: CharacterSet(charactersIn: " \"'»”)"))
            if let derniere = nu.last, ".?!…".contains(derniere) { clore() }
        }
    }
    clore()
    return phrases
}

/// Ligne affichée par mlx_whisper pendant le travail : "[01:23.400 --> 01:30.000]  Bonjour"
func lireBloc(_ ligne: String, id: Int) -> Phrase? {
    guard let m = ligne.wholeMatch(of: #/\[([\d:.]+) --> ([\d:.]+)\]\s*(.*)/#) else { return nil }
    return Phrase(id: id, debut: secondes(m.1), fin: secondes(m.2), texte: String(m.3))
}

func secondes(_ t: Substring) -> Double {
    t.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
}

/// 83.4 → "00:01:23" (ou "01:23" sans les heures)
func timecode(_ s: Double, heures: Bool = true) -> String {
    let t = Int(s)
    return heures ? String(format: "%02d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                  : String(format: "%02d:%02d", t / 60, t % 60)
}

/// 83.4 → "00:01:23,400" (format des sous-titres .srt)
func timecodeSRT(_ s: Double) -> String {
    let ms = Int((s * 1000).rounded())
    return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
}

enum FormatExport: String, CaseIterable, Identifiable {
    case timecodes = "Texte avec timecodes"
    case texte = "Texte seul"
    case srt = "Sous-titres (.srt)"
    var id: Self { self }

    func nomDeFichier(_ nom: String) -> String {
        switch self {
        case .timecodes: "\(nom) (transcription avec timecodes).txt"
        case .texte: "\(nom) (transcription).txt"
        case .srt: "\(nom).srt"
        }
    }

    func contenu(_ phrases: [Phrase]) -> String {
        switch self {
        case .timecodes: phrases.map { "[\(timecode($0.debut))] \($0.texte)" }.joined(separator: "\n")
        case .texte: phrases.map(\.texte).joined(separator: "\n")
        case .srt: phrases.enumerated().map { i, p in
            "\(i + 1)\n\(timecodeSRT(p.debut)) --> \(timecodeSRT(p.fin))\n\(p.texte)\n"
        }.joined(separator: "\n")
        }
    }
}

@MainActor @Observable
final class Transcription {
    enum Etat: Equatable { case aucune, preparation, progression, terminee, annulee, echec(String) }

    private(set) var etat = Etat.aucune
    private(set) var phrases: [Phrase] = []
    private(set) var dureeAudio: Double = 0
    private(set) var avance: Double = 0  // secondes d'audio déjà traitées
    private(set) var debut = Date.now
    private(set) var dureeTraitement: Double = 0
    private var processus: Process?

    static let moteur = URL(filePath: NSHomeDirectory() + "/.local/bin/mlx_whisper")

    var active: Bool { etat == .preparation || etat == .progression }
    var progression: Double { dureeAudio > 0 ? min(avance / dureeAudio, 1) : 0 }
    var restant: Double? {
        progression > 0.02 ? Date.now.timeIntervalSince(debut) / progression * (1 - progression) : nil
    }

    func lancer(_ fichier: URL, modele: String, langue: String?, vocabulaire: String) async {
        guard !active else { return }
        phrases = []
        avance = 0
        debut = .now
        etat = .preparation
        guard FileManager.default.fileExists(atPath: Self.moteur.path) else {
            etat = .echec("Moteur Whisper introuvable. Dans le Terminal : uv tool install mlx-whisper")
            return
        }
        dureeAudio = (try? await AVURLAsset(url: fichier).load(.duration).seconds) ?? 0

        let dossier = FileManager.default.temporaryDirectory.appending(path: "Transcrire-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            // Copie temporaire (instantanée sur APFS) : l'app a le droit de lire le fichier déposé,
            // mlx_whisper, lancé à part, pas forcément (Bureau, Documents, Téléchargements).
            let ext = fichier.pathExtension
            let copie = dossier.appending(path: ext.isEmpty ? "audio" : "audio.\(ext)")
            try FileManager.default.copyItem(at: fichier, to: copie)

            var arguments = [copie.path, "--model", modele, "--verbose", "True", "--word-timestamps", "True",
                             "-f", "json", "-o", dossier.path]
            if let langue { arguments += ["--language", langue] }
            if !vocabulaire.isEmpty { arguments += ["--initial-prompt", vocabulaire] }

            let p = Process()
            p.executableURL = Self.moteur
            p.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")  // ffmpeg
            env["PYTHONUNBUFFERED"] = "1"
            env["PYTHONIOENCODING"] = "utf-8"
            p.environment = env
            let tuyau = Pipe()
            p.standardOutput = tuyau
            p.standardError = tuyau
            try p.run()
            processus = p

            var derniereLigne = ""
            for try await ligne in tuyau.fileHandleForReading.bytes.lines {
                if let bloc = lireBloc(ligne, id: phrases.count) {
                    phrases.append(bloc)
                    avance = bloc.fin
                    etat = .progression
                } else if !ligne.trimmingCharacters(in: .whitespaces).isEmpty {
                    derniereLigne = ligne  // gardée pour expliquer une éventuelle erreur
                }
            }
            while p.isRunning { try await Task.sleep(for: .milliseconds(20)) }
            processus = nil
            guard etat != .annulee else { return }
            guard p.terminationStatus == 0 else { etat = .echec(derniereLigne); return }

            let json = try Data(contentsOf: dossier.appending(path: "audio.json"))
            phrases = regrouperEnPhrases(try JSONDecoder().decode(ResultatWhisper.self, from: json).segments)
            avance = dureeAudio
            dureeTraitement = Date.now.timeIntervalSince(debut)
            etat = .terminee
        } catch {
            processus = nil
            if etat != .annulee { etat = .echec(error.localizedDescription) }
        }
    }

    func annuler() {
        guard let processus else { return }
        etat = .annulee
        processus.terminate()
    }
}

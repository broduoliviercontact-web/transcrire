// Moteur de Transcrire : lance mlx_whisper, suit sa progression, découpe le résultat en phrases,
// et repère en parallèle qui parle (diarisation.py).
import AVFoundation
import Observation

struct Phrase: Identifiable, Hashable {
    let id: Int
    let debut: Double
    let fin: Double
    let texte: String
    var intervenant: Int? = nil
}

/// Tour de parole renvoyé par diarisation.py.
struct Tour: Decodable {
    let debut: Double
    let fin: Double
    let intervenant: Int
}

/// Chaque phrase revient à la personne qui y parle le plus longtemps (ou, à défaut, la plus proche).
/// Les intervenants sont renumérotés dans leur ordre d'apparition : « Intervenant 1 » parle en premier.
func attribuerIntervenants(_ phrases: [Phrase], _ tours: [Tour]) -> [Phrase] {
    guard !tours.isEmpty else { return phrases }
    var numeros: [Int: Int] = [:]
    return phrases.map { p in
        var duree: [Int: Double] = [:]
        for t in tours { duree[t.intervenant, default: 0] += max(0, min(p.fin, t.fin) - max(p.debut, t.debut)) }
        func ecart(_ t: Tour) -> Double { max(t.debut - p.fin, p.debut - t.fin, 0) }
        let brut = duree.filter { $0.value > 0 }.max { $0.value < $1.value }?.key
            ?? tours.min { ecart($0) < ecart($1) }!.intervenant
        if numeros[brut] == nil { numeros[brut] = numeros.count }
        var q = p
        q.intervenant = numeros[brut]
        return q
    }
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

    /// Les noms des intervenants n'apparaissent que s'il y en a au moins deux.
    func contenu(_ phrases: [Phrase], nom: (Int) -> String = { "Intervenant \($0 + 1)" }) -> String {
        let plusieurs = Set(phrases.compactMap(\.intervenant)).count > 1
        func etiquette(_ p: Phrase) -> String { plusieurs ? p.intervenant.map { nom($0) + " : " } ?? "" : "" }
        switch self {
        case .timecodes:
            return phrases.map { "[\(timecode($0.debut))] \(etiquette($0))\($0.texte)" }.joined(separator: "\n")
        case .texte:
            guard plusieurs else { return phrases.map(\.texte).joined(separator: "\n") }
            // un paragraphe par prise de parole
            var paragraphes: [(Phrase, [String])] = []
            for p in phrases {
                if let dernier = paragraphes.last, dernier.0.intervenant == p.intervenant {
                    paragraphes[paragraphes.count - 1].1.append(p.texte)
                } else {
                    paragraphes.append((p, [p.texte]))
                }
            }
            return paragraphes.map { etiquette($0.0) + $0.1.joined(separator: " ") }.joined(separator: "\n\n")
        case .srt:
            return phrases.enumerated().map { i, p in
                "\(i + 1)\n\(timecodeSRT(p.debut)) --> \(timecodeSRT(p.fin))\n\(etiquette(p))\(p.texte)\n"
            }.joined(separator: "\n")
        }
    }
}

@MainActor @Observable
final class Transcription {
    /// voix : Whisper a fini, on attend l'identification des personnes.
    enum Etat: Equatable { case aucune, preparation, progression, voix, terminee, annulee, echec(String) }

    private(set) var etat = Etat.aucune
    private(set) var phrases: [Phrase] = []
    private(set) var dureeAudio: Double = 0
    private(set) var avance: Double = 0  // secondes d'audio déjà traitées
    private(set) var progressionVoix: Double = 0
    private(set) var debut = Date.now
    private(set) var dureeTraitement: Double = 0
    private(set) var avertissement: String?
    var noms: [Int: String] = [:]  // noms donnés aux intervenants par l'utilisateur
    private var processus: [Process] = []

    static let moteur = URL(filePath: NSHomeDirectory() + "/.local/bin/mlx_whisper")
    static let uv = URL(filePath: NSHomeDirectory() + "/.local/bin/uv")

    var active: Bool { etat == .preparation || etat == .progression || etat == .voix }
    var progression: Double { dureeAudio > 0 ? min(avance / dureeAudio, 1) : 0 }
    var restant: Double? {
        progression > 0.02 ? Date.now.timeIntervalSince(debut) / progression * (1 - progression) : nil
    }
    /// Intervenants repérés (vide s'il n'y en a qu'un : inutile de l'afficher).
    var intervenants: [Int] {
        let ids = Set(phrases.compactMap(\.intervenant))
        return ids.count > 1 ? ids.sorted() : []
    }

    func nom(_ intervenant: Int) -> String {
        let nom = noms[intervenant]?.trimmingCharacters(in: .whitespaces) ?? ""
        return nom.isEmpty ? "Intervenant \(intervenant + 1)" : nom
    }

    /// nombreIntervenants : nil = détection automatique.
    func lancer(_ fichier: URL, modele: String, langue: String?, vocabulaire: String,
                identifier: Bool, nombreIntervenants: Int?) async {
        guard !active else { return }
        phrases = []
        noms = [:]
        avance = 0
        progressionVoix = 0
        avertissement = nil
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

            // Qui parle quand : sur le processeur, pendant que Whisper occupe la puce graphique.
            async let tours = identifier ? diariser(copie, nombre: nombreIntervenants) : []

            // --condition-on-previous-text False : sans ça, Whisper s'emballe et répète le même mot
            // des centaines de fois dès qu'il bute sur un silence ou une hésitation.
            var arguments = [copie.path, "--model", modele, "--verbose", "True", "--word-timestamps", "True",
                             "--condition-on-previous-text", "False", "-f", "json", "-o", dossier.path]
            if let langue { arguments += ["--language", langue] }
            if !vocabulaire.isEmpty { arguments += ["--initial-prompt", vocabulaire] }

            var derniereLigne = ""
            let code = try await executer(Self.moteur, arguments) { ligne in
                if let bloc = lireBloc(ligne, id: phrases.count) {
                    phrases.append(bloc)
                    avance = bloc.fin
                    etat = .progression
                } else if !ligne.trimmingCharacters(in: .whitespaces).isEmpty {
                    derniereLigne = ligne  // gardée pour expliquer une éventuelle erreur
                }
            }
            guard etat != .annulee else { return }
            guard code == 0 else {
                processus.forEach { $0.terminate() }
                etat = .echec(derniereLigne)
                return
            }

            let json = try Data(contentsOf: dossier.appending(path: "audio.json"))
            phrases = regrouperEnPhrases(try JSONDecoder().decode(ResultatWhisper.self, from: json).segments)
            avance = dureeAudio
            if identifier {
                etat = .voix
                let resultat = await tours
                guard etat != .annulee else { return }
                phrases = attribuerIntervenants(phrases, resultat)
            }
            dureeTraitement = Date.now.timeIntervalSince(debut)
            etat = .terminee
        } catch {
            processus.forEach { $0.terminate() }
            if etat != .annulee { etat = .echec(error.localizedDescription) }
        }
    }

    func annuler() {
        guard active else { return }
        etat = .annulee
        processus.forEach { $0.terminate() }
    }

    /// Lance diarisation.py (via uv, qui installe ses dépendances au premier usage).
    /// En cas de souci, la transcription reste utilisable : on prévient simplement.
    private func diariser(_ audio: URL, nombre: Int?) async -> [Tour] {
        guard let script = Bundle.main.url(forResource: "diarisation", withExtension: "py"),
              FileManager.default.fileExists(atPath: Self.uv.path) else {
            avertissement = "Identification des personnes indisponible : uv ou diarisation.py introuvable."
            return []
        }
        var arguments = ["run", "--quiet", "--script", script.path, audio.path]
        if let nombre { arguments.append(String(nombre)) }
        var tours: [Tour] = []
        var derniereLigne = ""
        let code = try? await executer(Self.uv, arguments) { ligne in
            if ligne.hasPrefix("PROGRESSION "), let p = Double(ligne.dropFirst(12)) {
                progressionVoix = p
            } else if let tour = try? JSONDecoder().decode(Tour.self, from: Data(ligne.utf8)) {
                tours.append(tour)
            } else if !ligne.trimmingCharacters(in: .whitespaces).isEmpty {
                derniereLigne = ligne
            }
        }
        guard code == 0 else {
            if etat != .annulee { avertissement = "Identification des personnes impossible. \(derniereLigne)" }
            return []
        }
        return tours
    }

    /// Lance un programme, transmet chaque ligne de sa sortie, renvoie son code de sortie.
    private func executer(_ programme: URL, _ arguments: [String], ligne: (String) -> Void) async throws -> Int32 {
        let p = Process()
        p.executableURL = programme
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
        processus.append(p)
        defer { processus.removeAll { $0 === p } }
        for try await l in tuyau.fileHandleForReading.bytes.lines { ligne(l) }
        while p.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        return p.terminationStatus
    }
}

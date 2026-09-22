// Interface de Transcrire (SwiftUI, macOS 26).
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

let violet = Color(red: 0.42, green: 0.33, blue: 0.96)  // même teinte que l'icône

let langues: [(code: String, nom: String)] = [
    ("auto", "Détection automatique"), ("fr", "Français"), ("en", "Anglais"), ("es", "Espagnol"),
    ("de", "Allemand"), ("it", "Italien"), ("pt", "Portugais"), ("nl", "Néerlandais"),
]

enum Qualite: String, CaseIterable, Identifiable {
    case rapide, precise
    var id: Self { self }
    var nom: String { self == .rapide ? "Rapide" : "Précise" }
    var modele: String {
        self == .rapide ? "mlx-community/whisper-large-v3-turbo" : "mlx-community/whisper-large-v3-mlx"
    }
    var detail: String {
        self == .rapide ? "Excellente dans la plupart des cas. Environ 1 min pour 10 min d'audio."
                        : "Un peu plus fidèle sur les enregistrements difficiles, 3 à 4 fois plus lente. Télécharge 3 Go au premier usage."
    }
}

func dureeLisible(_ s: Double) -> String {
    Duration.seconds(s).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
}

func dureeHorloge(_ s: Double) -> String {
    Duration.seconds(s.isFinite ? s : 0).formatted(.time(pattern: s >= 3600 ? .hourMinuteSecond : .minuteSecond))
}

// MARK: - App

@main
struct TranscrireApp: App {
    @NSApplicationDelegateAdaptor(Delegue.self) private var delegue

    var body: some Scene {
        Window("Transcrire", id: "transcrire") {
            FenetrePrincipale()
                .environment(Session.partagee)
                .tint(violet)
        }
        .defaultSize(width: 980, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir…") { Session.partagee.choisirFichier() }
                    .keyboardShortcut("o")
                    .disabled(Session.partagee.transcription.active)
            }
        }
    }
}

final class Delegue: NSObject, NSApplicationDelegate {
    /// Fichier glissé sur l'icône de l'app ou « Ouvrir avec > Transcrire »
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { if let url = urls.first { Session.partagee.ouvrir(url) } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Session.partagee.transcription.annuler() }
    }
}

// MARK: - État partagé

@MainActor @Observable
final class Session {
    static let partagee = Session()
    let transcription = Transcription()
    let lecteur = Lecteur()
    private(set) var fichier: URL?

    var nom: String { fichier?.deletingPathExtension().lastPathComponent ?? "" }

    func choisirFichier() {
        let panneau = NSOpenPanel()
        panneau.allowedContentTypes = [.audiovisualContent]
        panneau.message = "Choisis un fichier audio ou vidéo à retranscrire"
        panneau.prompt = "Transcrire"
        feuille(panneau) { if let url = panneau.url { self.ouvrir(url) } }
    }

    func ouvrir(_ url: URL) {
        guard !transcription.active else { return }
        fichier = url
        lecteur.charger(url)
        relancer()
    }

    func relancer() {
        guard let fichier, !transcription.active else { return }
        let reglages = UserDefaults.standard
        let qualite = Qualite(rawValue: reglages.string(forKey: "qualite") ?? "") ?? .rapide
        let langue = reglages.string(forKey: "langue") ?? "auto"
        let vocabulaire = reglages.string(forKey: "vocabulaire") ?? ""
        Task {
            await transcription.lancer(fichier, modele: qualite.modele,
                                       langue: langue == "auto" ? nil : langue, vocabulaire: vocabulaire)
        }
    }

    func exporter(_ format: FormatExport) {
        let panneau = NSSavePanel()
        panneau.nameFieldStringValue = format.nomDeFichier(nom)
        panneau.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panneau.allowedContentTypes = [format == .srt ? UTType(filenameExtension: "srt") ?? .plainText : .plainText]
        let texte = format.contenu(transcription.phrases)
        feuille(panneau) {
            guard let url = panneau.url else { return }
            do { try texte.write(to: url, atomically: true, encoding: .utf8) }
            catch { NSAlert(error: error).runModal() }
        }
    }

    func copier(_ texte: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texte, forType: .string)
    }

    /// Ouvre un panneau en feuille attachée à la fenêtre, comme les apps d'Apple.
    private func feuille(_ panneau: NSSavePanel, siOK: @escaping () -> Void) {
        guard let fenetre = NSApp.keyWindow ?? NSApp.windows.first else {
            if panneau.runModal() == .OK { siOK() }
            return
        }
        panneau.beginSheetModal(for: fenetre) { if $0 == .OK { siOK() } }
    }
}

@MainActor @Observable
final class Lecteur {
    private let player = AVPlayer()
    private(set) var temps: Double = 0
    private(set) var enLecture = false

    init() {
        player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.temps = t.seconds }
        }
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.enLecture = false
                self?.aller(à: 0, lire: false)
            }
        }
    }

    func charger(_ url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        temps = 0
        enLecture = false
    }

    func basculer() {
        enLecture ? player.pause() : player.play()
        enLecture.toggle()
    }

    func aller(à s: Double, lire: Bool = true) {
        player.seek(to: CMTime(seconds: s, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        temps = s
        if lire { player.play(); enLecture = true }
    }
}

// MARK: - Fenêtre

struct FenetrePrincipale: View {
    @Environment(Session.self) private var session
    @State private var reglagesVisibles = true
    @State private var survol = false

    var body: some View {
        let t = session.transcription
        Group {
            if session.fichier == nil { Accueil(survol: survol) } else { VueTranscription() }
        }
        .frame(minWidth: 560, minHeight: 440)
        .navigationTitle("Transcrire")
        .navigationSubtitle(session.fichier?.lastPathComponent ?? "")
        .inspector(isPresented: $reglagesVisibles) {
            Reglages().inspectorColumnWidth(min: 260, ideal: 290, max: 380)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Nouveau fichier", systemImage: "plus") { session.choisirFichier() }
                    .help("Transcrire un autre fichier (⌘O)")
                    .disabled(t.active)
                Menu("Exporter", systemImage: "square.and.arrow.up") {
                    ForEach(FormatExport.allCases) { f in Button(f.rawValue + "…") { session.exporter(f) } }
                    Divider()
                    Button("Copier tout le texte") { session.copier(FormatExport.texte.contenu(t.phrases)) }
                }
                .help("Enregistrer ou copier la transcription")
                .disabled(t.etat != .terminee)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Réglages", systemImage: "sidebar.trailing") { reglagesVisibles.toggle() }
                    .help("Afficher ou masquer les réglages")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !t.active else { return false }
            session.ouvrir(url)
            return true
        } isTargeted: { survol = $0 }
    }
}

// MARK: - Accueil

struct Accueil: View {
    @Environment(Session.self) private var session
    let survol: Bool

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(violet.gradient.opacity(survol ? 0.28 : 0.14))
                    .frame(width: 112, height: 112)
                Image(systemName: "waveform")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(violet.gradient)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: survol)
            }
            .scaleEffect(survol ? 1.08 : 1)
            .animation(.spring(duration: 0.35), value: survol)

            VStack(spacing: 8) {
                Text(survol ? "Lâche-le ici" : "Dépose un fichier audio ou vidéo")
                    .font(.title.weight(.semibold))
                    .contentTransition(.opacity)
                Text("Réunion, interview, mémo vocal, vidéo… Le texte apparaît au fil de l'eau, avec un timecode pour chaque phrase.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button("Choisir un fichier…") { session.choisirFichier() }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)

            Label("Gratuit, et tout reste sur ton Mac", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(violet.opacity(survol ? 0.06 : 0))
                .strokeBorder(survol ? AnyShapeStyle(violet) : AnyShapeStyle(.quaternary),
                              style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                .padding(24)
        }
        .animation(.easeOut(duration: 0.2), value: survol)
    }
}

// MARK: - Transcription

struct VueTranscription: View {
    @Environment(Session.self) private var session

    /// Phrase en cours de lecture, surlignée.
    private var active: Int? {
        let l = session.lecteur, t = session.transcription
        guard t.etat == .terminee, l.enLecture || l.temps > 0 else { return nil }
        return t.phrases.last { $0.debut <= l.temps + 0.05 }?.id
    }

    var body: some View {
        let t = session.transcription
        let heures = t.dureeAudio >= 3600
        ScrollViewReader { defilement in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    EnTete().id("haut")
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(t.phrases) { p in
                            LignePhrase(phrase: p, active: p.id == active, heures: heures, enDirect: t.active)
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 110)  // place pour la barre de lecture flottante
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { BarreLecture() }
            .onChange(of: active) { _, nouvelle in
                guard session.lecteur.enLecture, let nouvelle else { return }
                withAnimation(.easeInOut(duration: 0.4)) { defilement.scrollTo(nouvelle, anchor: .center) }
            }
            .onChange(of: t.phrases.count) {
                guard t.active, let derniere = t.phrases.last else { return }
                withAnimation { defilement.scrollTo(derniere.id, anchor: .bottom) }
            }
            .onChange(of: t.etat) { _, etat in
                if etat == .terminee { withAnimation { defilement.scrollTo("haut", anchor: .top) } }
            }
        }
    }
}

struct EnTete: View {
    @Environment(Session.self) private var session

    var body: some View {
        let t = session.transcription
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let fichier = session.fichier {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: fichier.path))
                        .resizable()
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.nom)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(sousTitre)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 12)
                if t.active {
                    Button("Annuler", systemImage: "xmark") { t.annuler() }
                        .buttonStyle(.glass)
                } else if t.etat == .annulee || isEchec {
                    Button("Relancer", systemImage: "arrow.clockwise") { session.relancer() }
                        .buttonStyle(.glass)
                }
            }

            switch t.etat {
            case .preparation:
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative)
                    Text("Préparation du modèle… Au tout premier usage, cela peut prendre quelques minutes.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            case .progression:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        ProgressView(value: t.progression)
                        Text(t.progression, format: .percent.precision(.fractionLength(0)))
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                            .contentTransition(.numericText())
                    }
                    Text(detailProgression)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .animation(.easeOut(duration: 0.4), value: t.progression)
            case .echec(let detail):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Impossible de retranscrire ce fichier. Est-ce bien un fichier audio ou vidéo ?",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    if !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            case .annulee:
                Label("Transcription annulée", systemImage: "stop.circle").foregroundStyle(.secondary)
            case .aucune, .terminee:
                EmptyView()
            }
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var isEchec: Bool { if case .echec = session.transcription.etat { true } else { false } }

    private var sousTitre: String {
        let t = session.transcription
        let duree = t.dureeAudio > 0 ? dureeHorloge(t.dureeAudio) : ""
        guard t.etat == .terminee else { return duree }
        return "\(duree) · \(t.phrases.count) phrases · transcrit en \(dureeLisible(t.dureeTraitement.rounded()))"
    }

    private var detailProgression: String {
        let t = session.transcription
        var texte = "\(dureeHorloge(t.avance)) sur \(dureeHorloge(t.dureeAudio))"
        if let restant = t.restant { texte += " · encore environ \(dureeLisible(max(restant.rounded(), 1)))" }
        return texte
    }
}

struct LignePhrase: View {
    @Environment(Session.self) private var session
    let phrase: Phrase
    let active: Bool
    let heures: Bool
    let enDirect: Bool
    @State private var survol = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(timecode(phrase.debut, heures: heures))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: heures ? 60 : 40, alignment: .leading)
            Text(phrase.texte)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(enDirect ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(fond, in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .onHover { survol = $0 }
        .onTapGesture { session.lecteur.aller(à: phrase.debut) }
        .help("Cliquer pour écouter ce passage")
        .contextMenu {
            Button("Écouter à partir d'ici", systemImage: "play") { session.lecteur.aller(à: phrase.debut) }
            Button("Copier la phrase", systemImage: "doc.on.doc") { session.copier(phrase.texte) }
            Button("Copier avec le timecode", systemImage: "clock") {
                session.copier("[\(timecode(phrase.debut))] \(phrase.texte)")
            }
        }
        .animation(.easeOut(duration: 0.15), value: active)
    }

    private var fond: Color {
        active ? violet.opacity(0.16) : survol ? Color.primary.opacity(0.05) : .clear
    }
}

struct BarreLecture: View {
    @Environment(Session.self) private var session

    var body: some View {
        let l = session.lecteur
        let duree = max(session.transcription.dureeAudio, 0.1)
        let largeurTemps: CGFloat = duree >= 3600 ? 58 : 40
        HStack(spacing: 12) {
            Button(l.enLecture ? "Pause" : "Lecture", systemImage: l.enLecture ? "pause.fill" : "play.fill") {
                l.basculer()
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .frame(width: 30, height: 30)
            .contentTransition(.symbolEffect(.replace))
            .buttonStyle(.plain)

            Text(dureeHorloge(l.temps))
                .frame(width: largeurTemps, alignment: .trailing)
            Slider(value: Binding(get: { min(l.temps, duree) }, set: { l.aller(à: $0, lire: false) }), in: 0...duree)
                .controlSize(.small)
            Text(dureeHorloge(duree))
                .frame(width: largeurTemps, alignment: .leading)
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: 600)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 18)
        .padding(.horizontal, 24)
    }
}

// MARK: - Réglages

struct Reglages: View {
    @Environment(Session.self) private var session
    @AppStorage("langue") private var langue = "auto"
    @AppStorage("qualite") private var qualite = Qualite.rapide
    @AppStorage("vocabulaire") private var vocabulaire = ""

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Langue", selection: $langue) {
                    ForEach(langues, id: \.code) { Text($0.nom).tag($0.code) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Qualité", selection: $qualite) {
                        ForEach(Qualite.allCases) { Text($0.nom).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(qualite.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                TextField("Mots à bien reconnaître", text: $vocabulaire,
                          prompt: Text("Mme Dubreuil, URSSAF, Villeurbanne…"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(3...6)
            } header: {
                Text("Vocabulaire")
            } footer: {
                Text("Facultatif. Noms propres, sigles ou jargon, pour que Whisper les écrive correctement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if session.fichier != nil {
                Section {
                    Button("Relancer avec ces réglages", systemImage: "arrow.clockwise") { session.relancer() }
                        .disabled(session.transcription.active)
                }
            }

            Section {
                Label("Whisper tourne sur ton Mac : aucun fichier n'est envoyé sur internet.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

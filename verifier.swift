// Vérification rapide du moteur (lancée par installer.sh avant de construire l'app).
@main
struct Verifier {
    static func main() {
        let mots = [" Oui.", " Bien", " sûr ?", " Il a dit « non. »", " Bon"].enumerated().map { i, w in
            ResultatWhisper.Mot(word: w, start: Double(i), end: Double(i) + 0.5)
        }
        let phrases = regrouperEnPhrases([.init(text: "", start: 0, end: 5, words: mots)])
        precondition(phrases.map(\.texte) == ["Oui.", "Bien sûr ?", "Il a dit « non. »", "Bon"], "\(phrases)")
        precondition(phrases[1].debut == 1 && phrases[1].fin == 2.5)

        let sansMots = regrouperEnPhrases([.init(text: " Bloc entier", start: 3, end: 4, words: nil)])
        precondition(sansMots.map(\.texte) == ["Bloc entier"])

        let bloc = lireBloc("[01:23.400 --> 1:01:30.000]  Bonjour", id: 7)
        precondition(bloc?.debut == 83.4 && bloc?.fin == 3690 && bloc?.texte == "Bonjour")
        precondition(lireBloc("Detected language: French", id: 0) == nil)

        precondition(timecode(3723.9) == "01:02:03" && timecode(83.4, heures: false) == "01:23")
        precondition(timecodeSRT(83.4) == "00:01:23,400")
        precondition(FormatExport.srt.contenu(phrases).hasPrefix("1\n00:00:00,000 --> 00:00:00,500\nOui.\n\n2\n"))
        print("Vérification du moteur : OK")
    }
}

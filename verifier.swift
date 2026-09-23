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

        // Intervenants : tours réels renvoyés par diarisation.py sur un dialogue à 3 voix (numéros bruts 5, 7, 9).
        let tours = [(0.03, 3.91, 5), (4.84, 10.27, 7), (10.93, 12.97, 5), (12.97, 13.68, 9), (14.61, 17.58, 9)]
            .map { Tour(debut: $0.0, fin: $0.1, intervenant: $0.2) }
        let dialogue = [(0.0, 4.2, "Bonjour."), (4.9, 10.2, "Merci."), (10.9, 14.0, "Et le budget ?"),
                        (14.6, 17.9, "Soixante pour cent."), (30, 31, "Au revoir.")]
            .enumerated().map { i, p in Phrase(id: i, debut: p.0, fin: p.1, texte: p.2) }
        let attribuees = attribuerIntervenants(dialogue, tours)
        // renumérotés dans l'ordre d'apparition ; la phrase 3 va à celui qui y parle le plus ;
        // la dernière, hors de tout tour, au plus proche
        precondition(attribuees.map(\.intervenant) == [0, 1, 0, 2, 2], "\(attribuees.map(\.intervenant))")
        precondition(attribuerIntervenants(dialogue, []).allSatisfy { $0.intervenant == nil })

        let noms = { (i: Int) in ["Jacques", "Amélie", "Paul"][i] }
        precondition(FormatExport.timecodes.contenu(attribuees, nom: noms)
            .hasPrefix("[00:00:00] Jacques : Bonjour.\n[00:00:04] Amélie : Merci.\n"))
        precondition(FormatExport.texte.contenu(attribuees, nom: noms)
            .hasSuffix("Jacques : Et le budget ?\n\nPaul : Soixante pour cent. Au revoir."))
        precondition(FormatExport.srt.contenu(attribuees, nom: noms).contains("\nAmélie : Merci.\n"))
        // un seul intervenant : pas d'étiquette
        let seul = dialogue.map { var p = $0; p.intervenant = 0; return p }
        precondition(FormatExport.texte.contenu(seul) == dialogue.map(\.texte).joined(separator: "\n"))
        print("Vérification du moteur : OK")
    }
}

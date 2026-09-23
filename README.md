# Transcrire

App macOS qui retranscrit des fichiers audio et vidéo en texte, gratuitement et 100 % en local,
avec [Whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper) optimisé pour les puces Apple.

![Transcrire](capture.png)

- un timecode par phrase ; un clic sur une phrase la fait écouter
- identification des personnes qui parlent (« Intervenant 1 », « Intervenant 2 »… renommables),
  avec [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) et les modèles pyannote / WeSpeaker
- barre de progression, texte affiché au fil de l'eau, annulation
- réglages : langue, qualité (rapide / précise), vocabulaire à bien reconnaître, nombre de personnes
- export : texte, texte avec timecodes, sous-titres `.srt` — avec le nom de chaque intervenant

## Installation

Une seule commande à coller dans le Terminal :

```bash
curl -fsSL https://raw.githubusercontent.com/broduoliviercontact-web/transcrire/main/install.sh | sh
```

Elle vérifie le Mac, installe ce qui manque (`ffmpeg`, `uv`, `mlx-whisper`), met le code dans
`~/Transcrire` et construit **Transcrire.app** sur le Bureau. Rien n'est demandé en administrateur.

Prérequis : Mac Apple Silicon sous macOS 26, [Homebrew](https://brew.sh) et les outils en ligne de
commande Xcode (`xcode-select --install`) — l'installateur prévient s'il en manque un.

Pour choisir les emplacements : `DOSSIER=~/code/transcrire DESTINATION=~/Applications/Transcrire.app`
devant la commande. Pour mettre à jour, relance la même commande.

À partir du code déjà cloné, `./installer.sh` suffit : il vérifie, compile et remplace l'app.

Au premier usage, le modèle Whisper (1,6 Go) et les outils d'identification des voix (≈ 60 Mo) se téléchargent.

## Fichiers

| Fichier | Rôle |
|---|---|
| `Transcrire.swift` | l'interface (SwiftUI) |
| `Moteur.swift` | lance `mlx_whisper` et `diarisation.py`, suit la progression, découpe en phrases, attribue chaque phrase à un intervenant |
| `diarisation.py` | repère qui parle quand (lancé via `uv`, qui installe ses dépendances tout seul) |
| `verifier.swift` | vérifications du moteur, lancées par `installer.sh` |
| `icone.swift` | dessine l'icône |
| `installer.sh` | vérifie, compile et assemble l'app — à relancer après chaque modification |

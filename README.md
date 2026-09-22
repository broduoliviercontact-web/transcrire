# Transcrire

App macOS qui retranscrit des fichiers audio et vidéo en texte, gratuitement et 100 % en local,
avec [Whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper) optimisé pour les puces Apple.

![Transcrire](capture.png)

- un timecode par phrase ; un clic sur une phrase la fait écouter
- barre de progression, texte affiché au fil de l'eau, annulation
- réglages : langue, qualité (rapide / précise), vocabulaire à bien reconnaître
- export : texte, texte avec timecodes, sous-titres `.srt`

## Installation

Prérequis : Mac Apple Silicon sous macOS 26, outils en ligne de commande Xcode (`xcode-select --install`).

```bash
brew install ffmpeg uv
uv tool install mlx-whisper
./installer.sh        # construit Transcrire.app sur le Bureau
```

Le modèle Whisper (1,6 Go) se télécharge au premier usage.

## Fichiers

| Fichier | Rôle |
|---|---|
| `Transcrire.swift` | l'interface (SwiftUI) |
| `Moteur.swift` | lance `mlx_whisper`, suit la progression, découpe en phrases |
| `verifier.swift` | vérifications du moteur, lancées par `installer.sh` |
| `icone.swift` | dessine l'icône |
| `installer.sh` | vérifie, compile et assemble l'app — à relancer après chaque modification |

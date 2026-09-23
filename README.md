# Transcrire

Une app macOS qui transforme tes enregistrements audio et vidéo en texte.
Gratuite, et **tout se passe sur ton Mac** : aucun fichier n'est envoyé sur internet.

![Transcrire](capture.png)

## Ce qu'elle fait

- **Transcrit** réunions, interviews, mémos vocaux, vidéos… dans une quarantaine de langues,
  avec [Whisper](https://github.com/openai/whisper) d'OpenAI, optimisé pour les puces Apple.
- **Repère qui parle** et regroupe le texte par personne. Tu peux renommer « Intervenant 1 » en
  « Marie », le nom suit partout.
- **Un timecode par phrase** : un clic sur une phrase joue l'enregistrement à cet instant précis.
- **Enregistre** le résultat en texte, en texte avec timecodes, ou en sous-titres `.srt`.
- Tu peux lui souffler du **vocabulaire** (noms propres, sigles, jargon) pour qu'elle l'écrive bien.

Compte environ **1 minute de traitement pour 10 minutes d'enregistrement**.

## Installation

Colle cette commande dans le Terminal, puis appuie sur Entrée :

```bash
curl -fsSL https://raw.githubusercontent.com/broduoliviercontact-web/transcrire/main/install.sh | sh
```

Elle installe les outils nécessaires, met le code dans `~/Transcrire` et pose **Transcrire.app**
sur ton Bureau. Aucun mot de passe administrateur n'est demandé. Pour mettre à jour plus tard,
relance exactement la même commande.

Il faut un **Mac à puce Apple** (M1 ou plus récent) sous **macOS 26**, ainsi que
[Homebrew](https://brew.sh) et les outils Xcode (`xcode-select --install`). L'installateur
vérifie tout ça et te dit précisément ce qui manque, le cas échéant.

Au premier fichier transcrit, l'app télécharge le modèle Whisper (1,6 Go) et les outils
d'identification des voix (~60 Mo). Ensuite, elle fonctionne même sans connexion internet.

## Utilisation

Ouvre l'app et dépose un fichier audio ou vidéo dessus (ou sur son icône). Le texte s'affiche au
fur et à mesure. À droite, tu choisis la langue, la qualité, le nombre de personnes qui parlent, et
tu renommes les intervenants. Le bouton **Télécharger** enregistre le résultat.

## Questions fréquentes

**Pourquoi une commande plutôt qu'un fichier à télécharger ?**
Parce que c'est plus simple pour toi, pas pour nous : l'app est compilée sur ton propre Mac, donc
macOS ne la bloque pas et il n'y a aucune alerte de sécurité à contourner. La commande installe
aussi les outils dont l'app a besoin, ce qu'un simple téléchargement ne ferait pas.

**Est-ce que mes enregistrements partent quelque part ?**
Non. Tout le traitement a lieu sur ton Mac. Les seuls téléchargements sont ceux des modèles, une
fois pour toutes, depuis Hugging Face et GitHub.

**Ça marche sur un Mac Intel ?**
Non : le moteur utilise les puces Apple Silicon.

**L'identification des personnes se trompe.**
Indique le nombre exact de personnes dans les réglages, à droite : c'est ce qui aide le plus.
Les voix proches et les passages où deux personnes parlent en même temps restent difficiles.

**Comment désinstaller ?**

```bash
rm -rf ~/Desktop/Transcrire.app ~/Transcrire ~/Library/Application\ Support/Transcrire
uv tool uninstall mlx-whisper
```

## Sous le capot

| Fichier | Rôle |
|---|---|
| `install.sh` | installation en une commande : prérequis, code, construction |
| `installer.sh` | vérifie, compile et assemble `Transcrire.app` |
| `Transcrire.swift` | l'interface (SwiftUI, macOS 26) |
| `Moteur.swift` | lance `mlx_whisper` et `diarisation.py`, suit la progression, découpe en phrases, attribue chaque phrase à un intervenant |
| `diarisation.py` | repère qui parle quand, avec [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (modèles pyannote et WeSpeaker), lancé par `uv` |
| `verifier.swift` | vérifications du moteur, lancées à chaque construction |
| `icone.swift` | dessine l'icône de l'app |

L'identification des voix tourne sur le processeur pendant que Whisper occupe la puce graphique :
les deux avancent en parallèle.

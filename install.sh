#!/bin/sh
# Installation de Transcrire en une commande :
#   curl -fsSL https://raw.githubusercontent.com/broduoliviercontact-web/transcrire/main/install.sh | sh
#
# Installe ce qui manque (ffmpeg, uv, mlx-whisper), récupère le code et construit l'app.
# Variables : DOSSIER (où mettre le code), DESTINATION (où mettre l'app).
set -e

DOSSIER=${DOSSIER:-"$HOME/Transcrire"}
DEPOT=https://github.com/broduoliviercontact-web/transcrire.git

echo "→ Vérification du Mac"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo "   Transcrire demande un Mac à puce Apple (M1 ou plus récent)." >&2
  exit 1
fi
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]; then
  echo "   Transcrire demande macOS 26 ou plus récent (ce Mac est en $(sw_vers -productVersion))." >&2
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "→ Outils de développement Apple manquants : une fenêtre d'installation va s'ouvrir."
  xcode-select --install || true
  echo "   Relance cette commande une fois l'installation terminée."
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "→ Homebrew est nécessaire. Installe-le depuis https://brew.sh puis relance cette commande." >&2
  exit 1
fi

echo "→ ffmpeg et uv"
for outil in ffmpeg uv; do
  command -v "$outil" >/dev/null 2>&1 || brew install "$outil"
done

echo "→ Moteur Whisper"
"$(command -v uv)" tool install mlx-whisper >/dev/null

echo "→ Code de Transcrire dans $DOSSIER"
if [ -f installer.sh ] && [ -f Transcrire.swift ]; then
  DOSSIER=$(pwd)  # déjà dans le dossier du projet
elif [ -d "$DOSSIER/.git" ]; then
  git -C "$DOSSIER" pull --quiet
else
  git clone --quiet --depth 1 "$DEPOT" "$DOSSIER"
fi

echo "→ Construction de l'app"
sh "$DOSSIER/installer.sh"

echo
echo "C'est prêt. Dépose un fichier audio ou vidéo sur l'app Transcrire."
echo "Au premier usage, elle télécharge le modèle Whisper (1,6 Go) et les outils"
echo "d'identification des voix (~60 Mo). Ensuite, tout fonctionne hors ligne."

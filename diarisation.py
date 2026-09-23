# /// script
# requires-python = ">=3.10"
# dependencies = ["sherpa-onnx>=1.12", "numpy"]
# ///
"""Qui parle quand ? Repère les intervenants d'un fichier audio, 100 % en local.

Usage (lancé par l'app) :  uv run --script diarisation.py <audio> [nombre de personnes]
Sortie : des lignes « PROGRESSION 0.42 », puis une ligne JSON par tour de parole :
         {"debut": 1.2, "fin": 4.8, "intervenant": 0}
"""
import json
import os
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

import numpy as np
import sherpa_onnx

MODELES = Path.home() / "Library/Application Support/Transcrire/modeles"
DEPOT = "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
SEGMENTATION = MODELES / "sherpa-onnx-pyannote-segmentation-3-0/model.onnx"  # où quelqu'un parle
EMPREINTE = MODELES / "wespeaker_en_voxceleb_resnet34_LM.onnx"  # à quoi ressemble chaque voix
SEUIL = 0.5  # ponytail: réglage du mode automatique ; plus haut = moins d'intervenants distincts


def telecharger(url, destination):
    """Téléchargement dans un fichier .part renommé à la fin : jamais de modèle à moitié écrit."""
    partiel = destination.with_name(destination.name + ".part")
    urllib.request.urlretrieve(url, partiel)
    partiel.rename(destination)


def installer_modeles():
    MODELES.mkdir(parents=True, exist_ok=True)
    if not SEGMENTATION.exists():
        archive = MODELES / "segmentation.tar.bz2"
        telecharger(DEPOT + "speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2", archive)
        with tarfile.open(archive) as t:
            t.extractall(MODELES, filter="data")
        archive.unlink()
    if not EMPREINTE.exists():
        telecharger(DEPOT + "speaker-recongition-models/" + EMPREINTE.name, EMPREINTE)  # sic : « recongition »


def charger_audio(chemin, frequence):
    """Décode n'importe quel audio/vidéo en mono 16 kHz avec ffmpeg."""
    brut = subprocess.run(
        ["ffmpeg", "-nostdin", "-loglevel", "error", "-i", chemin, "-f", "s16le", "-ac", "1", "-ar", str(frequence), "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(brut, np.int16).astype(np.float32) / 32768


def main():
    installer_modeles()
    nombre = int(sys.argv[2]) if len(sys.argv) > 2 else -1  # -1 : détection automatique
    fils = max(1, (os.cpu_count() or 2) // 2)
    config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(model=str(SEGMENTATION)),
            num_threads=fils),
        embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=str(EMPREINTE), num_threads=fils),
        clustering=sherpa_onnx.FastClusteringConfig(num_clusters=nombre, threshold=SEUIL),
        min_duration_on=0.3,
        min_duration_off=0.5,
    )
    if not config.validate():
        sys.exit("Configuration de la diarisation invalide")
    diarisation = sherpa_onnx.OfflineSpeakerDiarization(config)
    audio = charger_audio(sys.argv[1], diarisation.sample_rate)

    def progression(fait, total):
        print(f"PROGRESSION {fait / total:.3f}", flush=True)
        return 0  # 0 = continuer

    for tour in diarisation.process(audio, callback=progression).sort_by_start_time():
        print(json.dumps({"debut": round(tour.start, 2), "fin": round(tour.end, 2), "intervenant": tour.speaker}))


if __name__ == "__main__":
    main()

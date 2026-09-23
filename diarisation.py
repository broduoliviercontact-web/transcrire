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

# numpy et sherpa_onnx sont importés à l'intérieur des fonctions : le reste du fichier
# reste lisible par un Python nu (python3 -m doctest diarisation.py).

MODELES = Path.home() / "Library/Application Support/Transcrire/modeles"
DEPOT = "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
SEGMENTATION = MODELES / "sherpa-onnx-pyannote-segmentation-3-0/model.onnx"  # où quelqu'un parle
EMPREINTE = MODELES / "wespeaker_en_voxceleb_resnet34_LM.onnx"  # à quoi ressemble chaque voix
# Réglage du mode automatique : plus haut = moins d'intervenants distincts.
# 0.7153 est la valeur publiée par pyannote 3.1 pour ce modèle d'empreintes (WeSpeaker ResNet34).
# Ajustable sans recompiler :  TRANSCRIRE_SEUIL=0.8 uv run --script diarisation.py …
SEUIL = float(os.environ.get("TRANSCRIRE_SEUIL", 0.7153))
PLANCHER = 15  # secondes : en dessous, une « voix » est un mirage, on la rattache à sa voisine


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


def fusionner_les_mirages(tours, plancher=PLANCHER):
    """Une voix qui parle moins de `plancher` secondes en tout est presque toujours une erreur
    de regroupement : on rend ses tours à la voix d'à côté (vérifier : python3 -m doctest diarisation.py).

    >>> tours = [(0, 60, 1), (60, 63, 2), (63, 120, 1), (120, 180, 3)]
    >>> tours = [{"debut": d, "fin": f, "intervenant": i} for d, f, i in tours]
    >>> [t["intervenant"] for t in fusionner_les_mirages(tours, plancher=15)]
    [1, 1, 1, 3]
    """
    total = {}
    for t in tours:
        total[t["intervenant"]] = total.get(t["intervenant"], 0) + t["fin"] - t["debut"]
    gardees = {v for v, duree in total.items() if duree >= plancher} or set(total)
    for i, tour in enumerate(tours):
        if tour["intervenant"] in gardees:
            continue
        voisins = [t for t in tours[:i][::-1] + tours[i + 1:] if t["intervenant"] in gardees]
        if voisins:
            tour["intervenant"] = min(
                voisins, key=lambda v: max(v["debut"] - tour["fin"], tour["debut"] - v["fin"], 0)
            )["intervenant"]
    return tours


def charger_audio(chemin, frequence):
    """Décode n'importe quel audio/vidéo en mono 16 kHz avec ffmpeg."""
    import numpy as np

    brut = subprocess.run(
        ["ffmpeg", "-nostdin", "-loglevel", "error", "-i", chemin, "-f", "s16le", "-ac", "1", "-ar", str(frequence), "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(brut, np.int16).astype(np.float32) / 32768


def main():
    import sherpa_onnx

    installer_modeles()
    nombre = int(sys.argv[2]) if len(sys.argv) > 2 else -1  # -1 : détection automatique
    fils = max(2, (os.cpu_count() or 4) - 2)  # on laisse deux cœurs à Whisper
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

    tours = [{"debut": round(t.start, 2), "fin": round(t.end, 2), "intervenant": t.speaker}
             for t in diarisation.process(audio, callback=progression).sort_by_start_time()]
    for tour in fusionner_les_mirages(tours) if nombre < 2 else tours:
        print(json.dumps(tour))


if __name__ == "__main__":
    main()

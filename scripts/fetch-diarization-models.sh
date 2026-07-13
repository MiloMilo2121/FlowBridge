#!/usr/bin/env bash
# Stages the FluidAudio speaker-diarization CoreML models into the app
# bundle folder reference. Run once before building with speaker detection;
# the folder is git-ignored and `optional: true` in project.yml, so a build
# without it still works (LocalDiarizer reports unavailable).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/DiarizationModels"
BASE_URL="https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/main"

# Exactly the two compiled models DiarizerModels.load(local…:) expects.
MODELS=(pyannote_segmentation.mlmodelc wespeaker_v2.mlmodelc)
# Standard layout of a compiled .mlmodelc bundle on this HF repo.
FILES=(coremldata.bin model.mil metadata.json weights/weight.bin analytics/coremldata.bin)

rm -rf "$DEST_DIR"
for model in "${MODELS[@]}"; do
  for file in "${FILES[@]}"; do
    dest="$DEST_DIR/$model/$file"
    mkdir -p "$(dirname "$dest")"
    echo "Fetching $model/$file"
    curl -fsSL --retry 3 -o "$dest" "$BASE_URL/$model/$file"
  done
done

echo "Diarization models staged at $DEST_DIR"
du -sh "$DEST_DIR"/*

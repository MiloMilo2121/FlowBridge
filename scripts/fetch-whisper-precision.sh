#!/usr/bin/env bash
set -euo pipefail

# Stages the Precision model (Whisper large-v3-turbo, the compressed ~626MB
# variant — best multilingual/IT↔EN code-switching quality) for BUILD-TIME
# bundling into Resources/WhisperModels/PrecisionModel.
#
# This is a build-machine script. FlowBridge never downloads models at
# runtime: the offline guarantee stays intact — the Precision engine simply
# finds the folder in the bundle (or in Application Support if sideloaded).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$ROOT_DIR/.build/model-fetch"
ARGMAX_DIR="$WORK_DIR/argmax-oss-swift"
STAGING_DIR="$WORK_DIR/staging-precision"
DEST_DIR="$ROOT_DIR/Resources/WhisperModels/PrecisionModel"
SILENCE_FILE="$WORK_DIR/silence.wav"

rm -rf "$STAGING_DIR" "$DEST_DIR"
mkdir -p "$WORK_DIR" "$STAGING_DIR" "$DEST_DIR"

if [[ ! -d "$ARGMAX_DIR/.git" ]]; then
  git clone --depth 1 --branch v1.0.0 https://github.com/argmaxinc/argmax-oss-swift.git "$ARGMAX_DIR"
fi

python3 - <<PY
import struct
import wave
from pathlib import Path

path = Path("$SILENCE_FILE")
path.parent.mkdir(parents=True, exist_ok=True)
sample_rate = 16000
samples = int(sample_rate * 0.25)
with wave.open(str(path), "wb") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(sample_rate)
    for _ in range(samples):
        wav.writeframes(struct.pack("<h", 0))
PY

swift run --package-path "$ARGMAX_DIR" argmax-cli transcribe \
  --model large-v3-v20240930_626MB \
  --download-model-path "$STAGING_DIR/models" \
  --download-tokenizer-path "$STAGING_DIR/tokenizers" \
  --audio-path "$SILENCE_FILE" \
  --without-timestamps \
  --skip-special-tokens

MODEL_DIR="$(find "$STAGING_DIR" -type d -name 'openai_whisper-large-v3*626MB*' -print -quit)"
if [[ -z "$MODEL_DIR" ]]; then
  MODEL_DIR="$(find "$STAGING_DIR/models" -mindepth 1 -maxdepth 3 -type d -name 'openai_whisper-large-v3*' -print -quit)"
fi
TOKENIZER_JSON="$(find "$STAGING_DIR" -type f -name tokenizer.json -print -quit)"

if [[ -z "$MODEL_DIR" ]]; then
  echo "Could not locate the downloaded large-v3-turbo (626MB) model directory." >&2
  exit 1
fi

if [[ -z "$TOKENIZER_JSON" ]]; then
  echo "Could not locate downloaded tokenizer.json." >&2
  exit 1
fi

rsync -a "$MODEL_DIR"/ "$DEST_DIR"/
rsync -a "$(dirname "$TOKENIZER_JSON")"/ "$DEST_DIR"/

echo "Precision model (large-v3-turbo 626MB) staged at $DEST_DIR"
echo "Note: this adds ~626MB to the app bundle. Bundle it for personal/TestFlight"
echo "builds; for App Store distribution consider the sideload path instead."

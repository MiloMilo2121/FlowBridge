#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$ROOT_DIR/.build/model-fetch"
ARGMAX_DIR="$WORK_DIR/argmax-oss-swift"
STAGING_DIR="$WORK_DIR/staging"
DEST_DIR="$ROOT_DIR/Resources/WhisperModels/WhisperSmall"
SILENCE_FILE="$WORK_DIR/silence.wav"

rm -rf "$STAGING_DIR" "$DEST_DIR"
mkdir -p "$WORK_DIR" "$STAGING_DIR" "$DEST_DIR"

if [[ ! -d "$ARGMAX_DIR/.git" ]]; then
  git clone --depth 1 --branch v1.0.0 https://github.com/argmaxinc/argmax-oss-swift.git "$ARGMAX_DIR"
fi

python3 - <<PY
import math
import struct
import wave
from pathlib import Path

path = Path("$SILENCE_FILE")
path.parent.mkdir(parents=True, exist_ok=True)
sample_rate = 16000
duration_seconds = 0.25
samples = int(sample_rate * duration_seconds)
with wave.open(str(path), "wb") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(sample_rate)
    for _ in range(samples):
        wav.writeframes(struct.pack("<h", 0))
PY

swift run --package-path "$ARGMAX_DIR" argmax-cli transcribe \
  --model small \
  --download-model-path "$STAGING_DIR/models" \
  --download-tokenizer-path "$STAGING_DIR/tokenizers" \
  --audio-path "$SILENCE_FILE" \
  --without-timestamps \
  --skip-special-tokens

MODEL_DIR="$(find "$STAGING_DIR" -type d -name 'openai_whisper-small*' -print -quit)"
TOKENIZER_JSON="$(find "$STAGING_DIR" -type f -name tokenizer.json -print -quit)"

if [[ -z "$MODEL_DIR" ]]; then
  echo "Could not locate downloaded openai_whisper-small model directory." >&2
  exit 1
fi

if [[ -z "$TOKENIZER_JSON" ]]; then
  echo "Could not locate downloaded tokenizer.json." >&2
  exit 1
fi

rsync -a "$MODEL_DIR"/ "$DEST_DIR"/
rsync -a "$(dirname "$TOKENIZER_JSON")"/ "$DEST_DIR"/

echo "Whisper Small staged at $DEST_DIR"


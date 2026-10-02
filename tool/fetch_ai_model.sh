#!/usr/bin/env bash
set -euo pipefail

MODEL_URL="https://github.com/MustafaBeratYavas/Plant-Disease-Edge-AI-Diagnosis-System/raw/refs/heads/main/mobile/assets/models/best_model_quantized.tflite"
OUT="assets/models/plant_disease_mobilenetv3.tflite"
mkdir -p "$(dirname "$OUT")"
echo "Downloading offline PlantVillage MobileNetV3 TFLite model..."
curl -fL --retry 4 --retry-delay 2 "$MODEL_URL" -o "$OUT"
SIZE=$(wc -c < "$OUT" | tr -d ' ')
if [ "$SIZE" -lt 2500000 ]; then
  echo "Model download looks too small: ${SIZE} bytes" >&2
  exit 1
fi
python3 - <<'PY2'
from pathlib import Path
p = Path("assets/models/plant_disease_mobilenetv3.tflite")
b = p.read_bytes()[:8]
if len(b) < 8 or b[4:8] != b"TFL3":
    raise SystemExit("Downloaded file is not a valid TFLite flatbuffer")
print("TFLite signature verified")
PY2
echo "Model ready: $OUT (${SIZE} bytes)"

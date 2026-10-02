$ErrorActionPreference = 'Stop'
$ModelUrl = 'https://github.com/MustafaBeratYavas/Plant-Disease-Edge-AI-Diagnosis-System/raw/refs/heads/main/mobile/assets/models/best_model_quantized.tflite'
$Out = 'assets/models/plant_disease_mobilenetv3.tflite'
New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
Write-Host 'Downloading offline PlantVillage MobileNetV3 TFLite model...'
Invoke-WebRequest -Uri $ModelUrl -OutFile $Out
$size = (Get-Item $Out).Length
if ($size -lt 2500000) { throw "Model download looks too small: $size bytes" }
$bytes = [System.IO.File]::ReadAllBytes($Out)
$magic = [System.Text.Encoding]::ASCII.GetString($bytes, 4, 4)
if ($magic -ne 'TFL3') { throw 'Downloaded file is not a valid TFLite flatbuffer' }
Write-Host "Model ready: $Out ($size bytes)"

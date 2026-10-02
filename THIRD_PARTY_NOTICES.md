# Third-party AI model

Leaf AI uses the MobileNetV3 PlantVillage TensorFlow Lite artifact from:

MustafaBeratYavas/Plant-Disease-Edge-AI-Diagnosis-System

The upstream repository is published under the MIT License. The model is trained for 38 PlantVillage classes across 14 crop species. The model artifact is downloaded during the Android CI build by `tool/fetch_ai_model.sh` so the resulting APK/AAB contains the model and performs inference fully offline.

PlantVillage-based predictions are screening support only and can be less reliable on field images, unsupported crops, mixed diseases, blur, unusual lighting, or backgrounds.

import 'package:agro_connect/ai/plant_knowledge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Leaf AI supports five offline languages', () {
    expect(LeafLanguage.values.length, 5);
    for (final language in LeafLanguage.values) {
      expect(language.nativeName, isNotEmpty);
      expect(LeafText.ui(language, 'treatment'), isNotEmpty);
    }
  });

  test('PlantVillage labels map to localized advice', () {
    for (final language in LeafLanguage.values) {
      final advice = PlantKnowledge.forLabel(
        'Tomato___Early_blight',
        language,
      );
      expect(advice.crop, isNotEmpty);
      expect(advice.condition, isNotEmpty);
      expect(advice.treatment, isNotEmpty);
      expect(advice.prevention, isNotEmpty);
    }
  });

  test('Healthy labels use healthy guidance', () {
    final advice = PlantKnowledge.forLabel(
      'Potato___healthy',
      LeafLanguage.english,
    );
    expect(advice.condition.toLowerCase(), contains('healthy'));
  });
}

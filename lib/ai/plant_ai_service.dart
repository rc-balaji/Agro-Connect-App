import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class PlantPrediction {
  const PlantPrediction({
    required this.label,
    required this.confidence,
    required this.topResults,
  });

  final String label;
  final double confidence;
  final List<PlantScore> topResults;
}

class PlantScore {
  const PlantScore({required this.label, required this.score});

  final String label;
  final double score;
}

class PlantAiService {
  static const String modelAsset =
      'assets/models/plant_disease_mobilenetv3.tflite';
  static const String labelsAsset = 'assets/models/labels.txt';

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  List<String> _labels = const [];
  bool _ready = false;

  bool get isReady => _ready;
  List<String> get labels => List.unmodifiable(_labels);

  Future<void> initialize() async {
    if (_ready) return;

    final labelsRaw = await rootBundle.loadString(labelsAsset);
    _labels = labelsRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    if (_labels.length != 38) {
      throw StateError('Leaf AI label contract expected 38 classes.');
    }

    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(modelAsset, options: options);
    interpreter.allocateTensors();

    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;

    if (inputShape.length != 4 ||
        inputShape[1] != 224 ||
        inputShape[2] != 224 ||
        inputShape[3] != 3) {
      interpreter.close();
      throw StateError('Leaf AI model input must be [1, 224, 224, 3].');
    }

    if (outputShape.isEmpty || outputShape.last != _labels.length) {
      interpreter.close();
      throw StateError('Leaf AI model output does not match 38 labels.');
    }

    final isolateInterpreter =
        await IsolateInterpreter.create(address: interpreter.address);

    _interpreter = interpreter;
    _isolateInterpreter = isolateInterpreter;
    _ready = true;
  }

  Future<PlantPrediction> classifyFile(String path) async {
    if (!_ready || _interpreter == null || _isolateInterpreter == null) {
      await initialize();
    }

    final bytes = await File(path).readAsBytes();
    final flatInput = await Isolate.run(() => _prepareInput(bytes));
    final input = flatInput.reshape([1, 224, 224, 3]);
    final output = List<double>.filled(_labels.length, 0).reshape([1, _labels.length]);

    await _isolateInterpreter!.run(input, output);

    final scores = output[0].cast<double>();
    final ranked = <PlantScore>[];
    for (var i = 0; i < _labels.length; i++) {
      ranked.add(PlantScore(label: _labels[i], score: scores[i]));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));

    return PlantPrediction(
      label: ranked.first.label,
      confidence: ranked.first.score,
      topResults: ranked.take(3).toList(growable: false),
    );
  }

  Future<void> dispose() async {
    await _isolateInterpreter?.close();
    _isolateInterpreter = null;
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }
}

Float32List _prepareInput(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Unable to decode the selected image.');
  }

  final oriented = img.bakeOrientation(decoded);
  final side = oriented.width < oriented.height ? oriented.width : oriented.height;
  final cropped = img.copyCrop(
    oriented,
    x: (oriented.width - side) ~/ 2,
    y: (oriented.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = img.copyResize(
    cropped,
    width: 224,
    height: 224,
    interpolation: img.Interpolation.linear,
  );

  // Upstream MobileNetV3 embeds preprocessing in the graph, so the public
  // float32 input contract is raw RGB values in the 0..255 range.
  final input = Float32List(224 * 224 * 3);
  var offset = 0;
  for (var y = 0; y < 224; y++) {
    for (var x = 0; x < 224; x++) {
      final pixel = resized.getPixel(x, y);
      input[offset++] = pixel.r.toDouble();
      input[offset++] = pixel.g.toDouble();
      input[offset++] = pixel.b.toDouble();
    }
  }
  return input;
}

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/plant_ai_service.dart';
import '../ai/plant_knowledge.dart';
import '../core/app_theme.dart';

class LeafAiPage extends StatefulWidget {
  const LeafAiPage({super.key});

  @override
  State<LeafAiPage> createState() => LeafAiPageState();
}

class LeafAiPageState extends State<LeafAiPage> with WidgetsBindingObserver {
  final PlantAiService _ai = PlantAiService();
  final ImagePicker _picker = ImagePicker();

  CameraController? _camera;
  Timer? _liveTimer;
  PlantPrediction? _prediction;
  String? _photoPath;
  String? _error;
  bool _modelReady = false;
  bool _cameraReady = false;
  bool _live = false;
  bool _busy = false;
  int _analysisGeneration = 0;
  LeafLanguage _language = LeafLanguage.english;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreLanguage();
    _initialize();
  }

  Future<void> _restoreLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('leaf_ai_language');
    if (!mounted) return;
    setState(() => _language = LeafLanguageInfo.fromCode(saved));
  }

  Future<void> _setLanguage(LeafLanguage value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('leaf_ai_language', value.code);
    if (!mounted) return;
    setState(() => _language = value);
  }

  Future<void> _initialize() async {
    setState(() {
      _error = null;
      _modelReady = false;
    });

    try {
      await _ai.initialize();
      if (mounted) setState(() => _modelReady = true);
    } catch (e) {
      if (mounted) {
        debugPrint('Plant scan init failed: $e');
        setState(() => _error = LeafText.ui(_language, 'modelError'));
      }
    }

    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraReady = false);
        return;
      }

      final preferred = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        preferred,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Some devices/cameras do not expose flash control; preview still works.
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      await _camera?.dispose();
      setState(() {
        _camera = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraReady = false;
          debugPrint('Camera init failed: $e');
          _error ??= LeafText.ui(_language, 'cameraError');
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopLive();
      _camera?.dispose();
      _camera = null;
      _cameraReady = false;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  void _startLive() {
    if (!_modelReady || !_cameraReady || _camera == null) return;
    setState(() {
      _live = true;
      _photoPath = null;
      _error = null;
    });
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(
      const Duration(milliseconds: 1400),
      (_) => _captureAndAnalyzeLive(),
    );
    _captureAndAnalyzeLive();
  }

  void _stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
    if (mounted && _live) setState(() => _live = false);
  }

  Future<void> _captureAndAnalyzeLive() async {
    if (!_live || _busy || !_modelReady || !_cameraReady) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || camera.value.isTakingPicture) {
      return;
    }

    _busy = true;
    final generation = _analysisGeneration;
    try {
      final shot = await camera.takePicture();
      final result = await _ai.classifyFile(shot.path);
      try {
        await File(shot.path).delete();
      } catch (_) {}
      if (!mounted || !_live || generation != _analysisGeneration) return;
      setState(() {
        _prediction = result;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        debugPrint('Plant scan failed: $e');
        setState(() => _error = LeafText.ui(_language, 'scanError'));
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _captureStill() async {
    _stopLive();
    if (!_modelReady || !_cameraReady) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _busy) return;

    setState(() => _busy = true);
    final generation = _analysisGeneration;
    try {
      final shot = await camera.takePicture();
      final result = await _ai.classifyFile(shot.path);
      if (!mounted || generation != _analysisGeneration) return;
      setState(() {
        _photoPath = shot.path;
        _prediction = result;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        debugPrint('Plant scan failed: $e');
        setState(() => _error = LeafText.ui(_language, 'scanError'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    _stopLive();
    if (!_modelReady || _busy) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 1800,
    );
    if (picked == null) return;

    setState(() {
      _busy = true;
      _photoPath = picked.path;
      _error = null;
    });
    final generation = _analysisGeneration;
    try {
      final result = await _ai.classifyFile(picked.path);
      if (!mounted || generation != _analysisGeneration) return;
      setState(() => _prediction = result);
    } catch (e) {
      if (mounted) {
        debugPrint('Plant scan failed: $e');
        setState(() => _error = LeafText.ui(_language, 'scanError'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get hasActiveScan =>
      _live || _photoPath != null || _prediction != null || _busy || _error != null;

  bool resetIfNeeded() {
    if (!hasActiveScan) return false;
    resetScan();
    return true;
  }

  void resetScan() {
    _analysisGeneration++;
    _stopLive();
    if (!mounted) return;
    setState(() {
      _photoPath = null;
      _prediction = null;
      _error = null;
      _busy = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTimer?.cancel();
    _camera?.dispose();
    unawaited(_ai.dispose());
    super.dispose();
  }

  String _confidenceLabel(double c) {
    if (c >= 0.80) return LeafText.ui(_language, 'high');
    if (c >= 0.60) return LeafText.ui(_language, 'review');
    return LeafText.ui(_language, 'uncertain');
  }

  @override
  Widget build(BuildContext context) {
    final prediction = _prediction;
    final advice = prediction == null
        ? null
        : PlantKnowledge.forLabel(prediction.label, _language);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      LeafText.ui(_language, 'subtitle'),
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<LeafLanguage>(
                    tooltip: LeafText.ui(_language, 'language'),
                    initialValue: _language,
                    onSelected: _setLanguage,
                    itemBuilder: (context) => LeafLanguage.values
                        .map(
                          (language) => PopupMenuItem(
                            value: language,
                            child: Text(language.nativeName),
                          ),
                        )
                        .toList(growable: false),
                    icon: const Icon(Icons.translate_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ScannerCard(
                camera: _camera,
                cameraReady: _cameraReady,
                live: _live,
                busy: _busy,
                photoPath: _photoPath,
                language: _language,
                showReset: _photoPath != null || _prediction != null || _live,
                onReset: resetScan,
              ),
              const SizedBox(height: 14),
              _ControlRow(
                live: _live,
                canScan: _modelReady && _cameraReady && !_busy,
                onLive: _live ? _stopLive : _startLive,
                onCapture: _captureStill,
                onGallery: _pickPhoto,
                language: _language,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorCard(message: _error!),
              ],
              if (_busy) ...[
                const SizedBox(height: 14),
                _BusyCard(language: _language),
              ],
              const SizedBox(height: 14),
              if (prediction == null || advice == null)
                _EmptyResult(language: _language)
              else
                _DiagnosisCard(
                  prediction: prediction,
                  advice: advice,
                  language: _language,
                  confidenceLabel: _confidenceLabel(prediction.confidence),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScannerCard extends StatelessWidget {
  const _ScannerCard({
    required this.camera,
    required this.cameraReady,
    required this.live,
    required this.busy,
    required this.photoPath,
    required this.language,
    required this.showReset,
    required this.onReset,
  });

  final CameraController? camera;
  final bool cameraReady;
  final bool live;
  final bool busy;
  final String? photoPath;
  final LeafLanguage language;
  final bool showReset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF102B20), Color(0xFF06120E)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photoPath != null && !live)
                Image.file(File(photoPath!), fit: BoxFit.cover)
              else if (cameraReady && camera != null && camera!.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: camera!.value.previewSize?.height ?? 1,
                    height: camera!.value.previewSize?.width ?? 1,
                    child: CameraPreview(camera!),
                  ),
                )
              else
                const Center(
                  child: Icon(Icons.eco_outlined, size: 72, color: AppTheme.muted),
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(
                      color: live ? AppTheme.emeraldSoft : Colors.white70,
                      width: 2,
                    ),
                  ),
                ),
              ),
              if (showReset)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      onTap: onReset,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: live ? AppTheme.red : AppTheme.emerald,
                        boxShadow: [
                          BoxShadow(
                            color: (live ? AppTheme.red : AppTheme.emerald)
                                .withValues(alpha: 0.45),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        LeafText.ui(language, 'focus'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.live,
    required this.canScan,
    required this.onLive,
    required this.onCapture,
    required this.onGallery,
    required this.language,
  });

  final bool live;
  final bool canScan;
  final VoidCallback onLive;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final LeafLanguage language;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canScan || live ? onLive : null,
            icon: Icon(live ? Icons.stop_circle_outlined : Icons.center_focus_strong_rounded),
            label: Text(
              live ? LeafText.ui(language, 'stop') : LeafText.ui(language, 'start'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canScan ? onCapture : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(LeafText.ui(language, 'capture')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canScan || !live ? onGallery : null,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(LeafText.ui(language, 'gallery')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BusyCard extends StatelessWidget {
  const _BusyCard({required this.language});

  final LeafLanguage language;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(LeafText.ui(language, 'analyzing'))),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.red, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.language});
  final LeafLanguage language;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.emerald.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.eco_rounded, color: AppTheme.emerald, size: 34),
            ),
            const SizedBox(height: 14),
            Text(
              LeafText.ui(language, 'noResult'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosisCard extends StatelessWidget {
  const _DiagnosisCard({
    required this.prediction,
    required this.advice,
    required this.language,
    required this.confidenceLabel,
  });

  final PlantPrediction prediction;
  final DiseaseAdvice advice;
  final LeafLanguage language;
  final String confidenceLabel;

  @override
  Widget build(BuildContext context) {
    final percent = (prediction.confidence * 100).clamp(0, 100).toStringAsFixed(1);
    final confidenceColor = prediction.confidence >= 0.80
        ? AppTheme.emerald
        : prediction.confidence >= 0.60
            ? AppTheme.amber
            : AppTheme.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF123427), Color(0xFF0A1E17)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LeafText.ui(language, 'result'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                advice.crop,
                style: const TextStyle(fontSize: 14, color: AppTheme.emeraldSoft, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                advice.condition,
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, height: 1.1),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: prediction.confidence.clamp(0, 1),
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation(confidenceColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$percent%', style: TextStyle(color: confidenceColor, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                confidenceLabel,
                style: TextStyle(color: confidenceColor, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AdviceSection(
          icon: Icons.visibility_outlined,
          title: LeafText.ui(language, 'symptoms'),
          items: advice.symptoms,
        ),
        const SizedBox(height: 10),
        _AdviceSection(
          icon: Icons.healing_rounded,
          title: LeafText.ui(language, 'treatment'),
          items: advice.treatment,
        ),
        const SizedBox(height: 10),
        _AdviceSection(
          icon: Icons.shield_outlined,
          title: LeafText.ui(language, 'prevention'),
          items: advice.prevention,
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LeafText.ui(language, 'top'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final item in prediction.topResults.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            PlantKnowledge.forLabel(item.label, language).condition,
                            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                          ),
                        ),
                        Text(
                          '${(item.score * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.amber.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.24)),
          ),
          child: Text(
            advice.note,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11.5, height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _AdviceSection extends StatelessWidget {
  const _AdviceSection({
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.emerald, size: 20),
                const SizedBox(width: 9),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 11),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 5, color: AppTheme.emeraldSoft),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(color: AppTheme.muted, height: 1.4, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

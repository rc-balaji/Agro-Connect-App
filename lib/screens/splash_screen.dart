
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'root_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  late final AnimationController _pulse;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;
  late final Animation<double> _glow;
  late final Animation<double> _textFade;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _fadeIn = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
    );
    _scaleIn = Tween<double>(begin: 0.76, end: 1.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.0, 0.38, curve: Curves.elasticOut),
      ),
    );
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.05, 0.85, curve: Curves.easeInOut),
      ),
    );
    _textFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.30, 0.65, curve: Curves.easeOut),
    );

    _master.forward();
    Timer(const Duration(milliseconds: 3000), _goNext);
  }

  void _goNext() {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: const RootShell(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _master.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_master, _pulse]),
        builder: (context, _) {
          final pulseValue = 0.92 + (_pulse.value * 0.12);
          final orbit = 1.0 + (_pulse.value * 0.08);
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF06120E),
                  Color(0xFF0A1F17),
                  Color(0xFF0D281D),
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BackdropPainter(
                      progress: _master.value,
                      pulse: _pulse.value,
                    ),
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 248,
                          height: 248,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.scale(
                                scale: pulseValue,
                                child: Container(
                                  width: 210,
                                  height: 210,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.emerald.withValues(alpha: 0.08 * _glow.value),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.emerald.withValues(alpha: 0.24 * _glow.value),
                                        blurRadius: 34,
                                        spreadRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              ...List.generate(3, (index) {
                                final size = 158.0 + (index * 28.0);
                                final delay = index * 0.15;
                                final opacity = (0.38 - index * 0.1) * (0.7 + _pulse.value * 0.3);
                                final scale = 0.84 + (((_master.value + delay) % 1.0) * 0.22);
                                return Transform.scale(
                                  scale: scale,
                                  child: Container(
                                    width: size,
                                    height: size,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppTheme.emeraldSoft.withValues(alpha: opacity.clamp(0.0, 1.0)),
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              Transform.rotate(
                                angle: _pulse.value * 0.25,
                                child: Transform.scale(
                                  scale: orbit,
                                  child: const _FloatingElements(),
                                ),
                              ),
                              FadeTransition(
                                opacity: _fadeIn,
                                child: Transform.scale(
                                  scale: _scaleIn.value,
                                  child: Hero(
                                    tag: 'agro-app-icon',
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(58),
                                      child: Container(
                                        width: 144,
                                        height: 144,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(58),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.24),
                                              blurRadius: 26,
                                              offset: const Offset(0, 18),
                                            ),
                                          ],
                                        ),
                                        child: Image.asset(
                                          'assets/branding/app_icon.png',
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        FadeTransition(
                          opacity: _textFade,
                          child: Column(
                            children: [
                              Text(
                                'AGRO CONNECT',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Realtime Smart Farming Control',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.emeraldSoft.withValues(alpha: 0.92),
                                      fontSize: 14.2,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              const SizedBox(
                                width: 116,
                                child: LinearProgressIndicator(
                                  minHeight: 4,
                                  borderRadius: BorderRadius.all(Radius.circular(999)),
                                  backgroundColor: Color(0x1FFFFFFF),
                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.emerald),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FloatingElements extends StatelessWidget {
  const _FloatingElements();

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, Alignment alignment, Color color) {
      return Align(
        alignment: alignment,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF10271F).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 21),
        ),
      );
    }

    return IgnorePointer(
      child: SizedBox(
        width: 232,
        height: 232,
        child: Stack(
          children: [
            chip(Icons.wifi_tethering_rounded, const Alignment(0.95, -0.72), const Color(0xFFB8FF74)),
            chip(Icons.water_drop_rounded, const Alignment(-0.98, 0.08), AppTheme.cyan),
            chip(Icons.thermostat_rounded, const Alignment(0.92, 0.76), AppTheme.amber),
            chip(Icons.spa_rounded, const Alignment(-0.82, -0.78), AppTheme.emeraldSoft),
          ],
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.progress, required this.pulse});

  final double progress;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final topGlow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x3340E6A9), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(size.width * 0.82, size.height * 0.15), radius: size.width * 0.38));
    canvas.drawRect(rect, topGlow);

    final bottomGlow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x2228B382), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(size.width * 0.18, size.height * 0.88), radius: size.width * 0.34));
    canvas.drawRect(rect, bottomGlow);

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x22A2FFD6);

    for (int i = 0; i < 4; i++) {
      final path = Path();
      final baseY = size.height * (0.72 + (i * 0.06));
      path.moveTo(-20, baseY);
      for (double x = -20; x <= size.width + 20; x += 8) {
        final y = baseY + math.sin((x / 48) + progress * 8 + (i * 0.7)) * (8 + i * 2);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, wavePaint);
    }

    final dotPaint = Paint();
    for (int i = 0; i < 18; i++) {
      final dx = (size.width * ((i * 0.17 + progress * 0.06) % 1));
      final dy = (size.height * ((i * 0.11 + pulse * 0.08 + 0.2) % 1));
      dotPaint.color = AppTheme.emeraldSoft.withValues(alpha: 0.05 + ((i % 5) * 0.02));
      canvas.drawCircle(Offset(dx, dy), 1.8 + (i % 3), dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.pulse != pulse;
  }
}

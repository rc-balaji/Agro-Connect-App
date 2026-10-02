import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class MotorCard extends StatelessWidget {
  const MotorCard({
    super.key,
    required this.number,
    required this.desiredOn,
    required this.actualOn,
    required this.enabled,
    required this.pending,
    required this.onChanged,
  });

  final int number;
  final bool desiredOn;
  final bool actualOn;
  final bool enabled;
  final bool pending;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final actualColor = actualOn ? AppTheme.emerald : AppTheme.muted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: actualColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.water_drop_rounded, color: actualColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Motor $number', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    pending
                        ? 'Updating…'
                        : (actualOn ? 'Running' : 'Stopped'),
                    style: TextStyle(
                      color: pending ? AppTheme.amber : AppTheme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (pending)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amber),
                ),
              ),
            Switch.adaptive(
              value: desiredOn,
              onChanged: enabled && !pending ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

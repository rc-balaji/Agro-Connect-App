import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/plan_controller.dart';
import '../core/app_theme.dart';
import '../models/schedule_plan.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  int _motor = 1;
  late DateTime _selectedDay;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = _istNow();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlanController>();
    final motorPlans = controller.plansForMotor(_motor);
    final dayPlans = controller.plansForDay(_motor, _selectedDay);
    final upcoming = controller.upcomingForMotor(_motor);

    return RefreshIndicator(
      onRefresh: controller.refresh,
      color: AppTheme.emerald,
      backgroundColor: AppTheme.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(
            healthOk: controller.health.ok,
            healthConfigured: controller.health.configured,
            onCreate: controller.saving ? null : () => _createNew(context),
          ),
          if (controller.error != null && controller.error!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ErrorCard(
              message: controller.error!,
              onDismiss: controller.clearError,
            ),
          ],
          const SizedBox(height: 14),
          _MotorSelector(
            selected: _motor,
            counts: {
              for (var motor = 1; motor <= 3; motor += 1)
                motor: controller.plansForMotor(motor).length,
            },
            onChanged: (motor) => setState(() => _motor = motor),
          ),
          const SizedBox(height: 14),
          _OverviewStrip(
            motor: _motor,
            total: motorPlans.length,
            active: motorPlans.where((plan) => plan.enabled).length,
            next: _nextPlan(upcoming),
          ),
          const SizedBox(height: 14),
          _CalendarCard(
            visibleMonth: _visibleMonth,
            selectedDay: _selectedDay,
            motorPlans: motorPlans,
            onPrevious: () {
              setState(() {
                _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
              });
            },
            onNext: () {
              setState(() {
                _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
              });
            },
            onToday: () {
              final now = _istNow();
              setState(() {
                _selectedDay = DateTime(now.year, now.month, now.day);
                _visibleMonth = DateTime(now.year, now.month);
              });
            },
            onSelected: (day) {
              setState(() => _selectedDay = day);
            },
            onCreateForDay: () => _openEditor(
              context,
              motor: _motor,
              date: _selectedDay,
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(
            title: _friendlyDate(_selectedDay),
            subtitle: dayPlans.isEmpty
                ? 'No Motor $_motor plans on this date'
                : '${dayPlans.length} ${dayPlans.length == 1 ? 'plan' : 'plans'}',
            icon: Icons.today_rounded,
          ),
          const SizedBox(height: 10),
          if (controller.loading && !controller.initialized)
            const _LoadingCard()
          else if (dayPlans.isEmpty)
            _EmptyDayCard(
              motor: _motor,
              onCreate: () => _openEditor(
                context,
                motor: _motor,
                date: _selectedDay,
              ),
            )
          else
            ...dayPlans.map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlanCard(
                  plan: plan,
                  saving: controller.saving,
                  onEdit: () => _openEditor(context, existing: plan),
                  onDuplicate: () => _duplicate(context, plan),
                  onDelete: () => _delete(context, plan),
                  onEnabledChanged: (value) => _toggleEnabled(context, plan, value),
                ),
              ),
            ),
          const SizedBox(height: 8),
          _SectionTitle(
            title: 'All Motor $_motor plans',
            subtitle: 'Server-saved plans · IST · manual control remains independent',
            icon: Icons.event_repeat_rounded,
          ),
          const SizedBox(height: 10),
          if (upcoming.isEmpty)
            const _SimpleEmptyCard(
              icon: Icons.calendar_month_outlined,
              title: 'No saved plans yet',
              subtitle: 'Tap + New and choose a motor to create the first schedule.',
            )
          else
            ...upcoming.map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlanCard(
                  plan: plan,
                  saving: controller.saving,
                  compact: true,
                  onEdit: () => _openEditor(context, existing: plan),
                  onDuplicate: () => _duplicate(context, plan),
                  onDelete: () => _delete(context, plan),
                  onEnabledChanged: (value) => _toggleEnabled(context, plan, value),
                ),
              ),
            ),
        ],
      ),
    );
  }

  SchedulePlan? _nextPlan(List<SchedulePlan> plans) {
    for (final plan in plans) {
      if (plan.enabled && plan.nextRunAt != null) return plan;
    }
    return null;
  }

  Future<void> _createNew(BuildContext context) async {
    final motor = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _MotorPicker(initial: _motor),
    );
    if (!mounted || motor == null) return;
    setState(() => _motor = motor);
    await _openEditor(context, motor: motor, date: _selectedDay);
  }

  Future<void> _openEditor(
    BuildContext context, {
    int? motor,
    DateTime? date,
    SchedulePlan? existing,
  }) async {
    final controller = context.read<PlanController>();
    final result = await showModalBottomSheet<ScheduleDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => PlanEditorSheet(
        motor: motor ?? existing?.motor ?? _motor,
        initialDate: date ?? (existing == null ? _selectedDay : SchedulePlan.parseDateKey(existing.date)),
        existing: existing,
      ),
    );

    if (!mounted || result == null) return;
    final ok = existing == null
        ? await controller.create(result)
        : await controller.update(existing.id, result);
    if (!mounted) return;

    _showResult(
      context,
      ok: ok,
      success: existing == null ? 'Plan created and armed' : 'Plan updated and re-armed',
      error: controller.error,
    );
  }

  Future<void> _toggleEnabled(BuildContext context, SchedulePlan plan, bool enabled) async {
    final controller = context.read<PlanController>();
    final ok = await controller.setEnabled(plan, enabled);
    if (!mounted) return;
    _showResult(
      context,
      ok: ok,
      success: enabled ? 'Plan enabled' : 'Plan disabled',
      error: controller.error,
    );
  }

  Future<void> _duplicate(BuildContext context, SchedulePlan plan) async {
    final controller = context.read<PlanController>();
    final ok = await controller.duplicate(plan);
    if (!mounted) return;
    _showResult(
      context,
      ok: ok,
      success: 'Copy created in Disabled state',
      error: controller.error,
    );
  }

  Future<void> _delete(BuildContext context, SchedulePlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete plan?'),
        content: Text('${plan.title}\n\nThis removes its future server schedule.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(foregroundColor: AppTheme.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<PlanController>();
    final ok = await controller.delete(plan.id);
    if (!mounted) return;
    _showResult(context, ok: ok, success: 'Plan deleted', error: controller.error);
  }

  void _showResult(
    BuildContext context, {
    required bool ok,
    required String success,
    String? error,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: ok ? AppTheme.emeraldSoft : AppTheme.red),
            const SizedBox(width: 10),
            Expanded(child: Text(ok ? success : (error ?? 'Request failed'))),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.healthOk,
    required this.healthConfigured,
    required this.onCreate,
  });

  final bool healthOk;
  final bool healthConfigured;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final ready = healthOk && healthConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.emerald.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.auto_awesome_motion_rounded, color: AppTheme.emerald),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plan', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 3),
                  const Text(
                    'Server-side motor schedules in IST',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('New'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.emerald,
                foregroundColor: const Color(0xFF032118),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatusBadge(
              ready: ready,
              text: ready ? 'Scheduler ready' : 'Scheduler unavailable',
            ),
            const SizedBox(width: 8),
            const _InfoBadge(icon: Icons.schedule_rounded, text: 'IST'),
            const SizedBox(width: 8),
            const _InfoBadge(icon: Icons.timer_outlined, text: 'Seconds'),
          ],
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.ready, required this.text});

  final bool ready;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = ready ? AppTheme.emerald : AppTheme.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 7),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.muted),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: AppTheme.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MotorSelector extends StatelessWidget {
  const _MotorSelector({required this.selected, required this.counts, required this.onChanged});
  final int selected;
  final Map<int, int> counts;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const colors = <int, Color>{1: AppTheme.emerald, 2: AppTheme.amber, 3: AppTheme.red};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            for (var motor = 1; motor <= 3; motor += 1) ...[
              if (motor > 1) const SizedBox(width: 7),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onChanged(motor),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected == motor
                          ? colors[motor]!.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected == motor
                            ? colors[motor]!.withValues(alpha: 0.46)
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: colors[motor]),
                            ),
                            const SizedBox(width: 7),
                            Text('Motor $motor', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${counts[motor] ?? 0} plans',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip({required this.motor, required this.total, required this.active, required this.next});
  final int motor;
  final int total;
  final int active;
  final SchedulePlan? next;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10291F), Color(0xFF0B1E17)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _MiniMetric(value: '$active', label: 'Active'),
          const _VerticalLine(),
          _MiniMetric(value: '$total', label: 'Saved'),
          const _VerticalLine(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('NEXT RUN', style: TextStyle(color: AppTheme.muted, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                const SizedBox(height: 5),
                Text(
                  next == null ? 'No upcoming plan' : _nextRunText(next!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(color: AppTheme.emeraldSoft, fontWeight: FontWeight.w900, fontSize: 18)),
          Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _VerticalLine extends StatelessWidget {
  const _VerticalLine();
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, margin: const EdgeInsets.symmetric(horizontal: 11), color: AppTheme.border);
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.visibleMonth,
    required this.selectedDay,
    required this.motorPlans,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onSelected,
    required this.onCreateForDay,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final List<SchedulePlan> motorPlans;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onCreateForDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final days = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leading = first.weekday % 7;
    final cells = ((leading + days + 6) ~/ 7) * 7;
    final now = _istNow();
    final today = DateTime(now.year, now.month, now.day);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Column(
                    children: [
                      Text(_monthTitle(visibleMonth), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 2),
                      const Text('Tap a day to inspect plans', style: TextStyle(color: AppTheme.muted, fontSize: 10.5)),
                    ],
                  ),
                ),
                IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(onPressed: onToday, icon: const Icon(Icons.my_location_rounded, size: 16), label: const Text('Today')),
                const Spacer(),
                TextButton.icon(
                  onPressed: onCreateForDay,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                  label: const Text('Add on selected day'),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Row(
              children: [
                for (final day in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(day, style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800, fontSize: 10.5)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.84,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - leading + 1;
                if (dayNumber < 1 || dayNumber > days) return const SizedBox.shrink();
                final day = DateTime(visibleMonth.year, visibleMonth.month, dayNumber);
                final selected = _sameDay(day, selectedDay);
                final isToday = _sameDay(day, today);
                final occurrences = motorPlans.where((plan) => plan.occursOn(day)).toList();
                return _CalendarDay(
                  day: dayNumber,
                  selected: selected,
                  today: isToday,
                  plans: occurrences,
                  onTap: () => onSelected(day),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({required this.day, required this.selected, required this.today, required this.plans, required this.onTap});
  final int day;
  final bool selected;
  final bool today;
  final List<SchedulePlan> plans;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.fromLTRB(3, 7, 3, 4),
        decoration: BoxDecoration(
          color: selected ? AppTheme.emerald.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.emerald.withValues(alpha: 0.55)
                : (today ? AppTheme.border : Colors.transparent),
          ),
        ),
        child: Column(
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: selected ? AppTheme.emeraldSoft : AppTheme.text,
                fontWeight: selected || today ? FontWeight.w900 : FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
            const Spacer(),
            if (plans.isNotEmpty)
              Wrap(
                spacing: 2,
                runSpacing: 2,
                alignment: WrapAlignment.center,
                children: plans.take(3).map((plan) {
                  final color = plan.enabled ? AppTheme.emerald : AppTheme.muted;
                  return Container(width: 4.5, height: 4.5, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
                }).toList(),
              )
            else
              const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle, required this.icon});
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: AppTheme.emeraldSoft, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 10.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.saving,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onEnabledChanged,
    this.compact = false,
  });

  final SchedulePlan plan;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final motorColor = _motorColor(plan.motor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: motorColor.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text('M${plan.motor}', style: TextStyle(color: motorColor, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 7,
                        runSpacing: 5,
                        children: [
                          _TinyMeta(icon: Icons.schedule_rounded, text: plan.displayTime),
                          _TinyMeta(icon: Icons.timer_outlined, text: plan.durationLabel),
                          _TinyMeta(icon: Icons.repeat_rounded, text: plan.repeatLabel),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Plan actions',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'copy':
                        onDuplicate();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), dense: true)),
                    PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('Duplicate'), dense: true)),
                    PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: AppTheme.red), title: Text('Delete'), dense: true)),
                  ],
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _DetailBox(label: 'START DATE', value: _shortDateFromKey(plan.date))),
                  const SizedBox(width: 8),
                  Expanded(child: _DetailBox(label: 'NEXT RUN', value: plan.nextRunAt == null ? '—' : _nextRunText(plan))),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _EnableRadio(
                    enabled: plan.enabled,
                    locked: saving,
                    onChanged: onEnabledChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                    color: _schedulerColor(plan).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _schedulerText(plan),
                    style: TextStyle(color: _schedulerColor(plan), fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EnableRadio extends StatelessWidget {
  const _EnableRadio({required this.enabled, required this.locked, required this.onChanged});
  final bool enabled;
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RadioChoice(
              label: 'Enable',
              selected: enabled,
              color: AppTheme.emerald,
              onTap: locked || enabled ? null : () => onChanged(true),
            ),
          ),
          Expanded(
            child: _RadioChoice(
              label: 'Disable',
              selected: !enabled,
              color: AppTheme.amber,
              onTap: locked || !enabled ? null : () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadioChoice extends StatelessWidget {
  const _RadioChoice({required this.label, required this.selected, required this.color, required this.onTap});
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? color.withValues(alpha: 0.35) : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 11,
              height: 11,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? color : AppTheme.muted, width: 1.4)),
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? color : Colors.transparent),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: selected ? color : AppTheme.muted, fontWeight: FontWeight.w800, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _TinyMeta extends StatelessWidget {
  const _TinyMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.muted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: AppTheme.muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _DetailBox extends StatelessWidget {
  const _DetailBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.surface2.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(13)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
        ],
      ),
    );
  }
}

class _MotorPicker extends StatelessWidget {
  const _MotorPicker({required this.initial});
  final int initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 20),
          const Text('Which motor do you want to plan?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Each motor keeps its own independent schedule.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 18),
          for (var motor = 1; motor <= 3; motor += 1) ...[
            _MotorPickTile(motor: motor, preferred: motor == initial, onTap: () => Navigator.pop(context, motor)),
            if (motor < 3) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _MotorPickTile extends StatelessWidget {
  const _MotorPickTile({required this.motor, required this.preferred, required this.onTap});
  final int motor;
  final bool preferred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _motorColor(motor);
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: preferred ? color.withValues(alpha: 0.35) : AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.water_rounded, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Motor $motor', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text('Create or view Motor $motor timing', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class PlanEditorSheet extends StatefulWidget {
  const PlanEditorSheet({
    super.key,
    required this.motor,
    required this.initialDate,
    this.existing,
  });

  final int motor;
  final DateTime initialDate;
  final SchedulePlan? existing;

  @override
  State<PlanEditorSheet> createState() => _PlanEditorSheetState();
}

class _PlanEditorSheetState extends State<PlanEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _duration;
  late final TextEditingController _seconds;

  late int _motor;
  late DateTime _date;
  DateTime? _endDate;
  late TimeOfDay _time;
  late String _repeat;
  late Set<int> _weekdays;
  late bool _enabled;
  bool _hasEndDate = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _motor = existing?.motor ?? widget.motor;
    _date = existing == null ? widget.initialDate : SchedulePlan.parseDateKey(existing.date);
    _endDate = existing?.endDate == null ? null : SchedulePlan.parseDateKey(existing!.endDate!);
    _hasEndDate = _endDate != null;
    final timeParts = (existing?.time ?? '07:00:00').split(':');
    _time = TimeOfDay(hour: int.parse(timeParts[0]), minute: int.parse(timeParts[1]));
    _seconds = TextEditingController(text: timeParts.length > 2 ? timeParts[2] : '00');
    _duration = TextEditingController(text: '${existing?.durationSec ?? 30}');
    _title = TextEditingController(text: existing?.title ?? 'Motor $_motor plan');
    _repeat = existing?.repeat ?? 'once';
    _weekdays = {...?existing?.weekdays};
    if (_repeat == 'weekly' && _weekdays.isEmpty) {
      _weekdays.add(SchedulePlan.apiWeekday(_date));
    }
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.94),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.existing == null ? 'Create motor plan' : 'Edit motor plan', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 3),
                      const Text('Asia/Kolkata (IST) · second-level time', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 22 + bottom),
              children: [
                const _FormLabel('MOTOR'),
                const SizedBox(height: 8),
                _EditorMotorSelector(selected: _motor, onChanged: (value) {
                  setState(() {
                    _motor = value;
                    if (_title.text.startsWith('Motor ')) _title.text = 'Motor $_motor plan';
                  });
                }),
                const SizedBox(height: 18),
                const _FormLabel('PLAN NAME'),
                const SizedBox(height: 8),
                TextField(
                  controller: _title,
                  maxLength: 80,
                  decoration: _inputDecoration('Example: Morning watering', Icons.edit_calendar_rounded),
                ),
                const SizedBox(height: 6),
                const _FormLabel('STATUS'),
                const SizedBox(height: 8),
                _EditorStatusSelector(enabled: _enabled, onChanged: (value) => setState(() => _enabled = value)),
                const SizedBox(height: 18),
                const _FormLabel('START'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _PickerButton(
                        icon: Icons.calendar_today_rounded,
                        label: 'Date',
                        value: _friendlyDate(_date),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _PickerButton(
                        icon: Icons.schedule_rounded,
                        label: 'Time',
                        value: _displayTimeWithSeconds(),
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Seconds are stored exactly on the server.', style: TextStyle(color: AppTheme.muted, fontSize: 10.5)),
                    ),
                    SizedBox(
                      width: 84,
                      child: TextField(
                        controller: _seconds,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                        textAlign: TextAlign.center,
                        decoration: _inputDecoration('SS', Icons.timer_outlined).copyWith(
                          labelText: 'Seconds',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _FormLabel('RUN DURATION'),
                const SizedBox(height: 8),
                TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDecoration('Duration in seconds', Icons.hourglass_bottom_rounded).copyWith(suffixText: 'sec'),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [5, 10, 30, 60, 300].map((seconds) {
                    return ActionChip(
                      label: Text(seconds < 60 ? '$seconds sec' : '${seconds ~/ 60} min'),
                      onPressed: () => setState(() => _duration.text = '$seconds'),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                const _FormLabel('REPEAT'),
                const SizedBox(height: 8),
                _RepeatSelector(value: _repeat, onChanged: (value) {
                  setState(() {
                    _repeat = value;
                    if (value == 'weekly' && _weekdays.isEmpty) {
                      _weekdays.add(SchedulePlan.apiWeekday(_date));
                    }
                    if (value == 'once') {
                      _hasEndDate = false;
                      _endDate = null;
                    }
                  });
                }),
                if (_repeat == 'weekly') ...[
                  const SizedBox(height: 12),
                  const Text('Selected days', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 8),
                  _WeekdaySelector(
                    selected: _weekdays,
                    onChanged: (value) => setState(() => _weekdays = value),
                  ),
                ],
                if (_repeat != 'once') ...[
                  const SizedBox(height: 14),
                  _EndDateControl(
                    enabled: _hasEndDate,
                    date: _endDate,
                    onEnabledChanged: (value) {
                      setState(() {
                        _hasEndDate = value;
                        if (value && _endDate == null) _endDate = _date.add(const Duration(days: 30));
                        if (!value) _endDate = null;
                      });
                    },
                    onPick: _pickEndDate,
                  ),
                ],
                const SizedBox(height: 18),
                _SummaryCard(
                  motor: _motor,
                  date: _date,
                  time: _displayTimeWithSeconds(),
                  duration: int.tryParse(_duration.text) ?? 0,
                  repeat: _repeat,
                  weekdays: _weekdays,
                  enabled: _enabled,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF091913),
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.cloud_done_rounded),
                  label: Text(widget.existing == null ? 'Save plan' : 'Update plan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: const Color(0xFF032118),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035, 12, 31),
      helpText: 'Start date (IST)',
    );
    if (selected == null) return;
    setState(() {
      _date = selected;
      if (_endDate != null && _endDate!.isBefore(_date)) _endDate = _date;
    });
  }

  Future<void> _pickEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _date,
      firstDate: _date,
      lastDate: DateTime(2035, 12, 31),
      helpText: 'Repeat until (IST)',
    );
    if (selected != null) setState(() => _endDate = selected);
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Start time (IST)',
    );
    if (selected != null) setState(() => _time = selected);
  }

  String _displayTimeWithSeconds() {
    final seconds = (int.tryParse(_seconds.text) ?? 0).clamp(0, 59);
    final value = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return SchedulePlan.to12Hour(value);
  }

  void _save() {
    final title = _title.text.trim();
    final duration = int.tryParse(_duration.text);
    final seconds = int.tryParse(_seconds.text) ?? 0;

    if (title.isEmpty) return _validation('Enter a plan name');
    if (duration == null || duration < 1 || duration > 86400) {
      return _validation('Duration must be between 1 and 86400 seconds');
    }
    if (seconds < 0 || seconds > 59) return _validation('Seconds must be 0 to 59');
    if (_repeat == 'weekly' && _weekdays.isEmpty) return _validation('Choose at least one day');
    if (_hasEndDate && _endDate != null && _endDate!.isBefore(_date)) {
      return _validation('End date cannot be before start date');
    }

    final time = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    Navigator.pop(
      context,
      ScheduleDraft(
        title: title,
        motor: _motor,
        date: SchedulePlan.dateKey(_date),
        time: time,
        durationSec: duration,
        repeat: _repeat,
        weekdays: _weekdays.toList()..sort(),
        endDate: _hasEndDate && _endDate != null ? SchedulePlan.dateKey(_endDate!) : null,
        enabled: _enabled,
      ),
    );
  }

  void _validation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EditorMotorSelector extends StatelessWidget {
  const _EditorMotorSelector({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var motor = 1; motor <= 3; motor += 1) ...[
          if (motor > 1) const SizedBox(width: 8),
          Expanded(
            child: ChoiceChip(
              selected: selected == motor,
              label: SizedBox(width: double.infinity, child: Center(child: Text('Motor $motor'))),
              onSelected: (_) => onChanged(motor),
              selectedColor: _motorColor(motor).withValues(alpha: 0.18),
              side: BorderSide(color: selected == motor ? _motorColor(motor).withValues(alpha: 0.5) : AppTheme.border),
              labelStyle: TextStyle(color: selected == motor ? _motorColor(motor) : AppTheme.muted, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ],
    );
  }
}

class _EditorStatusSelector extends StatelessWidget {
  const _EditorStatusSelector({required this.enabled, required this.onChanged});
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: [
          Expanded(child: _LargeRadioChoice(label: 'Enable', subtitle: 'Schedule runs', selected: enabled, color: AppTheme.emerald, onTap: () => onChanged(true))),
          const SizedBox(width: 5),
          Expanded(child: _LargeRadioChoice(label: 'Disable', subtitle: 'Schedule stops', selected: !enabled, color: AppTheme.amber, onTap: () => onChanged(false))),
        ],
      ),
    );
  }
}

class _LargeRadioChoice extends StatelessWidget {
  const _LargeRadioChoice({required this.label, required this.subtitle, required this.selected, required this.color, required this.onTap});
  final String label;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.11) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: selected ? color.withValues(alpha: 0.32) : Colors.transparent),
        ),
        child: Row(
          children: [
            Container(
              width: 15,
              height: 15,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? color : AppTheme.muted, width: 1.4)),
              child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? color : Colors.transparent)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: selected ? color : AppTheme.text, fontWeight: FontWeight.w900, fontSize: 12)),
                  Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 9.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepeatSelector extends StatelessWidget {
  const _RepeatSelector({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [('once', 'Once', Icons.looks_one_outlined), ('daily', 'Daily', Icons.calendar_view_day_rounded), ('weekly', 'Selected days', Icons.date_range_rounded)];
    return Column(
      children: items.map((item) {
        final selected = value == item.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Material(
            color: selected ? AppTheme.emerald.withValues(alpha: 0.08) : AppTheme.surface,
            borderRadius: BorderRadius.circular(17),
            child: InkWell(
              onTap: () => onChanged(item.$1),
              borderRadius: BorderRadius.circular(17),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: selected ? AppTheme.emerald.withValues(alpha: 0.38) : AppTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(item.$3, size: 20, color: selected ? AppTheme.emerald : AppTheme.muted),
                    const SizedBox(width: 11),
                    Expanded(child: Text(item.$2, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? AppTheme.emeraldSoft : AppTheme.text))),
                    Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? AppTheme.emerald : AppTheme.muted, size: 19),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _WeekdaySelector extends StatelessWidget {
  const _WeekdaySelector({required this.selected, required this.onChanged});
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    const days = [(1, 'M'), (2, 'T'), (3, 'W'), (4, 'T'), (5, 'F'), (6, 'S'), (0, 'S')];
    return Row(
      children: days.map((entry) {
        final active = selected.contains(entry.$1);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () {
                final next = <int>{...selected};
                active ? next.remove(entry.$1) : next.add(entry.$1);
                onChanged(next);
              },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 42,
                decoration: BoxDecoration(
                  color: active ? AppTheme.emerald.withValues(alpha: 0.14) : AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: active ? AppTheme.emerald.withValues(alpha: 0.4) : AppTheme.border),
                ),
                child: Center(child: Text(entry.$2, style: TextStyle(color: active ? AppTheme.emeraldSoft : AppTheme.muted, fontWeight: FontWeight.w900))),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _EndDateControl extends StatelessWidget {
  const _EndDateControl({required this.enabled, required this.date, required this.onEnabledChanged, required this.onPick});
  final bool enabled;
  final DateTime? date;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('End date', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 3),
                Text(enabled && date != null ? _friendlyDate(date!) : 'No end date', style: const TextStyle(color: AppTheme.muted, fontSize: 10.5)),
              ],
            ),
          ),
          TextButton(onPressed: enabled ? onPick : null, child: const Text('Pick')),
          Switch(value: enabled, onChanged: onEnabledChanged),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(17), border: Border.all(color: AppTheme.border)),
          child: Row(
            children: [
              Icon(icon, size: 19, color: AppTheme.emerald),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label.toUpperCase(), style: const TextStyle(color: AppTheme.muted, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
                    const SizedBox(height: 3),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.motor, required this.date, required this.time, required this.duration, required this.repeat, required this.weekdays, required this.enabled});
  final int motor;
  final DateTime date;
  final String time;
  final int duration;
  final String repeat;
  final Set<int> weekdays;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    String repeatText = 'Once';
    if (repeat == 'daily') repeatText = 'Daily';
    if (repeat == 'weekly') {
      const names = {0: 'Sun', 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat'};
      repeatText = weekdays.map((d) => names[d] ?? '').where((s) => s.isNotEmpty).join(', ');
    }
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.emerald.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.fact_check_outlined, color: AppTheme.emeraldSoft, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Motor $motor · ${_friendlyDate(date)} · $time\n${_durationText(duration)} · $repeatText · ${enabled ? 'Enabled' : 'Disabled'}',
              style: const TextStyle(color: AppTheme.muted, height: 1.45, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: AppTheme.muted, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.9));
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 7, 11),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.red, size: 18),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: const TextStyle(color: AppTheme.red, fontSize: 11.5, fontWeight: FontWeight.w600))),
          IconButton(onPressed: onDismiss, visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, color: AppTheme.red, size: 17)),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => const Card(child: Padding(padding: EdgeInsets.all(26), child: Center(child: CircularProgressIndicator())));
}

class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard({required this.motor, required this.onCreate});
  final int motor;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.event_available_outlined, color: AppTheme.muted),
            const SizedBox(width: 12),
            Expanded(child: Text('No Motor $motor plan on this day.', style: const TextStyle(color: AppTheme.muted))),
            TextButton.icon(onPressed: onCreate, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
          ],
        ),
      ),
    );
  }
}

class _SimpleEmptyCard extends StatelessWidget {
  const _SimpleEmptyCard({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.muted),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 11))])),
            ],
          ),
        ),
      );
}

InputDecoration _inputDecoration(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 19, color: AppTheme.muted),
    filled: true,
    fillColor: AppTheme.surface,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: AppTheme.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: AppTheme.emerald, width: 1.2)),
  );
}

Color _motorColor(int motor) {
  switch (motor) {
    case 2:
      return AppTheme.amber;
    case 3:
      return AppTheme.red;
    default:
      return AppTheme.emerald;
  }
}

Color _schedulerColor(SchedulePlan plan) {
  if (!plan.enabled) return AppTheme.muted;
  if (plan.schedulerStatus == 'armed') return AppTheme.emerald;
  if (plan.schedulerStatus == 'sync_failed') return AppTheme.red;
  return AppTheme.amber;
}

String _schedulerText(SchedulePlan plan) {
  if (!plan.enabled) return 'Disabled';
  if (plan.expired) return 'Expired';
  switch (plan.schedulerStatus) {
    case 'armed':
      return 'Armed';
    case 'sync_failed':
      return 'Sync issue';
    case 'syncing':
      return 'Syncing';
    default:
      return plan.schedulerStatus ?? 'Saved';
  }
}

DateTime _istNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _monthTitle(DateTime value) {
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${months[value.month - 1]} ${value.year}';
}

String _friendlyDate(DateTime value) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[value.weekday - 1]}, ${value.day} ${months[value.month - 1]}';
}

String _shortDateFromKey(String value) {
  try {
    final date = SchedulePlan.parseDateKey(value);
    return _friendlyDate(date);
  } catch (_) {
    return value;
  }
}

String _nextRunText(SchedulePlan plan) {
  final epoch = plan.nextRunAt;
  if (epoch == null) return 'No next run';
  final dt = SchedulePlan.istDateTimeFromEpoch(epoch);
  final today = _istNow();
  final todayDate = DateTime(today.year, today.month, today.day);
  final runDate = DateTime(dt.year, dt.month, dt.day);
  final diff = runDate.difference(todayDate).inDays;
  final date = diff == 0 ? 'Today' : diff == 1 ? 'Tomorrow' : _friendlyDate(dt);
  final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  return '$date · ${SchedulePlan.to12Hour(time)}';
}

String _durationText(int seconds) {
  if (seconds < 60) return '$seconds sec';
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  return '${seconds ~/ 60} min ${seconds % 60} sec';
}

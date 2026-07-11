/// Read-only appointment view: live Today truth plus selectable history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../ui_common.dart';

class ProviderTimelineView extends ConsumerWidget {
  const ProviderTimelineView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = ref.watch(careCircleProvider);
    final personId = ref.watch(selectedProviderPersonProvider);
    final days = ref.watch(providerRangeDaysProvider);
    if (circle.people.isEmpty || personId == null) {
      return const Center(child: Text('No one in the circle yet.'));
    }
    final person = circle.personById(personId);
    if (person == null) {
      return const Center(child: Text('Choose a person to review.'));
    }
    final stats = ref.watch(
      adherenceProvider((personId: personId, days: days)),
    );
    final today = ref.watch(todayDosesProvider(personId));

    return ListView(
      key: const PageStorageKey('provider-view'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Provider appointment view',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reviewing:',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
                DropdownButton<String>(
                  key: const ValueKey('provider-person-picker'),
                  value: personId,
                  items: [
                    for (final candidate in circle.people)
                      DropdownMenuItem(
                        value: candidate.id,
                        child: Text(candidate.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(selectedProviderPersonProvider.notifier)
                          .select(value);
                    }
                  },
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'History:',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
                DropdownButton<int>(
                  key: const ValueKey('provider-range-picker'),
                  value: days,
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 14, child: Text('14 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(providerRangeDaysProvider.notifier)
                          .select(value);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TodayCard(person: person, doses: today),
        const SizedBox(height: 12),
        _HistorySummary(person: person, days: days, stats: stats),
        const SizedBox(height: 12),
        _DayGrid(person: person, days: days),
        const SizedBox(height: 10),
        const _HistoryLegend(),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.person, required this.doses});

  final Person person;
  final List<ScheduledDose> doses;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(
      context,
    ).colorScheme.primaryContainer.withValues(alpha: 0.23),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'TODAY · LIVE — ${person.name}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (doses.isEmpty)
            const Text('No doses scheduled today.')
          else
            for (final dose in doses) _TodayDoseRow(dose: dose),
        ],
      ),
    ),
  );
}

class _TodayDoseRow extends StatelessWidget {
  const _TodayDoseRow({required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context) => Semantics(
    label: doseSemanticLabel(dose),
    child: Container(
      key: ValueKey('provider-today-${dose.key}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            children: [
              ExcludeSemantics(child: DoseStatusIcon(dose: dose, size: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dose.med.name} · ${dose.slot.label}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(dose.med.dose),
                  ],
                ),
              ),
            ],
          );
          final status = Text(
            doseDisplayLabel(dose),
            style: TextStyle(
              color: doseDisplayColor(dose),
              fontWeight: FontWeight.w800,
            ),
          );
          if (constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: status,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 8),
              status,
            ],
          );
        },
      ),
    ),
  );
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({
    required this.person,
    required this.days,
    required this.stats,
  });

  final Person person;
  final int days;
  final AdherenceStats stats;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Previous $days days — ${person.name}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _Stat('Taken', stats.taken, takenColor),
              _Stat('Marked late', stats.lateMarked, lateMarkedColor),
              _Stat('Missed', stats.missed, missedColor),
              _Stat('Never marked', stats.notMarked, notMarkedColor),
            ],
          ),
          if (stats.notMarked > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: notMarkedColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Conversation starter: ${stats.notMarked} '
                'dose${stats.notMarked == 1 ? ' was' : 's were'} never '
                'marked. “Did you take those and forget to mark them — '
                'or miss them?”',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StatusDot(color, semanticLabel: label),
      const SizedBox(width: 5),
      Text('$value $label', style: const TextStyle(fontSize: 13)),
    ],
  );
}

class _DayGrid extends ConsumerWidget {
  const _DayGrid({required this.person, required this.days});

  final Person person;
  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = ref.watch(careCircleProvider);
    final today = ref.watch(currentDateTimeProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (var offset = days; offset >= 1; offset--)
              _DayRow(
                circle: circle,
                person: person,
                day: calendarDay(today, addDays: -offset),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.circle,
    required this.person,
    required this.day,
  });

  final CareCircle circle;
  final Person person;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final date = dateKey(day);
    final schedules = circle.schedules
        .where(
          (schedule) =>
              schedule.personId == person.id && schedule.isActiveOn(date),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              '${weekdays[day.weekday - 1]} ${day.month}/${day.day}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
          Expanded(
            child: schedules.isEmpty
                ? Text(
                    'No schedule yet',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).disabledColor,
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      for (final schedule in schedules)
                        for (final slot in schedule.slots)
                          _HistoryPill(
                            circle: circle,
                            person: person,
                            schedule: schedule,
                            slot: slot,
                            date: date,
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryPill extends StatelessWidget {
  const _HistoryPill({
    required this.circle,
    required this.person,
    required this.schedule,
    required this.slot,
    required this.date,
  });

  final CareCircle circle;
  final Person person;
  final Schedule schedule;
  final DoseSlot slot;
  final String date;

  @override
  Widget build(BuildContext context) {
    final med = circle.medById(schedule.medId);
    if (med == null) return const SizedBox.shrink();
    final key = DoseEvent.keyOf(person.id, med.id, date, slot);
    final event = circle.events[key];
    final status = event?.status ?? DoseStatus.notMarked;
    final late = event?.lateMarked ?? false;
    final label = statusLabel(status, lateMarked: late);
    final color = statusColor(status, lateMarked: late);
    final icon = switch (status) {
      DoseStatus.taken => Icons.check,
      DoseStatus.missed => Icons.close,
      DoseStatus.notMarked => Icons.question_mark,
    };
    final shortName = med.name.length <= 3
        ? med.name
        : med.name.substring(0, 3);
    final recorded = event?.recordedAt?.toLocal();
    final recordedText = recorded == null
        ? ''
        : ' Recorded ${recorded.month}/${recorded.day} '
              '${recorded.hour.toString().padLeft(2, '0')}:'
              '${recorded.minute.toString().padLeft(2, '0')}.';

    return Tooltip(
      message: '${med.name} — ${slot.label}: $label.$recordedText',
      child: Semantics(
        label: '${person.name}, ${med.name}, ${slot.label}, $label',
        child: Container(
          key: ValueKey('provider-history-$key'),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 3),
              Text(
                '$shortName ${slot.label.substring(0, 2)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryLegend extends StatelessWidget {
  const _HistoryLegend();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 6,
    children: const [
      _LegendItem(Icons.check, takenColor, 'Taken'),
      _LegendItem(Icons.check, lateMarkedColor, 'Taken, marked late'),
      _LegendItem(Icons.close, missedColor, 'Missed'),
      _LegendItem(Icons.question_mark, notMarkedColor, 'Never marked'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.icon, this.color, this.label);

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

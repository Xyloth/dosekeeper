/// Peace of mind at a glance: urgent unknowns and confirmed misses first,
/// followed by per-person live Today state and historical adherence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../ui_common.dart';

class CaregiverView extends ConsumerWidget {
  const CaregiverView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = ref.watch(careCircleProvider);
    final attention = ref.watch(caregiverAlertsProvider);

    return ListView(
      key: const PageStorageKey('caregiver-view'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Caregiver dashboard',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        if (attention.isNotEmpty) ...[
          Text(
            'Needs attention',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: notMarkedColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final dose in attention) _AttentionCard(dose: dose),
          const SizedBox(height: 12),
        ] else ...[
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: takenColor),
              title: Text('Nothing needs attention right now'),
              subtitle: Text('No urgent unknown or confirmed missed doses.'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text('The circle', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final person in circle.people) _PersonCard(person: person),
      ],
    );
  }
}

class _AttentionCard extends ConsumerWidget {
  const _AttentionCard({required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final confirmedMiss = dose.status == DoseStatus.missed;
    final color = confirmedMiss ? missedColor : notMarkedColor;
    final title =
        '${dose.person.name} — ${dose.med.name}, ${dose.slot.label.toLowerCase()}';
    final subtitle = confirmedMiss
        ? 'Missed — explicitly confirmed by ${dose.person.name}.'
        : dose.date == dateKey(ref.watch(currentDateTimeProvider))
        ? dose.urgency == DoseUrgency.question
              ? 'Window closed and still not marked. An answer is needed.'
              : 'Window closing and still not marked.'
        : 'Yesterday’s dose is still unresolved.';

    return Card(
      key: ValueKey('caregiver-alert-${dose.key}'),
      color: color.withValues(alpha: 0.07),
      margin: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label: '$title. $subtitle',
        child: ListTile(
          leading: ExcludeSemantics(
            child: Icon(
              confirmedMiss ? Icons.cancel : Icons.help_outline,
              color: color,
            ),
          ),
          title: Text(title),
          subtitle: Text(subtitle),
        ),
      ),
    );
  }
}

class _PersonCard extends ConsumerWidget {
  const _PersonCard({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doses = ref.watch(todayDosesProvider(person.id));
    final week = ref.watch(adherenceProvider((personId: person.id, days: 7)));
    final confirmed = week.taken + week.lateMarked;
    final proportion = week.scheduled == 0 ? 1.0 : confirmed / week.scheduled;
    final percentage = '${(proportion * 100).round()}% previous 7 days';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final identity = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      backgroundColor: personColor(person),
                      child: Text(
                        person.name.characters.first,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        person.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                );
                final score = Text(
                  percentage,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: proportion >= 0.9 ? takenColor : notMarkedColor,
                  ),
                );
                if (constraints.maxWidth < 390) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [identity, const SizedBox(height: 8), score],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 8),
                    score,
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Semantics(
              label: '${person.name}, $percentage confirmed taken',
              child: LinearProgressIndicator(
                value: proportion,
                minHeight: 8,
                borderRadius: BorderRadius.circular(6),
                color: proportion >= 0.9 ? takenColor : notMarkedColor,
                backgroundColor: const Color(0x14000000),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'TODAY · LIVE',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 6),
            if (doses.isEmpty)
              const Text('No doses scheduled today.')
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final dose in doses)
                    Semantics(
                      label: doseSemanticLabel(dose),
                      child: Chip(
                        key: ValueKey('caregiver-dose-${dose.key}'),
                        visualDensity: VisualDensity.compact,
                        avatar: ExcludeSemantics(
                          child: DoseStatusIcon(dose: dose, size: 17),
                        ),
                        label: Text(
                          '${dose.med.name} · ${dose.slot.label} · '
                          '${doseDisplayLabel(dose)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            if (week.notMarked > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${week.notMarked} dose${week.notMarked == 1 ? '' : 's'} in '
                'the previous 7 days never got marked — taken or missed, '
                'nobody knows yet.',
                style: const TextStyle(fontSize: 12, color: notMarkedColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

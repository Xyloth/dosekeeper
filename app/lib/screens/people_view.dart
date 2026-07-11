/// Read-only care-circle roster and medication schedules for v0.1.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../ui_common.dart';

class PeopleView extends ConsumerWidget {
  const PeopleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = ref.watch(careCircleProvider);
    return ListView(
      key: const PageStorageKey('circle-view'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Care Circle', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Who is tracked and the schedules everyone coordinates.'),
        const SizedBox(height: 10),
        if (circle.people.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No one is in this care circle yet.'),
            ),
          )
        else
          for (final person in circle.people)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        Expanded(
                          child: Text(
                            person.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final schedule in circle.schedules.where(
                      (schedule) => schedule.personId == person.id,
                    ))
                      Builder(
                        builder: (context) {
                          final med = circle.medById(schedule.medId);
                          if (med == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.medication_outlined,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${med.name} · ${med.dose}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          schedule.slots
                                              .map((slot) => slot.label)
                                              .join(' · '),
                                        ),
                                        if (schedule.effectiveFrom != null)
                                          Text(
                                            'History begins '
                                            '${schedule.effectiveFrom}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(
                                                context,
                                              ).hintColor,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Fictional example family. DoseKeeper is a coordination demo, '
            'not a medical device, and gives no medical advice. Demo reset '
            'and technical details are in Settings.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

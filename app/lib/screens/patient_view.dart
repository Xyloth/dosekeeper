/// The person taking the meds. Big targets, explicit human answers, and no
/// green confirmation until a person acts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../ui_common.dart';

enum _QuestionAnswer { tookIt, missed }

enum _DoseCorrection { taken, missed, clear }

class PatientView extends ConsumerStatefulWidget {
  const PatientView({super.key, required this.personId, this.active = true});

  /// The one person this tab belongs to (James's ruling: a top-level tab per
  /// patient, no sub-selection inside the view).
  final String personId;

  /// Only the visible tab may fire pop-ups; inactive siblings in the
  /// IndexedStack stay silent and rely on their tab badge + banners.
  final bool active;

  @override
  ConsumerState<PatientView> createState() => _PatientViewState();
}

class _PatientViewState extends ConsumerState<PatientView> {
  final _questionQueue = <ScheduledDose>[];
  final _queuedKeys = <String>{};
  var _drainingQuestions = false;

  @override
  Widget build(BuildContext context) {
    final circle = ref.watch(careCircleProvider);
    final person = circle.personById(widget.personId);
    if (person == null) {
      return const Center(child: Text('This person left the circle.'));
    }

    ref.listen(patientActionDosesProvider(widget.personId), (previous, next) {
      _onEscalation(previous, next);
    });

    final doses = ref.watch(todayDosesProvider(widget.personId));
    final pending = ref.watch(pendingQuestionsProvider(widget.personId));

    return ListView(
      key: ValueKey('patient-list-${widget.personId}'),
      padding: const EdgeInsets.all(16),
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
                '${person.name} — patient view',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (pending.isNotEmpty) ...[
          Text(
            'Needs your answer',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: notMarkedColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text('These are from yesterday and remain unknown.'),
          const SizedBox(height: 8),
          for (final dose in pending) _DoseCard(dose: dose),
          const SizedBox(height: 12),
        ],
        Text('Today', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (doses.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No doses scheduled today.'),
            ),
          ),
        for (final dose in doses) _DoseCard(dose: dose),
      ],
    );
  }

  void _onEscalation(List<ScheduledDose>? previous, List<ScheduledDose> next) {
    if (previous == null) return;
    // Inactive tabs never pop dialogs/snacks; their badge carries the signal.
    if (!widget.active || !mounted) return;
    final before = {for (final dose in previous) dose.key: dose.urgency};
    final newlyDue = <ScheduledDose>[];
    final newlyClosing = <ScheduledDose>[];
    final newlyQuestion = <ScheduledDose>[];

    for (final dose in next) {
      if (dose.status != DoseStatus.notMarked) continue;
      final oldUrgency = before[dose.key];
      if (oldUrgency == null || oldUrgency == dose.urgency) continue;
      switch (dose.urgency) {
        case DoseUrgency.due when oldUrgency == DoseUrgency.scheduled:
          newlyDue.add(dose);
        case DoseUrgency.lateReminder
            when oldUrgency == DoseUrgency.scheduled ||
                oldUrgency == DoseUrgency.due:
          newlyClosing.add(dose);
        case DoseUrgency.question:
          newlyQuestion.add(dose);
        case DoseUrgency.scheduled ||
            DoseUrgency.due ||
            DoseUrgency.lateReminder:
          break;
      }
    }

    if (newlyQuestion.isNotEmpty) {
      _enqueueQuestions(newlyQuestion);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (newlyClosing.isNotEmpty) {
      final dose = newlyClosing.first;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _snack(
            'Still not marked — the ${dose.slot.label.toLowerCase()} window is '
            'closing. ${dose.med.name} for ${dose.person.name}.',
            Icons.notification_important_outlined,
            const Color(0xFF8A5A00),
          ),
        );
    } else if (newlyDue.isNotEmpty) {
      final dose = newlyDue.first;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _snack(
            '${dose.slot.label} dose coming up: ${dose.med.name} for '
            '${dose.person.name}.',
            Icons.notifications_active_outlined,
            const Color(0xFF445A2A),
          ),
        );
    }
  }

  void _enqueueQuestions(List<ScheduledDose> doses) {
    for (final dose in doses) {
      if (_queuedKeys.add(dose.key)) _questionQueue.add(dose);
    }
    if (_drainingQuestions) return;
    _drainingQuestions = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainQuestionQueue());
  }

  Future<void> _drainQuestionQueue() async {
    try {
      while (mounted && _questionQueue.isNotEmpty) {
        final dose = _questionQueue.removeAt(0);
        _queuedKeys.remove(dose.key);
        if (!_stillUnresolved(dose)) continue;
        final answer = await _askQuestion(dose);
        if (!mounted || answer == null) {
          _questionQueue.clear();
          _queuedKeys.clear();
          break;
        }
        if (!_stillUnresolved(dose)) continue;
        final notifier = ref.read(careCircleProvider.notifier);
        switch (answer) {
          case _QuestionAnswer.tookIt:
            await notifier.resolveTookIt(
              dose.person.id,
              dose.med.id,
              dose.date,
              dose.slot,
            );
          case _QuestionAnswer.missed:
            await notifier.resolveMissedIt(
              dose.person.id,
              dose.med.id,
              dose.date,
              dose.slot,
            );
        }
      }
    } finally {
      _drainingQuestions = false;
      if (mounted && _questionQueue.isNotEmpty) {
        _drainingQuestions = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _drainQuestionQueue(),
        );
      }
    }
  }

  bool _stillUnresolved(ScheduledDose dose) {
    final circle = ref.read(careCircleProvider);
    final stillScheduled = circle.schedules.any(
      (schedule) =>
          schedule.personId == dose.person.id &&
          schedule.medId == dose.med.id &&
          schedule.slots.contains(dose.slot) &&
          schedule.isActiveOn(dose.date),
    );
    return stillScheduled && !circle.events.containsKey(dose.key);
  }

  Future<_QuestionAnswer?> _askQuestion(ScheduledDose dose) =>
      showDialog<_QuestionAnswer>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.help_outline, color: notMarkedColor, size: 40),
          title: const Text('A dose was never marked'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${dose.med.name} (${dose.med.dose}) — '
                  '${dose.slot.label.toLowerCase()}, for ${dose.person.name}.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Did you take it and forget to mark it — or miss it?',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Not now'),
            ),
            FilledButton.tonal(
              onPressed: () =>
                  Navigator.pop(dialogContext, _QuestionAnswer.tookIt),
              child: const Text('I took it — forgot to mark'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: missedColor),
              onPressed: () =>
                  Navigator.pop(dialogContext, _QuestionAnswer.missed),
              child: const Text('I missed this dose'),
            ),
          ],
        ),
      );

  SnackBar _snack(String text, IconData icon, Color background) => SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: background,
    duration: const Duration(seconds: 3),
    content: Row(
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _DoseCard extends ConsumerWidget {
  const _DoseCard({required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trailing = _trailing(context, ref);
    final banner = _bannerFor(context);

    return Semantics(
      label: doseSemanticLabel(dose),
      container: true,
      child: Card(
        key: ValueKey('patient-dose-${dose.key}'),
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final identity = Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dose.slot.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dose.med.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              dose.med.dose,
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 500) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: trailing,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 10),
                      trailing,
                    ],
                  );
                },
              ),
              if (banner != null) ...[const SizedBox(height: 10), banner],
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(careCircleProvider.notifier);
    if (dose.status == DoseStatus.notMarked) {
      if (dose.urgency == DoseUrgency.scheduled) {
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, color: scheduledColor),
            SizedBox(width: 6),
            Text('Later today'),
          ],
        );
      }
      if (dose.urgency == DoseUrgency.question) {
        return const SizedBox.shrink();
      }
      return Semantics(
        button: true,
        label: 'Mark ${dose.med.name} ${dose.slot.label} as taken',
        child: FilledButton.icon(
          key: ValueKey('patient-taken-${dose.key}'),
          style: FilledButton.styleFrom(
            backgroundColor: notMarkedColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
          ),
          onPressed: () => notifier.markTaken(
            dose.person.id,
            dose.med.id,
            dose.date,
            dose.slot,
          ),
          icon: const Icon(Icons.question_mark),
          label: const Text('Taken?', style: TextStyle(fontSize: 17)),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DoseStatusIcon(dose: dose, size: 28),
        const SizedBox(width: 6),
        Text(
          statusLabel(dose.status, lateMarked: dose.lateMarked),
          style: TextStyle(
            color: statusColor(dose.status, lateMarked: dose.lateMarked),
            fontWeight: FontWeight.w700,
          ),
        ),
        PopupMenuButton<_DoseCorrection>(
          key: ValueKey('correct-${dose.key}'),
          tooltip: 'Correct this dose record',
          onSelected: (correction) =>
              _applyCorrection(context, ref, correction),
          itemBuilder: (_) => [
            if (dose.status != DoseStatus.taken)
              const PopupMenuItem(
                value: _DoseCorrection.taken,
                child: Text('Correct to taken'),
              ),
            if (dose.status != DoseStatus.missed)
              const PopupMenuItem(
                value: _DoseCorrection.missed,
                child: Text('Correct to missed'),
              ),
            const PopupMenuItem(
              value: _DoseCorrection.clear,
              child: Text('Clear answer'),
            ),
          ],
          icon: const Icon(Icons.more_vert),
        ),
      ],
    );
  }

  Widget? _bannerFor(BuildContext context) {
    if (dose.status != DoseStatus.notMarked) return null;
    return switch (dose.urgency) {
      DoseUrgency.scheduled => null,
      DoseUrgency.due => _ReminderBanner(
        background: notMarkedColor.withValues(alpha: 0.12),
        icon: Icons.notifications_active_outlined,
        text: '${dose.slot.label} dose is due now.',
      ),
      DoseUrgency.lateReminder => _ReminderBanner(
        background: notMarkedColor.withValues(alpha: 0.2),
        icon: Icons.notification_important_outlined,
        text:
            'Still not marked — the ${dose.slot.label.toLowerCase()} '
            'window is closing.',
      ),
      DoseUrgency.question => _QuestionBanner(dose: dose),
    };
  }

  Future<void> _applyCorrection(
    BuildContext context,
    WidgetRef ref,
    _DoseCorrection correction,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final circle = ref.read(careCircleProvider);
    final previous = circle.events[dose.key];
    if (previous == null) return;
    final notifier = ref.read(careCircleProvider.notifier);
    final label = switch (correction) {
      _DoseCorrection.taken => 'taken',
      _DoseCorrection.missed => 'missed',
      _DoseCorrection.clear => 'not marked',
    };

    switch (correction) {
      case _DoseCorrection.taken:
        if (dose.urgency == DoseUrgency.question) {
          await notifier.resolveTookIt(
            dose.person.id,
            dose.med.id,
            dose.date,
            dose.slot,
          );
        } else {
          await notifier.markTaken(
            dose.person.id,
            dose.med.id,
            dose.date,
            dose.slot,
          );
        }
      case _DoseCorrection.missed:
        await notifier.resolveMissedIt(
          dose.person.id,
          dose.med.id,
          dose.date,
          dose.slot,
        );
      case _DoseCorrection.clear:
        await notifier.clearEvent(
          dose.person.id,
          dose.med.id,
          dose.date,
          dose.slot,
        );
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Dose corrected to $label.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(notifier.restoreEvent(previous)),
          ),
        ),
      );
  }
}

class _ReminderBanner extends StatelessWidget {
  const _ReminderBanner({
    required this.background,
    required this.icon,
    required this.text,
  });

  final Color background;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: notMarkedColor),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _QuestionBanner extends ConsumerWidget {
  const _QuestionBanner({required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(careCircleProvider.notifier);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: notMarkedColor.withValues(alpha: 0.09),
        border: Border.all(color: notMarkedColor.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline, color: notMarkedColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'The ${dose.slot.label.toLowerCase()} window closed and '
                  'this dose was never marked.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text('Did you take it and forget to mark it — or miss it?'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                key: ValueKey('question-taken-${dose.key}'),
                onPressed: () => notifier.resolveTookIt(
                  dose.person.id,
                  dose.med.id,
                  dose.date,
                  dose.slot,
                ),
                child: const Text('I took it — forgot to mark'),
              ),
              OutlinedButton(
                key: ValueKey('question-missed-${dose.key}'),
                style: OutlinedButton.styleFrom(foregroundColor: missedColor),
                onPressed: () => notifier.resolveMissedIt(
                  dose.person.id,
                  dose.med.id,
                  dose.date,
                  dose.slot,
                ),
                child: const Text('I missed this dose'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

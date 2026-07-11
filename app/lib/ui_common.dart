/// Shared colors, labels, and semantics so every role speaks one language.
library;

import 'package:flutter/material.dart';

import 'models.dart';
import 'state.dart';

Color personColor(Person person) =>
    HSLColor.fromAHSL(1, person.colorSeed.toDouble(), 0.45, 0.45).toColor();

const takenColor = Color(0xFF2E7D32);
const lateMarkedColor = Color(0xFF00796B);
const missedColor = Color(0xFFC62828);
const notMarkedColor = Color(0xFFB26A00);
const scheduledColor = Color(0xFF667085);

Color statusColor(DoseStatus status, {bool lateMarked = false}) =>
    switch (status) {
      DoseStatus.taken => lateMarked ? lateMarkedColor : takenColor,
      DoseStatus.missed => missedColor,
      DoseStatus.notMarked => notMarkedColor,
    };

String statusLabel(DoseStatus status, {bool lateMarked = false}) =>
    switch (status) {
      DoseStatus.taken => lateMarked ? 'Taken, marked late' : 'Taken',
      DoseStatus.missed => 'Missed',
      DoseStatus.notMarked => 'Not marked',
    };

String urgencyLabel(DoseUrgency urgency) => switch (urgency) {
  DoseUrgency.scheduled => 'Scheduled for later',
  DoseUrgency.due => 'Due now',
  DoseUrgency.lateReminder => 'Still not marked',
  DoseUrgency.question => 'Window closed — answer needed',
};

String doseDisplayLabel(ScheduledDose dose) {
  if (dose.status != DoseStatus.notMarked) {
    return statusLabel(dose.status, lateMarked: dose.lateMarked);
  }
  return urgencyLabel(dose.urgency);
}

Color doseDisplayColor(ScheduledDose dose) {
  if (dose.status == DoseStatus.notMarked &&
      dose.urgency == DoseUrgency.scheduled) {
    return scheduledColor;
  }
  return statusColor(dose.status, lateMarked: dose.lateMarked);
}

IconData doseDisplayIcon(ScheduledDose dose) {
  if (dose.status == DoseStatus.taken) return Icons.check_circle;
  if (dose.status == DoseStatus.missed) return Icons.cancel;
  if (dose.urgency == DoseUrgency.scheduled) return Icons.schedule;
  return Icons.help_outline;
}

String doseSemanticLabel(ScheduledDose dose) =>
    '${dose.person.name}, ${dose.med.name}, ${dose.slot.label}: '
    '${doseDisplayLabel(dose)}';

class DoseStatusIcon extends StatelessWidget {
  const DoseStatusIcon({required this.dose, super.key, this.size = 20});

  final ScheduledDose dose;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: doseSemanticLabel(dose),
    child: ExcludeSemantics(
      child: Icon(
        doseDisplayIcon(dose),
        color: doseDisplayColor(dose),
        size: size,
      ),
    ),
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 10, this.semanticLabel});

  final Color color;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (semanticLabel == null) return dot;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(child: dot),
    );
  }
}

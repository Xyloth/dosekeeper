/// DoseKeeper domain models.
///
/// The load-bearing invariant: a dose has THREE states —
/// taken / missed / notMarked — and notMarked is never silently
/// converted to missed. Only a human answer resolves it.
library;

/// Named dose slots with time windows behind them (local time).
/// Schedules speak human ("Afternoon dose"); logic uses the window.
enum DoseSlot {
  morning('Morning', 6, 11),
  noon('Noon', 11, 13),
  afternoon('Afternoon', 13, 17),
  evening('Evening', 17, 21),
  bedtime('Bedtime', 21, 24);

  const DoseSlot(this.label, this.startHour, this.endHour);
  final String label;
  final int startHour;
  final int endHour;

  /// Fraction of the way through this slot's window at [hour] (0–1, clamped).
  double progress(double hour) =>
      ((hour - startHour) / (endHour - startHour)).clamp(0.0, 1.0);

  bool contains(double hour) => hour >= startHour && hour < endHour;
  bool isPast(double hour) => hour >= endHour;
}

enum DoseStatus { notMarked, taken, missed }

class Person {
  const Person({required this.id, required this.name, required this.colorSeed});
  final String id;
  final String name;

  /// Stable hue seed so a person keeps their color everywhere.
  final int colorSeed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorSeed': colorSeed,
  };
  factory Person.fromJson(Map<String, dynamic> j) => Person(
    id: j['id'] as String,
    name: j['name'] as String,
    colorSeed: j['colorSeed'] as int,
  );
}

class Med {
  const Med({required this.id, required this.name, required this.dose});
  final String id;
  final String name;
  final String dose; // human text: "5 mg", "1 tablet"

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'dose': dose};
  factory Med.fromJson(Map<String, dynamic> j) => Med(
    id: j['id'] as String,
    name: j['name'] as String,
    dose: j['dose'] as String,
  );
}

/// A person takes a med at a set of named slots, daily.
class Schedule {
  const Schedule({
    required this.personId,
    required this.medId,
    required this.slots,
    this.effectiveFrom,
    this.effectiveTo,
  });
  final String personId;
  final String medId;
  final List<DoseSlot> slots;

  /// Inclusive local calendar-date boundaries (`yyyy-MM-dd`). A null bound
  /// means the schedule has no boundary in that direction.
  final String? effectiveFrom;
  final String? effectiveTo;

  bool isActiveOn(String date) =>
      (effectiveFrom == null || date.compareTo(effectiveFrom!) >= 0) &&
      (effectiveTo == null || date.compareTo(effectiveTo!) <= 0);

  Map<String, dynamic> toJson() => {
    'personId': personId,
    'medId': medId,
    'slots': slots.map((s) => s.name).toList(),
    'effectiveFrom': effectiveFrom,
    'effectiveTo': effectiveTo,
  };
  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
    personId: j['personId'] as String,
    medId: j['medId'] as String,
    slots: (j['slots'] as List)
        .map((s) => DoseSlot.values.byName(s as String))
        .toList(),
    effectiveFrom: j['effectiveFrom'] as String?,
    effectiveTo: j['effectiveTo'] as String?,
  );
}

/// One scheduled dose on one date. Absence of an event == notMarked.
class DoseEvent {
  const DoseEvent({
    required this.personId,
    required this.medId,
    required this.date, // 'yyyy-MM-dd'
    required this.slot,
    required this.status,
    this.lateMarked = false, // resolved AFTER the window via "the question"
    this.recordedAt,
  });
  final String personId;
  final String medId;
  final String date;
  final DoseSlot slot;
  final DoseStatus status;
  final bool lateMarked;

  /// When the human recorded this answer. This is deliberately not presented
  /// as the time medication was ingested.
  final DateTime? recordedAt;

  static String keyOf(
    String personId,
    String medId,
    String date,
    DoseSlot slot,
  ) => '$personId|$medId|$date|${slot.name}';
  String get key => keyOf(personId, medId, date, slot);

  Map<String, dynamic> toJson() => {
    'personId': personId,
    'medId': medId,
    'date': date,
    'slot': slot.name,
    'status': status.name,
    'lateMarked': lateMarked,
    'recordedAt': recordedAt?.toUtc().toIso8601String(),
  };
  factory DoseEvent.fromJson(Map<String, dynamic> j) => DoseEvent(
    personId: j['personId'] as String,
    medId: j['medId'] as String,
    date: j['date'] as String,
    slot: DoseSlot.values.byName(j['slot'] as String),
    status: DoseStatus.values.byName(j['status'] as String),
    lateMarked: j['lateMarked'] as bool? ?? false,
    recordedAt: (j['recordedAt'] as String?) == null
        ? null
        : DateTime.parse(j['recordedAt'] as String),
  );
}

/// The whole shared world: everyone every screen watches.
class CareCircle {
  const CareCircle({
    this.people = const [],
    this.meds = const [],
    this.schedules = const [],
    this.events = const {},
  });
  final List<Person> people;
  final List<Med> meds;
  final List<Schedule> schedules;

  /// DoseEvent.key -> event. A scheduled dose with no entry is notMarked.
  final Map<String, DoseEvent> events;

  CareCircle copyWith({
    List<Person>? people,
    List<Med>? meds,
    List<Schedule>? schedules,
    Map<String, DoseEvent>? events,
  }) => CareCircle(
    people: people ?? this.people,
    meds: meds ?? this.meds,
    schedules: schedules ?? this.schedules,
    events: events ?? this.events,
  );

  Person? personById(String id) =>
      people.where((p) => p.id == id).cast<Person?>().firstOrNull;
  Med? medById(String id) =>
      meds.where((m) => m.id == id).cast<Med?>().firstOrNull;

  /// Status for a scheduled dose; notMarked when no event exists.
  DoseStatus statusOf(
    String personId,
    String medId,
    String date,
    DoseSlot slot,
  ) =>
      events[DoseEvent.keyOf(personId, medId, date, slot)]?.status ??
      DoseStatus.notMarked;

  Map<String, dynamic> toJson() => {
    'people': people.map((p) => p.toJson()).toList(),
    'meds': meds.map((m) => m.toJson()).toList(),
    'schedules': schedules.map((s) => s.toJson()).toList(),
    'events': events.map((k, v) => MapEntry(k, v.toJson())),
  };
  factory CareCircle.fromJson(Map<String, dynamic> j) {
    final circle = CareCircle(
      people: (j['people'] as List)
          .map((p) => Person.fromJson(p as Map<String, dynamic>))
          .toList(),
      meds: (j['meds'] as List)
          .map((m) => Med.fromJson(m as Map<String, dynamic>))
          .toList(),
      schedules: (j['schedules'] as List)
          .map((s) => Schedule.fromJson(s as Map<String, dynamic>))
          .toList(),
      events: (j['events'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, DoseEvent.fromJson(v as Map<String, dynamic>)),
      ),
    );
    circle.validate();
    return circle;
  }

  /// Rejects structurally valid JSON that would otherwise crash a screen or
  /// manufacture impossible adherence data.
  void validate() {
    final personIds = <String>{};
    for (final person in people) {
      if (person.id.trim().isEmpty ||
          person.name.trim().isEmpty ||
          !personIds.add(person.id) ||
          person.colorSeed < 0 ||
          person.colorSeed >= 360) {
        throw const FormatException('Invalid person data');
      }
    }

    final medIds = <String>{};
    for (final med in meds) {
      if (med.id.trim().isEmpty ||
          med.name.trim().isEmpty ||
          med.dose.trim().isEmpty ||
          !medIds.add(med.id)) {
        throw const FormatException('Invalid medication data');
      }
    }

    final scheduledKeys = <String>{};
    for (final schedule in schedules) {
      if (!personIds.contains(schedule.personId) ||
          !medIds.contains(schedule.medId) ||
          schedule.slots.isEmpty) {
        throw const FormatException('Invalid schedule reference');
      }
      _validateDate(schedule.effectiveFrom);
      _validateDate(schedule.effectiveTo);
      if (schedule.effectiveFrom != null &&
          schedule.effectiveTo != null &&
          schedule.effectiveFrom!.compareTo(schedule.effectiveTo!) > 0) {
        throw const FormatException('Invalid schedule date range');
      }
      for (final slot in schedule.slots) {
        if (!scheduledKeys.add(
          '${schedule.personId}|${schedule.medId}|${slot.name}',
        )) {
          throw const FormatException('Duplicate scheduled dose');
        }
      }
    }

    for (final entry in events.entries) {
      final event = entry.value;
      _validateDate(event.date, required: true);
      if (event.key != entry.key ||
          event.status == DoseStatus.notMarked ||
          event.recordedAt == null ||
          !personIds.contains(event.personId) ||
          !medIds.contains(event.medId)) {
        throw const FormatException('Invalid dose event');
      }
      final hasSchedule = schedules.any(
        (schedule) =>
            schedule.personId == event.personId &&
            schedule.medId == event.medId &&
            schedule.slots.contains(event.slot) &&
            schedule.isActiveOn(event.date),
      );
      if (!hasSchedule) {
        throw const FormatException('Event has no active schedule');
      }
    }
  }

  static void _validateDate(String? value, {bool required = false}) {
    if (value == null) {
      if (required) throw const FormatException('Missing date');
      return;
    }
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
    final parsed = DateTime.tryParse(value);
    if (!match || parsed == null || dateKey(parsed) != value) {
      throw const FormatException('Invalid date');
    }
  }
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Calendar-day arithmetic that remains correct across daylight-saving jumps.
DateTime calendarDay(DateTime date, {int addDays = 0}) =>
    DateTime(date.year, date.month, date.day + addDays);

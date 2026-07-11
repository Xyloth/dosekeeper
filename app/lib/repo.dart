/// Persistence behind one interface, so v0.2 can swap in Firestore
/// without touching providers or screens.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

abstract class CareRepo {
  Future<CareCircle?> load();
  Stream<CareCircle> watch();
  Future<void> save(CareCircle circle);
}

class LocalRepo implements CareRepo {
  LocalRepo(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'dosekeeper.circle.v3';

  @override
  Future<CareCircle?> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return CareCircle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupt/old data: fall back to seed rather than crash
    }
  }

  @override
  Stream<CareCircle> watch() => const Stream.empty();

  @override
  Future<void> save(CareCircle circle) async {
    circle.validate();
    final saved = await _prefs.setString(_key, jsonEncode(circle.toJson()));
    if (!saved) {
      throw StateError('Shared preferences rejected the DoseKeeper save.');
    }
  }
}

/// Fictional example family — clearly labeled demo data.
/// History is generated relative to [today] so the demo always looks alive:
/// a mix of taken, missed, late-marked, and (crucially) NOT-MARKED doses,
/// plus today's doses left pending so the reminder flow can fire.
CareCircle seedCircle(DateTime today) {
  const rose = Person(id: 'p-rose', name: 'Grandma Rose', colorSeed: 210);
  const leo = Person(id: 'p-leo', name: 'Leo (age 9)', colorSeed: 25);

  const lisinopril = Med(id: 'm-lis', name: 'Lisinopril', dose: '10 mg');
  const metformin = Med(id: 'm-met', name: 'Metformin', dose: '500 mg');
  const inhaler = Med(id: 'm-inh', name: 'Flovent inhaler', dose: '2 puffs');

  final localToday = calendarDay(today);
  final historyStart = dateKey(calendarDay(localToday, addDays: -10));
  final schedules = [
    Schedule(
      personId: 'p-rose',
      medId: 'm-lis',
      slots: const [DoseSlot.morning],
      effectiveFrom: historyStart,
    ),
    Schedule(
      personId: 'p-rose',
      medId: 'm-met',
      slots: const [DoseSlot.morning, DoseSlot.evening],
      effectiveFrom: historyStart,
    ),
    Schedule(
      personId: 'p-leo',
      medId: 'm-inh',
      slots: const [DoseSlot.morning, DoseSlot.bedtime],
      effectiveFrom: historyStart,
    ),
  ];

  // Deterministic-but-varied 10-day history (no randomness: reproducible demo).
  final events = <String, DoseEvent>{};
  void put(
    Person p,
    Med m,
    DateTime day,
    DoseSlot slot,
    DoseStatus st, {
    bool late = false,
  }) {
    final onTime = DateTime(
      day.year,
      day.month,
      day.day,
      slot.startHour,
    ).add(const Duration(minutes: 20));
    final afterWindow = DateTime(
      day.year,
      day.month,
      day.day,
      slot.endHour,
    ).add(const Duration(minutes: 20));
    final e = DoseEvent(
      personId: p.id,
      medId: m.id,
      date: dateKey(day),
      slot: slot,
      status: st,
      lateMarked: late,
      recordedAt: late || st == DoseStatus.missed ? afterWindow : onTime,
    );
    events[e.key] = e;
  }

  for (var i = 10; i >= 1; i--) {
    final day = calendarDay(localToday, addDays: -i);
    // Rose morning lisinopril: mostly taken; day-7 late-marked; day-3 NOT marked.
    if (i == 3) {
      // no event: stays notMarked — the "did you take it or forget to mark it?" day
    } else {
      put(
        rose,
        lisinopril,
        day,
        DoseSlot.morning,
        DoseStatus.taken,
        late: i == 7,
      );
    }
    // Rose metformin: morning taken; evening missed on day-5 and day-2.
    put(rose, metformin, day, DoseSlot.morning, DoseStatus.taken);
    put(
      rose,
      metformin,
      day,
      DoseSlot.evening,
      (i == 5 || i == 2) ? DoseStatus.missed : DoseStatus.taken,
    );
    // Leo inhaler: morning taken; bedtime NOT marked on day-4, else taken.
    put(leo, inhaler, day, DoseSlot.morning, DoseStatus.taken);
    if (i != 4) {
      put(leo, inhaler, day, DoseSlot.bedtime, DoseStatus.taken);
    }
  }
  // Today is seeded with NOTHING marked (the demo rule): every checkmark
  // in the demo must be earned by a human tap, so nothing ever looks
  // auto-marked. Landing mid-day, the morning doses are already past their
  // window — the viewer meets THE QUESTION immediately.

  final circle = CareCircle(
    people: const [rose, leo],
    meds: const [lisinopril, metformin, inhaler],
    schedules: schedules,
    events: events,
  );
  circle.validate();
  return circle;
}

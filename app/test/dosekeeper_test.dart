import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dosekeeper/models.dart';
import 'package:dosekeeper/repo.dart';
import 'package:dosekeeper/state.dart';

import 'support/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cross-role state', () {
    test(
      'patient mutation updates caregiver attention and live Today state',
      () async {
        final harness = makeHarness();
        final container = harness.container;
        final today = dateKey(harness.clock.now());

        container.read(demoClockProvider.notifier).set(20.5);
        expect(
          container
              .read(caregiverAlertsProvider)
              .any(
                (dose) =>
                    dose.person.id == 'p-rose' &&
                    dose.med.id == 'm-met' &&
                    dose.slot == DoseSlot.evening,
              ),
          isTrue,
        );

        await container
            .read(careCircleProvider.notifier)
            .markTaken('p-rose', 'm-met', today, DoseSlot.evening);

        expect(
          container
              .read(caregiverAlertsProvider)
              .any(
                (dose) =>
                    dose.person.id == 'p-rose' &&
                    dose.med.id == 'm-met' &&
                    dose.slot == DoseSlot.evening,
              ),
          isFalse,
        );
        final liveToday = findDose(
          container.read(todayDosesProvider('p-rose')),
          'm-met',
          DoseSlot.evening,
        );
        expect(liveToday.status, DoseStatus.taken);
        expect(liveToday.recordedAt, harness.clock.now());
      },
    );

    test('confirmed miss remains a high-priority caregiver item', () async {
      final harness = makeHarness();
      final container = harness.container;
      final today = dateKey(harness.clock.now());
      container.read(demoClockProvider.notifier).set(22);

      await container
          .read(careCircleProvider.notifier)
          .resolveMissedIt('p-rose', 'm-met', today, DoseSlot.evening);

      final attention = container.read(caregiverAlertsProvider);
      final missed = findDose(attention, 'm-met', DoseSlot.evening);
      expect(missed.status, DoseStatus.missed);
      expect(missed.person.id, 'p-rose');
    });

    test('patient selection survives care-circle event mutations', () async {
      final harness = makeHarness();
      final container = harness.container;
      final today = dateKey(harness.clock.now());
      container.read(selectedPatientProvider.notifier).select('p-leo');

      await container
          .read(careCircleProvider.notifier)
          .markTaken('p-leo', 'm-inh', today, DoseSlot.morning);

      expect(container.read(selectedPatientProvider), 'p-leo');
    });

    test(
      'remote people refresh preserves valid selection and repairs removal',
      () async {
        final harness = makeHarness();
        final container = harness.container;
        container.read(selectedPatientProvider.notifier).select('p-leo');

        final samePeople = seedCircle(harness.clock.now());
        harness.repo.controller.add(samePeople);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(selectedPatientProvider), 'p-leo');

        final roseOnly = samePeople.copyWith(
          people: [samePeople.personById('p-rose')!],
          schedules: samePeople.schedules
              .where((schedule) => schedule.personId == 'p-rose')
              .toList(),
          events: Map.fromEntries(
            samePeople.events.entries.where(
              (entry) => entry.value.personId == 'p-rose',
            ),
          ),
        );
        roseOnly.validate();
        harness.repo.controller.add(roseOnly);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(selectedPatientProvider), 'p-rose');
      },
    );
  });

  group('three-state and clock integrity', () {
    test(
      'window close asks; only explicit answers resolve the state',
      () async {
        final harness = makeHarness();
        final container = harness.container;
        final today = dateKey(harness.clock.now());
        container.read(demoClockProvider.notifier).set(22);

        var evening = findDose(
          container.read(todayDosesProvider('p-rose')),
          'm-met',
          DoseSlot.evening,
        );
        expect(evening.status, DoseStatus.notMarked);
        expect(evening.urgency, DoseUrgency.question);

        await container
            .read(careCircleProvider.notifier)
            .resolveTookIt('p-rose', 'm-met', today, DoseSlot.evening);
        evening = findDose(
          container.read(todayDosesProvider('p-rose')),
          'm-met',
          DoseSlot.evening,
        );
        expect(evening.status, DoseStatus.taken);
        expect(evening.lateMarked, isTrue);

        await container
            .read(careCircleProvider.notifier)
            .resolveMissedIt('p-rose', 'm-met', today, DoseSlot.evening);
        evening = findDose(
          container.read(todayDosesProvider('p-rose')),
          'm-met',
          DoseSlot.evening,
        );
        expect(evening.status, DoseStatus.missed);

        await container
            .read(careCircleProvider.notifier)
            .clearEvent('p-rose', 'm-met', today, DoseSlot.evening);
        evening = findDose(
          container.read(todayDosesProvider('p-rose')),
          'm-met',
          DoseSlot.evening,
        );
        expect(evening.status, DoseStatus.notMarked);
      },
    );

    test('bedtime crosses into question in the explicit +1 day demo range', () {
      final harness = makeHarness();
      final container = harness.container;
      container.read(demoClockProvider.notifier).set(24.1);

      final bedtime = findDose(
        container.read(todayDosesProvider('p-leo')),
        'm-inh',
        DoseSlot.bedtime,
      );
      expect(bedtime.status, DoseStatus.notMarked);
      expect(bedtime.urgency, DoseUrgency.question);
    });

    test(
      'midnight rollover keeps yesterday bedtime answerable by its date',
      () async {
        final harness = makeHarness(now: DateTime(2026, 7, 11, 23, 59));
        final container = harness.container;
        harness.clock.value = DateTime(2026, 7, 12, 0, 1);
        container.read(currentDateTimeProvider.notifier).refresh();

        final pending = findDose(
          container.read(pendingQuestionsProvider('p-leo')),
          'm-inh',
          DoseSlot.bedtime,
        );
        expect(pending.date, '2026-07-11');

        await container
            .read(careCircleProvider.notifier)
            .resolveMissedIt(
              pending.person.id,
              pending.med.id,
              pending.date,
              pending.slot,
            );

        final circle = container.read(careCircleProvider);
        expect(
          circle.statusOf('p-leo', 'm-inh', '2026-07-11', DoseSlot.bedtime),
          DoseStatus.missed,
        );
        expect(
          circle.statusOf('p-leo', 'm-inh', '2026-07-12', DoseSlot.bedtime),
          DoseStatus.notMarked,
        );
      },
    );

    test('demo clock follows real ticks until the viewer takes control', () {
      final harness = makeHarness(now: DateTime(2026, 7, 11, 8, 15));
      final container = harness.container;
      expect(container.read(demoClockProvider).hour, 8.25);
      expect(container.read(demoClockProvider).followsNow, isTrue);

      container.read(demoClockProvider.notifier).set(24.1);
      harness.clock.value = DateTime(2026, 7, 11, 9, 30);
      container.read(currentDateTimeProvider.notifier).refresh();
      expect(container.read(demoClockProvider).hour, 24.1);

      container.read(demoClockProvider.notifier).resetToNow();
      expect(container.read(demoClockProvider).hour, 9.5);
      expect(container.read(demoClockProvider).followsNow, isTrue);
    });

    test('escalation boundaries are ordered, including bedtime', () {
      expect(urgencyFor(DoseSlot.afternoon, 12.99), DoseUrgency.scheduled);
      expect(urgencyFor(DoseSlot.afternoon, 13), DoseUrgency.due);
      expect(urgencyFor(DoseSlot.afternoon, 16), DoseUrgency.lateReminder);
      expect(urgencyFor(DoseSlot.afternoon, 17), DoseUrgency.question);
      expect(urgencyFor(DoseSlot.bedtime, 23.99), DoseUrgency.lateReminder);
      expect(urgencyFor(DoseSlot.bedtime, 24), DoseUrgency.question);
    });
  });

  group('history coverage and model integrity', () {
    test('effective schedule boundaries prevent fabricated history', () {
      final harness = makeHarness();
      final stats = harness.container.read(
        adherenceProvider((personId: 'p-rose', days: 14)),
      );

      expect(stats.scheduled, 30, reason: 'only ten active days × three doses');
      expect(stats.lateMarked, 1);
      expect(stats.missed, 2);
      expect(stats.notMarked, 1);
    });

    test('schedule date bounds are inclusive', () {
      const schedule = Schedule(
        personId: 'p',
        medId: 'm',
        slots: [DoseSlot.morning],
        effectiveFrom: '2026-07-01',
        effectiveTo: '2026-07-10',
      );
      expect(schedule.isActiveOn('2026-06-30'), isFalse);
      expect(schedule.isActiveOn('2026-07-01'), isTrue);
      expect(schedule.isActiveOn('2026-07-10'), isTrue);
      expect(schedule.isActiveOn('2026-07-11'), isFalse);
    });

    test('calendar-day arithmetic crosses month and year without 24h math', () {
      expect(
        dateKey(calendarDay(DateTime(2026, 1, 1), addDays: -1)),
        '2025-12-31',
      );
      expect(
        dateKey(calendarDay(DateTime(2026, 2, 28), addDays: 1)),
        '2026-03-01',
      );
      expect(
        dateKey(calendarDay(DateTime(2028, 2, 28), addDays: 1)),
        '2028-02-29',
      );
      expect(calendarDay(DateTime(2026, 3, 8, 23), addDays: 1).hour, 0);
    });

    test(
      'recorded timestamp and every domain field survive JSON round-trip',
      () {
        final circle = seedCircle(DateTime(2026, 7, 11));
        final back = CareCircle.fromJson(circle.toJson());

        expect(
          back.people.map((person) => person.toJson()),
          circle.people.map((person) => person.toJson()),
        );
        expect(
          back.meds.map((med) => med.toJson()),
          circle.meds.map((med) => med.toJson()),
        );
        expect(
          back.schedules.map((schedule) => schedule.toJson()),
          circle.schedules.map((schedule) => schedule.toJson()),
        );
        expect(back.events.keys, unorderedEquals(circle.events.keys));
        for (final key in circle.events.keys) {
          expect(back.events[key]!.toJson(), circle.events[key]!.toJson());
          expect(back.events[key]!.recordedAt, isNotNull);
        }
      },
    );

    test('semantic corruption is rejected instead of reaching widgets', () {
      final json = seedCircle(DateTime(2026, 7, 11)).toJson();
      final people = (json['people'] as List).cast<Map<String, dynamic>>();
      people.first['name'] = '';
      expect(() => CareCircle.fromJson(json), throwsFormatException);
    });
  });

  group('repository behavior', () {
    test(
      'rapid optimistic mutations persist sequentially in final-state order',
      () async {
        final repo = RecordingRepo()
          ..saveDelay = const Duration(milliseconds: 5);
        final harness = makeHarness(repo: repo);
        final container = harness.container;
        final today = dateKey(harness.clock.now());

        final first = container
            .read(careCircleProvider.notifier)
            .markTaken('p-rose', 'm-lis', today, DoseSlot.morning);
        final second = container
            .read(careCircleProvider.notifier)
            .markTaken('p-rose', 'm-met', today, DoseSlot.morning);
        await Future.wait([first, second]);

        expect(repo.maxConcurrentSaves, 1);
        expect(repo.snapshots, hasLength(2));
        expect(
          repo.stored!.statusOf('p-rose', 'm-lis', today, DoseSlot.morning),
          DoseStatus.taken,
        );
        expect(
          repo.stored!.statusOf('p-rose', 'm-met', today, DoseSlot.morning),
          DoseStatus.taken,
        );
      },
    );

    test(
      'a failed save does not poison the queue; retrying state succeeds',
      () async {
        final repo = RecordingRepo()..failuresRemaining = 1;
        final harness = makeHarness(repo: repo);
        final container = harness.container;
        final today = dateKey(harness.clock.now());

        await container
            .read(careCircleProvider.notifier)
            .markTaken('p-rose', 'm-lis', today, DoseSlot.morning);
        expect(
          container.read(persistenceStatusProvider).phase,
          PersistencePhase.failed,
        );

        await container.read(careCircleProvider.notifier).retrySave();
        expect(
          container.read(persistenceStatusProvider).phase,
          PersistencePhase.saved,
        );
        expect(
          repo.stored!.statusOf('p-rose', 'm-lis', today, DoseSlot.morning),
          DoseStatus.taken,
        );
      },
    );

    test('remote stream updates shared state without echo-saving', () async {
      final repo = RecordingRepo();
      final harness = makeHarness(repo: repo);
      final container = harness.container;
      final remote = seedCircle(DateTime(2026, 7, 11));
      final event = DoseEvent(
        personId: 'p-rose',
        medId: 'm-lis',
        date: '2026-07-11',
        slot: DoseSlot.morning,
        status: DoseStatus.taken,
        recordedAt: harness.clock.now(),
      );
      final remoteWithEvent = remote.copyWith(
        events: {...remote.events, event.key: event},
      );

      repo.controller.add(remoteWithEvent);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(careCircleProvider).events[event.key], isNotNull);
      expect(repo.snapshots, isEmpty);
    });

    test(
      'a stale remote echo cannot roll back an optimistic local save',
      () async {
        final repo = RecordingRepo()..saveGate = Completer<void>();
        final harness = makeHarness(repo: repo);
        final container = harness.container;
        final today = dateKey(harness.clock.now());
        final localWrite = container
            .read(careCircleProvider.notifier)
            .markTaken('p-rose', 'm-lis', today, DoseSlot.morning);
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(persistenceStatusProvider).phase,
          PersistencePhase.saving,
        );

        repo.controller.add(seedCircle(harness.clock.now()));
        await Future<void>.delayed(Duration.zero);
        expect(
          container
              .read(careCircleProvider)
              .statusOf('p-rose', 'm-lis', today, DoseSlot.morning),
          DoseStatus.taken,
        );
        expect(
          container.read(persistenceStatusProvider).phase,
          PersistencePhase.saving,
        );

        repo.saveGate!.complete();
        await localWrite;
        expect(
          container.read(persistenceStatusProvider).phase,
          PersistencePhase.saved,
        );
      },
    );

    test(
      'invalid remote state is rejected and leaves current state intact',
      () async {
        final harness = makeHarness();
        final container = harness.container;
        final before = container.read(careCircleProvider);
        const invalid = CareCircle(
          people: [Person(id: '', name: '', colorSeed: -1)],
        );

        harness.repo.controller.add(invalid);
        await Future<void>.delayed(Duration.zero);

        expect(identical(container.read(careCircleProvider), before), isTrue);
        expect(
          container.read(persistenceStatusProvider).phase,
          PersistencePhase.failed,
        );
      },
    );

    test(
      'LocalRepo persists, restores, and rejects corrupt payloads',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = LocalRepo(prefs);
        final circle = seedCircle(DateTime(2026, 7, 11));

        await repo.save(circle);
        final loaded = await repo.load();
        expect(loaded, isNotNull);
        expect(loaded!.toJson(), circle.toJson());

        await prefs.setString('dosekeeper.circle.v3', '{"people": []}');
        expect(await repo.load(), isNull);
      },
    );
  });
}

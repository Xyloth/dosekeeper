/// All shared state lives here as Riverpod providers.
///
/// The shared-state story in one file: every screen watches [careCircleProvider].
/// Patient actions mutate it; caregiver attention, provider history, live
/// Today views, and badges recompute automatically. Screens pass no domain
/// state to one another.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'repo.dart';

/// Both are overridden once during bootstrap (and in tests).
final repoProvider = Provider<CareRepo>(
  (_) => throw UnimplementedError('Repository missing'),
);
final initialCircleProvider = Provider<CareCircle>(
  (_) => throw UnimplementedError('Initial care circle missing'),
);

enum PersistencePhase { saved, saving, failed }

class PersistenceStatus {
  const PersistenceStatus({
    required this.phase,
    this.message,
    this.lastSavedAt,
  });

  const PersistenceStatus.saved({DateTime? at})
    : this(phase: PersistencePhase.saved, lastSavedAt: at);

  final PersistencePhase phase;
  final String? message;
  final DateTime? lastSavedAt;
}

class PersistenceStatusNotifier extends Notifier<PersistenceStatus> {
  @override
  PersistenceStatus build() => const PersistenceStatus.saved();

  void saving() => state = PersistenceStatus(
    phase: PersistencePhase.saving,
    lastSavedAt: state.lastSavedAt,
  );

  void saved(DateTime at) => state = PersistenceStatus.saved(at: at);

  void failed(Object error) => state = PersistenceStatus(
    phase: PersistencePhase.failed,
    message: error.toString(),
    lastSavedAt: state.lastSavedAt,
  );
}

final persistenceStatusProvider =
    NotifierProvider<PersistenceStatusNotifier, PersistenceStatus>(
      PersistenceStatusNotifier.new,
    );

class CareCircleNotifier extends Notifier<CareCircle> {
  Future<void> _saveQueue = Future<void>.value();
  StreamSubscription<CareCircle>? _remoteSubscription;
  var _saveVersion = 0;
  var _pendingSaves = 0;

  @override
  CareCircle build() {
    final repo = ref.watch(repoProvider);
    unawaited(_remoteSubscription?.cancel());
    _remoteSubscription = repo.watch().listen(
      (remote) {
        scheduleMicrotask(() {
          if (!ref.mounted) return;
          try {
            remote.validate();
            // Local optimistic state wins while its ordered save queue drains.
            // A streaming backend will emit the authoritative post-write
            // snapshot afterwards; applying a stale pre-write echo here would
            // make a confirmed tap visibly roll back.
            if (_pendingSaves > 0) return;
            state = remote;
            ref
                .read(persistenceStatusProvider.notifier)
                .saved(ref.read(currentDateTimeProvider));
          } catch (error) {
            ref.read(persistenceStatusProvider.notifier).failed(error);
          }
        });
      },
      onError: (Object error, StackTrace _) =>
          ref.read(persistenceStatusProvider.notifier).failed(error),
    );
    ref.onDispose(() => unawaited(_remoteSubscription?.cancel()));
    return ref.watch(initialCircleProvider);
  }

  Future<void> _set(CareCircle next) {
    next.validate();
    state = next;
    return _queueSave(next);
  }

  Future<void> _queueSave(CareCircle snapshot) {
    final version = ++_saveVersion;
    final repo = ref.read(repoProvider);
    _pendingSaves++;
    ref.read(persistenceStatusProvider.notifier).saving();
    _saveQueue = _saveQueue.then((_) async {
      try {
        await repo.save(snapshot);
        _pendingSaves--;
        if (!ref.mounted) return;
        if (version == _saveVersion) {
          ref
              .read(persistenceStatusProvider.notifier)
              .saved(ref.read(currentDateTimeProvider));
        }
      } catch (error) {
        _pendingSaves--;
        if (!ref.mounted) return;
        if (version == _saveVersion) {
          ref.read(persistenceStatusProvider.notifier).failed(error);
        }
      }
    });
    return _saveQueue;
  }

  Future<void> _putEvent(DoseEvent event) {
    final events = Map<String, DoseEvent>.from(state.events);
    events[event.key] = event;
    return _set(state.copyWith(events: events));
  }

  /// Used by the UI's explicit Undo action; the exact prior timestamp and
  /// late-marked meaning are restored rather than synthesized again.
  Future<void> restoreEvent(DoseEvent event) => _putEvent(event);

  DateTime get _recordedNow => ref.read(currentDateTimeProvider);

  /// Patient taps "Taken" while the dose window is open.
  Future<void> markTaken(
    String personId,
    String medId,
    String date,
    DoseSlot slot,
  ) => _putEvent(
    DoseEvent(
      personId: personId,
      medId: medId,
      date: date,
      slot: slot,
      status: DoseStatus.taken,
      recordedAt: _recordedNow,
    ),
  );

  /// THE QUESTION answer: "I took it, forgot to mark it."
  Future<void> resolveTookIt(
    String personId,
    String medId,
    String date,
    DoseSlot slot,
  ) => _putEvent(
    DoseEvent(
      personId: personId,
      medId: medId,
      date: date,
      slot: slot,
      status: DoseStatus.taken,
      lateMarked: true,
      recordedAt: _recordedNow,
    ),
  );

  /// THE QUESTION answer: "I missed it" — explicitly human-confirmed.
  Future<void> resolveMissedIt(
    String personId,
    String medId,
    String date,
    DoseSlot slot,
  ) => _putEvent(
    DoseEvent(
      personId: personId,
      medId: medId,
      date: date,
      slot: slot,
      status: DoseStatus.missed,
      recordedAt: _recordedNow,
    ),
  );

  /// A human correction removes the answer and restores the default unknown.
  Future<void> clearEvent(
    String personId,
    String medId,
    String date,
    DoseSlot slot,
  ) {
    final key = DoseEvent.keyOf(personId, medId, date, slot);
    if (!state.events.containsKey(key)) return Future<void>.value();
    final events = Map<String, DoseEvent>.from(state.events)..remove(key);
    return _set(state.copyWith(events: events));
  }

  Future<void> retrySave() => _queueSave(state);

  Future<void> resetDemo() =>
      _set(seedCircle(ref.read(currentDateTimeProvider)));
}

final careCircleProvider = NotifierProvider<CareCircleNotifier, CareCircle>(
  CareCircleNotifier.new,
);

abstract interface class AppClock {
  DateTime now();
}

class SystemAppClock implements AppClock {
  const SystemAppClock();

  @override
  DateTime now() => DateTime.now();
}

final appClockProvider = Provider<AppClock>((_) => const SystemAppClock());
final clockRefreshIntervalProvider = Provider<Duration?>(
  (_) => const Duration(seconds: 30),
);

/// Ticks while the app remains open so threshold and calendar-day providers
/// do not freeze at startup. Tests override [appClockProvider] and call refresh.
class CurrentDateTimeNotifier extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    final clock = ref.watch(appClockProvider);
    final refreshInterval = ref.watch(clockRefreshIntervalProvider);
    _timer?.cancel();
    if (refreshInterval != null) {
      _timer = Timer.periodic(refreshInterval, (_) => state = clock.now());
    }
    ref.onDispose(() => _timer?.cancel());
    return clock.now();
  }

  void refresh() => state = ref.read(appClockProvider).now();
}

final currentDateTimeProvider =
    NotifierProvider<CurrentDateTimeNotifier, DateTime>(
      CurrentDateTimeNotifier.new,
    );

class DemoClockState {
  const DemoClockState({required this.hour, required this.followsNow});

  final double hour;
  final bool followsNow;
}

/// Labeled demo control. The 24:00–24:30 range deliberately represents the
/// next-day side of Bedtime's boundary while keeping the occurrence date fixed.
class DemoClockNotifier extends Notifier<DemoClockState> {
  @override
  DemoClockState build() {
    ref.listen(currentDateTimeProvider, (_, next) {
      if (state.followsNow) {
        state = DemoClockState(hour: _hourOf(next), followsNow: true);
      }
    });
    return DemoClockState(
      hour: _hourOf(ref.read(currentDateTimeProvider)),
      followsNow: true,
    );
  }

  static double _hourOf(DateTime dateTime) =>
      dateTime.hour + dateTime.minute / 60.0;

  void set(double hour) =>
      state = DemoClockState(hour: hour.clamp(0.0, 24.5), followsNow: false);

  void resetToNow() => state = DemoClockState(
    hour: _hourOf(ref.read(currentDateTimeProvider)),
    followsNow: true,
  );
}

final demoClockProvider = NotifierProvider<DemoClockNotifier, DemoClockState>(
  DemoClockNotifier.new,
);

String? _firstPersonId(CareCircle circle) => circle.people.firstOrNull?.id;

class SelectedPatientNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.listen(careCircleProvider.select((circle) => circle.people), (
      _,
      people,
    ) {
      if (state != null && people.any((person) => person.id == state)) return;
      state = people.firstOrNull?.id;
    });
    return _firstPersonId(ref.read(careCircleProvider));
  }

  void select(String id) {
    if (ref.read(careCircleProvider).personById(id) != null) state = id;
  }
}

final selectedPatientProvider =
    NotifierProvider<SelectedPatientNotifier, String?>(
      SelectedPatientNotifier.new,
    );

class SelectedProviderPersonNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.listen(careCircleProvider.select((circle) => circle.people), (
      _,
      people,
    ) {
      if (state != null && people.any((person) => person.id == state)) return;
      state = people.firstOrNull?.id;
    });
    return _firstPersonId(ref.read(careCircleProvider));
  }

  void select(String id) {
    if (ref.read(careCircleProvider).personById(id) != null) state = id;
  }
}

final selectedProviderPersonProvider =
    NotifierProvider<SelectedProviderPersonNotifier, String?>(
      SelectedProviderPersonNotifier.new,
    );

class ProviderRangeDaysNotifier extends Notifier<int> {
  @override
  int build() => 14;

  void select(int days) {
    if (const {7, 14, 30}.contains(days)) state = days;
  }
}

final providerRangeDaysProvider =
    NotifierProvider<ProviderRangeDaysNotifier, int>(
      ProviderRangeDaysNotifier.new,
    );

class AppSettings {
  const AppSettings({
    required this.demoClockFollowsNow,
    required this.providerRangeDays,
  });

  final bool demoClockFollowsNow;
  final int providerRangeDays;
}

final settingsProvider = Provider<AppSettings>(
  (ref) => AppSettings(
    demoClockFollowsNow: ref.watch(demoClockProvider).followsNow,
    providerRangeDays: ref.watch(providerRangeDaysProvider),
  ),
);

enum DoseUrgency { scheduled, due, lateReminder, question }

DoseUrgency urgencyFor(DoseSlot slot, double hour) {
  if (slot.isPast(hour)) return DoseUrgency.question;
  if (!slot.contains(hour)) return DoseUrgency.scheduled;
  return slot.progress(hour) < 0.6 ? DoseUrgency.due : DoseUrgency.lateReminder;
}

class ScheduledDose {
  const ScheduledDose({
    required this.date,
    required this.person,
    required this.med,
    required this.slot,
    required this.status,
    required this.lateMarked,
    required this.urgency,
    this.recordedAt,
  });

  final String date;
  final Person person;
  final Med med;
  final DoseSlot slot;
  final DoseStatus status;
  final bool lateMarked;
  final DoseUrgency urgency;
  final DateTime? recordedAt;

  String get key => DoseEvent.keyOf(person.id, med.id, date, slot);
}

List<ScheduledDose> _dosesForDate({
  required CareCircle circle,
  required String personId,
  required String date,
  required double hour,
  bool forceQuestion = false,
}) {
  final person = circle.personById(personId);
  if (person == null) return const [];

  final doses = <ScheduledDose>[];
  for (final schedule in circle.schedules.where(
    (schedule) => schedule.personId == personId && schedule.isActiveOn(date),
  )) {
    final med = circle.medById(schedule.medId);
    if (med == null) continue;
    for (final slot in schedule.slots) {
      final event =
          circle.events[DoseEvent.keyOf(personId, schedule.medId, date, slot)];
      doses.add(
        ScheduledDose(
          date: date,
          person: person,
          med: med,
          slot: slot,
          status: event?.status ?? DoseStatus.notMarked,
          lateMarked: event?.lateMarked ?? false,
          urgency: forceQuestion
              ? DoseUrgency.question
              : urgencyFor(slot, hour),
          recordedAt: event?.recordedAt,
        ),
      );
    }
  }
  doses.sort((a, b) => a.slot.index.compareTo(b.slot.index));
  return doses;
}

final todayDosesProvider = Provider.family<List<ScheduledDose>, String>((
  ref,
  personId,
) {
  final circle = ref.watch(careCircleProvider);
  final date = dateKey(ref.watch(currentDateTimeProvider));
  final hour = ref.watch(demoClockProvider).hour;
  return _dosesForDate(
    circle: circle,
    personId: personId,
    date: date,
    hour: hour,
  );
});

/// Previous-day unresolved occurrences stay answerable after midnight.
final pendingQuestionsProvider = Provider.family<List<ScheduledDose>, String>((
  ref,
  personId,
) {
  final circle = ref.watch(careCircleProvider);
  final now = ref.watch(currentDateTimeProvider);
  final date = dateKey(calendarDay(now, addDays: -1));
  return _dosesForDate(
    circle: circle,
    personId: personId,
    date: date,
    hour: 24.5,
    forceQuestion: true,
  ).where((dose) => dose.status == DoseStatus.notMarked).toList();
});

/// Used by the Patient notification listener so a bedtime occurrence can move
/// from today's late reminder to yesterday's question without losing identity.
final patientActionDosesProvider = Provider.family<List<ScheduledDose>, String>(
  (ref, personId) => [
    ...ref.watch(pendingQuestionsProvider(personId)),
    ...ref.watch(todayDosesProvider(personId)),
  ],
);

/// Attention includes urgent unknowns and confirmed misses. A human answering
/// "missed" therefore changes the alert's meaning/color, never removes it.
final caregiverAlertsProvider = Provider<List<ScheduledDose>>((ref) {
  final circle = ref.watch(careCircleProvider);
  final attention = <ScheduledDose>[];
  for (final person in circle.people) {
    attention.addAll(ref.watch(pendingQuestionsProvider(person.id)));
    attention.addAll(
      ref
          .watch(todayDosesProvider(person.id))
          .where(
            (dose) =>
                dose.status == DoseStatus.missed ||
                (dose.status == DoseStatus.notMarked &&
                    (dose.urgency == DoseUrgency.lateReminder ||
                        dose.urgency == DoseUrgency.question)),
          ),
    );
  }
  attention.sort((a, b) {
    final aRank = a.status == DoseStatus.missed ? 0 : 1;
    final bRank = b.status == DoseStatus.missed ? 0 : 1;
    if (aRank != bRank) return aRank.compareTo(bRank);
    return a.date.compareTo(b.date);
  });
  return attention;
});

/// Red-badge count for one patient's own tab: yesterday's unanswered
/// questions plus today's urgent unknowns that need that person's action.
final patientAttentionCountProvider = Provider.family<int, String>((
  ref,
  personId,
) {
  final pending = ref.watch(pendingQuestionsProvider(personId)).length;
  final urgent = ref
      .watch(todayDosesProvider(personId))
      .where(
        (dose) =>
            dose.status == DoseStatus.notMarked &&
            (dose.urgency == DoseUrgency.lateReminder ||
                dose.urgency == DoseUrgency.question),
      )
      .length;
  return pending + urgent;
});

class AdherenceStats {
  const AdherenceStats({
    required this.taken,
    required this.lateMarked,
    required this.missed,
    required this.notMarked,
  });

  final int taken;
  final int lateMarked;
  final int missed;
  final int notMarked;

  int get scheduled => taken + lateMarked + missed + notMarked;
}

final adherenceProvider =
    Provider.family<AdherenceStats, ({String personId, int days})>((ref, arg) {
      final circle = ref.watch(careCircleProvider);
      final today = ref.watch(currentDateTimeProvider);
      var taken = 0;
      var late = 0;
      var missed = 0;
      var notMarked = 0;

      for (var i = 1; i <= arg.days; i++) {
        final date = dateKey(calendarDay(today, addDays: -i));
        for (final schedule in circle.schedules.where(
          (schedule) =>
              schedule.personId == arg.personId && schedule.isActiveOn(date),
        )) {
          for (final slot in schedule.slots) {
            final event =
                circle.events[DoseEvent.keyOf(
                  arg.personId,
                  schedule.medId,
                  date,
                  slot,
                )];
            switch (event?.status) {
              case DoseStatus.taken:
                event!.lateMarked ? late++ : taken++;
              case DoseStatus.missed:
                missed++;
              case DoseStatus.notMarked || null:
                notMarked++;
            }
          }
        }
      }
      return AdherenceStats(
        taken: taken,
        lateMarked: late,
        missed: missed,
        notMarked: notMarked,
      );
    });

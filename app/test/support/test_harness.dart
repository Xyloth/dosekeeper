import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dosekeeper/models.dart';
import 'package:dosekeeper/repo.dart';
import 'package:dosekeeper/state.dart';

class MutableClock implements AppClock {
  MutableClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

class RecordingRepo implements CareRepo {
  final controller = StreamController<CareCircle>.broadcast(sync: true);
  final snapshots = <CareCircle>[];
  CareCircle? stored;
  int failuresRemaining = 0;
  int activeSaves = 0;
  int maxConcurrentSaves = 0;
  Duration saveDelay = Duration.zero;
  Completer<void>? saveGate;

  @override
  Future<CareCircle?> load() async => stored;

  @override
  Future<void> save(CareCircle circle) async {
    activeSaves++;
    if (activeSaves > maxConcurrentSaves) {
      maxConcurrentSaves = activeSaves;
    }
    try {
      if (saveGate case final gate?) await gate.future;
      if (saveDelay != Duration.zero) await Future<void>.delayed(saveDelay);
      if (failuresRemaining > 0) {
        failuresRemaining--;
        throw StateError('simulated write failure');
      }
      stored = circle;
      snapshots.add(circle);
    } finally {
      activeSaves--;
    }
  }

  @override
  Stream<CareCircle> watch() => controller.stream;

  Future<void> dispose() => controller.close();
}

class Harness {
  Harness({required this.container, required this.clock, required this.repo});

  final ProviderContainer container;
  final MutableClock clock;
  final RecordingRepo repo;
}

Harness makeHarness({DateTime? now, RecordingRepo? repo, CareCircle? circle}) {
  final clock = MutableClock(now ?? DateTime(2026, 7, 11, 15, 30));
  final recordingRepo = repo ?? RecordingRepo();
  final initial = circle ?? seedCircle(clock.now());
  final container = ProviderContainer(
    overrides: [
      appClockProvider.overrideWithValue(clock),
      clockRefreshIntervalProvider.overrideWithValue(null),
      repoProvider.overrideWithValue(recordingRepo),
      initialCircleProvider.overrideWithValue(initial),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await recordingRepo.dispose();
  });
  container.read(careCircleProvider);
  return Harness(container: container, clock: clock, repo: recordingRepo);
}

ScheduledDose findDose(
  List<ScheduledDose> doses,
  String medId,
  DoseSlot slot,
) => doses.singleWhere((dose) => dose.med.id == medId && dose.slot == slot);

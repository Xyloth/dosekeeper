import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dosekeeper/main.dart';
import 'package:dosekeeper/models.dart';
import 'package:dosekeeper/state.dart';

import 'support/test_harness.dart';

Future<Harness> pumpDoseKeeper(
  WidgetTester tester, {
  DateTime? now,
  RecordingRepo? repo,
}) async {
  final harness = makeHarness(now: now, repo: repo);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const DoseKeeperApp(),
    ),
  );
  await tester.pump();
  return harness;
}

Future<void> selectRole(WidgetTester tester, String role) async {
  final finder = find.byKey(ValueKey('role-${role.toLowerCase()}'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<Finder> ensureKeyInVisibleList(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      finder,
      find.byType(ListView),
      const Offset(0, -220),
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  return finder;
}

Future<void> tapPatientControl(WidgetTester tester, String key) async {
  final finder = await ensureKeyInVisibleList(tester, key);
  await tester.tap(finder);
}

Finder dialogButton(String label) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a Patient tap becomes live truth in Caregiver and Provider', (
    tester,
  ) async {
    final harness = await pumpDoseKeeper(
      tester,
      now: DateTime(2026, 7, 11, 20, 30),
    );
    final container = harness.container;
    const date = '2026-07-11';
    final key = DoseEvent.keyOf('p-rose', 'm-met', date, DoseSlot.evening);
    final attentionBefore = container.read(caregiverAlertsProvider).length;

    await tapPatientControl(tester, 'patient-taken-$key');
    await tester.pump();

    expect(
      container
          .read(careCircleProvider)
          .statusOf('p-rose', 'm-met', date, DoseSlot.evening),
      DoseStatus.taken,
    );
    expect(container.read(caregiverAlertsProvider).length, attentionBefore - 1);

    await selectRole(tester, 'Caregiver');
    expect(find.byKey(ValueKey('caregiver-alert-$key')), findsNothing);
    final caregiverDose = await ensureKeyInVisibleList(
      tester,
      'caregiver-dose-$key',
    );
    expect(caregiverDose, findsOneWidget);
    expect(
      find.descendant(
        of: caregiverDose,
        matching: find.textContaining('Taken'),
      ),
      findsOneWidget,
    );

    await selectRole(tester, 'Provider');
    final providerDose = find.byKey(ValueKey('provider-today-$key'));
    expect(providerDose, findsOneWidget);
    expect(
      find.descendant(of: providerDose, matching: find.text('Taken')),
      findsOneWidget,
    );
  });

  testWidgets('a confirmed miss stays in attention and Provider Today', (
    tester,
  ) async {
    final harness = await pumpDoseKeeper(
      tester,
      now: DateTime(2026, 7, 11, 22),
    );
    final container = harness.container;
    const date = '2026-07-11';
    final key = DoseEvent.keyOf('p-rose', 'm-met', date, DoseSlot.evening);
    final attentionBefore = container.read(caregiverAlertsProvider).length;

    await tapPatientControl(tester, 'question-missed-$key');
    await tester.pump();

    expect(container.read(caregiverAlertsProvider).length, attentionBefore);
    expect(
      container.read(careCircleProvider).events[key]!.status,
      DoseStatus.missed,
    );

    await selectRole(tester, 'Caregiver');
    final alert = find.byKey(ValueKey('caregiver-alert-$key'));
    expect(alert, findsOneWidget);
    expect(
      find.descendant(of: alert, matching: find.textContaining('explicitly')),
      findsOneWidget,
    );

    await selectRole(tester, 'Provider');
    final providerDose = find.byKey(ValueKey('provider-today-$key'));
    expect(
      find.descendant(of: providerDose, matching: find.text('Missed')),
      findsOneWidget,
    );
  });

  testWidgets('Leo stays selected after recording his dose', (tester) async {
    final harness = await pumpDoseKeeper(tester, now: DateTime(2026, 7, 11, 8));
    const date = '2026-07-11';
    final key = DoseEvent.keyOf('p-leo', 'm-inh', date, DoseSlot.morning);

    await tester.tap(find.byKey(const ValueKey('patient-p-leo')));
    await tester.pump();
    await tapPatientControl(tester, 'patient-taken-$key');
    await tester.pump();

    expect(harness.container.read(selectedPatientProvider), 'p-leo');
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('patient-p-leo')),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('multiple threshold questions are serialized, never stacked', (
    tester,
  ) async {
    final harness = await pumpDoseKeeper(tester, now: DateTime(2026, 7, 11, 5));
    final container = harness.container;
    container.read(demoClockProvider.notifier).set(12);
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(dialogButton('I took it — forgot to mark'));
    await tester.pumpAndSettle();

    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'the second unresolved morning dose should be next',
    );
    await tester.tap(dialogButton('I missed this dose'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      container
          .read(careCircleProvider)
          .events[DoseEvent.keyOf(
            'p-rose',
            'm-lis',
            '2026-07-11',
            DoseSlot.morning,
          )]!
          .status,
      DoseStatus.taken,
    );
    expect(
      container
          .read(careCircleProvider)
          .events[DoseEvent.keyOf(
            'p-rose',
            'm-met',
            '2026-07-11',
            DoseSlot.morning,
          )]!
          .status,
      DoseStatus.missed,
    );
  });

  testWidgets('Not now closes the queue without changing any answer', (
    tester,
  ) async {
    final harness = await pumpDoseKeeper(tester, now: DateTime(2026, 7, 11, 5));
    harness.container.read(demoClockProvider.notifier).set(12);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(dialogButton('Not now'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      harness.container
          .read(careCircleProvider)
          .statusOf('p-rose', 'm-lis', '2026-07-11', DoseSlot.morning),
      DoseStatus.notMarked,
    );
    expect(
      harness.container
          .read(careCircleProvider)
          .statusOf('p-rose', 'm-met', '2026-07-11', DoseSlot.morning),
      DoseStatus.notMarked,
    );
  });

  testWidgets('correction can be undone with the exact original event', (
    tester,
  ) async {
    final harness = await pumpDoseKeeper(
      tester,
      now: DateTime(2026, 7, 11, 20, 30),
    );
    const date = '2026-07-11';
    final key = DoseEvent.keyOf('p-rose', 'm-met', date, DoseSlot.evening);

    await tapPatientControl(tester, 'patient-taken-$key');
    await tester.pump();
    final original = harness.container.read(careCircleProvider).events[key]!;

    await tapPatientControl(tester, 'correct-$key');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct to missed'));
    await tester.pumpAndSettle();
    expect(
      harness.container.read(careCircleProvider).events[key]!.status,
      DoseStatus.missed,
    );

    await tester.tap(find.text('Undo'));
    await tester.pump();
    final restored = harness.container.read(careCircleProvider).events[key]!;
    expect(restored.status, original.status);
    expect(restored.lateMarked, original.lateMarked);
    expect(restored.recordedAt, original.recordedAt);
  });

  testWidgets('all five views are reachable and retain shared state', (
    tester,
  ) async {
    await pumpDoseKeeper(tester, now: DateTime(2026, 7, 11, 15));
    expect(find.text('Patient view'), findsOneWidget);

    await selectRole(tester, 'Caregiver');
    expect(find.text('Caregiver dashboard'), findsOneWidget);
    await selectRole(tester, 'Provider');
    expect(find.text('Provider appointment view'), findsOneWidget);
    await selectRole(tester, 'Circle');
    expect(find.text('Care Circle'), findsOneWidget);
    await selectRole(tester, 'Settings');
    expect(find.text('Settings & about'), findsOneWidget);
    expect(find.textContaining('not a medical device'), findsOneWidget);
  });

  testWidgets('narrow, large-text layout reaches every view without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await pumpDoseKeeper(tester, now: DateTime(2026, 7, 11, 20, 30));
    expect(tester.takeException(), isNull);
    for (final role in [
      'Caregiver',
      'Provider',
      'Circle',
      'Settings',
      'Patient',
    ]) {
      await selectRole(tester, role);
      expect(tester.takeException(), isNull, reason: '$role overflowed');
    }
  });

  testWidgets('dose state and demo time have non-color semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpDoseKeeper(tester, now: DateTime(2026, 7, 11, 20, 30));

    expect(find.bySemanticsLabel('Demo time of day'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(
        const ValueKey('patient-dose-p-rose|m-met|2026-07-11|evening'),
      ),
      find.byType(ListView),
      const Offset(0, -220),
    );
    expect(
      find.bySemanticsLabel(
        RegExp('Grandma Rose, Metformin, Evening.*Still not marked'),
      ),
      findsWidgets,
    );
    handle.dispose();
  });

  testWidgets('save failure is visible and retryable', (tester) async {
    final repo = RecordingRepo()..failuresRemaining = 1;
    final harness = await pumpDoseKeeper(
      tester,
      now: DateTime(2026, 7, 11, 20, 30),
      repo: repo,
    );
    final key = DoseEvent.keyOf(
      'p-rose',
      'm-met',
      '2026-07-11',
      DoseSlot.evening,
    );

    await tapPatientControl(tester, 'patient-taken-$key');
    await tester.pump();
    expect(
      find.text('Saved on screen, but not on this device yet.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry save'));
    await tester.pump();
    expect(
      harness.container.read(persistenceStatusProvider).phase,
      PersistencePhase.saved,
    );
    expect(
      find.text('Saved on screen, but not on this device yet.'),
      findsNothing,
    );
  });
}

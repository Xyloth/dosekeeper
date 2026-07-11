import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dosekeeper/main.dart';
import 'package:dosekeeper/models.dart';
import 'package:dosekeeper/repo.dart';

import 'support/test_harness.dart';

final _captureRequested =
    Platform.environment['DOSEKEEPER_CAPTURE_SCREENSHOTS'] == 'true';
final _captureNow = DateTime(2026, 7, 11, 20, 30);

Future<void> _loadCaptureFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT is required for release captures.');
  }

  Future<void> load(String family, String filename) async {
    final file = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/$filename',
    );
    final bytes = ByteData.sublistView(file.readAsBytesSync());
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }

  await load('Roboto', 'Roboto-Regular.ttf');
  await load('MaterialIcons', 'MaterialIcons-Regular.otf');
}

CareCircle _captureCircle({bool includeMiss = false}) {
  final circle = seedCircle(_captureNow);
  final taken = DoseEvent(
    personId: 'p-rose',
    medId: 'm-lis',
    date: '2026-07-11',
    slot: DoseSlot.morning,
    status: DoseStatus.taken,
    recordedAt: _captureNow,
  );
  final events = {...circle.events, taken.key: taken};
  if (includeMiss) {
    final missed = DoseEvent(
      personId: 'p-rose',
      medId: 'm-met',
      date: '2026-07-11',
      slot: DoseSlot.evening,
      status: DoseStatus.missed,
      recordedAt: _captureNow,
    );
    events[missed.key] = missed;
  }
  return circle.copyWith(events: events);
}

Future<void> _captureRole(
  WidgetTester tester, {
  required int role,
  required String filename,
  bool includeMiss = false,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final harness = makeHarness(
    now: _captureNow,
    circle: _captureCircle(includeMiss: includeMiss),
  );
  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: RepaintBoundary(
        key: boundaryKey,
        child: DoseKeeperApp(initialRole: role, fontFamily: 'Roboto'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  await expectLater(
    find.byKey(boundaryKey),
    matchesGoldenFile('../../docs/screenshots/$filename'),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    if (_captureRequested) await _loadCaptureFonts();
  });

  // Tab indices: patients occupy 0..n-1 (seed family n=2), then the four
  // shared views. Rose's patient tab is 0; Caregiver starts at 2.
  testWidgets(
    'capture Patient release view',
    (tester) => _captureRole(tester, role: 0, filename: 'patient.png'),
    skip: !_captureRequested,
  );
  testWidgets(
    'capture Caregiver release view',
    (tester) => _captureRole(
      tester,
      role: 2,
      filename: 'caregiver.png',
      includeMiss: true,
    ),
    skip: !_captureRequested,
  );
  testWidgets(
    'capture Provider release view',
    (tester) => _captureRole(
      tester,
      role: 3,
      filename: 'provider.png',
      includeMiss: true,
    ),
    skip: !_captureRequested,
  );
  testWidgets(
    'capture Circle release view',
    (tester) => _captureRole(tester, role: 4, filename: 'circle.png'),
    skip: !_captureRequested,
  );
  testWidgets(
    'capture Settings release view',
    (tester) => _captureRole(tester, role: 5, filename: 'settings.png'),
    skip: !_captureRequested,
  );
}

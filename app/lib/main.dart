import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repo.dart';
import 'screens/caregiver_view.dart';
import 'screens/patient_view.dart';
import 'screens/people_view.dart';
import 'screens/provider_view.dart';
import 'screens/settings_view.dart';
import 'state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final repo = LocalRepo(prefs);
  final saved = await repo.load();
  final initial = saved ?? seedCircle(DateTime.now());
  runApp(
    ProviderScope(
      overrides: [
        repoProvider.overrideWithValue(repo),
        initialCircleProvider.overrideWithValue(initial),
      ],
      child: const DoseKeeperApp(),
    ),
  );
}

class DoseKeeperApp extends StatelessWidget {
  const DoseKeeperApp({super.key, this.initialRole = 0, this.fontFamily});

  final int initialRole;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DoseKeeper',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C7B)),
      scaffoldBackgroundColor: const Color(0xFFF8FAF9),
      fontFamily: fontFamily,
      useMaterial3: true,
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: Color(0x22000000)),
        ),
      ),
    ),
    home: RoleShell(initialRole: initialRole),
  );
}

class _RoleDestination {
  const _RoleDestination({
    required this.label,
    required this.icon,
    required this.view,
    required this.keyId,
    this.badgeCount = 0,
    this.badgeSemantics,
  });

  final String label;
  final IconData icon;
  final Widget view;
  final String keyId;
  final int badgeCount;
  final String? badgeSemantics;
}

/// One running app, one Riverpod source of truth — and a top-level tab per
/// PATIENT (James's ruling): each person in the circle gets their own tab
/// with their own red attention badge, alongside Caregiver / Provider /
/// Circle / Settings. No sub-selection inside the patient view.
class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({super.key, this.initialRole = 0});

  final int initialRole;

  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  late int _role;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(
      careCircleProvider.select((circle) => circle.people),
    );
    final alerts = ref.watch(caregiverAlertsProvider);
    final persistence = ref.watch(persistenceStatusProvider);
    final wide = MediaQuery.sizeOf(context).width >= 520;

    final totalTabs = people.length + 4;
    final role = _role.clamp(0, totalTabs - 1);

    final destinations = <_RoleDestination>[
      for (var i = 0; i < people.length; i++)
        _RoleDestination(
          label: people[i].name,
          icon: Icons.medication_outlined,
          keyId: 'role-patient-${people[i].id}',
          badgeCount: ref.watch(patientAttentionCountProvider(people[i].id)),
          badgeSemantics:
              '${people[i].name}, '
              '${ref.watch(patientAttentionCountProvider(people[i].id))} '
              'attention items',
          view: PatientView(
            key: ValueKey('patient-view-${people[i].id}'),
            personId: people[i].id,
            active: role == i,
          ),
        ),
      _RoleDestination(
        label: 'Caregiver',
        icon: Icons.favorite_outline,
        keyId: 'role-caregiver',
        badgeCount: alerts.length,
        badgeSemantics: 'Caregiver, ${alerts.length} attention items',
        view: const CaregiverView(),
      ),
      const _RoleDestination(
        label: 'Provider',
        icon: Icons.badge_outlined,
        keyId: 'role-provider',
        view: ProviderTimelineView(),
      ),
      const _RoleDestination(
        label: 'Circle',
        icon: Icons.group_outlined,
        keyId: 'role-circle',
        view: PeopleView(),
      ),
      const _RoleDestination(
        label: 'Settings',
        icon: Icons.settings_outlined,
        keyId: 'role-settings',
        view: SettingsView(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DoseKeeper',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'DEMO · FICTIONAL FAMILY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Demo with a fictional family',
                child: Icon(Icons.science_outlined),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _RoleSwitcher(
            selected: role,
            destinations: destinations,
            onSelected: (value) {
              if (value < people.length) {
                ref
                    .read(selectedPatientProvider.notifier)
                    .select(people[value].id);
              }
              setState(() => _role = value);
            },
          ),
          const DemoClockBar(),
          if (persistence.phase == PersistencePhase.failed)
            _PersistenceFailureBanner(message: persistence.message),
          const Divider(height: 1),
          Expanded(
            child: IndexedStack(
              index: role,
              children: [
                for (final destination in destinations) destination.view,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleSwitcher extends StatelessWidget {
  const _RoleSwitcher({
    required this.selected,
    required this.destinations,
    required this.onSelected,
  });

  final int selected;
  final List<_RoleDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DEMO MODE · SWITCH VIEW',
          style: TextStyle(
            color: Theme.of(context).hintColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 5),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: [
              for (var i = 0; i < destinations.length; i++)
                ButtonSegment(
                  value: i,
                  label: Text(
                    destinations[i].label,
                    key: ValueKey(destinations[i].keyId),
                  ),
                  icon: destinations[i].badgeSemantics != null
                      ? Semantics(
                          label: destinations[i].badgeSemantics,
                          child: Badge(
                            isLabelVisible: destinations[i].badgeCount > 0,
                            label: Text('${destinations[i].badgeCount}'),
                            child: Icon(destinations[i].icon),
                          ),
                        )
                      : Icon(destinations[i].icon),
                ),
            ],
            selected: {selected},
            onSelectionChanged: (values) => onSelected(values.first),
          ),
        ),
      ],
    ),
  );
}

class _PersistenceFailureBanner extends ConsumerWidget {
  const _PersistenceFailureBanner({this.message});

  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.errorContainer,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Icon(
          Icons.sync_problem,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        Text(
          'Saved on screen, but not on this device yet.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextButton(
          onPressed: () => ref.read(careCircleProvider.notifier).retrySave(),
          child: const Text('Retry save'),
        ),
        if (message != null)
          Tooltip(
            message: message!,
            child: const Icon(Icons.info_outline, size: 18),
          ),
      ],
    ),
  );
}

/// Labeled demo control; the +1 range crosses Bedtime's midnight boundary.
class DemoClockBar extends ConsumerWidget {
  const DemoClockBar({super.key});

  static String labelFor(double hour) {
    final displayHour = hour % 24;
    final h = displayHour.floor();
    final m = ((displayHour - h) * 60).round();
    final clock =
        '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} '
        '${h < 12 ? 'AM' : 'PM'}';
    return hour >= 24 ? '$clock · next day' : clock;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(demoClockProvider);
    final label = labelFor(clock.hour);
    return Container(
      color: const Color(0xFFFFF6E5),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.schedule, size: 17, color: Color(0xFF8A6D1D)),
              const Text(
                'DEMO CLOCK',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A6D1D),
                ),
              ),
              if (clock.followsNow)
                const Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('following now', style: TextStyle(fontSize: 10)),
                ),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              TextButton(
                onPressed: clock.followsNow
                    ? null
                    : () => ref.read(demoClockProvider.notifier).resetToNow(),
                child: const Text('now'),
              ),
            ],
          ),
          Semantics(
            label: 'Demo time of day',
            value: label,
            child: Slider(
              key: const ValueKey('demo-clock-slider'),
              value: clock.hour.clamp(5, 24.5),
              min: 5,
              max: 24.5,
              divisions: 78,
              label: label,
              semanticFormatterCallback: (_) => label,
              onChanged: (value) =>
                  ref.read(demoClockProvider.notifier).set(value),
            ),
          ),
        ],
      ),
    );
  }
}

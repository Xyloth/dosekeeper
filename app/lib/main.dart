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
  const _RoleDestination(this.label, this.icon, this.view);

  final String label;
  final IconData icon;
  final Widget view;
}

/// One running app, five perspectives, and one Riverpod source of truth.
class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({super.key, this.initialRole = 0});

  final int initialRole;

  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  static const _destinations = [
    _RoleDestination('Patient', Icons.medication_outlined, PatientView()),
    _RoleDestination('Caregiver', Icons.favorite_outline, CaregiverView()),
    _RoleDestination('Provider', Icons.badge_outlined, ProviderTimelineView()),
    _RoleDestination('Circle', Icons.group_outlined, PeopleView()),
    _RoleDestination('Settings', Icons.settings_outlined, SettingsView()),
  ];

  late int _role;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole.clamp(0, _destinations.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(caregiverAlertsProvider);
    final persistence = ref.watch(persistenceStatusProvider);
    final wide = MediaQuery.sizeOf(context).width >= 520;

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
            selected: _role,
            attentionCount: alerts.length,
            destinations: _destinations,
            onSelected: (value) => setState(() => _role = value),
          ),
          const DemoClockBar(),
          if (persistence.phase == PersistencePhase.failed)
            _PersistenceFailureBanner(message: persistence.message),
          const Divider(height: 1),
          Expanded(
            child: IndexedStack(
              index: _role,
              children: [
                for (final destination in _destinations) destination.view,
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
    required this.attentionCount,
    required this.destinations,
    required this.onSelected,
  });

  final int selected;
  final int attentionCount;
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
                    key: ValueKey(
                      'role-${destinations[i].label.toLowerCase()}',
                    ),
                  ),
                  icon: i == 1
                      ? Semantics(
                          label: 'Caregiver, $attentionCount attention items',
                          child: Badge(
                            isLabelVisible: attentionCount > 0,
                            label: Text('$attentionCount'),
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

/// Demo controls, persistence health, and honest product boundaries.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final persistence = ref.watch(persistenceStatusProvider);

    return ListView(
      key: const PageStorageKey('settings-view'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Settings & about',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        _InfoCard(
          icon: Icons.shield_outlined,
          title: 'Local, fictional, and intentionally limited',
          children: const [
            Text(
              'DoseKeeper v0.1 is an offline coordination demo using a '
              'fictional family. It has no accounts, cloud sync, push '
              'notifications, drug database, dosage advice, or PHI workflow.',
            ),
            SizedBox(height: 8),
            Text(
              'It is not a medical device and does not provide medical advice.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        _InfoCard(
          icon: persistence.phase == PersistencePhase.failed
              ? Icons.sync_problem
              : Icons.save_outlined,
          title: 'On-device persistence',
          children: [
            Row(
              children: [
                Icon(
                  _persistenceIcon(persistence.phase),
                  color: _persistenceColor(context, persistence.phase),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _persistenceLabel(persistence.phase),
                    key: const ValueKey('persistence-status'),
                  ),
                ),
                if (persistence.phase == PersistencePhase.failed)
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(careCircleProvider.notifier).retrySave(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The current care circle is stored as validated JSON through a '
              'repository interface. No data leaves this device in v0.1.',
            ),
          ],
        ),
        _InfoCard(
          icon: Icons.schedule,
          title: 'Demo clock',
          children: [
            Text(
              settings.demoClockFollowsNow
                  ? 'The demo currently follows real local time.'
                  : 'The demo time is detached from real time.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Drag the amber clock above to demonstrate due, window-closing, '
              'and question states. “Next day” exists so the Bedtime window '
              'can cross midnight without changing the demo date.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: settings.demoClockFollowsNow
                  ? null
                  : () => ref.read(demoClockProvider.notifier).resetToNow(),
              icon: const Icon(Icons.update),
              label: const Text('Return clock to now'),
            ),
          ],
        ),
        _InfoCard(
          icon: Icons.restart_alt,
          title: 'Example family',
          children: [
            const Text(
              'Reset Grandma Rose and Leo to the deterministic fictional '
              '10-day history. This replaces any demo answers recorded here.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('reset-demo-button'),
              onPressed: () => _confirmReset(context, ref),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset fictional example family'),
            ),
          ],
        ),
        _InfoCard(
          icon: Icons.account_tree_outlined,
          title: 'Architecture at a glance',
          children: const [
            Text(
              'Patient actions update CareCircleNotifier, which queues a '
              'repository save while Riverpod recomputes Today, attention, '
              'history, and settings views.',
            ),
            SizedBox(height: 8),
            Text(
              'A repository watch stream is already part of the contract for '
              'a future Firestore implementation; the UI remains unchanged.',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset the fictional family?'),
        content: const Text(
          'This clears answers recorded during the demo and rebuilds the '
          'example history relative to today.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset demo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(careCircleProvider.notifier).resetDemo();
    ref.read(demoClockProvider.notifier).resetToNow();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fictional example family reset.')),
    );
  }

  static IconData _persistenceIcon(PersistencePhase phase) => switch (phase) {
    PersistencePhase.saved => Icons.check_circle_outline,
    PersistencePhase.saving => Icons.sync,
    PersistencePhase.failed => Icons.error_outline,
  };

  static Color _persistenceColor(
    BuildContext context,
    PersistencePhase phase,
  ) => switch (phase) {
    PersistencePhase.saved => Colors.green.shade700,
    PersistencePhase.saving => Theme.of(context).colorScheme.primary,
    PersistencePhase.failed => Theme.of(context).colorScheme.error,
  };

  static String _persistenceLabel(PersistencePhase phase) => switch (phase) {
    PersistencePhase.saved => 'Saved on this device',
    PersistencePhase.saving => 'Saving on this device…',
    PersistencePhase.failed => 'Save failed — your on-screen state remains',
  };
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

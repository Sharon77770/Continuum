import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';

import '../../../app/theme.dart';
import '../../../app/app_strings.dart';
import '../../../app/navigation.dart';
import '../../../state/locale_controller.dart';
import '../../../state/workspace_controller.dart';
import 'studio_navigation.dart';
import 'studio_sections.dart';
import 'studio_sidebar.dart';

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key, required this.worldId});
  final String? worldId;

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  StudioSection _section = StudioSection.overview;

  @override
  Widget build(BuildContext context) {
    final WorkspaceState workspace = ref.watch(workspaceProvider);
    final AppStrings strings = AppStrings(ref.watch(localeProvider));
    final world = workspace.worlds
            .where((item) => item.id == widget.worldId)
            .firstOrNull ??
        workspace.currentWorld;
    if (world == null) {
      return Scaffold(body: Center(child: Text(strings.text('no_world'))));
    }
    if (workspace.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(workspace.errorMessage!)));
        }
      });
    }
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            StudioSidebar(world: world, selected: _section, onSelect: _select),
            Expanded(
              child: Column(
                children: [
                  _StudioTopBar(
                    worldName: world.name,
                    section: _section,
                    strings: strings,
                    autosaveStatus: workspace.autosaveStatus,
                    onLibrary: () => ref
                        .read(navigationProvider.notifier)
                        .goTo(AppDestination.library),
                    onSettings: () => ref
                        .read(navigationProvider.notifier)
                        .openSettings(SettingsReturnDestination.studio),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: _buildSection(world),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(World world) => switch (_section) {
        StudioSection.overview => OverviewEditor(
            world: world,
            onChanged: ref.read(workspaceProvider.notifier).updateCurrentWorld,
          ),
        StudioSection.lore => LoreEditor(
            world: world,
            onChanged: ref.read(workspaceProvider.notifier).updateCurrentWorld,
          ),
        StudioSection.characters => CharactersEditor(
            world: world,
            onChanged: ref.read(workspaceProvider.notifier).updateCurrentWorld,
          ),
        StudioSection.locations => LocationsEditor(
            world: world,
            onChanged: ref.read(workspaceProvider.notifier).updateCurrentWorld,
          ),
        StudioSection.player => PlayerDefinitionEditor(
            world: world,
            onChanged: ref.read(workspaceProvider.notifier).updateCurrentWorld,
          ),
        StudioSection.opening => OpeningDefinitionEditor(
            world: world,
            onChanged: ref.read(workspaceProvider.notifier).updateCurrentWorld,
          ),
        _ => _PlaceholderSection(
            title: AppStrings(ref.read(localeProvider)).text(
              'studio_${_section.name}',
            ),
            subtitle:
                AppStrings(ref.read(localeProvider)).text('waiting_to_write'),
          ),
      };

  void _select(StudioSection section) {
    ref.read(workspaceProvider.notifier).flushPendingChanges();
    setState(() => _section = section);
  }
}

class _StudioTopBar extends StatelessWidget {
  const _StudioTopBar(
      {required this.worldName,
      required this.section,
      required this.strings,
      required this.onSettings,
      required this.onLibrary,
      required this.autosaveStatus});
  final String worldName;
  final StudioSection section;
  final AppStrings strings;
  final VoidCallback onSettings;
  final VoidCallback onLibrary;
  final AutosaveStatus autosaveStatus;

  @override
  Widget build(BuildContext context) => Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF292A26))),
        ),
        child: Row(
          children: [
            Text(
              worldName.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                color: ContinuumTheme.muted,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(
                Icons.chevron_right,
                size: 14,
                color: ContinuumTheme.muted,
              ),
            ),
            Text(
              strings.text('studio_${section.name}'),
              style: const TextStyle(fontSize: 12, color: ContinuumTheme.text),
            ),
            const Spacer(),
            Text(
              switch (autosaveStatus) {
                AutosaveStatus.saving => strings.text('saving'),
                AutosaveStatus.saved => strings.text('saved'),
                AutosaveStatus.failed => strings.text('save_failed'),
                AutosaveStatus.idle => ''
              },
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                color: ContinuumTheme.muted,
              ),
            ),
            IconButton(
              tooltip: strings.text('library'),
              onPressed: onLibrary,
              icon: const Icon(Icons.arrow_back, size: 17),
            ),
            IconButton(
              tooltip: strings.text('settings'),
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined, size: 17),
            ),
          ],
        ),
      );
}

class _PlaceholderSection extends StatelessWidget {
  const _PlaceholderSection({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}

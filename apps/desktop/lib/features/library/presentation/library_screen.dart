import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';

import '../../../app/app_strings.dart';
import '../../../app/navigation.dart';
import '../../../app/theme.dart';
import '../../../state/locale_controller.dart';
import '../../../state/workspace_controller.dart';
import '../../novel/application/novel_controller.dart';
import '../../models/application/model_manager_controller.dart';
import 'world_list_item.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WorkspaceState workspace = ref.watch(workspaceProvider);
    final ModelManagerState modelState =
        ref.watch(modelManagerControllerProvider);
    final bool isGenerating = ref.watch(novelControllerProvider).isGenerating;
    final AppStrings strings = AppStrings(ref.watch(localeProvider));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: CustomScrollView(
              slivers: [
                if (workspace.loadStatus == WorkspaceLoadStatus.loading)
                  const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 1)),
                if (workspace.errorMessage != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(44, 16, 44, 0),
                    sliver: SliverToBoxAdapter(
                        child: Text(workspace.errorMessage!,
                            style: const TextStyle(color: Color(0xFFE0A38C)))),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(44, 28, 44, 0),
                  sliver: SliverToBoxAdapter(
                    child: _LibraryHeader(
                      strings: strings,
                      onImport: () => _importScenario(context, ref, strings),
                      onCreate: () => ref
                          .read(navigationProvider.notifier)
                          .goTo(AppDestination.createWorld),
                      onSettings: () => ref
                          .read(navigationProvider.notifier)
                          .openSettings(SettingsReturnDestination.library),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(44, 76, 44, 18),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      strings.text('your_worlds'),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                ),
                if (workspace.loadStatus == WorkspaceLoadStatus.ready &&
                    !modelState.isLoading &&
                    modelState.selection == null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(44, 0, 44, 20),
                    sliver: SliverToBoxAdapter(
                      child: Card(
                        color: ContinuumTheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_stories_outlined,
                                  color: ContinuumTheme.accent),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        strings.text('model_onboarding_title')),
                                    const SizedBox(height: 4),
                                    Text(strings.text('model_onboarding_body')),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: () => ref
                                    .read(navigationProvider.notifier)
                                    .goTo(AppDestination.models),
                                child: Text(strings.text('choose_model')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  sliver: workspace.worlds.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 35),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      workspace.loadStatus ==
                                              WorkspaceLoadStatus.failed
                                          ? 'World storage is unavailable.'
                                          : 'No worlds have been created yet.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 10),
                                  Text(
                                      workspace.loadStatus ==
                                              WorkspaceLoadStatus.failed
                                          ? (workspace.errorMessage ??
                                              'Check the local database permissions and restart Continuum.')
                                          : 'Begin with a place only you could imagine.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium),
                                  const SizedBox(height: 18),
                                  FilledButton.icon(
                                      onPressed: workspace.loadStatus ==
                                              WorkspaceLoadStatus.ready
                                          ? () => ref
                                              .read(navigationProvider.notifier)
                                              .goTo(AppDestination.createWorld)
                                          : null,
                                      icon: const Icon(Icons.add),
                                      label:
                                          Text(strings.text('create_world'))),
                                ]),
                          ),
                        )
                      : SliverList.separated(
                          itemCount: workspace.worlds.length + 1,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: Color(0xFF292A26)),
                          itemBuilder: (BuildContext context, int index) {
                            if (index == workspace.worlds.length) {
                              return WorldListItem.create(
                                onCreate: () => ref
                                    .read(navigationProvider.notifier)
                                    .goTo(AppDestination.createWorld),
                              );
                            }
                            final World world = workspace.worlds[index];
                            final List<Campaign> worldCampaigns = workspace
                                .campaigns
                                .where(
                                    (Campaign item) => item.worldId == world.id)
                                .toList()
                              ..sort((Campaign left, Campaign right) => right
                                  .lastPlayedAt
                                  .compareTo(left.lastPlayedAt));
                            return WorldListItem(
                              world: world,
                              status:
                                  [...world.genre, ...world.tone].join(' · '),
                              primaryLabel: strings.text('open_studio'),
                              onOpen: () {
                                _openWorld(context, ref, world.id);
                              },
                              campaign: worldCampaigns.firstOrNull,
                              campaigns: worldCampaigns,
                              onContinue: worldCampaigns.isEmpty || isGenerating
                                  ? null
                                  : () => _continueGame(
                                      context, ref, worldCampaigns.first),
                              onChooseCampaign: (Campaign selected) =>
                                  _continueGame(context, ref, selected),
                              onNewGame: isGenerating
                                  ? null
                                  : () => _newGame(context, ref, world),
                              onActions: (String action) => _showWorldActions(
                                  context, ref, world, action),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showWorldActions(
      BuildContext context, WidgetRef ref, World world, String action) async {
    final AppStrings strings = AppStrings(Localizations.localeOf(context));
    if (action == 'export') {
      try {
        final bool exported =
            await ref.read(workspaceProvider.notifier).exportScenario(world.id);
        if (exported && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(strings.text('scenario_exported'))));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(strings.text('scenario_export_failed'))));
        }
      }
      return;
    }
    if (action == 'duplicate') {
      try {
        await ref.read(workspaceProvider.notifier).duplicateWorld(world.id);
        ref.read(navigationProvider.notifier).goTo(AppDestination.studio);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(strings.text('world_duplicate_failed'))));
        }
      }
      return;
    }
    if (action != 'delete') return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(strings
            .text('delete_world_confirm')
            .replaceAll('{name}', world.name)),
        content: Text(strings.text('world_duplicate_details')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(strings.text('delete_world'))),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(workspaceProvider.notifier).deleteWorld(world.id);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(strings.text('delete_world_failed'))));
        }
      }
    }
  }

  Future<void> _importScenario(
      BuildContext context, WidgetRef ref, AppStrings strings) async {
    try {
      final World? imported =
          await ref.read(workspaceProvider.notifier).importScenario();
      if (imported != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.text('scenario_imported'))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.text('scenario_import_failed'))));
      }
    }
  }

  Future<void> _newGame(
      BuildContext context, WidgetRef ref, World world) async {
    try {
      if (ref.read(novelControllerProvider).isGenerating) return;
      final modelController = ref.read(modelManagerControllerProvider.notifier);
      if (ref.read(modelManagerControllerProvider).isLoading) {
        await modelController.load();
      }
      if (ref.read(modelManagerControllerProvider).selection == null) {
        modelController.showMessage(
            'Choose a story model to play. Your Worlds and templates remain available without one.');
        ref.read(navigationProvider.notifier).goTo(AppDestination.models);
        return;
      }
      await ref.read(novelControllerProvider.notifier).loadSettings();
      ref.read(novelControllerProvider.notifier).validatePlayableWorld(world);
      await ref.read(novelControllerProvider.notifier).createCampaign(world);
      if (context.mounted) {
        ref.read(navigationProvider.notifier).goTo(AppDestination.player);
      }
      await ref.read(workspaceProvider.notifier).refreshCampaigns(world.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _continueGame(
      BuildContext context, WidgetRef ref, Campaign campaign) async {
    try {
      await ref.read(novelControllerProvider.notifier).loadSettings();
      await ref
          .read(novelControllerProvider.notifier)
          .continueCampaign(campaign.id);
      if (context.mounted) {
        ref.read(navigationProvider.notifier).goTo(AppDestination.player);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _openWorld(
      BuildContext context, WidgetRef ref, String worldId) async {
    try {
      await ref.read(workspaceProvider.notifier).openWorld(worldId);
      if (context.mounted) {
        ref.read(navigationProvider.notifier).goTo(AppDestination.studio);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not finish saving the current world. Your edits are still visible.')));
      }
    }
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader(
      {required this.onCreate,
      required this.onImport,
      required this.onSettings,
      required this.strings});
  final VoidCallback onCreate;
  final VoidCallback onImport;
  final VoidCallback onSettings;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Text(
            'CONTINUUM',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 2.8,
              color: ContinuumTheme.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: strings.text('settings'),
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          TextButton(
              onPressed: onImport,
              child: Text(strings.text('import_scenario'))),
          TextButton(
            onPressed: onCreate,
            child: Text(strings.text('create_world_upper')),
          ),
        ],
      );
}

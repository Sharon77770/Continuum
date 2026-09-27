import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';

import '../../../app/app_strings.dart';
import '../../../app/theme.dart';
import '../../../state/locale_controller.dart';

class WorldListItem extends ConsumerWidget {
  const WorldListItem.create({super.key, required this.onCreate})
      : world = null,
        status = '',
        primaryLabel = '',
        onOpen = null,
        onContinue = null,
        campaign = null,
        campaigns = const [],
        onNewGame = null,
        onActions = null,
        onChooseCampaign = null;

  const WorldListItem({
    super.key,
    required this.world,
    required this.status,
    required this.primaryLabel,
    required this.onOpen,
    required this.onContinue,
    required this.campaign,
    required this.campaigns,
    required this.onNewGame,
    required this.onActions,
    required this.onChooseCampaign,
  }) : onCreate = null;

  final World? world;
  final String status;
  final String primaryLabel;
  final VoidCallback? onOpen;
  final VoidCallback? onContinue;
  final Campaign? campaign;
  final List<Campaign> campaigns;
  final VoidCallback? onNewGame;
  final ValueChanged<String>? onActions;
  final ValueChanged<Campaign>? onChooseCampaign;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings(ref.watch(localeProvider));
    final World? itemWorld = world;
    if (itemWorld == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 17),
            label: Text(strings.text('create_world')),
            style: TextButton.styleFrom(foregroundColor: ContinuumTheme.accent),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _WorldCover(name: itemWorld.name),
          const SizedBox(width: 27),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemWorld.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: <Widget>[
                      if (campaign != null)
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: onContinue,
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: Text(strings.text('continue')),
                          ),
                          if (campaigns.length > 1)
                            PopupMenuButton<Campaign>(
                              tooltip: strings.text('choose_campaign'),
                              onSelected: (Campaign item) =>
                                  onChooseCampaign?.call(item),
                              itemBuilder: (BuildContext context) =>
                                  <PopupMenuEntry<Campaign>>[
                                for (final Campaign item in campaigns)
                                  PopupMenuItem<Campaign>(
                                      value: item,
                                      child: Text(
                                          '${item.name} · ${item.worldState.turnNumber} turns')),
                              ],
                            ),
                        ]),
                      FilledButton.tonalIcon(
                        onPressed: onNewGame,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(strings.text('new_game')),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      itemWorld.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      status.isEmpty ? strings.text('no_genre') : status,
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.05,
                        color: ContinuumTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          PopupMenuButton<String>(
            tooltip: strings.text('world_actions'),
            onSelected: (String action) => onActions?.call(action),
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                  value: 'duplicate',
                  child: Text(strings.text('duplicate_world'))),
              PopupMenuItem(
                  value: 'export',
                  child: Text(strings.text('export_scenario'))),
              PopupMenuItem(
                  value: 'delete', child: Text(strings.text('delete_world'))),
            ],
            child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_horiz, size: 20)),
          ),
        ],
      ),
    );
  }
}

class _WorldCover extends StatelessWidget {
  const _WorldCover({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Container(
        width: 108,
        height: 126,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFF24241F),
          border: Border.all(color: const Color(0xFF3A3931)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF34332B), Color(0xFF171815)],
          ),
        ),
        child: Text(
          name
              .split(' ')
              .map((String part) => part.isNotEmpty ? part[0] : '')
              .take(2)
              .join(),
          style: const TextStyle(
            fontSize: 22,
            letterSpacing: 2,
            color: ContinuumTheme.accent,
          ),
        ),
      );
}

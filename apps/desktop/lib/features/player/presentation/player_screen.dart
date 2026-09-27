import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';

import '../../../app/app_strings.dart';
import '../../../app/navigation.dart';
import '../../../app/theme.dart';
import '../../../state/locale_controller.dart';
import '../../../state/workspace_controller.dart';
import '../../novel/application/novel_controller.dart';

/// Presents Campaign history as a scrollable conversation transcript.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.worldId});
  final String? worldId;
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  final TextEditingController _action = TextEditingController();
  final ScrollController _transcriptScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollTranscriptToEnd());
  }

  @override
  void dispose() {
    _action.dispose();
    _transcriptScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NovelState>(novelControllerProvider, (previous, next) {
      final String? previousCampaignId = previous?.campaign?.id;
      final String? nextCampaignId = next.campaign?.id;
      final int previousTurnCount = previous?.campaign?.history.length ?? 0;
      final int nextTurnCount = next.campaign?.history.length ?? 0;
      if (previousCampaignId != nextCampaignId ||
          previousTurnCount != nextTurnCount) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollTranscriptToEnd());
      }
    });
    final NovelState novel = ref.watch(novelControllerProvider);
    final AppStrings strings = AppStrings(ref.watch(localeProvider));
    final WorkspaceState workspace = ref.watch(workspaceProvider);
    final Campaign? campaign = novel.campaign;
    final World? world = workspace.worlds
        .where((World item) => item.id == (campaign?.worldId ?? widget.worldId))
        .firstOrNull;
    final SceneTurn? scene = campaign?.currentScene;
    final List<SceneTurn> transcript =
        campaign?.history ?? const <SceneTurn>[];
    final String location = world?.locations
            .where((StoryLocation item) =>
                item.id == campaign?.worldState.currentLocationId)
            .map((StoryLocation item) => item.name)
            .firstOrNull ??
        '';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _PlayerHeader(
              worldName: world?.name ?? 'CONTINUUM',
              location: location,
              strings: strings,
              onLibrary: () => ref
                  .read(navigationProvider.notifier)
                  .goTo(AppDestination.library),
            ),
            const Divider(height: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: scene == null
                        ? _EmptyScene(
                            world: world,
                            novel: novel,
                            strings: strings,
                            onRetry: () async {
                              try {
                                await ref
                                    .read(novelControllerProvider.notifier)
                                    .regenerate();
                              } catch (_) {}
                            })
                        : _SceneView(
                            world: world,
                            scene: scene,
                            transcript: transcript,
                            novel: novel,
                            strings: strings,
                            scrollController: _transcriptScroll,
                            actionController: _action,
                            onSubmit: _submit,
                            onCancel: ref
                                .read(novelControllerProvider.notifier)
                                .cancelGeneration,
                            onRegenerate: () async {
                              try {
                                await ref
                                    .read(novelControllerProvider.notifier)
                                    .regenerate();
                              } catch (_) {}
                            },
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(String action) async {
    _action.clear();
    try {
      await ref.read(novelControllerProvider.notifier).act(action);
    } catch (_) {
      // The controller exposes a friendly retryable message.
    }
  }

  void _scrollTranscriptToEnd() {
    if (!_transcriptScroll.hasClients) return;
    _transcriptScroll.animateTo(
      _transcriptScroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader(
      {required this.worldName,
      required this.location,
      required this.strings,
      required this.onLibrary});
  final String worldName;
  final String location;
  final AppStrings strings;
  final VoidCallback onLibrary;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(30, 16, 30, 12),
        child: Row(
          children: <Widget>[
            Text(worldName, style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            if (location.isNotEmpty)
              Text(location,
                  style: const TextStyle(color: ContinuumTheme.accent)),
            const SizedBox(width: 18),
            TextButton(
                onPressed: onLibrary, child: Text(strings.text('library'))),
          ],
        ),
      );
}

class _EmptyScene extends StatelessWidget {
  const _EmptyScene(
      {
    required this.world,
    required this.novel,
    required this.strings,
    required this.onRetry,
  });
  final World? world;
  final NovelState novel;
  final AppStrings strings;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(world?.name ?? strings.text('novel_player'),
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 12),
          Text(
              novel.errorMessage ??
                  strings.text('playable_world_hint'),
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          if (novel.isGenerating) const LinearProgressIndicator(),
          if (novel.errorMessage != null)
            TextButton(
                onPressed: onRetry, child: Text(strings.text('try_again'))),
        ],
      );
}

class _TranscriptTurn extends StatelessWidget {
  const _TranscriptTurn({
    required this.turn,
    required this.world,
    required this.strings,
  });

  final SceneTurn turn;
  final World? world;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (turn.playerAction != null)
            _ChatBubble(
              name: world?.playerDefinition.name.trim().isNotEmpty == true
                  ? world!.playerDefinition.name
                  : strings.text('you'),
              message: turn.playerAction!,
              isPlayer: true,
            ),
          if (turn.narration.trim().isNotEmpty) ...<Widget>[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
              decoration: const BoxDecoration(
                color: Color(0xFF151613),
                border: Border(
                  left: BorderSide(color: Color(0xFF49453B), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.text('narration'),
                    style: const TextStyle(
                      color: ContinuumTheme.muted,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    turn.narration,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.8,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            ),
          ],
          for (final SceneDialogue line in turn.dialogue)
            _ChatBubble(
              name: world?.characters
                      .where((StoryCharacter character) =>
                          character.id == line.characterId)
                      .map((StoryCharacter character) => character.name)
                      .firstOrNull ??
                  strings.text('unknown_character'),
              message: line.text,
              isPlayer: false,
            ),
        ],
      );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.name,
    required this.message,
    required this.isPlayer,
  });

  final String name;
  final String message;
  final bool isPlayer;

  @override
  Widget build(BuildContext context) => Align(
        alignment: isPlayer ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 7),
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
            decoration: BoxDecoration(
              color: isPlayer
                  ? const Color(0xFF29271F)
                  : ContinuumTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isPlayer
                    ? const Color(0xFF514735)
                    : const Color(0xFF30312C),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: TextStyle(
                    color:
                        isPlayer ? ContinuumTheme.accent : ContinuumTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(message, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      );
}

class _SceneView extends StatelessWidget {
  const _SceneView(
      {required this.world,
      required this.scene,
      required this.transcript,
      required this.novel,
      required this.strings,
      required this.scrollController,
      required this.actionController,
      required this.onSubmit,
      required this.onCancel,
      required this.onRegenerate});
  final World? world;
  final SceneTurn scene;
  final List<SceneTurn> transcript;
  final NovelState novel;
  final AppStrings strings;
  final ScrollController scrollController;
  final TextEditingController actionController;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onRegenerate;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 28),
              itemCount: transcript.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 28),
              itemBuilder: (BuildContext context, int index) =>
                  _TranscriptTurn(
                turn: transcript[index],
                world: world,
                strings: strings,
              ),
            ),
          ),
          const Divider(),
          if (novel.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(strings.phrase(novel.errorMessage!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (novel.isGenerating)
            Row(children: <Widget>[
              const Expanded(child: LinearProgressIndicator()),
              TextButton(onPressed: onCancel, child: Text(strings.text('cancel'))),
            ]),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String choice in scene.choices)
                OutlinedButton(
                    onPressed:
                        novel.isGenerating ? null : () => onSubmit(choice),
                    child: Text(choice)),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
              child: TextField(
                controller: actionController,
                enabled: !novel.isGenerating,
                decoration:
                    InputDecoration(hintText: strings.text('describe_action')),
                onSubmitted: onSubmit,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
                onPressed: novel.isGenerating
                    ? null
                    : () => onSubmit(actionController.text),
                icon: const Icon(Icons.arrow_forward)),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: novel.isGenerating ? null : onRegenerate,
                child: Text(strings.text('regenerate'))),
          ),
        ],
      );
}

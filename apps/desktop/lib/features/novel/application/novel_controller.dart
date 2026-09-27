import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';
import 'package:novel_system/novel_system.dart';

import '../../../core/developer_tools_providers.dart';
import '../../../state/workspace_controller.dart';
import '../../../state/locale_controller.dart';
import '../domain/language_model_settings.dart';
import '../data/llm_provider.dart';
import '../../models/application/model_manager_controller.dart';
import '../../models/domain/local_runtime_tuning.dart';
import '../../models/domain/model_catalog.dart';

final llmProvider =
    Provider<LlmProvider>((ref) => ref.watch(managedLanguageModelProvider));
final novelControllerProvider =
    NotifierProvider<NovelController, NovelState>(NovelController.new);

class NovelState {
  const NovelState(
      {this.campaign,
      this.settings = const LanguageModelSettings(),
      this.isGenerating = false,
      this.isStartingCampaign = false,
      this.errorMessage,
      this.context,
      this.providerStatus = 'Not tested',
      this.lastRequestDuration,
      this.lastOutputCharacters});
  final Campaign? campaign;
  final LanguageModelSettings settings;
  final bool isGenerating;
  final bool isStartingCampaign;
  final String? errorMessage;
  final NarrativeContext? context;
  final String providerStatus;
  final Duration? lastRequestDuration;
  final int? lastOutputCharacters;
  NovelState copyWith(
          {Campaign? campaign,
          LanguageModelSettings? settings,
          bool? isGenerating,
          bool? isStartingCampaign,
          String? errorMessage,
          bool clearError = false,
          NarrativeContext? context,
          String? providerStatus,
          Duration? lastRequestDuration,
          int? lastOutputCharacters,
          bool clearCampaign = false}) =>
      NovelState(
        campaign: clearCampaign ? null : campaign ?? this.campaign,
        settings: settings ?? this.settings,
        isGenerating: isGenerating ?? this.isGenerating,
        isStartingCampaign: isStartingCampaign ?? this.isStartingCampaign,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        context: context ?? this.context,
        providerStatus: providerStatus ?? this.providerStatus,
        lastRequestDuration: lastRequestDuration ?? this.lastRequestDuration,
        lastOutputCharacters: lastOutputCharacters ?? this.lastOutputCharacters,
      );
}

/// Owns the turn lifecycle: build context, validate a candidate, then commit once.
class NovelController extends Notifier<NovelState> {
  String? _apiKey;
  String? _pendingAction;
  Campaign? _regenerationBase;
  bool _cancelled = false;
  String? _narrationRepairFailure;

  @override
  NovelState build() => const NovelState();

  Future<void> loadSettings() async {
    final LanguageModelSettings settings = await ref
        .read(languageModelSettingsRepositoryProvider)
        .getLanguageModelSettings();
    state = state.copyWith(settings: settings);
  }

  Future<void> saveSettings(LanguageModelSettings settings,
      {String? apiKey}) async {
    _apiKey = apiKey?.isNotEmpty == true ? apiKey : _apiKey;
    await ref
        .read(languageModelSettingsRepositoryProvider)
        .saveLanguageModelSettings(settings);
    state = state.copyWith(settings: settings, clearError: true);
  }

  Future<void> testConnection() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      await ref.read(llmProvider).healthCheck(state.settings, apiKey: _apiKey);
      state = state.copyWith(
          providerStatus: 'Connected', lastRequestDuration: stopwatch.elapsed);
    } catch (_) {
      state = state.copyWith(
          providerStatus: 'Unavailable',
          lastRequestDuration: stopwatch.elapsed);
      rethrow;
    }
  }

  Future<List<String>> listModels() =>
      ref.read(llmProvider).listModels(state.settings, apiKey: _apiKey);

  /// Removes an optional credential from process memory.
  void clearApiKey() => _apiKey = null;

  Future<void> createCampaign(World world) async {
    if (state.isGenerating) return;
    validatePlayableWorld(world);
    _pendingAction = null;
    _regenerationBase = null;
    final DateTime now = DateTime.now().toUtc();
    final Campaign campaign = Campaign(
      id: createStableId('campaign'),
      worldId: world.id,
      name: world.name,
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      worldState: WorldState(
        currentLocationId: world.openingDefinition.startingLocationId,
        presentCharacterIds: world.openingDefinition.startingCharacterIds
            .where((String id) =>
                world.characters.any((StoryCharacter item) => item.id == id))
            .toList(),
      ),
      languageCode: ref.read(gameLanguageProvider),
    );
    _regenerationBase = campaign;
    _pendingAction = world.openingDefinition.situation;
    state = state.copyWith(
        campaign: campaign, isStartingCampaign: true, clearError: true);
    try {
      await _generate(world, campaign, world.openingDefinition.situation,
          isOpening: true);
    } catch (_) {
      if (state.campaign?.id == campaign.id) {
        state = state.copyWith(clearCampaign: true);
      }
      rethrow;
    } finally {
      state = state.copyWith(isStartingCampaign: false);
    }
  }

  /// Validates all authoring prerequisites before navigation begins.
  void validatePlayableWorld(World world) {
    final List<String> issues = playableWorldIssues(world);
    if (issues.isNotEmpty) {
      throw StateError(
          'This world is not ready to play. Complete: ${issues.join(', ')}.');
    }
  }

  Future<void> continueCampaign(String campaignId) async {
    final Campaign? campaign =
        await ref.read(campaignRepositoryProvider).getCampaign(campaignId);
    if (campaign == null) throw StateError('This campaign could not be found.');
    _pendingAction = null;
    _regenerationBase = null;
    state = state.copyWith(campaign: campaign, clearError: true);
  }

  Future<void> act(String action) async {
    final String cleanAction = action.trim();
    final Campaign? campaign = state.campaign;
    if (campaign == null || cleanAction.isEmpty || state.isGenerating) return;
    _pendingAction = cleanAction;
    _regenerationBase = campaign;
    final World? world = ref
        .read(workspaceProvider)
        .worlds
        .where((World item) => item.id == campaign.worldId)
        .firstOrNull;
    if (world == null) throw StateError('The source world is unavailable.');
    await _generate(world, campaign, cleanAction);
  }

  Future<void> regenerate() async {
    final Campaign? campaign = state.campaign;
    final String? action = _pendingAction;
    if (campaign == null || action == null || state.isGenerating) return;
    final Campaign base = _regenerationBase ?? campaign;
    final World? world = ref
        .read(workspaceProvider)
        .worlds
        .where((World item) => item.id == base.worldId)
        .firstOrNull;
    if (world == null) throw StateError('The source world is unavailable.');
    await _generate(world, base, action,
        isOpening: base.worldState.turnNumber == 0);
  }

  void cancelGeneration() {
    _cancelled = true;
    ref.read(llmProvider).cancelCurrentRequest();
  }

  Future<void> _generate(World world, Campaign campaign, String action,
      {bool isOpening = false}) async {
    _cancelled = false;
    final DateTime requestStartedAt = DateTime.now();
    state = state.copyWith(isGenerating: true, clearError: true);
    try {
      final int contextLimit = await _effectiveContextLimit();
      final LanguageModelSettings requestSettings = LanguageModelSettings(
        baseUrl: state.settings.baseUrl,
        model: state.settings.model,
        temperature: state.settings.temperature,
        contextLimit: contextLimit,
      );
      final String storyLanguage = _languageName(campaign.languageCode);
      final String actionResolutionRule = switch (campaign.languageCode) {
        'ko' =>
          '플레이어 행동을 나레이션으로 다시 쓰거나 바꿔 말하지 않는다. 플레이어가 NPC에게 질문하면 그 NPC가 대사로 답한다. context에 기록된 사실만 근거로 답하고, 답을 뒷받침할 사실이 없으면 모른다고 말한다. NPC가 플레이어의 질문을 다른 말로 되풀이하거나, 이미 주어진 정보를 플레이어에게 다시 확인하라고 떠넘기지 않는다. 짧은 질문에는 짧고 직접 답한다. 플레이어가 부탁이나 의뢰를 거절하면 그 거절을 받아들이고 같은 일을 다시 권하거나 수락한 것으로 진행하지 않는다. 일반 턴 나레이션은 플레이어 이름을 주어로 삼지 않는다. 선택지는 플레이어가 지금 직접 수행할 수 있는 행동만 쓴다. NPC의 답변이나 플레이어가 NPC에게 전달하는 말을 선택지로 쓰지 않는다. 선택지는 자연스러운 완결형 한국어 행동 문장으로 쓰고, 외국어를 억지로 섞거나 같은 행동을 어미만 바꾸어 중복하지 않는다. 플레이어용 문장에는 내부 ID를 쓰지 말고 세계 설정에 적힌 이름만 쓴다.',
        'ja' =>
          'プレイヤーの行動を地の文で言い換えて繰り返さない。質問されたNPCはcontextに記録された事実だけを根拠に答え、情報がなければ知らないと答える。既知の情報をプレイヤーに確認し直させない。短い質問には短く直接答える。プレイヤーが依頼やクエストを断ったらその意思を受け入れ、同じ依頼を繰り返したり受諾したことにして進めたりしない。通常の地の文ではプレイヤー名を主語にしない。選択肢はプレイヤーが今すぐ実行できる行動だけにし、NPCの返答や伝言を選択肢にしない。',
        'zh' =>
          '不要在旁白中复述或改写玩家的行动。NPC回答问题时只能依据context中记录的事实；没有依据就明确说不知道，不要让玩家重复确认已知信息。简短问题要简短直接地回答。玩家拒绝请求或任务后，NPC应接受拒绝，不要重复请求，也不要当作玩家已经答应。普通回合的旁白不要以玩家姓名为主语。选项只能是玩家现在可以亲自执行的行动，不得写成NPC的回答或让玩家转述信息。',
        _ =>
          'Do not restate or paraphrase the player action as narration. NPC answers must rely only on facts recorded in context; if there is no supporting fact, the NPC should say they do not know. Do not ask the player to reconfirm information already known. Answer short questions briefly and directly. When the player refuses a request or quest, accept the refusal and do not ask again or proceed as if accepted. In ordinary turns, do not use the player name as the subject of narration. Choices must be actions the player can take now, not an NPC answer or a message for the player to relay.',
      };
      final String currentLocationName = world.locations
              .where((StoryLocation item) =>
                  item.id == campaign.worldState.currentLocationId)
              .map((StoryLocation item) => item.name)
              .firstOrNull ??
          '';
      final String presentCharacterName = world.characters
              .where((StoryCharacter item) =>
                  campaign.worldState.presentCharacterIds.contains(item.id))
              .map((StoryCharacter item) => item.name)
              .firstOrNull ??
          '';
      final String? actionDestinationId = isOpening
          ? null
          : _explicitDestinationLocationId(action, campaign.languageCode, world,
              campaign.worldState.currentLocationId);
      final bool playerMovesAlone = actionDestinationId != null &&
          !_actionTakesNpcAlong(action, world, campaign);
      final StoryLocation? fallbackLocation = world.locations
          .where((StoryLocation item) =>
              item.id ==
              (actionDestinationId ?? campaign.worldState.currentLocationId))
          .firstOrNull;
      final List<String> fallbackChoices = _fallbackSceneChoices(
        campaign.languageCode,
        fallbackLocation?.name ?? currentLocationName,
        actionDestinationId == null ? presentCharacterName : '',
      );
      final NarrativeContext context = ContextBuilder(
              tokenLimit: (requestSettings.contextLimit * 0.75).floor())
          .build(
              world: world,
              campaign: playerMovesAlone
                  ? campaign.copyWith(
                      worldState: WorldState(
                        currentLocationId: actionDestinationId,
                        presentCharacterIds: const <String>[],
                        timeDescription: campaign.worldState.timeDescription,
                        atmosphere: campaign.worldState.atmosphere,
                        relevantObjects: campaign.worldState.relevantObjects,
                        facts: campaign.worldState.facts,
                        events: campaign.worldState.events,
                        turnNumber: campaign.worldState.turnNumber,
                      ),
                    )
                  : campaign,
              playerAction: action,
              isOpening: isOpening);
      final String openingSequenceRule = !isOpening
          ? ''
          : switch (campaign.languageCode) {
              'ko' =>
                'Opening의 첫 두 문장 안에 ${world.playerDefinition.name}이 누구인지, $currentLocationName에 왜 와 있는지, 지금 벌어진 일을 관찰 가능한 상황으로 설명한다. 플레이어가 이미 그곳에 온 이유는 작성된 캐릭터 배경과 Opening Situation에 맞춰 설명하되, 플레이어가 아직 입력하지 않은 현재 행동을 시작시키지 않는다. 설정을 나열하지 않는다.',
              'ja' =>
                'Openingの最初の2文で、${world.playerDefinition.name}が誰で、なぜ$currentLocationNameに来たのか、今何が起きているのかを観察できる状況で示す。すでに来た理由は設定済みの背景とOpening Situationに従い、まだ入力されていない現在の行動を始めさせず、設定も列挙しない。',
              'zh' =>
                'Opening前两句要通过可观察情况说明${world.playerDefinition.name}是谁、为何来到$currentLocationName以及眼下发生了什么。玩家来此的原因应符合已编写的角色背景和Opening Situation；不要替玩家开始尚未输入的当前行动，也不要罗列设定。',
              _ =>
                'In the first two opening sentences, establish who ${world.playerDefinition.name} is, why they came to $currentLocationName, and what is happening through observable details. Follow the authored player background and Opening Situation; do not begin a current action the player has not entered or list setting facts.',
            };
      final String localizedSystemPrompt =
          '${context.systemPrompt}\n\nWrite all player-facing story content in $storyLanguage. '
          'This includes narration, dialogue, choices, events, state changes, memories, and scene fields. '
          'Keep proper nouns and authored World text as written unless a character naturally translates them. '
          'NPC dialogue is optional; narration without dialogue is a complete valid turn. When no NPC is present, use environmental observation or consequences and do not invent a character. Only narrate the player speaking to themselves if the player explicitly chose that action. '
          '$actionResolutionRule $openingSequenceRule';
      final String localizedPrompt = context.userPrompt;
      state = state.copyWith(context: context);
      NarrativeResult? result;
      String raw = '';
      String? repairReason;
      final List<String> attemptedChoices = <String>[];
      for (int attempt = 0; attempt < 3; attempt++) {
        raw = '';
        final String prompt = attempt == 0
            ? localizedPrompt
            : '$localizedPrompt\n\nCorrect the specific validation issue from your previous output. Return one compact JSON object without markdown. Required fields: schemaVersion, narration, and 2-5 concrete choices. Dialogue is optional; omit it or return an empty array when no NPC needs to speak. Omit optional events/stateChanges/memoryUpdates/npcChanges/sceneChanges unless a meaningful change occurred. Use only active speaker/NPC IDs and valid world IDs. Valid locations are: ${world.locations.map((StoryLocation item) => "${item.id} (${item.name})").join(", ")}. If present, sceneChanges.locationId must be an exact location ID. Avoid the repeated narration identified below and advance only the current scene. Keep all player-facing text in $storyLanguage.';
        final String recentTurnDetails = campaign.history.reversed
            .take(6)
            .map((SceneTurn item) =>
                '- Narration: ${item.narration}\n  Dialogue: ${item.dialogue.map((SceneDialogue line) => line.text).join(' / ')}\n  Choices already offered: ${item.choices.join(' / ')}')
            .join('\n');
        final String requestPrompt = attempt == 0
            ? prompt
            : '$prompt\n${isOpening ? 'Opening repair: the first two sentences must include the exact player name "${world.playerDefinition.name}" and starting location "${world.locations.where((StoryLocation item) => item.id == campaign.worldState.currentLocationId).map((StoryLocation item) => item.name).firstOrNull ?? ''}", plus why the player is there.' : ''}\nValidation issue: $repairReason. Do not repeat recent dialogue or any choices already offered; write fresh, concrete player actions.\nRecent scene output that must not be repeated:\n$recentTurnDetails';
        await for (final String chunk in ref.read(llmProvider).stream(
              requestPrompt,
              requestSettings,
              apiKey: _apiKey,
              maxTokens: isOpening
                  ? (requestSettings.contextLimit ~/ 8 + 128).clamp(128, 1024)
                  : (requestSettings.contextLimit ~/ 8).clamp(64, 768),
              systemPrompt: localizedSystemPrompt,
              jsonMode: true,
            )) {
          if (_cancelled) throw const LlmException('Generation cancelled.');
          if (raw.length + chunk.length > 65536) {
            throw const LlmException(
                'The model response exceeded the 64 KB limit.');
          }
          raw += chunk;
        }
        try {
          result = NarrativeResult.parse(
            raw,
            campaign.worldState.presentCharacterIds.toSet(),
            minimumChoices: 1,
            ignoreDialogue: playerMovesAlone ||
                campaign.worldState.presentCharacterIds.isEmpty,
          );
          if (_containsInternalWorldId(result, world)) {
            throw const FormatException(
                'Player-facing text contains an internal world ID.');
          }
          result = _boundNpcKnowledge(
            _removeRelayChoices(result, campaign.languageCode),
            world,
            campaign,
            action,
            campaign.languageCode,
          );
          if (!isOpening) {
            result = _respectExplicitNpcRefusal(
                result, action, world, campaign, campaign.languageCode);
          }
          attemptedChoices.addAll(result.choices);
          if (isOpening) {
            final String locationName = world.locations
                    .where((StoryLocation item) =>
                        item.id == campaign.worldState.currentLocationId)
                    .map((StoryLocation item) => item.name)
                    .firstOrNull ??
                '';
            if (locationName.isEmpty ||
                !result.narration.contains(world.playerDefinition.name) ||
                !result.narration.contains(locationName)) {
              final String? authoredPurpose = _authoredOpeningPurpose(
                  world, campaign.worldState.currentLocationId ?? '');
              if (authoredPurpose != null) {
                final String sceneDescription = _removeRedundantOpeningArrival(
                  result.narration,
                  world.playerDefinition.name,
                  locationName,
                );
                result = NarrativeResult(
                  narration: '$authoredPurpose $sceneDescription',
                  dialogue: result.dialogue,
                  choices: result.choices,
                  sceneChanges: result.sceneChanges,
                  npcChanges: result.npcChanges,
                  events: result.events,
                  stateChanges: result.stateChanges,
                  memoryUpdates: result.memoryUpdates,
                );
              }
            }
            if (locationName.isEmpty ||
                !result.narration.contains(world.playerDefinition.name) ||
                !result.narration.contains(locationName)) {
              throw const FormatException(
                  'Opening must name the player and starting location.');
            }
            if (!_openingExplainsPlayerPurpose(
                result.narration, world, campaign.languageCode)) {
              final String? authoredPurpose = _authoredOpeningPurpose(
                  world, campaign.worldState.currentLocationId ?? '');
              if (authoredPurpose != null) {
                final String sceneDescription = _removeRedundantOpeningArrival(
                  result.narration,
                  world.playerDefinition.name,
                  locationName,
                );
                result = NarrativeResult(
                  narration: '$authoredPurpose $sceneDescription',
                  dialogue: result.dialogue,
                  choices: result.choices,
                  sceneChanges: result.sceneChanges,
                  npcChanges: result.npcChanges,
                  events: result.events,
                  stateChanges: result.stateChanges,
                  memoryUpdates: result.memoryUpdates,
                );
              }
            }
            if (!_openingExplainsPlayerPurpose(
                result.narration, world, campaign.languageCode)) {
              throw const FormatException(
                  'Opening does not explain why the player is at this location.');
            }
            if (_describesPrivatePlayerState(
                result.narration, world.playerDefinition.name, storyLanguage)) {
              throw const FormatException(
                  'Opening invents a player thought or feeling.');
            }
            if (_openingInventsPlayerAction(
                result.narration, world.playerDefinition.name, storyLanguage)) {
              throw const FormatException(
                  'Opening starts a player action before the first input.');
            }
            if (_normalizeNarrativeText(result.narration) ==
                _normalizeNarrativeText(action)) {
              throw const FormatException(
                  'Opening repeats the setup instead of grounding the scene.');
            }
          }
          if (!isOpening &&
              action.trim().length >= 5 &&
              (_echoesAction(result.narration, action) ||
                  campaign.history.any((SceneTurn previous) =>
                      previous.playerAction != null &&
                      _echoesAction(
                          result!.narration, previous.playerAction!)))) {
            throw const FormatException(
                'Narration repeats a current or earlier player action instead of resolving the current turn.');
          }
          if (!isOpening &&
              campaign.history.any((SceneTurn previous) =>
                  _similarity(previous.narration, result!.narration) >= 0.68)) {
            throw const FormatException(
                'Narration repeats a recent scene instead of advancing it.');
          }
          if (!isOpening &&
              _describesPlayerAgency(
                  result.narration, world.playerDefinition.name, storyLanguage,
                  otherCharacterNames: world.characters
                      .map((StoryCharacter item) => item.name))) {
            throw const FormatException(
                'Narration invents a player action, thought, or feeling.');
          }
          if (!isOpening) {
            final Set<String> recentDialogue = campaign.history.reversed
                .take(4)
                .expand((SceneTurn previous) => previous.dialogue)
                .map((SceneDialogue line) => _normalizeNarrativeText(line.text))
                .toSet();
            result = _removeActionEchoDialogue(
              _removeRepeatedDialogue(result, recentDialogue),
              <String>[
                action,
                ...campaign.history.reversed
                    .take(4)
                    .map((SceneTurn turn) => turn.playerAction ?? ''),
              ],
            );
            result = _ensureNpcQuestionAnswered(
                result, action, world, campaign, campaign.languageCode);
            result = _ensureConciseWhyAnswered(
                result, action, world, campaign, campaign.languageCode);
          }
          if (!isOpening) {
            final Set<String> recentChoices = campaign.history.reversed
                .take(3)
                .expand((SceneTurn previous) => previous.choices)
                .map(_normalizeNarrativeText)
                .toSet();
            final int repeatedChoices = result.choices
                .map(_normalizeNarrativeText)
                .where(recentChoices.contains)
                .length;
            if (repeatedChoices >= 2) {
              throw const FormatException(
                  'Most choices repeat recent actions instead of reflecting the scene.');
            }
          }
          if (result.choices.any((String choice) =>
              choice.length > 120 ||
              _hasQuestionMark(choice) ||
              RegExp(r'^(continue|keep going|think about|consider what|무엇을 하|계속 진행|다른 방법을 생각)',
                      caseSensitive: false)
                  .hasMatch(choice.trim()))) {
            throw const FormatException(
                'Narrative suggestions are not scene actions.');
          }
          break;
        } on FormatException catch (error) {
          if (attempt == 2 &&
              (error.message.toLowerCase().contains('repeat') ||
                  error.message.toLowerCase().contains('player action') ||
                  error.message.toLowerCase().contains('player agency'))) {
            final NarrativeResult rejectedCandidate = result!;
            final bool choicesOnlyRepair = error.message
                .toLowerCase()
                .contains('choices repeat recent actions');
            final bool narrationOnlyRepair =
                error.message.toLowerCase().contains('player action') ||
                    error.message.toLowerCase().contains('player agency') ||
                    error.message.contains('Narration repeats a recent scene');
            String? repairedNarration;
            NarrativeResult? repairedScene;
            if (choicesOnlyRepair) {
              repairedNarration = rejectedCandidate.narration;
            } else if (narrationOnlyRepair) {
              repairedNarration = await _regenerateNarrationOnly(
                world,
                campaign,
                action,
                storyLanguage,
                _narrationOnlySystemPrompt(storyLanguage),
              );
            }
            if (repairedNarration == null && !choicesOnlyRepair) {
              repairedScene = await _regenerateScene(world, campaign, action,
                  storyLanguage, localizedSystemPrompt);
            }
            if (repairedNarration == null && repairedScene == null) {
              repairedNarration = _fallbackNarrationForAction(
                  action, campaign.languageCode, presentCharacterName,
                  recentNarrations:
                      campaign.history.map((SceneTurn turn) => turn.narration));
            }
            List<String> mergedChoices = _mergeFreshChoices(
                campaign.history,
                <String>[
                  if (repairedScene != null) ...repairedScene.choices,
                  ...attemptedChoices,
                ],
                fallbackChoices: fallbackChoices,
                lastPlayerAction: action);
            if (mergedChoices.length < 2 && repairedScene == null) {
              repairedScene = await _regenerateScene(world, campaign, action,
                  storyLanguage, localizedSystemPrompt);
              if (repairedScene != null) {
                mergedChoices = _mergeFreshChoices(
                    campaign.history,
                    <String>[
                      ...repairedScene.choices,
                      ...attemptedChoices,
                    ],
                    fallbackChoices: fallbackChoices,
                    lastPlayerAction: action);
              }
            }
            if (mergedChoices.length < 2) {
              throw const FormatException(
                  'Could not find two usable scene actions after repairing repeated content.');
            }
            final NarrativeResult dialogueSource = repairedScene ??
                _removeActionEchoDialogue(
                  _removeRepeatedDialogue(
                      rejectedCandidate,
                      campaign.history.reversed
                          .take(4)
                          .expand((SceneTurn previous) => previous.dialogue)
                          .map((SceneDialogue line) =>
                              _normalizeNarrativeText(line.text))
                          .toSet()),
                  <String>[
                    action,
                    ...campaign.history.reversed
                        .take(4)
                        .map((SceneTurn turn) => turn.playerAction ?? ''),
                  ],
                );
            result = NarrativeResult(
              narration: repairedNarration ?? repairedScene!.narration,
              dialogue: dialogueSource.dialogue,
              choices: mergedChoices,
              sceneChanges: repairedScene?.sceneChanges ??
                  (choicesOnlyRepair
                      ? rejectedCandidate.sceneChanges
                      : const {}),
              npcChanges: repairedScene?.npcChanges ??
                  (choicesOnlyRepair ? rejectedCandidate.npcChanges : const {}),
              events: repairedScene?.events ??
                  (choicesOnlyRepair ? rejectedCandidate.events : const []),
              stateChanges: repairedScene?.stateChanges ??
                  (choicesOnlyRepair
                      ? rejectedCandidate.stateChanges
                      : const {}),
              memoryUpdates: repairedScene?.memoryUpdates ??
                  (choicesOnlyRepair
                      ? rejectedCandidate.memoryUpdates
                      : const {}),
            );
            break;
          }
          if (attempt == 2) rethrow;
          repairReason = error.message;
        }
      }
      if (_cancelled) throw const LlmException('Generation cancelled.');
      if (isOpening) {
        final String locationName = world.locations
                .where((StoryLocation item) =>
                    item.id == campaign.worldState.currentLocationId)
                .map((StoryLocation item) => item.name)
                .firstOrNull ??
            '';
        final NarrativeResult openingResult = result!;
        final bool missingGrounding = locationName.isEmpty ||
            !openingResult.narration.contains(world.playerDefinition.name) ||
            !openingResult.narration.contains(locationName) ||
            !_openingExplainsPlayerPurpose(
                openingResult.narration, world, campaign.languageCode);
        final String? authoredPurpose = missingGrounding
            ? _authoredOpeningPurpose(
                world, campaign.worldState.currentLocationId ?? '')
            : null;
        if (authoredPurpose != null) {
          final String sceneDescription = _removeRedundantOpeningArrival(
            openingResult.narration,
            world.playerDefinition.name,
            locationName,
          );
          result = NarrativeResult(
            narration: '$authoredPurpose $sceneDescription',
            dialogue: openingResult.dialogue,
            choices: openingResult.choices,
            sceneChanges: openingResult.sceneChanges,
            npcChanges: openingResult.npcChanges,
            events: openingResult.events,
            stateChanges: openingResult.stateChanges,
            memoryUpdates: openingResult.memoryUpdates,
          );
        }
        if (locationName.isEmpty ||
            !result.narration.contains(world.playerDefinition.name) ||
            !result.narration.contains(locationName) ||
            !_openingExplainsPlayerPurpose(
                result.narration, world, campaign.languageCode)) {
          throw const FormatException(
              'Opening could not establish player identity, location, and purpose.');
        }
      }
      result = _ensureNpcQuestionAnswered(
          result!, action, world, campaign, campaign.languageCode);
      result = _ensureSpecificFactAnswerGrounded(
          result, action, world, campaign, campaign.languageCode);
      result = _ensureAuthoredSecretDisclosure(
          result, action, world, campaign, campaign.languageCode);
      result = _ensureNoRepeatedNpcAnswer(
          result, action, world, campaign, campaign.languageCode);
      result = _ensureConciseWhyAnswered(
          result, action, world, campaign, campaign.languageCode);
      late List<String> resolvedChoices;
      if (actionDestinationId != null) {
        final List<String> locationChoices = _fallbackSceneChoices(
          campaign.languageCode,
          fallbackLocation?.name ?? currentLocationName,
          '',
        );
        resolvedChoices = <String>[locationChoices[0], locationChoices[2]];
      } else {
        resolvedChoices = _mergeFreshChoices(
          campaign.history,
          <String>[...result.choices, ...attemptedChoices],
          fallbackChoices: fallbackChoices,
          lastPlayerAction: action,
        ).take(2).toList();
      }
      final Set<String> activeCharacterIds = playerMovesAlone
          ? <String>{}
          : campaign.worldState.presentCharacterIds.toSet();
      if (activeCharacterIds.isEmpty && actionDestinationId == null) {
        final Set<String> absentCharacterNames = world.characters
            .where(
                (StoryCharacter item) => !activeCharacterIds.contains(item.id))
            .map((StoryCharacter item) => item.name)
            .where((String name) => name.isNotEmpty)
            .toSet();
        final List<String> sceneSafeChoices = resolvedChoices
            .where((String choice) =>
                currentLocationName.isNotEmpty &&
                choice.contains(currentLocationName) &&
                !absentCharacterNames
                    .any((String name) => choice.contains(name)))
            .toList();
        resolvedChoices = _mergeFreshChoices(
          campaign.history,
          sceneSafeChoices,
          fallbackChoices: _fallbackSceneChoices(
              campaign.languageCode, currentLocationName, ''),
          lastPlayerAction: action,
        ).take(2).toList();
      }
      if (resolvedChoices.length < 2) {
        throw const FormatException(
            'Could not resolve two distinct player actions for the scene.');
      }
      final Map<String, Object?> sceneChanges = result.sceneChanges;
      final String? resolvedLocationId =
          actionDestinationId ?? campaign.worldState.currentLocationId;
      final StoryLocation? resolvedLocation = world.locations
          .where((StoryLocation item) => item.id == resolvedLocationId)
          .firstOrNull;
      final bool enteredNewLocation = resolvedLocation != null &&
          resolvedLocation.id != campaign.worldState.currentLocationId;
      final String resolvedNarration = enteredNewLocation
          ? _arrivalNarration(resolvedLocation, campaign.languageCode)
          : result.narration;
      final NarrativeResult accepted = NarrativeResult(
        narration: resolvedNarration,
        dialogue: playerMovesAlone
            ? result.dialogue
                .where((SceneDialogue line) => !campaign
                    .worldState.presentCharacterIds
                    .contains(line.characterId))
                .toList()
            : result.dialogue,
        choices: resolvedChoices,
        sceneChanges: result.sceneChanges,
        npcChanges: result.npcChanges,
        events: result.events,
        stateChanges: result.stateChanges,
        memoryUpdates: result.memoryUpdates,
      );
      final String? validLocationId = resolvedLocationId;
      final List<String>? proposedCharacterIds =
          (sceneChanges['presentCharacterIds'] as List?)?.cast<String>();
      final Set<String> validCharacterIds =
          world.characters.map((StoryCharacter item) => item.id).toSet();
      final List<String>? validCharacterIdsInScene =
          proposedCharacterIds != null &&
                  proposedCharacterIds.toSet().length ==
                      proposedCharacterIds.length &&
                  proposedCharacterIds.every(validCharacterIds.contains)
              ? proposedCharacterIds
              : null;
      final List<String> resolvedPresentCharacterIds = playerMovesAlone
          ? const <String>[]
          : enteredNewLocation
              ? validCharacterIdsInScene ?? const <String>[]
              : campaign.worldState.presentCharacterIds;
      final List<String>? proposedObjects =
          (sceneChanges['relevantObjects'] as List?)?.cast<String>();
      final String? proposedTime = sceneChanges['timeDescription'] as String?;
      final String? proposedAtmosphere = sceneChanges['atmosphere'] as String?;
      if ((proposedTime?.length ?? 0) > 160 ||
          (proposedAtmosphere?.length ?? 0) > 240 ||
          (proposedObjects?.length ?? 0) > 20 ||
          (proposedObjects?.any((String item) => item.length > 120) ?? false)) {
        throw const FormatException(
            'Narrative scene changes exceed safe limits.');
      }
      if (accepted.stateChanges.length > 20 ||
          accepted.stateChanges.entries.any((MapEntry<String, String> entry) =>
              entry.key.trim().isEmpty ||
              entry.key.length > 80 ||
              entry.value.length > 500)) {
        throw const FormatException(
            'Narrative state changes exceed safe limits.');
      }
      if (accepted.npcChanges.values.any((NpcStateChange change) =>
          (change.relationship?.length ?? 0) > 240 ||
          (change.currentEmotion?.length ?? 0) > 120 ||
          change.goals.length > 20 ||
          change.goals.any((String goal) => goal.length > 300) ||
          change.recentEvents.length > 20 ||
          change.recentEvents.any((String event) => event.length > 300))) {
        throw const FormatException('NPC state changes exceed safe limits.');
      }
      final DateTime now = DateTime.now().toUtc();
      final SceneTurn scene = SceneTurn(
        id: createStableId('scene'),
        narration: accepted.narration,
        dialogue: accepted.dialogue,
        choices: accepted.choices,
        playerAction: isOpening ? null : action,
        createdAt: now,
      );
      final Map<String, CharacterMemory> memories = {
        ...campaign.characterMemory
      };
      accepted.memoryUpdates.forEach((String id, List<String> updates) {
        final CharacterMemory existing =
            memories[id] ?? const CharacterMemory();
        memories[id] = CharacterMemory(
          importantMemories:
              _mergeUnique(existing.importantMemories, updates, 40),
          knownFacts: _mergeUnique(existing.knownFacts, updates, 80),
        );
      });
      accepted.npcChanges.forEach((String id, NpcStateChange change) {
        final CharacterMemory existing =
            memories[id] ?? const CharacterMemory();
        final List<String> recentEvents = {
          ...existing.recentEvents,
          ...change.recentEvents,
        }.toList();
        memories[id] = CharacterMemory(
          importantMemories: existing.importantMemories,
          knownFacts: existing.knownFacts,
          relationship: change.relationship ?? existing.relationship,
          currentEmotion: change.currentEmotion ?? existing.currentEmotion,
          goals: {...existing.goals, ...change.goals}.take(40).toList(),
          recentEvents: recentEvents.length <= 20
              ? recentEvents
              : recentEvents.sublist(recentEvents.length - 20),
        );
      });
      final Campaign committed = campaign.copyWith(
        updatedAt: now,
        lastPlayedAt: now,
        currentScene: scene,
        history: [...campaign.history, scene],
        characterMemory: memories,
        worldState: WorldState(
          currentLocationId:
              validLocationId ?? campaign.worldState.currentLocationId,
          presentCharacterIds: resolvedPresentCharacterIds,
          timeDescription: proposedTime ?? campaign.worldState.timeDescription,
          atmosphere: proposedAtmosphere ?? campaign.worldState.atmosphere,
          relevantObjects:
              proposedObjects ?? campaign.worldState.relevantObjects,
          facts: {...campaign.worldState.facts, ...accepted.stateChanges},
          events: [
            ...campaign.worldState.events,
            ...accepted.events.map((NarrativeEvent event) => GameEvent(
                id: createStableId('event'),
                kind: event.kind,
                description: event.description)),
            ...accepted.stateChanges.entries.map(
                (MapEntry<String, String> entry) => GameEvent(
                    id: createStableId('event'),
                    kind: 'state_change',
                    description: '${entry.key}=${entry.value}'))
          ],
          turnNumber: campaign.worldState.turnNumber + 1,
        ),
      );
      await ref.read(campaignRepositoryProvider).saveCampaign(committed);
      await ref
          .read(workspaceProvider.notifier)
          .refreshCampaigns(committed.worldId);
      state = state.copyWith(
          campaign: committed,
          isGenerating: false,
          clearError: true,
          providerStatus: 'Connected',
          lastRequestDuration: DateTime.now().difference(requestStartedAt),
          lastOutputCharacters: raw.length);
      _regenerationBase = campaign;
      _pendingAction = action;
    } catch (error, stackTrace) {
      state = state.copyWith(
          isGenerating: false,
          errorMessage: error is LlmException ||
                  error is StateError ||
                  error is FormatException
              ? error.toString()
              : 'The scene could not be generated. Check Language Model settings and try again.');
      await ref
          .read(appFileLoggerProvider)
          .error('Novel generation failed', error, stackTrace);
      rethrow;
    }
  }

  Future<int> _effectiveContextLimit() async {
    final int configuredLimit = state.settings.contextLimit;
    final models = ref.read(modelManagerRepositoryProvider);
    final ModelSelection? selection = await models.getSelection();
    if (selection?.kind != ModelProviderKind.local) return configuredLimit;
    final InstalledModel? model = (await models.listInstalled())
        .where((InstalledModel value) => value.id == selection!.modelId)
        .firstOrNull;
    if (model == null) return configuredLimit;
    final LocalRuntimeTuning tuning = LocalRuntimeTuning.forProfile(
      profile: await models.getLocalResourceProfile(),
      modelContextSize: model.contextSize,
    );
    return configuredLimit < tuning.contextSize
        ? configuredLimit
        : tuning.contextSize;
  }

  Future<String?> _regenerateNarrationOnly(World world, Campaign campaign,
      String action, String storyLanguage, String systemPrompt) async {
    final String location = world.locations
            .where((StoryLocation item) =>
                item.id == campaign.worldState.currentLocationId)
            .map((StoryLocation item) => item.name)
            .firstOrNull ??
        '';
    final String characters = world.characters
        .where((StoryCharacter item) =>
            campaign.worldState.presentCharacterIds.contains(item.id))
        .map((StoryCharacter item) =>
            '${item.name}: ${item.personality}; known facts: ${_knownNpcFacts(item, campaign)}')
        .join('\n');
    final String previous = campaign.history.reversed
        .take(4)
        .map((SceneTurn item) => item.narration)
        .join('\n');
    final String prompt = campaign.languageCode == 'ko'
        ? '''한국어 나레이션 한두 문장만 쓴다. JSON, 제목, 선택지, 대사는 출력하지 않는다.
장소: $location
보이는 NPC와 이미 알려진 정보:
$characters
최근 나레이션(반복 금지):
$previous
플레이어 행동: $action
잘못된 예: "발전기 경고등을 확인한다"처럼 행동을 다시 쓰는 문장.
좋은 예: "빨간 불이 두 번 짧게 깜박인 뒤 길게 꺼져 있다."처럼 확인한 대상에서 새로 관찰한 결과.
플레이어 이름이나 행동을 나레이션에 쓰지 않는다. 행동을 다시 말하거나 바꿔 말하지 말고, NPC의 반응이나 그 행동 뒤 새로 관찰되는 환경 결과만 한 문장으로 쓴다. NPC는 이미 아는 정보만 말한다.'''
        : '''Write 1-2 sentences of narration only in $storyLanguage. No JSON, heading, choices, or dialogue.
Location: $location
Visible NPCs and facts they already know:
$characters
Recent narration (do not repeat):
$previous
Player action: $action
Bad: "The player checks the warning light." Good: "The red lamp flashes twice, then stays dark." Describe the new observable result of the action, not the action itself. Do not mention the player. NPCs may use only facts they already know.''';
    _narrationRepairFailure = null;
    for (int attempt = 0; attempt < 2; attempt++) {
      String response = '';
      try {
        await for (final String chunk in ref.read(llmProvider).stream(
              attempt == 0
                  ? prompt
                  : '$prompt\n${storyLanguage == 'Korean' ? '앞선 응답은 $_narrationRepairFailure. 플레이어를 언급하지 말고 다른 결과를 한두 문장으로 쓴다.' : 'Previous response failed: $_narrationRepairFailure. Do not mention the player; write a different consequence in one or two sentences.'}',
              state.settings,
              apiKey: _apiKey,
              maxTokens: 128,
              systemPrompt: systemPrompt,
            )) {
          if (_cancelled) throw const LlmException('Generation cancelled.');
          response += chunk;
          if (response.length > 2000) break;
        }
      } on LlmException {
        rethrow;
      } catch (error) {
        _narrationRepairFailure = error.runtimeType.toString();
        continue;
      }
      final String candidate = response
          .trim()
          .replaceFirst(RegExp(r'^```(?:text)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .replaceAll(RegExp(r'^"|"$'), '');
      final bool wrongLanguage =
          storyLanguage == 'Korean' && !RegExp(r'[가-힣]').hasMatch(candidate);
      final bool repeatsRecent = campaign.history.reversed.take(6).any(
          (SceneTurn item) => _similarity(item.narration, candidate) >= 0.68);
      final bool echoesAction =
          action.trim().length >= 5 && _echoesAction(candidate, action);
      final bool inventsPlayerAgency = _describesPlayerAgency(
          candidate, world.playerDefinition.name, storyLanguage,
          otherCharacterNames:
              world.characters.map((StoryCharacter item) => item.name));
      if (candidate.isEmpty ||
          candidate.startsWith('{') ||
          wrongLanguage ||
          repeatsRecent ||
          echoesAction ||
          inventsPlayerAgency) {
        _narrationRepairFailure =
            'invalid narration-only response: ${candidate.substring(0, candidate.length.clamp(0, 240))}';
        continue;
      }
      return candidate;
    }
    return null;
  }

  String _narrationOnlySystemPrompt(String language) => switch (language) {
        'Korean' =>
          '당신은 대화형 소설의 게임 마스터다. 한국어 나레이션 한두 문장만 출력한다. JSON, 선택지, 대사, 제목은 쓰지 않는다. 플레이어 행동을 되풀이하거나 플레이어의 생각과 자발적 행동을 대신 정하지 않는다. 즉시 관찰할 수 있는 결과를 쓰고 NPC는 이미 아는 정보만 말한다.',
        'Japanese' =>
          'あなたはインタラクティブ小説のゲームマスターです。日本語の地の文を1〜2文だけ出力してください。JSON、選択肢、会話、見出しは禁止です。プレイヤーの行動を繰り返さず、思考や自発的な行動を決めないでください。直ちに観察できる結果を書き、NPCは既知の情報だけを使います。',
        'Chinese' =>
          '你是互动小说的游戏主持人。只用中文输出一到两句叙述，不要输出 JSON、选项、对话或标题。不要复述玩家行动，也不要替玩家决定想法或主动行为。描述可立即观察到的结果，NPC 只能使用已知信息。',
        _ =>
          'You are the Game Master for an interactive novel. Output only one or two sentences of narration in $language. No JSON, choices, dialogue, or heading. Do not repeat the player action or decide the player\'s thoughts or voluntary actions. Describe an immediately observable consequence; NPCs use only known facts.',
      };

  Future<NarrativeResult?> _regenerateScene(World world, Campaign campaign,
      String action, String storyLanguage, String systemPrompt) async {
    final String location = world.locations
            .where((StoryLocation item) =>
                item.id == campaign.worldState.currentLocationId)
            .map((StoryLocation item) => item.name)
            .firstOrNull ??
        '';
    final String characters = world.characters
        .where((StoryCharacter item) =>
            campaign.worldState.presentCharacterIds.contains(item.id))
        .map((StoryCharacter item) =>
            '${item.name}: ${item.personality}; known facts: ${_knownNpcFacts(item, campaign)}')
        .join('\n');
    final List<SceneTurn> previousTurns =
        campaign.history.reversed.take(4).toList().reversed.toList();
    final String previous = previousTurns
        .map((SceneTurn item) =>
            'Player action: ${item.playerAction ?? '(opening)'}\n'
            'Narration: ${item.narration}\n'
            'Dialogue: ${item.dialogue.map((SceneDialogue line) => '${line.characterId}: ${line.text}').join(' / ')}\n'
            'Choices: ${item.choices.join(' / ')}')
        .join('\n\n');
    final String recentChoiceList = previousTurns
        .expand((SceneTurn item) => item.choices)
        .toSet()
        .join(' / ');
    final String choiceExamples = switch (campaign.languageCode) {
      'ko' => '"현재 장소에서 달라진 흔적을 살펴본다.","주변의 다른 단서를 확인한다."',
      'ja' => '"この場所で変化した痕跡を調べる。","周囲にある別の手がかりを確かめる。"',
      'zh' => '"检查这个地点出现的变化痕迹。","查看周围的其他线索。"',
      _ =>
        '"Examine what has changed in this location.","Check another clue in the surroundings."',
    };
    final String schema =
        'Output one JSON object with schemaVersion=1, a nonempty narration, and exactly two distinct, nonempty player actions in choices. Example action choices: [$choiceExamples]. The dialogue key is optional; if included, it must be an array of zero to two lines. Use an empty array or omit dialogue when no one needs to speak. If dialogue is present, use only IDs of NPCs listed as visible in this scene. Never invent an NPC. Do not put a character reaction or scene description in choices. No markdown or extra text.';
    final String prompt = storyLanguage == 'Korean'
        ? '''당신은 이 장면의 게임 마스터다. 모든 플레이어용 문장은 한국어로 쓴다. 내부 인물·장소 ID는 발화자를 지정하는 JSON 필드에서만 사용하고 나레이션, 대사, 선택지에는 절대 노출하지 않는다. 플레이어에게는 세계 설정에 적힌 이름만 보여준다. $schema
장소: $location
현재 보이는 인물과 알려진 성격/정보:
$characters
최근 장면 기록(대사와 선택지를 그대로 반복하지 않는다):
Previously offered choices that must not be repeated or paraphrased: $recentChoiceList
$previous
플레이어가 방금 한 행동: $action
-플레이어 행동을 나레이션으로 다시 쓰거나 바꿔 말하지 않는다. 플레이어가 NPC에게 질문하면 그 NPC가 아는 내용에 근거해 답한다. 질문 자체를 되풀이하거나 모르는 정보를 지어내지 않는다. NPC 대사는 선택사항이며 빈 대사 배열도 유효하다. 보이는 NPC가 없으면 인물을 새로 만들지 말고 주변 관찰이나 환경 변화만으로 진행한다. 플레이어가 독백을 명시적으로 선택한 경우에만 그 독백을 반영한다. 물건을 살펴본 행동이라면 그 대상에서 새로 관찰되는 결과를 쓴다. 일반 턴 나레이션은 NPC 반응이나 환경 변화를 중심으로 쓴다. 이전 장면의 나레이션, 대사, 선택지를 그대로 반복하지 않는다. 플레이어의 자발적 행동이나 판단은 대신 정하지 않는다. 선택지는 정확히 두 개다. 각각 지금 플레이어가 직접 할 수 있는 서로 다른 행동 문장으로 쓴.'''
        : '''You are the Game Master for this scene. Write all player-facing text in $storyLanguage. $schema
Location: $location
Visible NPCs and their known traits/facts:
$characters
Recent scene history (do not repeat dialogue or choices verbatim):
Previously offered choices that must not be repeated or paraphrased: $recentChoiceList
$previous
Player action: $action
Do not restate or paraphrase the player action as narration. When the player addresses a visible NPC, answer using only facts that character knows; do not repeat the question or invent information. NPC dialogue is optional. An empty dialogue array is valid. If no NPC is visible, do not invent one; advance the scene through environmental observation or consequences. Include a player monologue only when the player explicitly chose it. Do not repeat any recent narration, dialogue, or choices verbatim. Do not decide the player's body, emotions, thoughts, or voluntary actions. Return exactly two distinct action sentences that the player can take now; choices are not character reactions or scene descriptions.''';
    _narrationRepairFailure = null;
    for (int attempt = 0; attempt < 2; attempt++) {
      String raw = '';
      try {
        await for (final String chunk in ref.read(llmProvider).stream(
              attempt == 0
                  ? prompt
                  : '$prompt\n${storyLanguage == 'Korean' ? '이전 출력 오류: $_narrationRepairFailure. 같은 오류를 수정하고 위 JSON 자료형과 필드 규칙을 정확히 지킨다. 플레이어를 언급하지 말고 목록과 다른 환경 또는 NPC 반응만 새로 쓴다.' : 'Previous output error: $_narrationRepairFailure. Correct it and follow the JSON types and fields exactly. Do not mention the player. Write a fresh environmental or NPC reaction unlike every listed sentence.'}',
              state.settings,
              apiKey: _apiKey,
              maxTokens: 768,
              systemPrompt: systemPrompt,
              jsonMode: true,
            )) {
          if (_cancelled) throw const LlmException('Generation cancelled.');
          raw += chunk;
          if (raw.length > 4000) break;
        }
      } on LlmException {
        rethrow;
      } catch (error) {
        _narrationRepairFailure = error.runtimeType.toString();
        continue;
      }
      final String response = raw.trim();
      try {
        final NarrativeResult candidate = NarrativeResult.parse(
          response,
          campaign.worldState.presentCharacterIds.toSet(),
          minimumChoices: 1,
        );
        final bool repeatsRecent = campaign.history.reversed.take(6).any(
            (SceneTurn item) =>
                _similarity(item.narration, candidate.narration) >= 0.68);
        final bool echoesAction = action.trim().length >= 5 &&
            _echoesAction(candidate.narration, action);
        final Iterable<String> allText = <String>[
          candidate.narration,
          ...candidate.dialogue.map((SceneDialogue line) => line.text),
          ...candidate.choices,
        ];
        final bool wrongLanguage = storyLanguage == 'Korean' &&
            allText.any((String text) => !RegExp(r'[가-힣]').hasMatch(text));
        final Set<String> recentDialogue = campaign.history.reversed
            .take(4)
            .expand((SceneTurn turn) => turn.dialogue.map(
                (SceneDialogue line) => _normalizeNarrativeText(line.text)))
            .toSet();
        final NarrativeResult sceneWithoutRepeatedDialogue =
            _removeRepeatedDialogue(candidate, recentDialogue);
        final bool describesPlayerAgency = _describesPlayerAgency(
            candidate.narration, world.playerDefinition.name, storyLanguage,
            otherCharacterNames:
                world.characters.map((StoryCharacter item) => item.name));
        if (candidate.narration.isEmpty ||
            echoesAction ||
            repeatsRecent ||
            describesPlayerAgency ||
            wrongLanguage) {
          _narrationRepairFailure = repeatsRecent
              ? 'response repeated recent narration: ${candidate.narration.substring(0, candidate.narration.length.clamp(0, 240))}'
              : echoesAction
                  ? 'response echoed the player action: ${candidate.narration.substring(0, candidate.narration.length.clamp(0, 240))}'
                  : describesPlayerAgency
                      ? 'response invented player agency: ${candidate.narration.substring(0, candidate.narration.length.clamp(0, 240))}'
                      : 'response was invalid or not in $storyLanguage';
          continue;
        }
        return sceneWithoutRepeatedDialogue;
      } on FormatException catch (error) {
        _narrationRepairFailure =
            'invalid full-scene JSON: ${error.message}; ${response.substring(0, response.length.clamp(0, 400))}';
      }
    }
    return null;
  }
}

String _knownNpcFacts(StoryCharacter character, Campaign campaign) => {
      character.publicInformation.trim(),
      ...?campaign.characterMemory[character.id]?.knownFacts
          .map((String fact) => fact.trim()),
    }.where((String fact) => fact.isNotEmpty).join('; ');

String _normalizeNarrativeText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

NarrativeResult _removeActionEchoDialogue(
    NarrativeResult result, Iterable<String> actions) {
  final List<String> normalizedActions = actions
      .map(_normalizeNarrativeText)
      .where((String action) => action.isNotEmpty)
      .toList();
  return NarrativeResult(
    narration: result.narration,
    dialogue: result.dialogue.where((SceneDialogue line) {
      final String normalizedLine = _normalizeNarrativeText(line.text);
      return normalizedLine.isNotEmpty &&
          normalizedActions.every((String action) =>
              !action.contains(normalizedLine) &&
              !normalizedLine.contains(action) &&
              !_echoesAction(line.text, action));
    }).toList(),
    choices: result.choices,
    sceneChanges: result.sceneChanges,
    npcChanges: result.npcChanges,
    events: result.events,
    stateChanges: result.stateChanges,
    memoryUpdates: result.memoryUpdates,
  );
}

NarrativeResult _removeRelayChoices(
    NarrativeResult result, String languageCode) {
  final RegExp relays = switch (languageCode) {
    'ko' => RegExp(r'(?:라고|다고|냐고)\s*(?:말|전하|설명|알리)|에게.{0,18}말하기|\b케어\b',
        caseSensitive: false),
    'ja' => RegExp(r'(?:と|って)(?:伝え|話し|説明し|知らせ)'),
    'zh' => RegExp(r'(?:告诉|转告|向.+说)'),
    _ => RegExp(r'^(?:tell|report|inform|explain to)\b', caseSensitive: false),
  };
  return NarrativeResult(
    narration: result.narration,
    dialogue: result.dialogue,
    choices: result.choices
        .where((String choice) => !relays.hasMatch(choice.trim()))
        .toList(),
    sceneChanges: result.sceneChanges,
    npcChanges: result.npcChanges,
    events: result.events,
    stateChanges: result.stateChanges,
    memoryUpdates: result.memoryUpdates,
  );
}

NarrativeResult _boundNpcKnowledge(NarrativeResult result, World world,
    Campaign campaign, String action, String languageCode) {
  final Set<String> activeIds = campaign.worldState.presentCharacterIds.toSet();
  final List<SceneDialogue> dialogue =
      result.dialogue.where((SceneDialogue line) {
    final StoryCharacter? speaker = world.characters
        .where((StoryCharacter item) => item.id == line.characterId)
        .firstOrNull;
    if (speaker == null) return false;
    final CharacterMemory? memory = campaign.characterMemory[speaker.id];
    final List<String> establishedFacts = <String>[
      speaker.publicInformation,
      ...?memory?.knownFacts,
      ...campaign.worldState.facts.values,
    ];
    final bool secretDiscovered = establishedFacts.any((String fact) =>
        _informationOverlap(speaker.secretInformation, fact) >= 0.6);
    final bool repeatsUndiscoveredSecret =
        speaker.secretInformation.isNotEmpty &&
            !secretDiscovered &&
            _informationOverlap(speaker.secretInformation, line.text) >= 0.6;
    return activeIds.contains(speaker.id) && !repeatsUndiscoveredSecret;
  }).toList();

  final String? requestedSpeakerName =
      _requestedNpcName(action, world, activeIds);
  final StoryCharacter? requestedCharacter = world.characters
      .where((StoryCharacter item) =>
          activeIds.contains(item.id) &&
          (requestedSpeakerName == null || item.name == requestedSpeakerName))
      .firstOrNull;
  final bool asksNpcQuestion =
      requestedSpeakerName != null && _isQuestionIntent(action);
  final List<SceneDialogue> groundedDialogue = asksNpcQuestion
      ? _preventNpcQuestionBack(
          dialogue, requestedCharacter?.id, action, languageCode)
      : dialogue;
  final List<SceneDialogue> nonRepeatedDialogue = _replaceRepeatedNpcAnswers(
    groundedDialogue,
    requestedCharacter?.id,
    action,
    campaign,
    languageCode,
  );
  final List<SceneDialogue> factBoundDialogue = requestedCharacter != null &&
          _isSpecificFactQuestion(action, languageCode) &&
          !_hasKnownQuestionTopic(
            action,
            languageCode,
            _factsSupportingQuestion(
              action,
              requestedCharacter,
              world,
              campaign,
              languageCode,
            ),
          )
      ? _replaceNpcAnswerWithUnknown(
          nonRepeatedDialogue, requestedCharacter.id, languageCode)
      : nonRepeatedDialogue;
  final List<SceneDialogue> answeredDialogue = asksNpcQuestion &&
          requestedCharacter != null &&
          !factBoundDialogue.any(
              (SceneDialogue line) => line.characterId == requestedCharacter.id)
      ? <SceneDialogue>[
          ...factBoundDialogue,
          SceneDialogue(
            characterId: requestedCharacter.id,
            text:
                _unknownNpcReply(campaign, requestedCharacter.id, languageCode),
          ),
        ]
      : factBoundDialogue;
  final List<SceneDialogue> conciseDialogue =
      _isConciseWhyAction(action, languageCode) && requestedCharacter != null
          ? _replaceNpcDialogue(
              answeredDialogue,
              requestedCharacter.id,
              switch (languageCode) {
                'ko' => '그냥 신경이 쓰여서.',
                'ja' => 'ただ気になっただけ。',
                'zh' => '就是有点在意。',
                _ => 'It just bothered me.',
              },
            )
          : answeredDialogue;
  if (requestedCharacter != null &&
      _directlyAsksAboutAccessCardLoan(
          action, requestedCharacter.secretInformation, languageCode)) {
    return _ensureAuthoredSecretDisclosure(
      _withDialogue(result, conciseDialogue),
      action,
      world,
      campaign,
      languageCode,
    );
  }
  final bool asksSoundDirection = _asksSoundDirection(action, languageCode);
  if (!asksSoundDirection) {
    return _withDialogue(result, conciseDialogue);
  }

  final StoryCharacter? speaker = world.characters
      .where((StoryCharacter item) =>
          activeIds.contains(item.id) &&
          (requestedSpeakerName == null || item.name == requestedSpeakerName))
      .firstOrNull;
  if (speaker == null) return _withDialogue(result, conciseDialogue);
  final List<String> knownFacts = <String>[
    speaker.publicInformation,
    ...?campaign.characterMemory[speaker.id]?.knownFacts,
  ];
  StoryLocation? sourceLocation;
  int closestDistance = 1 << 30;
  for (final String fact in knownFacts) {
    if (!_hasSoundTerm(fact, languageCode)) continue;
    final int soundIndex = _soundTermIndex(fact, languageCode);
    for (final StoryLocation location in world.locations) {
      if (location.name.isEmpty) continue;
      final int locationIndex = fact.indexOf(location.name);
      if (locationIndex < 0) continue;
      final int distance =
          (soundIndex - (locationIndex + location.name.length ~/ 2)).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        sourceLocation = location;
      }
    }
  }
  if (sourceLocation == null) return _withDialogue(result, conciseDialogue);
  final String answer = switch (languageCode) {
    'ko' => '${sourceLocation.name} 쪽에서 들었어.',
    'ja' => '${sourceLocation.name}のほうから聞こえたよ。',
    'zh' => '我是在${sourceLocation.name}那边听到的。',
    _ => 'I heard it from the ${sourceLocation.name}.',
  };
  final List<SceneDialogue> correctedDialogue = <SceneDialogue>[
    ...factBoundDialogue
        .where((SceneDialogue line) => line.characterId != speaker.id),
    SceneDialogue(characterId: speaker.id, text: answer),
  ];
  if (_echoesAction(result.narration, action) ||
      _describesPlayerAgency(result.narration, world.playerDefinition.name,
          _languageName(languageCode),
          otherCharacterNames:
              world.characters.map((StoryCharacter item) => item.name))) {
    return _withDialogue(result, correctedDialogue);
  }
  return _withNarrationAndDialogue(
    result,
    switch (languageCode) {
      'ko' => '금속 소리는 ${sourceLocation.name}에서 났다.',
      'ja' => '金属音は${sourceLocation.name}から聞こえた。',
      'zh' => '金属声是从${sourceLocation.name}传来的。',
      _ => 'The metallic sound came from ${sourceLocation.name}.',
    },
    correctedDialogue,
  );
}

NarrativeResult _ensureNpcQuestionAnswered(NarrativeResult result,
    String action, World world, Campaign campaign, String languageCode) {
  final Set<String> activeIds = campaign.worldState.presentCharacterIds.toSet();
  if (!_isQuestionIntent(action)) return result;
  final String? requestedName = _requestedNpcName(action, world, activeIds);
  if (requestedName == null) return result;
  final StoryCharacter? speaker = world.characters
      .where((StoryCharacter item) =>
          activeIds.contains(item.id) && item.name == requestedName)
      .firstOrNull;
  if (speaker == null ||
      result.dialogue
          .any((SceneDialogue line) => line.characterId == speaker.id)) {
    return result;
  }
  return _withDialogue(result, <SceneDialogue>[
    ...result.dialogue,
    SceneDialogue(
        characterId: speaker.id,
        text: _unknownNpcReply(campaign, speaker.id, languageCode)),
  ]);
}

NarrativeResult _ensureAuthoredSecretDisclosure(NarrativeResult result,
    String action, World world, Campaign campaign, String languageCode) {
  final Set<String> activeIds = campaign.worldState.presentCharacterIds.toSet();
  final String? requestedName = _requestedNpcName(action, world, activeIds);
  if (requestedName == null && activeIds.length != 1) return result;
  final StoryCharacter? speaker = world.characters
      .where((StoryCharacter item) =>
          activeIds.contains(item.id) &&
          (requestedName == null || item.name == requestedName))
      .firstOrNull;
  if (speaker == null ||
      !_directlyAsksAboutAccessCardLoan(
          action, speaker.secretInformation, languageCode)) {
    return result;
  }

  final bool hasLoanedCard =
      _secretAffirmsAccessCardLoan(speaker.secretInformation, languageCode);
  final String answer = switch (languageCode) {
    'ko' => hasLoanedCard ? '응, 실험실 카드키를 빌려준 적 있어.' : '아니, 실험실 카드키를 빌려준 적 없어.',
    'ja' =>
      hasLoanedCard ? 'うん、実験室のカードキーを貸したことがある。' : 'ううん、実験室のカードキーを貸したことはない。',
    'zh' => hasLoanedCard ? '嗯，我借出过实验室门禁卡。' : '没有，我没借出过实验室门禁卡。',
    _ => hasLoanedCard
        ? 'Yes, I have lent out the lab key card.'
        : 'No, I have not lent out the lab key card.',
  };
  final String revealedFact = switch (languageCode) {
    'ko' => hasLoanedCard
        ? '윤서는 실험실 카드키를 빌려준 적이 있다고 인정했다.'
        : '윤서는 실험실 카드키를 빌려준 적이 없다고 말했다.',
    'ja' => hasLoanedCard
        ? 'ユンソは実験室のカードキーを貸したことがあると認めた。'
        : 'ユンソは実験室のカードキーを貸したことがないと話した。',
    'zh' => hasLoanedCard ? '允书承认曾借出实验室门禁卡。' : '允书说她没有借出实验室门禁卡。',
    _ => hasLoanedCard
        ? 'Yoon admitted lending out the lab key card.'
        : 'Yoon said she had not lent out the lab key card.',
  };
  return _withDialogueAndMemoryUpdate(
    result,
    _replaceNpcDialogue(result.dialogue, speaker.id, answer),
    speaker.id,
    revealedFact,
  );
}

NarrativeResult _ensureSpecificFactAnswerGrounded(NarrativeResult result,
    String action, World world, Campaign campaign, String languageCode) {
  if (!_isSpecificFactQuestion(action, languageCode)) return result;
  final Set<String> activeIds = campaign.worldState.presentCharacterIds.toSet();
  final String? requestedName = _requestedNpcName(action, world, activeIds);
  if (requestedName == null && activeIds.length != 1) return result;
  final StoryCharacter? speaker = world.characters
      .where((StoryCharacter item) =>
          activeIds.contains(item.id) &&
          (requestedName == null || item.name == requestedName))
      .firstOrNull;
  if (speaker == null) return result;
  final List<String> knownFacts = _factsSupportingQuestion(
    action,
    speaker,
    world,
    campaign,
    languageCode,
  );
  if (_hasKnownQuestionTopic(action, languageCode, knownFacts)) return result;
  return _withDialogue(
    result,
    _replaceNpcAnswerWithUnknown(result.dialogue, speaker.id, languageCode),
  );
}

NarrativeResult _ensureNoRepeatedNpcAnswer(NarrativeResult result,
    String action, World world, Campaign campaign, String languageCode) {
  final Set<String> activeIds = campaign.worldState.presentCharacterIds.toSet();
  final String? requestedName = _requestedNpcName(action, world, activeIds);
  if (requestedName == null && activeIds.length != 1) return result;
  final String? speakerId = world.characters
      .where((StoryCharacter item) =>
          activeIds.contains(item.id) &&
          (requestedName == null || item.name == requestedName))
      .map((StoryCharacter item) => item.id)
      .firstOrNull;
  if (speakerId == null) return result;
  return _withDialogue(
    result,
    _replaceRepeatedNpcAnswers(
      result.dialogue,
      speakerId,
      action,
      campaign,
      languageCode,
    ),
  );
}

NarrativeResult _ensureConciseWhyAnswered(NarrativeResult result, String action,
    World world, Campaign campaign, String languageCode) {
  if (!_isConciseWhyAction(action, languageCode)) return result;
  final Set<String> activeIds = campaign.worldState.presentCharacterIds.toSet();
  final String? requestedName = _requestedNpcName(action, world, activeIds);
  if (requestedName == null) return result;
  final StoryCharacter? speaker = world.characters
      .where((StoryCharacter item) =>
          activeIds.contains(item.id) && item.name == requestedName)
      .firstOrNull;
  if (speaker == null) return result;
  return _withDialogue(
      result,
      _replaceNpcDialogue(
          result.dialogue,
          speaker.id,
          switch (languageCode) {
            'ko' => '그냥 신경이 쓰여서.',
            'ja' => 'ただ気になっただけ。',
            'zh' => '就是有点在意。',
            _ => 'It just bothered me.',
          }));
}

bool _isConciseWhyAction(String action, String languageCode) =>
    switch (languageCode) {
      'ko' => _normalizeNarrativeText(action).length <= 18 &&
          RegExp(r'왜').hasMatch(action),
      'ja' => _normalizeNarrativeText(action).length <= 18 &&
          RegExp(r'なぜ|どうして').hasMatch(action),
      'zh' => _normalizeNarrativeText(action).length <= 18 &&
          RegExp(r'为什么|为何').hasMatch(action),
      _ => _normalizeNarrativeText(action).length <= 24 &&
          RegExp(r'\bwhy\b', caseSensitive: false).hasMatch(action),
    };

List<SceneDialogue> _replaceNpcDialogue(
        List<SceneDialogue> dialogue, String speakerId, String text) =>
    <SceneDialogue>[
      ...dialogue.where((SceneDialogue line) => line.characterId != speakerId),
      SceneDialogue(characterId: speakerId, text: text),
    ];

NarrativeResult _respectExplicitNpcRefusal(NarrativeResult result,
    String action, World world, Campaign campaign, String languageCode) {
  final bool refused = switch (languageCode) {
    'ko' => RegExp(r'(?:거절|싫어|안\s*(?:할|하겠|도와)|원치 않)').hasMatch(action),
    'ja' => RegExp(r'(?:断る|嫌だ|したくない)').hasMatch(action),
    'zh' => RegExp(r'(?:拒绝|不愿意|不想)').hasMatch(action),
    _ => RegExp(r'\b(?:refuse|decline|no)\b', caseSensitive: false)
        .hasMatch(action),
  };
  if (!refused) return result;

  final Set<String> activeIds = campaign.worldState.presentCharacterIds.toSet();
  final String? requestedName = _requestedNpcName(action, world, activeIds);
  final StoryCharacter? speaker = world.characters
      .where((StoryCharacter item) =>
          activeIds.contains(item.id) &&
          (requestedName == null || item.name == requestedName))
      .firstOrNull;
  if (speaker == null) return result;
  final String acknowledgement = switch (languageCode) {
    'ko' => '알겠어. 다른 방법을 찾아볼게.',
    'ja' => '分かった。別の方法を考えるね。',
    'zh' => '好吧，我再想别的办法。',
    _ => 'All right. I will find another way.',
  };
  return _withDialogue(result, <SceneDialogue>[
    ...result.dialogue
        .where((SceneDialogue line) => line.characterId != speaker.id),
    SceneDialogue(characterId: speaker.id, text: acknowledgement),
  ]);
}

NarrativeResult _withNarrationAndDialogue(NarrativeResult result,
        String narration, List<SceneDialogue> dialogue) =>
    NarrativeResult(
      narration: narration,
      dialogue: dialogue,
      choices: result.choices,
      sceneChanges: result.sceneChanges,
      npcChanges: result.npcChanges,
      events: result.events,
      stateChanges: result.stateChanges,
      memoryUpdates: result.memoryUpdates,
    );

List<SceneDialogue> _preventNpcQuestionBack(List<SceneDialogue> dialogue,
    String? speakerId, String action, String languageCode) {
  if (speakerId == null) return dialogue;
  final List<SceneDialogue> result = <SceneDialogue>[];
  bool replaced = false;
  for (final SceneDialogue line in dialogue) {
    final bool asksPlayer = _containsInterrogative(line.text) &&
        _similarity(line.text, action) >= 0.12;
    if (line.characterId != speakerId || !asksPlayer) {
      result.add(line);
      continue;
    }
    if (replaced) continue;
    replaced = true;
    result.add(SceneDialogue(
      characterId: speakerId,
      text: switch (languageCode) {
        'ko' => '그건 지금은 잘 모르겠어.',
        'ja' => 'それは今はよく分からない。',
        'zh' => '这个我现在不太清楚。',
        _ => 'I am not sure about that right now.',
      },
    ));
  }
  return result;
}

List<SceneDialogue> _replaceRepeatedNpcAnswers(List<SceneDialogue> dialogue,
    String? speakerId, String action, Campaign campaign, String languageCode) {
  if (speakerId == null || !_isQuestionIntent(action)) return dialogue;
  final List<SceneTurn> previousTurns = campaign.history.reversed.toList();
  final List<SceneDialogue> result = <SceneDialogue>[];
  bool insertedUnknown = false;
  for (final SceneDialogue line in dialogue) {
    final bool repeatsAnUnrelatedAnswer = previousTurns.any((SceneTurn turn) {
      if (turn.playerAction == null ||
          _similarity(turn.playerAction!, action) >= 0.52) {
        return false;
      }
      return turn.dialogue.any((SceneDialogue previous) =>
          previous.characterId == speakerId &&
          _similarity(previous.text, line.text) >= 0.86);
    });
    if (line.characterId != speakerId || !repeatsAnUnrelatedAnswer) {
      result.add(line);
      continue;
    }
    if (!insertedUnknown) {
      result.add(SceneDialogue(
        characterId: speakerId,
        text: _unknownNpcReply(campaign, speakerId, languageCode),
      ));
      insertedUnknown = true;
    }
  }
  return result;
}

bool _isSpecificFactQuestion(String action, String languageCode) {
  if (_accessCardPattern(languageCode)?.hasMatch(action) ?? false) {
    return _asksWhoHoldsAccessCard(action, languageCode) ||
        _asksAboutAccessCardLoan(action, languageCode);
  }
  return switch (languageCode) {
    'ko' => RegExp(
            r'(?:언제|몇\s*시|시각|누구|어디서|어느\s*쪽).*(?:봤|본|들었|있었|마지막|발견)|(?:봤|본|들었|있었|발견).*(?:언제|몇\s*시|시각|누구|어디서|어느\s*쪽)|(?:누구|누가).*(?:가진|소유|빌려|가지고)|(?:가진|소유|빌려|가지고).*(?:누구|누가)')
        .hasMatch(action),
    'ja' => RegExp(r'(?:いつ|何時|誰|どこ).*(?:見|聞|いた|最後)|(?:見|聞|いた).*(?:いつ|何時|誰|どこ)')
        .hasMatch(action),
    'zh' => RegExp(
            r'(?:什么时候|几点|谁|哪里).*(?:看见|听见|出现|最后)|(?:看见|听见|出现).*(?:什么时候|几点|谁|哪里)')
        .hasMatch(action),
    _ => RegExp(
            r'(?:when|what time|who|where).*(?:see|saw|hear|heard|last)|(?:see|saw|hear|heard|last).*(?:when|what time|who|where)',
            caseSensitive: false)
        .hasMatch(action),
  };
}

bool _hasKnownQuestionTopic(
    String action, String languageCode, List<String> knownFacts) {
  if (_isSpecificTimeQuestion(action, languageCode)) {
    return knownFacts.any((String fact) =>
        _factIncludesWitnessAndTime(fact, action, languageCode));
  }
  final RegExp? accessCard = _accessCardPattern(languageCode);
  if (accessCard != null && accessCard.hasMatch(action)) {
    return knownFacts.any((String fact) => accessCard.hasMatch(fact));
  }
  final Set<String> questionTerms = _informationTerms(action);
  if (questionTerms.isEmpty) return false;
  return knownFacts.any((String fact) =>
      questionTerms.intersection(_informationTerms(fact)).length >= 2);
}

List<String> _factsSupportingQuestion(String action, StoryCharacter character,
    World world, Campaign campaign, String languageCode) {
  final RegExp? accessCard = _accessCardPattern(languageCode);
  if (accessCard == null || !accessCard.hasMatch(action)) {
    return <String>[
      character.publicInformation,
      ...?campaign.characterMemory[character.id]?.knownFacts,
    ];
  }
  final List<String> groundedCardFacts = <String>[
    character.publicInformation,
    ...campaign.history
        .expand((SceneTurn turn) => turn.dialogue)
        .where((SceneDialogue line) =>
            line.characterId == character.id && accessCard.hasMatch(line.text))
        .map((SceneDialogue line) => line.text),
  ].where((String fact) => accessCard.hasMatch(fact)).toList();
  if (_asksWhoHoldsAccessCard(action, languageCode) &&
      !groundedCardFacts.any((String fact) => world.characters.any(
          (StoryCharacter knownCharacter) =>
              fact.contains(knownCharacter.name)))) {
    return const <String>[];
  }
  return groundedCardFacts;
}

bool _asksWhoHoldsAccessCard(String action, String languageCode) =>
    switch (languageCode) {
      'ko' =>
        RegExp(r'(?:누구|누가).{0,20}(?:가진|소유|가지고)|(?:가진|소유|가지고).{0,20}(?:누구|누가)')
            .hasMatch(action),
      'ja' => RegExp(r'誰.{0,16}(?:持|所有)|(?:持|所有).{0,16}誰').hasMatch(action),
      'zh' => RegExp(r'谁.{0,16}(?:有|持)|(?:有|持).{0,16}谁').hasMatch(action),
      _ => RegExp(
              r'who.{0,32}(?:has|holds|carries)|(?:has|holds|carries).{0,32}who',
              caseSensitive: false)
          .hasMatch(action),
    };

bool _asksAboutAccessCardLoan(String action, String languageCode) =>
    switch (languageCode) {
      'ko' => RegExp(r'(?:빌려|대여)').hasMatch(action),
      'ja' => RegExp(r'(?:貸し|借り)').hasMatch(action),
      'zh' => RegExp(r'(?:借|出借)').hasMatch(action),
      _ => RegExp(r'\b(?:lend|lent|loan|loaned|borrow|borrowed)\w*\b',
              caseSensitive: false)
          .hasMatch(action),
    };

RegExp? _accessCardPattern(String languageCode) => switch (languageCode) {
      'ko' => RegExp(r'(?:카드\s*키|카드키|키카드|출입\s*카드)'),
      'ja' => RegExp(r'(?:カードキー|キーカード|入館カード)'),
      'zh' => RegExp(r'(?:门禁卡|门卡|钥匙卡|卡钥匙)'),
      _ =>
        RegExp(r'(?:key\s*card|keycard|access\s*card)', caseSensitive: false),
    };

bool _directlyAsksAboutAccessCardLoan(
        String action, String secret, String languageCode) =>
    _isQuestionIntent(action) &&
    _asksAboutAccessCardLoan(action, languageCode) &&
    (_accessCardPattern(languageCode)?.hasMatch(action) ?? false) &&
    (_accessCardPattern(languageCode)?.hasMatch(secret) ?? false) &&
    switch (languageCode) {
      'ko' => RegExp(r'(?:빌려준|빌려주는|빌려주고|대여)').hasMatch(secret),
      'ja' => RegExp(r'(?:貸し|貸した|貸して)').hasMatch(secret),
      'zh' => RegExp(r'(?:借给|出借)').hasMatch(secret),
      _ => RegExp(r'\b(?:lent|loaned|borrowed)\b', caseSensitive: false)
          .hasMatch(secret),
    };

bool _secretAffirmsAccessCardLoan(String secret, String languageCode) {
  final bool hasLoan = switch (languageCode) {
    'ko' => RegExp(r'(?:빌려준|빌려주는|빌려주고|대여)').hasMatch(secret),
    'ja' => RegExp(r'(?:貸し|貸した|貸して)').hasMatch(secret),
    'zh' => RegExp(r'(?:借给|出借)').hasMatch(secret),
    _ => RegExp(r'\b(?:lent|loaned)\b', caseSensitive: false).hasMatch(secret),
  };
  final bool deniesLoan = switch (languageCode) {
    'ko' => RegExp(r'(?:빌려준|대여한)\s*(?:적이\s*)?없|빌려주지\s*않').hasMatch(secret),
    'ja' => RegExp(r'(?:貸したことがない|貸していない)').hasMatch(secret),
    'zh' => RegExp(r'(?:没借|没有借|未曾借)').hasMatch(secret),
    _ => RegExp(r'\b(?:never lent|did not lend|has not lent|never loaned)\b',
            caseSensitive: false)
        .hasMatch(secret),
  };
  return hasLoan && !deniesLoan;
}

NarrativeResult _withDialogueAndMemoryUpdate(NarrativeResult result,
        List<SceneDialogue> dialogue, String characterId, String fact) =>
    NarrativeResult(
      narration: result.narration,
      dialogue: dialogue,
      choices: result.choices,
      sceneChanges: result.sceneChanges,
      npcChanges: result.npcChanges,
      events: result.events,
      stateChanges: result.stateChanges,
      memoryUpdates: <String, List<String>>{
        ...result.memoryUpdates,
        characterId: <String>[
          ...?result.memoryUpdates[characterId],
          fact,
        ],
      },
    );

bool _isSpecificTimeQuestion(String action, String languageCode) =>
    switch (languageCode) {
      'ko' =>
        RegExp(r'(?:언제|몇\s*시|시각).*(?:봤|본|보았|목격)|(?:봤|본|보았|목격).*(?:언제|몇\s*시|시각)')
            .hasMatch(action),
      'ja' =>
        RegExp(r'(?:いつ|何時).*(?:見|目撃)|(?:見|目撃).*(?:いつ|何時)').hasMatch(action),
      'zh' => RegExp(r'(?:什么时候|几点).*(?:看见|看到|目击)|(?:看见|看到|目击).*(?:什么时候|几点)')
          .hasMatch(action),
      _ => RegExp(
              r'(?:when|what time).*(?:saw|seen|witnessed)|(?:saw|seen|witnessed).*(?:when|what time)',
              caseSensitive: false)
          .hasMatch(action),
    };

bool _factIncludesWitnessAndTime(
    String fact, String action, String languageCode) {
  final bool witnessed = switch (languageCode) {
    'ko' => RegExp(r'(?:봤|본|보았|목격)').hasMatch(fact),
    'ja' => RegExp(r'(?:見た|見て|目撃)').hasMatch(fact),
    'zh' => RegExp(r'(?:看见|看到|目击)').hasMatch(fact),
    _ => RegExp(r'\b(?:saw|seen|witnessed)\b', caseSensitive: false)
        .hasMatch(fact),
  };
  final bool hasTime = switch (languageCode) {
    'ko' =>
      RegExp(r'(?:\d{1,2}\s*시|\d{1,2}\s*분|새벽|오전|오후|밤|어제|오늘|저녁)').hasMatch(fact),
    'ja' => RegExp(r'(?:[0-9０-９]+時|分|夜|朝|昨日|昼)').hasMatch(fact),
    'zh' =>
      RegExp(r'(?:[0-9０-９]+点|[0-9０-９]+时|分|凌晨|上午|下午|晚上|昨天|今天)').hasMatch(fact),
    _ => RegExp(
            r'(?:\bat\s+\d|\d\s*(?:am|pm)|o.?clock|hour|minute|yesterday|last night|morning|afternoon|evening)',
            caseSensitive: false)
        .hasMatch(fact),
  };
  final bool matchesAskedSubject = switch (languageCode) {
    'ko' => (!action.contains('사람') || fact.contains('사람')) &&
        (!action.contains('계단') || fact.contains('계단')),
    'ja' => (!action.contains('人') || fact.contains('人')) &&
        (!action.contains('階段') || fact.contains('階段')),
    'zh' => (!action.contains('人') || fact.contains('人')) &&
        (!action.contains('楼梯') || fact.contains('楼梯')),
    _ => true,
  };
  return witnessed && hasTime && matchesAskedSubject;
}

List<SceneDialogue> _replaceNpcAnswerWithUnknown(
    List<SceneDialogue> dialogue, String speakerId, String languageCode) {
  return <SceneDialogue>[
    ...dialogue.where((SceneDialogue line) => line.characterId != speakerId),
    SceneDialogue(
      characterId: speakerId,
      text: switch (languageCode) {
        'ko' => '그건 정확히 기억나지 않아.',
        'ja' => 'それははっきり覚えていない。',
        'zh' => '这个我记不太清楚。',
        _ => 'I do not remember that clearly.',
      },
    ),
  ];
}

bool _openingExplainsPlayerPurpose(
    String narration, World world, String languageCode) {
  final String authoredContext =
      '${world.playerDefinition.background} ${world.openingDefinition.situation}';
  final String playerName = RegExp.escape(world.playerDefinition.name);
  final String authoredPurposePattern = switch (languageCode) {
    'ko' => r'(?:하러|하기\s*위해|하려고|때문에|찾으러|보러|담당|근무|방문|목적)',
    'ja' => r'(?:ため|ようと|目的|向か|働きに|通う)',
    'zh' => r'(?:为了|打算|前往|工作|上学|寻找)',
    _ => r'(?:to |in order to|because|so that|for work|to find)',
  };
  final String narratedPurposePattern = switch (languageCode) {
    'ko' => r'(?:하러|하기\s*위해|때문에|찾으러|보러|담당|근무|방문|목적|확인|조사|점검|알아보|살피)',
    'ja' => r'(?:ため|目的|働きに|通う)',
    'zh' => r'(?:为了|前往|工作|上学|寻找)',
    _ => authoredPurposePattern,
  };
  if (!RegExp(authoredPurposePattern, caseSensitive: false)
      .hasMatch(authoredContext)) {
    return true;
  }
  final String knownSubjects = <String>[
    playerName,
    ...world.characters.map((StoryCharacter item) => RegExp.escape(item.name)),
  ].where((String name) => name.isNotEmpty).join('|');
  final RegExp clauseBoundary = languageCode == 'ko'
      ? RegExp('(?<=[.!?。！？])\\s+|(?=(?:$knownSubjects)(?:는|가|이|도))',
          caseSensitive: false)
      : RegExp(r'(?<=[.!?。！？])\s+');
  return narration.split(clauseBoundary).any((String clause) => RegExp(
          '$playerName.{0,100}$narratedPurposePattern|$narratedPurposePattern.{0,100}$playerName',
          caseSensitive: false,
          dotAll: true)
      .hasMatch(clause));
}

String? _authoredOpeningPurpose(World world, String locationId) {
  final String locationName = world.locations
          .where((StoryLocation item) => item.id == locationId)
          .map((StoryLocation item) => item.name)
          .firstOrNull ??
      '';
  final String playerName = world.playerDefinition.name;
  if (locationName.isEmpty || playerName.isEmpty) return null;
  final RegExp purpose = RegExp(
      r'(?:하러|하기\s*위해|하려고|때문에|찾으러|보러|to\s|in order to|because|ため|ようと|为了|打算)',
      caseSensitive: false);
  final Iterable<String> sentences = <String>[
    world.openingDefinition.situation,
    world.playerDefinition.background,
  ].expand((String text) => text.split(RegExp(r'(?<=[.!?。！？])\s+|[\r\n]+')));
  return sentences
      .map((String sentence) => sentence.trim())
      .where((String sentence) => sentence.isNotEmpty && sentence.length <= 240)
      .where((String sentence) =>
          sentence.contains(playerName) &&
          sentence.contains(locationName) &&
          purpose.hasMatch(sentence))
      .firstOrNull;
}

String _removeRedundantOpeningArrival(
    String narration, String playerName, String locationName) {
  final Match? sentenceEnd = RegExp(r'[.!?。！？]').firstMatch(narration);
  if (sentenceEnd == null || sentenceEnd.end > 50) return narration;
  final String firstSentence = narration.substring(0, sentenceEnd.end);
  if (!firstSentence.contains(playerName) ||
      !firstSentence.contains(locationName) ||
      !RegExp(r'(?:왔|들어|도착|came|arriv|entered)', caseSensitive: false)
          .hasMatch(firstSentence)) {
    return narration;
  }
  final String remainder = narration.substring(sentenceEnd.end).trimLeft();
  return remainder.isEmpty ? narration : remainder;
}

bool _openingInventsPlayerAction(
    String narration, String playerName, String language) {
  final String player = RegExp.escape(playerName);
  return switch (language) {
    'Korean' => RegExp(
            '(?:$player(?:는|가|이|도)|플레이어(?:는|가|이|도)).{0,120}(?:요청(?:한다|했다|하고|한|해)|부탁(?:한다|했다|하고|한|해)|말하|대답하|관찰|(?:확인|점검|조사)(?:한다|했다|하려\\s*한다|하게\\s*된다|하고|한)|살펴(?:본다|봤다|보고)|(?:확인하고|점검하고|조사하고|살펴보고)(?:\\s*있|[, ])|시작하|고개를 끄덕|동의하|거절하|수락하|열고\\s*있|닫고\\s*있|걸어가고\\s*있|이동하고\\s*있)')
        .hasMatch(narration),
    'Japanese' =>
      RegExp('$player.{0,100}(?:確認している|調査している|頼んでいる|尋ねている|同意し|拒否し|始め|開け|歩き出し)')
          .hasMatch(narration),
    'Simplified Chinese' =>
      RegExp('$player.{0,100}(?:正在检查|正在调查|请求|拒绝|同意|开始|打开|走向)')
          .hasMatch(narration),
    _ => RegExp(
            '$player.{0,100}(?:is checking|is inspecting|asks|requests|refuses|agrees|starts|opens|walks toward|begins to)',
            caseSensitive: false)
        .hasMatch(narration),
  };
}

bool _containsInternalWorldId(NarrativeResult result, World world) {
  final List<String> visibleText = <String>[
    result.narration,
    ...result.dialogue.map((SceneDialogue line) => line.text),
    ...result.choices,
  ];
  final Iterable<String> internalIds = <String>[
    ...world.characters.map((StoryCharacter item) => item.id),
    ...world.locations.map((StoryLocation item) => item.id),
    ...world.loreEntries.map((LoreEntry item) => item.id),
  ].where((String id) => id.isNotEmpty);
  return visibleText
      .any((String text) => internalIds.any((String id) => text.contains(id)));
}

NarrativeResult _withDialogue(
        NarrativeResult result, List<SceneDialogue> dialogue) =>
    NarrativeResult(
      narration: result.narration,
      dialogue: dialogue,
      choices: result.choices,
      sceneChanges: result.sceneChanges,
      npcChanges: result.npcChanges,
      events: result.events,
      stateChanges: result.stateChanges,
      memoryUpdates: result.memoryUpdates,
    );

String? _requestedNpcName(
    String action, World world, Set<String> activeCharacterIds) {
  final StoryCharacter? character = world.characters
      .where((StoryCharacter item) =>
          activeCharacterIds.contains(item.id) && action.contains(item.name))
      .firstOrNull;
  if (character != null) return character.name;
  final Match? recipient = RegExp(r'^(.+?)(?:에게|한테)').firstMatch(action);
  if (recipient == null) return null;
  return world.characters
      .where((StoryCharacter item) =>
          activeCharacterIds.contains(item.id) &&
          (recipient.group(1)!.contains(item.name) ||
              item.name.contains(recipient.group(1)!)))
      .map((StoryCharacter item) => item.name)
      .firstOrNull;
}

bool _asksSoundDirection(String action, String languageCode) =>
    switch (languageCode) {
      'ko' => RegExp(r'(?:소리|소음).*(?:어디|어느 쪽|방향|어디서|어디로)').hasMatch(action),
      'ja' => RegExp(r'音.*(?:どこ|方向|どちら)').hasMatch(action),
      'zh' => RegExp(r'(?:声音|声响).*(?:哪里|哪边|方向)').hasMatch(action),
      _ => RegExp(r'(?:sound|noise).*(?:where|which direction|from where)',
              caseSensitive: false)
          .hasMatch(action),
    };

bool _hasSoundTerm(String text, String languageCode) => switch (languageCode) {
      'ko' => RegExp(r'(?:소리|소음)').hasMatch(text),
      'ja' => text.contains('音'),
      'zh' => RegExp(r'(?:声音|声响)').hasMatch(text),
      _ => RegExp(r'\b(?:sound|noise)\b', caseSensitive: false).hasMatch(text),
    };

int _soundTermIndex(String text, String languageCode) {
  final RegExp pattern = switch (languageCode) {
    'ko' => RegExp(r'(?:소리|소음)'),
    'ja' => RegExp(r'音'),
    'zh' => RegExp(r'(?:声音|声响)'),
    _ => RegExp(r'\b(?:sound|noise)\b', caseSensitive: false),
  };
  return pattern.firstMatch(text)?.start ?? text.length;
}

double _informationOverlap(String source, String candidate) {
  final Set<String> sourceTerms = _informationTerms(source);
  if (sourceTerms.isEmpty) return 0;
  final Set<String> candidateTerms = _informationTerms(candidate);
  return sourceTerms.intersection(candidateTerms).length / sourceTerms.length;
}

Set<String> _informationTerms(String text) {
  const Set<String> stopWords = <String>{
    'she',
    'he',
    'the',
    'that',
    'this',
    'was',
    'has',
    'had',
    '있다',
    '있었다',
    '적이',
    '있지만',
    '아직',
    '그',
    '사실을',
    '말하지',
    '않았다',
  };
  return RegExp(r'[A-Za-z0-9가-힣ぁ-んァ-ン一-龯]{2,}')
      .allMatches(text.toLowerCase())
      .map((Match match) => match.group(0)!)
      .map((String term) => term.replaceFirst(
          RegExp(r'(?:은|는|이|가|을|를|의|에|에서|에게|한테|으로|로|와|과|도|만|요)$'), ''))
      .where((String term) => term.length > 1 && !stopWords.contains(term))
      .toSet();
}

NarrativeResult _removeRepeatedDialogue(
        NarrativeResult result, Set<String> recentDialogue) =>
    NarrativeResult(
      narration: result.narration,
      dialogue: result.dialogue
          .where((SceneDialogue line) => !recentDialogue.any((String recent) =>
              recent == _normalizeNarrativeText(line.text) ||
              _similarity(recent, line.text) >= 0.68))
          .toList(),
      choices: result.choices,
      sceneChanges: result.sceneChanges,
      npcChanges: result.npcChanges,
      events: result.events,
      stateChanges: result.stateChanges,
      memoryUpdates: result.memoryUpdates,
    );

List<String> _mergeFreshChoices(List<SceneTurn> history, List<String> options,
    {List<String> fallbackChoices = const [], String lastPlayerAction = ''}) {
  final Set<String> recentChoices = history.reversed
      .take(3)
      .expand((SceneTurn turn) => turn.choices)
      .map(_normalizeNarrativeText)
      .toSet();
  final Set<String> seen = <String>{};
  final List<String> distinct = <String>[];
  for (final String choice in options) {
    final String normalized = _normalizeNarrativeText(choice);
    if (normalized.isEmpty ||
        _hasQuestionMark(choice) ||
        !seen.add(normalized)) {
      continue;
    }
    if (_repeatsQuestionAction(choice, lastPlayerAction)) {
      continue;
    }
    if (distinct
        .any((String previous) => _similarity(previous, choice) >= 0.68)) {
      continue;
    }
    distinct.add(choice);
  }
  final List<String> fresh = distinct
      .where((String choice) =>
          !recentChoices.contains(_normalizeNarrativeText(choice)))
      .take(5)
      .toList();
  if (fresh.length >= 2) return fresh;
  if (fresh.isEmpty) {
    final List<String> generatedFallbacks = fallbackChoices
        .where((String choice) => !_hasQuestionMark(choice))
        .where((String choice) =>
            !_repeatsQuestionAction(choice, lastPlayerAction))
        .where((String choice) => !recentChoices.any((String recent) =>
            recent == _normalizeNarrativeText(choice) ||
            _similarity(recent, choice) >= 0.68))
        .take(2)
        .toList();
    if (generatedFallbacks.length >= 2) return generatedFallbacks;
    return generatedFallbacks;
  }
  final List<String> selected = <String>[...fresh];
  for (final String choice in <String>[...distinct, ...fallbackChoices]) {
    if (selected.length == 2) break;
    if (_hasQuestionMark(choice)) continue;
    if (_repeatsQuestionAction(choice, lastPlayerAction)) {
      continue;
    }
    final String normalized = _normalizeNarrativeText(choice);
    if (recentChoices.any((String recent) =>
        recent == normalized || _similarity(recent, choice) >= 0.68)) {
      continue;
    }
    if (selected
        .any((String previous) => _similarity(previous, choice) >= 0.68)) {
      continue;
    }
    if (selected.every((String previous) => previous != choice)) {
      selected.add(choice);
    }
  }
  return selected;
}

bool _repeatsQuestionAction(String choice, String action) =>
    action.trim().length >= 5 &&
    (_echoesAction(choice, action) ||
        (_isQuestionIntent(action) && _similarity(choice, action) >= 0.38));

bool _actionTakesNpcAlong(String action, World world, Campaign campaign) {
  final bool namesPresentCharacter = world.characters.any(
      (StoryCharacter item) =>
          campaign.worldState.presentCharacterIds.contains(item.id) &&
          action.contains(item.name));
  if (!namesPresentCharacter) return false;
  return switch (campaign.languageCode) {
    'ko' => RegExp(r'(?:함께|같이).{0,16}(?:나가|가|이동|향하|들어가)|(?:데리고|따라오|동행)')
        .hasMatch(action),
    'ja' => RegExp(r'(?:一緒に|連れて|同行|ついて来)').hasMatch(action),
    'zh' => RegExp(r'(?:一起|带着|陪同|跟着)').hasMatch(action),
    _ =>
      RegExp(r'(?:with me|take .{1,30} along|accompany)', caseSensitive: false)
          .hasMatch(action),
  };
}

String? _explicitDestinationLocationId(String action, String languageCode,
    World world, String? currentLocationId) {
  final bool indicatesMovement = switch (languageCode) {
    'ko' => RegExp(r'(?:나가|들어가|이동|향하|달려|뛰어|떠나|돌아가|진입|걸어가)').hasMatch(action),
    'ja' => RegExp(r'(?:向か|移動|出る|入る|駆け|走る|離れる|戻る)').hasMatch(action),
    'zh' => RegExp(r'(?:走向|前往|离开|进入|跑到|返回)').hasMatch(action),
    _ => RegExp(r'\b(?:go to|head to|move to|run into|leave|enter|walk to)\b',
            caseSensitive: false)
        .hasMatch(action),
  };
  if (!indicatesMovement) return null;
  final String normalizedAction = _normalizeNarrativeText(action);
  return world.locations
      .where((StoryLocation item) => item.id != currentLocationId)
      .where((StoryLocation item) =>
          item.name.isNotEmpty &&
          normalizedAction.contains(_normalizeNarrativeText(item.name)))
      .map((StoryLocation item) => item.id)
      .firstOrNull;
}

String _arrivalNarration(StoryLocation location, String languageCode) {
  final String description = location.description.trim();
  final String grounding = description.isEmpty
      ? switch (languageCode) {
          'ko' => '새 공간의 모습이 눈앞에 펼쳐진다.',
          'ja' => '新しい場所の様子が目の前に広がる。',
          'zh' => '新的环境展现在眼前。',
          _ => 'The new surroundings come into view.',
        }
      : description;
  return switch (languageCode) {
    'ko' => '${location.name}에 들어서자, $grounding',
    'ja' => '${location.name}に着くと、$grounding',
    'zh' => '来到${location.name}，$grounding',
    _ => 'At ${location.name}, $grounding',
  };
}

List<String> _fallbackSceneChoices(
    String languageCode, String location, String character) {
  final String place = location.trim().isEmpty ? 'here' : location.trim();
  if (character.trim().isEmpty) {
    return switch (languageCode) {
      'ko' => <String>[
          '$place에서 아직 확인하지 않은 흔적을 찾아본다.',
          '$place의 다른 출입구를 살펴본다.',
          '$place의 바닥에서 발자국이나 긁힌 흔적을 찾는다.',
          '$place에 남은 물건의 위치를 기록한다.',
          '$place에서 새로 들리는 소리가 있는지 기다려 본다.',
          '$place의 문틀과 손잡이에 새 흠집이 있는지 살펴본다.',
          '$place 바닥의 물기와 발자국이 향하는 쪽을 확인한다.',
          '$place의 벽과 모서리에서 끌린 자국을 찾아본다.',
          '$place의 조명과 그림자가 달라지는지 지켜본다.',
          '$place의 바닥과 문턱에서 먼지 자국을 비교한다.',
          '$place에서 계단문 쪽으로 이어지는 흔적을 따라가 본다.',
          '$place의 출입구 주변에서 바람이나 진동을 확인한다.',
        ],
      'ja' => <String>[
          '$placeで見落とした痕跡を探す。',
          '$placeの別の出入口を調べる。',
          '$placeの床に足跡や擦れた跡がないか探す。',
          '$placeに残された物の位置を記録する。',
          '$placeで新しい音がしないか少し待つ。',
          '$placeのドア枠と取っ手に新しい傷がないか調べる。',
          '$placeの床の水気と足跡の向きを確かめる。',
          '$placeの壁や隅に引きずった跡がないか探す。',
          '$placeの照明や影に変化がないか見守る。',
          '$placeの床と敷居のほこりの跡を比べる。',
          '$placeから階段扉へ続く痕跡をたどる。',
          '$placeの出入口付近で風や振動がないか確かめる。',
        ],
      'zh' => <String>[
          '在$place寻找遗漏的痕迹。',
          '检查$place的其他出入口。',
          '寻找$place地面上的脚印或擦痕。',
          '记录$place里遗留物品的位置。',
          '在$place稍等片刻，留意是否有新的声音。',
          '检查$place门框和把手上有没有新划痕。',
          '查看$place地面水迹和脚印的方向。',
          '寻找$place墙边或角落的拖擦痕迹。',
          '留意$place的灯光和影子是否变化。',
          '对比$place地面和门槛上的灰尘痕迹。',
          '沿着$place通往楼梯门的痕迹查看。',
          '检查$place出入口附近是否有风或震动。',
        ],
      _ => <String>[
          'Search $place for a clue you have not checked yet.',
          'Check another entrance to $place.',
          'Look for footprints or scrape marks on the floor of $place.',
          'Record where objects have been left in $place.',
          'Wait briefly in $place and listen for a new sound.',
          'Inspect the door frame and handle in $place for fresh marks.',
          'Check the moisture and direction of footprints on the floor of $place.',
          'Look along the walls and corners of $place for drag marks.',
          'Watch for changes in the lighting and shadows in $place.',
          'Compare dust marks on the floor and threshold of $place.',
          'Trace any marks in $place toward the stairwell door.',
          'Check the entrance to $place for a draft or vibration.',
        ],
    };
  }
  final String person = character.trim();
  return switch (languageCode) {
    'ko' => <String>[
        '$place에서 아직 확인하지 않은 흔적을 찾아본다.',
        '$person에게 방금 확인한 단서에 대해 묻는다.',
        '$place의 다른 출입구를 살펴본다.',
        '$place에서 들리는 소리를 다시 확인한다.',
        '$place의 바닥에서 발자국이나 긁힌 흔적을 찾는다.',
        '$place의 경고등과 오류 화면을 함께 살펴본다.',
        '$place의 출입 기록에서 정전 전후를 비교한다.',
        '$place에 있는 케이블이 어디로 이어지는지 따라가 본다.',
        '$person에게 정전 직전의 상황을 묻는다.',
        '$place에서 복도로 이어지는 길을 살펴본다.',
        '$place에 남은 물건의 위치를 기록한다.',
        '$place에서 새로 들리는 소리가 있는지 기다려 본다.',
      ],
    'ja' => <String>[
        '$placeで見落とした痕跡を探す。',
        '$personに見つけた手掛かりについて尋ねる。',
        '$placeの別の出入口を調べる。',
        '$placeで聞こえる音をもう一度確かめる。',
        '$placeの床に足跡や擦れた跡がないか探す。',
        '$placeの警告灯とエラー画面を見比べる。',
        '$placeの入退室記録から停電の前後を調べる。',
        '$placeのケーブルがどこへ続くかたどる。',
        '$personに停電直前の様子を尋ねる。',
        '$placeから廊下へ続く道を調べる。',
        '$placeに残された物の位置を記録する。',
        '$placeで新しい音がしないか少し待つ。',
      ],
    'zh' => <String>[
        '在$place寻找遗漏的痕迹。',
        '询问$person对刚发现线索的看法。',
        '检查$place的其他出入口。',
        '重新听听$place里的动静。',
        '寻找$place地面上的脚印或擦痕。',
        '对照查看$place的警示灯和错误屏幕。',
        '检查$place停电前后的门禁记录。',
        '沿着$place的电缆查看它通向哪里。',
        '询问$person停电前发生了什么。',
        '查看$place通往走廊的通道。',
        '记录$place里遗留物品的位置。',
        '在$place稍等片刻，留意是否有新的声音。',
      ],
    _ => <String>[
        'Search $place for a clue you have not checked yet.',
        'Ask $person what they make of the clue.',
        'Check another entrance to $place.',
        'Listen for another sound in $place.',
        'Look for footprints or scrape marks on the floor of $place.',
        'Compare the warning light with the error display in $place.',
        'Compare access records from before and after the outage in $place.',
        'Trace the cable in $place to where it leads.',
        'Ask $person what happened just before the outage.',
        'Inspect the route from $place into the corridor.',
        'Record where objects have been left in $place.',
        'Wait briefly in $place and listen for a new sound.',
      ],
  };
}

String _fallbackNarrationForAction(
    String action, String languageCode, String characterName,
    {Iterable<String> recentNarrations = const []}) {
  final bool isQuestion = switch (languageCode) {
    'ko' => RegExp(r'(?:묻|물어|질문)').hasMatch(action),
    'ja' => RegExp(r'(?:尋ね|質問|聞く)').hasMatch(action),
    'zh' => RegExp(r'(?:询问|问一问|提问)').hasMatch(action),
    _ => RegExp(r'\b(?:ask|asks|asked|question)\b', caseSensitive: false)
        .hasMatch(action),
  };
  if (isQuestion) {
    final String character = characterName.trim().isEmpty
        ? switch (languageCode) {
            'ko' => '상대는',
            'ja' => '相手は',
            'zh' => '对方',
            _ => 'The character',
          }
        : characterName;
    final List<String> options = switch (languageCode) {
      'ko' => <String>[
          '$character는 잠시 생각한 뒤 짧게 답한다.',
          '$character가 말을 고른 뒤 대답한다.',
          '$character의 대답은 짧았다.',
          '$character는 필요한 말만 덧붙인다.',
          '$character가 간단히 답한다.',
        ],
      'ja' => <String>[
          '$characterは少し言葉を選んでから短く答える。',
          '$characterは答えを選ぶように、言葉を少し遅らせる。',
          '$characterから短い返事が返る。',
          '$characterはそれ以上言葉を足さない。',
          '$characterは短く答える。',
        ],
      'zh' => <String>[
          '$character斟酌片刻，简短地回答。',
          '$character斟酌着措辞，稍后才开口。',
          '$character给了一个简短的回答。',
          '$character没有再补充。',
          '$character简短地答了一句。',
        ],
      _ => <String>[
          '$character chooses the words, then answers briefly.',
          '$character pauses while choosing an answer.',
          '$character gives a short reply.',
          '$character adds nothing more.',
          '$character answers in a few words.',
        ],
    };
    final List<String> recent = recentNarrations.toList();
    return options.firstWhere(
      (String candidate) => !recent
          .any((String previous) => _similarity(candidate, previous) >= 0.68),
      orElse: () => options[recent.length % options.length],
    );
  }
  if (languageCode == 'ko') {
    const List<String> knownSubjects = <String>[
      '계단문 손잡이',
      '젖은 발자국',
      '점멸 간격',
      '오류 코드',
      '출입 기록',
      '카드 태그',
      '경고등',
      '검은 케이블',
      '케이블',
      '계단문',
      '발자국',
      '관리 복도',
    ];
    final String normalizedAction = _normalizeNarrativeText(action);
    final String? subject = knownSubjects
        .where((String item) =>
            normalizedAction.contains(_normalizeNarrativeText(item)))
        .firstOrNull;
    if (subject != null) return '$subject에서 추가로 확인된 변화는 없다.';
  }
  final String subject = switch (languageCode) {
    'ko' => action
        .replaceAll(
            RegExp(r'(?:을|를|의)?\s*(?:살펴본다|살펴본다|확인한다|조사한다|점검한다|관찰한다|읽는다|본다).*$'),
            '')
        .trim(),
    'ja' =>
      action.replaceAll(RegExp(r'(?:を)?(?:調べる|確認する|見る|読む).*$'), '').trim(),
    'zh' => action.replaceAll(RegExp(r'(?:检查|查看|观察|读取).*$'), '').trim(),
    _ => action
        .replaceAll(
            RegExp(r'\b(?:inspect|check|examine|look at|read)\b.*$',
                caseSensitive: false),
            '')
        .trim(),
  };
  if (subject.isNotEmpty && subject != action.trim()) {
    return switch (languageCode) {
      'ko' => '$subject에서는 뚜렷한 새 변화를 확인하기 어렵다.',
      'ja' => '$subjectには、はっきりした新しい変化は見当たらない。',
      'zh' => '$subject没有显现出明显的新变化。',
      _ => 'No clear new change is visible on $subject.',
    };
  }
  return switch (languageCode) {
    'ko' => '주변에는 당장 달라진 점이 보이지 않는다.',
    'ja' => '周囲に目立った変化は見られない。',
    'zh' => '周围暂时没有明显变化。',
    _ => 'Nothing nearby has visibly changed yet.',
  };
}

bool _echoesAction(String narration, String action) {
  final String normalizedNarration = _normalizeNarrativeText(narration);
  final String normalizedAction = _normalizeNarrativeText(action);
  final String? actionRecipient =
      RegExp(r'^(.+?)(?:에게|한테)').firstMatch(action)?.group(1);
  final bool questionIntent = _isQuestionIntent(action);
  final bool repeatsKoreanQuestion =
      questionIntent && RegExp(r'(?:묻|물어|물었|질문하|확인하|확인했)').hasMatch(narration);
  final bool paraphrasesQuestion = questionIntent &&
      _similarity(narration, action) >= 0.3 &&
      (actionRecipient == null || narration.contains(actionRecipient)) &&
      _containsInterrogative(narration) &&
      (_hasQuestionMark(narration) || _isQuestionIntent(narration));
  final bool asksPlayerToRepeat = questionIntent &&
      _similarity(narration, action) >= 0.28 &&
      _hasQuestionMark(narration) &&
      _containsInterrogative(narration);
  final bool refusalIntent = RegExp(
          r'(?:거절|싫어|안\s*(?:할|하겠|도와)|원치 않|断る|嫌だ|したくない|拒绝|不愿意|不想|\brefus(?:e|ed|al)|\bdeclin(?:e|ed|al))',
          caseSensitive: false)
      .hasMatch(action);
  final bool repeatsRefusal = refusalIntent &&
      RegExp(r'(?:부탁|요청).{0,50}(?:거절|거부|拒绝)|(?:거절|거부|拒绝).{0,50}(?:부탁|요청)|(?:request|quest).{0,60}(?:refus|declin)|(?:refus|declin).{0,60}(?:request|quest)',
              caseSensitive: false)
          .hasMatch(narration);
  return normalizedNarration.contains(normalizedAction) ||
      _similarity(narration, action) >= 0.62 ||
      repeatsKoreanQuestion ||
      paraphrasesQuestion ||
      asksPlayerToRepeat ||
      repeatsRefusal;
}

bool _isQuestionIntent(String action) =>
    RegExp(r'(?:묻|물어|질문|ask|asked|asks|question|尋ね|質問|询问|提问)',
            caseSensitive: false)
        .hasMatch(action);

String _unknownNpcReply(
    Campaign campaign, String characterId, String languageCode) {
  final List<String> candidates = switch (languageCode) {
    'ko' => <String>[
        '그건 잘 모르겠어.',
        '정확히는 기억나지 않아.',
        '그 이야기는 들은 적 없어.',
        '그 부분은 나도 확실하지 않아.',
        '지금은 아는 게 없어.',
      ],
    'ja' => <String>[
        'それはよく分からない。',
        '正確には覚えていない。',
        'その話は聞いたことがない。',
        'そこは私にも確かではない。',
        '今は分かることがない。',
      ],
    'zh' => <String>[
        '这个我不太清楚。',
        '我记不太准确。',
        '我没听说过这件事。',
        '这部分我也不能确定。',
        '我现在没有相关消息。',
      ],
    _ => <String>[
        'I am not sure about that.',
        'I cannot remember exactly.',
        'I have not heard about that.',
        'I cannot say for certain.',
        'I do not know anything about that yet.',
      ],
  };
  final Set<String> recent = campaign.history.reversed
      .take(6)
      .expand((SceneTurn turn) => turn.dialogue)
      .where((SceneDialogue line) => line.characterId == characterId)
      .map((SceneDialogue line) => _normalizeNarrativeText(line.text))
      .toSet();
  return candidates.firstWhere(
    (String candidate) => !recent.contains(_normalizeNarrativeText(candidate)),
    orElse: () =>
        candidates[campaign.worldState.turnNumber % candidates.length],
  );
}

bool _hasQuestionMark(String text) => text.contains('?') || text.contains('？');

bool _containsInterrogative(String text) => RegExp(
        r'(?:누구|언제|어디|어느|어떤|얼마|몇|무엇|무슨|왜|어떻게|who|when|where|which|what|why|how|誰|いつ|どこ|どちら|何|なぜ|谁|什么时候|哪里|哪边|什么|为什么|如何)',
        caseSensitive: false)
    .hasMatch(text);

/// Detects near-duplicate prose by comparing adjacent characters without
/// treating shared setting nouns alone as a repeated scene.
double _similarity(String first, String second) {
  final String normalizedFirst = _normalizeNarrativeText(first);
  final String normalizedSecond = _normalizeNarrativeText(second);
  if (normalizedFirst == normalizedSecond) return 1;
  final List<int> firstRunes = normalizedFirst.runes.toList();
  final List<int> secondRunes = normalizedSecond.runes.toList();
  if (firstRunes.length < 8 || secondRunes.length < 8) return 0;
  final Set<int> firstBigrams = _characterBigrams(firstRunes);
  final Set<int> secondBigrams = _characterBigrams(secondRunes);
  final int intersection = firstBigrams.intersection(secondBigrams).length;
  final int union = firstBigrams.union(secondBigrams).length;
  return union == 0 ? 0 : intersection / union;
}

Set<int> _characterBigrams(List<int> runes) => <int>{
      for (int index = 0; index < runes.length - 1; index++)
        (runes[index] << 21) | runes[index + 1],
    };

bool _describesPlayerAgency(String text, String playerName, String language,
    {Iterable<String> otherCharacterNames = const []}) {
  final String normalized = _normalizeNarrativeText(text);
  final bool addsPrivateState =
      _describesPrivatePlayerState(text, playerName, language);
  final bool namesAnotherCharacter = otherCharacterNames.any((String name) =>
      name.isNotEmpty && normalized.contains(_normalizeNarrativeText(name)));
  final bool impliesUnassignedPlayerThought = !namesAnotherCharacter &&
      switch (language) {
        'Korean' => RegExp(r'(?:떠올랐|생각났|기억났|궁금해졌|관심을 기울|주의를 기울|신경이 쓰|머릿속에)')
            .hasMatch(text),
        'Japanese' => RegExp(r'(?:思い出し|思い浮かび|気になり|頭に浮かび)').hasMatch(text),
        'Simplified Chinese' => RegExp(r'(?:想起|想到|好奇|记起|脑海中浮现)').hasMatch(text),
        _ => RegExp(
                r'\b(?:came to mind|remembered|wondered|was curious|thought about)\b',
                caseSensitive: false)
            .hasMatch(text),
      };
  if (impliesUnassignedPlayerThought) return true;
  if (language == 'Korean') {
    final String name = _normalizeNarrativeText(playerName);
    final bool namesPlayer =
        normalized.contains(name) || normalized.contains('플레이어');
    final String playerSubject =
        '(?:${RegExp.escape(playerName)}(?:는|가|이|도)|플레이어(?:는|가|이|도))';
    final bool narratesVoluntaryAction = namesPlayer &&
        RegExp('$playerSubject.{0,80}(?:묻|물어|물었|질문하|질문했|질문한|대답하|대답했|말하|말했|부탁|요청|확인하|확인했|확인한|점검하|점검했|점검한|조사하|살펴보|살피|살펴본|찾|찾은|열|열어|닫|닫은|들어가|들어선|나가|나섰|돌아오|떠나|진입하|옮겨|걷|걸어|이동하|향하|다가가|따르|듣|기다리|두드리|거절|수락|동의|따르|돕|시도하|시도했|고개를 끄덕)')
            .hasMatch(text);
    return addsPrivateState || narratesVoluntaryAction;
  }
  final String subject =
      '(?:the player|player|he|his|she|her|${RegExp.escape(playerName)})';
  final String privateState =
      r'\b(?:thought|felt|decided|agreed|refused|nodded|believed|trusted)\b';
  final String voluntaryAction = switch (language) {
    'Japanese' => r'(?:尋ね|聞き|確認|調べ|見る|向か|歩き|待ち|開け|閉め|答え|話し)',
    'Simplified Chinese' => r'(?:询问|问|查看|检查|观察|走向|前往|等待|打开|关闭|寻找|回答|说)',
    _ =>
      r'\b(?:ask|asks|asked|check|checks|checked|look|looks|looked|inspect|inspects|inspected|walk|walks|walked|wait|waits|waited|open|opens|opened|close|closes|closed|answer|answers|answered|follow|follows|followed|decide|decides|decided)\b',
  };
  return RegExp('$subject.{0,80}(?:$privateState|$voluntaryAction)',
              caseSensitive: false)
          .hasMatch(text) ||
      addsPrivateState;
}

bool _describesPrivatePlayerState(
    String text, String playerName, String language) {
  if (language == 'Korean') {
    final String player = '(?:${RegExp.escape(playerName)}|플레이어|그|그녀|자신)';
    return RegExp(
      '$player.{0,120}(?:표정|감정|생각|느끼|결심|동의|마음|관심|주의|귀를 기울|신경을 쓰|긴장|불안|이유를|원하|바라|무섭|두렵|안도|기쁘|화가)',
      caseSensitive: false,
    ).hasMatch(text);
  }
  final String subject =
      '(?:the player|player|he|his|she|her|${RegExp.escape(playerName)})';
  final String privateState = switch (language) {
    'Japanese' => r'(?:思い|感じ|決意|同意|拒否|信じ|不安|安心|嬉し)',
    'Simplified Chinese' => r'(?:觉得|感到|决定|同意|拒绝|相信|不安|放心|高兴)',
    _ =>
      r'\b(?:thought|felt|decided|agreed|refused|believed|trusted|wanted|feared|hoped|realized)\b',
  };
  return RegExp('$subject.{0,120}$privateState', caseSensitive: false)
      .hasMatch(text);
}

List<String> _mergeUnique(
        List<String> existing, List<String> updates, int limit) =>
    {...existing, ...updates.map((String item) => item.trim())}
        .where((String item) => item.isNotEmpty)
        .take(limit)
        .toList();

String _languageName(String languageCode) => switch (languageCode) {
      'ko' => 'Korean',
      'zh' => 'Simplified Chinese',
      'ja' => 'Japanese',
      _ => 'English',
    };

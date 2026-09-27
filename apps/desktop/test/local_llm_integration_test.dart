import 'dart:io';

import 'package:continuum_desktop/features/novel/application/novel_controller.dart';
import 'package:continuum_desktop/features/novel/data/llm_provider.dart';
import 'package:continuum_desktop/features/world/data/sqlite_world_repository.dart';
import 'package:continuum_desktop/features/novel/domain/language_model_settings.dart';
import 'package:continuum_desktop/state/locale_controller.dart';
import 'package:continuum_desktop/state/workspace_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final bool _runLocalLlm =
    Platform.environment['CONTINUUM_RUN_LOCAL_LLM'] == '1';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'real local model handles player QA, resolves 20 turns and continues after reload',
    skip: !_runLocalLlm,
    () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('continuum-local-llm-');
      final String path = '${directory.path}/campaign.sqlite3';
      SqliteWorldRepository repository = await SqliteWorldRepository.open(path);
      final World world = _world();
      await repository.createWorld(world);
      await repository.updateWorldDraft(world);
      ProviderContainer? container;
      final List<OpenAiCompatibleProvider> providers = [];
      ProviderContainer createContainer(SqliteWorldRepository db) {
        final OpenAiCompatibleProvider provider = OpenAiCompatibleProvider();
        providers.add(provider);
        return ProviderContainer(overrides: <Override>[
          worldRepositoryProvider.overrideWithValue(db),
          workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
          llmProvider.overrideWithValue(provider),
        ]);
      }

      container = createContainer(repository);
      addTearDown(() async {
        container?.dispose();
        for (final OpenAiCompatibleProvider provider in providers) {
          provider.close();
        }
        await repository.close();
        await directory.delete(recursive: true);
      });

      final String baseUrl = Platform.environment['CONTINUUM_LLM_BASE_URL'] ??
          'http://127.0.0.1:11434/v1';
      final String model =
          Platform.environment['CONTINUUM_LLM_MODEL'] ?? 'qwen3-1_7b-q4km';
      final NovelController controller =
          container.read(novelControllerProvider.notifier);
      container.read(gameLanguageProvider.notifier).restoreLanguage('ko');
      const int qaContextLimit = 8192;
      final LanguageModelSettings qaSettings = LanguageModelSettings(
          baseUrl: baseUrl, model: model, contextLimit: qaContextLimit);
      await controller.saveSettings(qaSettings);
      await controller.createCampaign(world);
      final Campaign opening =
          container.read(novelControllerProvider).campaign!;
      expect(opening.currentScene, isNotNull);
      expect(opening.currentScene!.choices, hasLength(greaterThanOrEqualTo(2)));
      expect(opening.currentScene!.narration, isNotEmpty);
      expect(opening.languageCode, 'ko');
      expect(RegExp(r'[가-힣]').hasMatch(opening.currentScene!.narration), isTrue,
          reason: 'The opening must be written in Korean.');
      expect(opening.currentScene!.narration, contains('민재'));
      expect(opening.currentScene!.narration, contains('서버실'));
      expect(
        RegExp(r'민재(?:는|가|이|도).{0,120}(?:확인했다|확인하게|확인하려 한다|요청한다|부탁한다|살펴본다|조사한다)',
                dotAll: true)
            .hasMatch(opening.currentScene!.narration),
        isFalse,
        reason:
            'The opening must not make Minjae act before the player enters an action: ${opening.currentScene!.narration}',
      );
      expect(
        RegExp(r'민재.{0,100}(?:정전 원인|경고등|오류 화면|발전기).{0,30}(?:확인|조사|점검|보)',
                dotAll: true)
            .hasMatch(opening.currentScene!.narration),
        isTrue,
        reason:
            'The opening must tell the player why Minjae came to the Server Room: ${opening.currentScene!.narration}',
      );
      expect(
          opening.currentScene!.dialogue.every(
              (SceneDialogue line) => RegExp(r'[가-힣]').hasMatch(line.text)),
          isTrue,
          reason: 'Opening NPC speech must be written in Korean.');
      expect(
          opening.currentScene!.choices
              .every((String choice) => RegExp(r'[가-힣]').hasMatch(choice)),
          isTrue,
          reason: 'Opening suggestions must be written in Korean.');
      expect(
        RegExp(r'\b(?:char_yoon|loc_server|loc_hall)\b').hasMatch(
          <String>[
            opening.currentScene!.narration,
            ...opening.currentScene!.dialogue
                .map((SceneDialogue line) => line.text),
            ...opening.currentScene!.choices,
          ].join(' '),
        ),
        isFalse,
        reason: 'Opening text must not expose internal World IDs.',
      );

      final List<String> actions = [
        '윤서에게 발전기 경고등을 함께 확인해 달라는 부탁을 "싫어."라고 거절한다.',
        '윤서에게 금속 소리가 어느 쪽에서 났는지 묻는다.',
        '윤서에게 "왜?"라고만 묻는다.',
        '윤서에게 계단 근처에서 사람을 마지막으로 본 시각을 묻는다.',
        '윤서에게 실험실 카드키를 가진 사람이 누구인지 묻는다.',
        '윤서에게 그 카드키를 빌려준 적이 있는지 묻는다.',
        '윤서에게 금속 소리를 들은 뒤 무엇을 했는지 묻는다.',
        '윤서에게 계단문 쪽에 혼자 가도 괜찮은지 묻는다.',
        '윤서에게 출입 기록에서 무엇을 확인해야 하는지 묻는다.',
        '윤서에게 지금도 같이 확인하고 싶은지 묻는다.',
        '대화를 끊고 서버실을 뛰쳐나가 관리 복도 반대편으로 달린다.',
        '발전기 경고등의 점멸 간격을 살펴본다.',
        '출입 기록에서 최근 카드 태그 시각을 확인한다.',
        '확인한 출입 기록을 윤서에게 보여준다.',
        '발전기 옆에 늘어진 케이블이 어디로 이어지는지 살펴본다.',
        '관리 복도로 나가 계단문 주변을 살펴본다.',
        '젖은 발자국이 계단문 안팎 중 어디로 향하는지 확인한다.',
        '계단문 손잡이의 물기와 흠집을 살펴본다.',
        '출입 기록에서 정전 직전과 직후 기록을 더 확인한다.',
        '계단문을 열기 전에 안쪽에 사람이 있는지 확인한다.',
      ];
      final int requestedTurns =
          int.tryParse(Platform.environment['CONTINUUM_LLM_QA_TURNS'] ?? '') ??
              actions.length;
      final List<String> qaActions =
          actions.take(requestedTurns.clamp(1, actions.length)).toList();
      final Set<String> narrations = <String>{};
      final List<Set<String>> recentDialogueTurns = <Set<String>>[];
      final List<Set<String>> recentChoiceTurns = <Set<String>>[];
      final List<(String action, String speakerId, String text)> npcAnswers =
          <(String, String, String)>[];
      final List<String> playerLog = <String>[
        'Opening:\n${opening.currentScene!.narration}\n'
            'NPC: ${opening.currentScene!.dialogue.map((SceneDialogue line) => line.text).join(' / ')}\n'
            '추천 행동: ${opening.currentScene!.choices.join(' / ')}'
      ];
      Campaign current = opening;
      for (final String action in qaActions) {
        try {
          await controller.act(action);
        } catch (error) {
          fail(
              'Player action failed: $action\n${playerLog.join('\n\n')}\n$error');
        }
        current = (await repository.getCampaign(opening.id))!;
        expect(current.currentScene, isNotNull);
        expect(current.history.length, current.worldState.turnNumber);
        playerLog.add('플레이어: $action\n${current.currentScene!.narration}\n'
            'NPC: ${current.currentScene!.dialogue.map((SceneDialogue line) => line.text).join(' / ')}\n'
            '추천 행동: ${current.currentScene!.choices.join(' / ')}');
        expect(
            RegExp(r'[가-힣]').hasMatch(current.currentScene!.narration), isTrue,
            reason:
                'Non-Korean narration after player action: $action\n${playerLog.join('\n\n')}');
        expect(
          RegExp(r'(?:민재(?:는|가|이|도)|플레이어(?:는|가|이|도)).{0,80}(?:조사|확인|살펴|들어가|나가|떠올|생각|기억|관심|결심|동의|거절|수락)',
                  dotAll: true)
              .hasMatch(current.currentScene!.narration),
          isFalse,
          reason:
              'Narration assigned the player an action or private state: $action\n${playerLog.join('\n\n')}',
        );
        expect(
            current.currentScene!.dialogue.every(
                (SceneDialogue line) => RegExp(r'[가-힣]').hasMatch(line.text)),
            isTrue,
            reason:
                'Non-Korean NPC speech after player action: $action\n${playerLog.join('\n\n')}');
        if (action.startsWith('윤서에게') &&
            RegExp(r'(?:묻|물어|질문)').hasMatch(action)) {
          expect(current.currentScene!.dialogue, isNotEmpty,
              reason:
                  'A player question addressed to Yoon must receive an answer: $action\n${playerLog.join('\n\n')}');
        }
        expect(
            current.currentScene!.choices
                .every((String choice) => RegExp(r'[가-힣]').hasMatch(choice)),
            isTrue,
            reason:
                'Non-Korean suggested action after player action: $action\n${playerLog.join('\n\n')}');
        if (action.contains('"싫어."')) {
          expect(
            <String>[
              current.currentScene!.narration,
              ...current.currentScene!.dialogue
                  .map((SceneDialogue line) => line.text),
            ].join(' '),
            isNot(RegExp(r'(?:민재가|플레이어가).{0,30}(?:수락|동의|따르기로|돕기로)',
                dotAll: true)),
            reason:
                'The world must not narrate acceptance after the player refused: $action\n${playerLog.join('\n\n')}',
          );
          expect(
            current.currentScene!.dialogue
                .map((SceneDialogue line) => line.text),
            contains('알겠어. 다른 방법을 찾아볼게.'),
            reason:
                'The NPC must accept the refusal instead of pressing the same request: $action\n${playerLog.join('\n\n')}',
          );
        }
        if (action.contains('"왜?"')) {
          expect(
            current.currentScene!.dialogue
                .map((SceneDialogue line) => line.text),
            contains('그냥 신경이 쓰여서.'),
            reason:
                'A short why-question should receive a concise NPC answer: $action\n${playerLog.join('\n\n')}',
          );
          expect(current.currentScene!.narration.length, lessThan(420),
              reason:
                  'A short dialogue should not trigger a long narration: $action\n${playerLog.join('\n\n')}');
          expect(
            current.currentScene!.dialogue.fold<int>(
                0, (int total, SceneDialogue line) => total + line.text.length),
            lessThan(420),
            reason:
                'A short question should receive a concise NPC response: $action\n${playerLog.join('\n\n')}',
          );
        }
        if (action.contains('뛰쳐나가 관리 복도')) {
          expect(current.worldState.currentLocationId, 'loc_hall',
              reason:
                  'An explicit move to the Management Hall must change the active scene location: ${playerLog.join('\n\n')}');
          expect(current.currentScene!.narration, contains('관리 복도'));
          expect(current.worldState.presentCharacterIds, isEmpty,
              reason:
                  'A character left behind must not remain in the new scene.');
          expect(current.currentScene!.dialogue, isEmpty,
              reason:
                  'A character left behind must not speak from the new scene.');
          expect(
            current.currentScene!.choices,
            everyElement(contains('관리 복도')),
            reason:
                'Suggested actions after arrival must use the new location: ${playerLog.join('\n\n')}',
          );
        }
        if (_normalize(action).length >= 5) {
          expect(_normalize(current.currentScene!.narration),
              isNot(contains(_normalize(action))),
              reason:
                  'The scene echoed player input: $action\n${playerLog.join('\n\n')}');
        }
        narrations.add(_normalize(current.currentScene!.narration));
        expect(
            current.currentScene!.choices, hasLength(greaterThanOrEqualTo(2)));
        expect(current.currentScene!.choices, everyElement(isNotEmpty));
        expect(
          current.currentScene!.choices.where(
              (String choice) => choice.contains('?') || choice.contains('？')),
          isEmpty,
          reason:
              'Suggested actions must be executable actions, not follow-up questions: $action\n${playerLog.join('\n\n')}',
        );
        expect(
          RegExp(r'\b(?:char_yoon|loc_server|loc_hall)\b').hasMatch(
            <String>[
              current.currentScene!.narration,
              ...current.currentScene!.dialogue
                  .map((SceneDialogue line) => line.text),
              ...current.currentScene!.choices,
            ].join(' '),
          ),
          isFalse,
          reason:
              'Player-facing scene text exposed an internal World ID: $action\n${playerLog.join('\n\n')}',
        );
        if (action.contains('계단 근처에서 사람을 마지막으로 본 시각')) {
          expect(
            current.currentScene!.dialogue
                .map((SceneDialogue line) => line.text),
            contains('그건 정확히 기억나지 않아.'),
            reason:
                'The NPC must admit when the question asks for a fact absent from her known memory. Known facts: ${current.characterMemory['char_yoon']?.knownFacts}.\n${playerLog.join('\n\n')}',
          );
        }
        if (action.contains('카드키를 가진 사람이 누구인지')) {
          expect(
            current.currentScene!.dialogue
                .map((SceneDialogue line) => line.text),
            everyElement(
                matches(RegExp(r'(?:모르|기억나지 않아|확실하지 않아|들은 적 없어|아는 게 없어)'))),
            reason:
                'Yoon must not invent a card-key holder when no such fact is known: ${playerLog.join('\n\n')}',
          );
        }
        if (action.contains('그 카드키를 빌려준 적이 있는지')) {
          expect(
            current.currentScene!.dialogue
                .map((SceneDialogue line) => line.text),
            contains('응, 실험실 카드키를 빌려준 적 있어.'),
            reason:
                'A direct question should reveal and record the NPC fact authored in secret information: ${playerLog.join('\n\n')}',
          );
          expect(
            current.characterMemory['char_yoon']!.knownFacts,
            contains('윤서는 실험실 카드키를 빌려준 적이 있다고 인정했다.'),
          );
        }
        final List<String> turnDialogue = current.currentScene!.dialogue
            .map((SceneDialogue line) => _normalize(line.text))
            .toList();
        for (final SceneDialogue line in current.currentScene!.dialogue) {
          final String normalizedAnswer = _normalize(line.text);
          final bool repeatedForAnotherQuestion = npcAnswers.any(
            ((String action, String speakerId, String text) previous) =>
                previous.$2 == line.characterId &&
                previous.$3 == normalizedAnswer &&
                _similarity(previous.$1, action) < 0.52,
          );
          expect(
            repeatedForAnotherQuestion,
            isFalse,
            reason:
                'The NPC reused an earlier answer for a different question: $action\n${playerLog.join('\n\n')}',
          );
          npcAnswers.add((action, line.characterId, normalizedAnswer));
        }
        if (RegExp(r'(?:묻|물어|질문)').hasMatch(action)) {
          final String normalizedAction = _normalize(action);
          final List<String> questionBacks = current.currentScene!.dialogue
              .where((SceneDialogue line) =>
                  (line.text.contains('?') || line.text.contains('？')) &&
                  _similarity(normalizedAction, _normalize(line.text)) >= 0.28)
              .map((SceneDialogue line) => line.text)
              .toList();
          expect(questionBacks, isEmpty,
              reason:
                  'The NPC repeated the question back to the player after: $action\n${playerLog.join('\n\n')}');
          expect(
            current.currentScene!.choices.where((String choice) =>
                _similarity(normalizedAction, _normalize(choice)) >= 0.38),
            isEmpty,
            reason:
                'Suggested actions repeated the player question after: $action\n${playerLog.join('\n\n')}',
          );
        }
        final Set<String> recentDialogue =
            recentDialogueTurns.expand((Set<String> turn) => turn).toSet();
        expect(turnDialogue, everyElement(isNot(recentDialogue)),
            reason:
                'The NPC repeated recent dialogue after: $action\n${playerLog.join('\n\n')}');
        final Set<String> recentChoices =
            recentChoiceTurns.expand((Set<String> turn) => turn).toSet();
        final int repeatedChoices = current.currentScene!.choices
            .map(_normalize)
            .where(recentChoices.contains)
            .length;
        expect(repeatedChoices, lessThan(2),
            reason:
                'Suggested actions stayed stale after: $action\n${playerLog.join('\n\n')}');
        recentDialogueTurns.add(turnDialogue.toSet());
        if (recentDialogueTurns.length > 4) recentDialogueTurns.removeAt(0);
        recentChoiceTurns
            .add(current.currentScene!.choices.map(_normalize).toSet());
        if (recentChoiceTurns.length > 3) recentChoiceTurns.removeAt(0);
      }
      final int minimumUniqueScenes =
          ((qaActions.length + 1) * 0.85).floor().clamp(1, qaActions.length);
      expect(narrations.length, greaterThanOrEqualTo(minimumUniqueScenes),
          reason:
              'Narration repeated too often across ${qaActions.length + 1} scenes.\n${playerLog.join('\n\n')}');
      // Keep the generated play experience visible in test output for a
      // human player-perspective review alongside mechanical assertions.
      // ignore: avoid_print
      print('Korean player QA session:\n${playerLog.join('\n\n')}');
      final int completedTurns = qaActions.length + 1;
      expect(current.worldState.turnNumber, completedTurns);
      expect(current.history, hasLength(completedTurns));

      container.dispose();
      container = null;
      await repository.close();
      repository = await SqliteWorldRepository.open(path);
      final Campaign restored = (await repository.getCampaign(opening.id))!;
      expect(restored.currentScene!.id, current.currentScene!.id);
      expect(restored.worldState.turnNumber, completedTurns);
      expect(restored.history, hasLength(completedTurns));
      container = createContainer(repository);
      final NovelController resumed =
          container.read(novelControllerProvider.notifier);
      await resumed.saveSettings(qaSettings);
      await resumed.continueCampaign(opening.id);
      expect(container.read(novelControllerProvider).campaign!.currentScene!.id,
          current.currentScene!.id);
      await resumed.act('윤서에게 더 들은 게 있는지 묻는다.');
      final Campaign continued = (await repository.getCampaign(opening.id))!;
      expect(continued.worldState.turnNumber, completedTurns + 1);
      expect(continued.history, hasLength(completedTurns + 1));
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}

World _world() => const World(
      id: 'manual_world',
      name: '정전된 대학 캠퍼스',
      description: '새벽 정전이 반복된 대학 캠퍼스. 오늘은 서버실 발전기 경고등까지 켜졌다.',
      genre: <String>['미스터리'],
      tone: <String>['현실적'],
      rules: <String>['초자연 현상 없이 현실적인 사건만 다룬다.'],
      playerDefinition: PlayerDefinition(
        name: '민재',
        description: '야간 서버를 관리하는 컴퓨터공학과 학생.',
        background: '비상 발전기를 확인하러 서버실에 와 있다.',
        traits: <String>['관찰력이 좋다'],
      ),
      openingDefinition: OpeningDefinition(
        startingLocationId: 'loc_server',
        startingCharacterIds: <String>['char_yoon'],
        situation:
            '새벽 2시, 캠퍼스에 정전이 났다. 비상 발전기는 작동하지만 빨간 경고등이 켜져 있다. 관리 복도 계단문 쪽에서 금속 끄는 소리가 났다. 야간 서버 담당인 민재는 정전 원인을 확인하러 서버실에 왔다. 실험실 조교 윤서는 민재에게 비상 발전기 경고등을 함께 확인해 달라고 부탁하려 한다.',
      ),
      locations: <StoryLocation>[
        StoryLocation(
            id: 'loc_server',
            name: '서버실',
            description:
                '비상등과 비상 발전기가 켜져 있다. 발전기에는 빨간 경고등과 오류 화면이 있고, 벽에는 출입 제어기와 카드 기록 단말이 있다. 서버 랙 아래로 검은 케이블 하나가 늘어져 있다.'),
        StoryLocation(
            id: 'loc_hall',
            name: '관리 복도',
            description:
                '비상 계단문으로 이어지는 좁은 콘크리트 복도. 계단문 앞 바닥에 젖은 신발 자국 하나가 남아 있다.'),
      ],
      characters: <StoryCharacter>[
        StoryCharacter(
          id: 'char_yoon',
          name: '윤서',
          role: '실험실 조교',
          description: '서버실 입구에 선 실험실 조교. 소리에 신경을 곤두세우고 있다.',
          personality: '신중하고 관찰력이 좋다. 짧고 자연스러운 구어체로 말하며 모르는 일은 모른다고 한다.',
          background: '캠퍼스 실험실에서 일한다.',
          publicInformation: '정전 당시 서버실에 있었고, 관리 복도에서 금속 끄는 소리를 들었다.',
          secretInformation: '실험실 카드키를 빌려준 적이 있지만 아직 그 사실을 말하지 않았다.',
        ),
      ],
    );

class _TestWorkspaceController extends WorkspaceController {
  _TestWorkspaceController(this.world);
  final World world;
  @override
  WorkspaceState build() => WorkspaceState(
        worlds: <World>[world],
        loadStatus: WorkspaceLoadStatus.ready,
      );
  @override
  Future<void> refreshCampaigns(String worldId) async {}
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

double _similarity(String first, String second) {
  if (first == second) return 1;
  if (first.length < 8 || second.length < 8) return 0;
  final Set<String> firstBigrams = <String>{
    for (int index = 0; index < first.length - 1; index++)
      first.substring(index, index + 2),
  };
  final Set<String> secondBigrams = <String>{
    for (int index = 0; index < second.length - 1; index++)
      second.substring(index, index + 2),
  };
  final int intersection = firstBigrams.intersection(secondBigrams).length;
  return intersection / firstBigrams.union(secondBigrams).length;
}

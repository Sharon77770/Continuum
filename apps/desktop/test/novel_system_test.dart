import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:continuum_desktop/features/world/data/sqlite_world_repository.dart';
import 'package:continuum_desktop/features/novel/data/llm_provider.dart';
import 'package:continuum_desktop/features/novel/application/novel_controller.dart';
import 'package:continuum_desktop/features/library/application/sample_world_factory.dart';
import 'package:continuum_desktop/features/novel/domain/language_model_settings.dart';
import 'package:continuum_desktop/features/models/application/model_manager_controller.dart';
import 'package:continuum_desktop/features/models/data/model_manager_repository.dart';
import 'package:continuum_desktop/features/models/domain/model_catalog.dart';
import 'package:continuum_desktop/state/locale_controller.dart';
import 'package:continuum_desktop/state/workspace_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';
import 'package:novel_system/novel_system.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:continuum_desktop/core/app_file_logger.dart';
import 'package:continuum_desktop/core/developer_tools_providers.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('parses structured narrative and rejects unknown speakers', () {
    const String json =
        '{"schemaVersion":1,"narration":"A light flickers.","dialogue":[{"characterId":"char_yoon","text":"Did you see?"}],"choices":["Look outside","Stay here"],"stateChanges":{},"memoryUpdates":[{"characterId":"char_yoon","summary":"The player noticed the light."}]}';
    final NarrativeResult result = NarrativeResult.parse(json, {'char_yoon'});
    expect(result.dialogue.single.characterId, 'char_yoon');
    expect(result.choices, hasLength(2));
    expect(
        NarrativeResult.parse('$json\n\nExtra model chatter.', {'char_yoon'})
            .narration,
        'A light flickers.');
    expect(
        result.memoryUpdates['char_yoon'], ['The player noticed the light.']);
    const String oneChoiceJson =
        '{"schemaVersion":1,"narration":"A light flickers.","dialogue":[],"choices":["Check the panel"]}';
    expect(
        NarrativeResult.parse(oneChoiceJson, {'char_yoon'}, minimumChoices: 1)
            .choices,
        ['Check the panel']);
    expect(() => NarrativeResult.parse(json, {'char_other'}),
        throwsFormatException);
    expect(
      NarrativeResult.parse(json, {'char_other'}, ignoreDialogue: true)
          .dialogue,
      isEmpty,
      reason: 'A solo scene can discard generated NPC dialogue entirely.',
    );
    expect(
        () => NarrativeResult.parse('{', {'char_yoon'}), throwsFormatException);
  });

  test('parses scene state proposals and rejects malformed scene fields', () {
    final NarrativeResult result = NarrativeResult.parse(
        '{"schemaVersion":1,"narration":"The door opens.","dialogue":[],"choices":["Enter the hall","Stay by the door"],"sceneChanges":{"locationId":"loc_hall","presentCharacterIds":["char_yoon"],"timeDescription":"Night","atmosphere":"Cold","relevantObjects":["Lantern"]},"npcChanges":[{"characterId":"char_yoon","relationship":"Trusts the player","currentEmotion":"Wary","goals":["Find the missing key"],"recentEvents":["Heard a latch move"]}]}',
        {'char_yoon'});
    expect(result.sceneChanges['locationId'], 'loc_hall');
    expect(result.sceneChanges['presentCharacterIds'], ['char_yoon']);
    expect(result.npcChanges['char_yoon']!.relationship, 'Trusts the player');
    expect(result.npcChanges['char_yoon']!.goals, ['Find the missing key']);
    expect(
        () => NarrativeResult.parse(
            '{"schemaVersion":1,"narration":"A.","dialogue":[],"choices":["Look","Wait"],"sceneChanges":{"untrustedMutation":true}}',
            {'char_yoon'}),
        throwsFormatException);
  });

  test('built-in first-run world is ready to start a campaign', () {
    expect(playableWorldIssues(SampleWorldFactory.create()), isEmpty);
  });

  test('starts and saves a campaign with no NPCs or NPC dialogue', () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository repository = SqliteWorldRepository(db);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-solo-opening-');
    final World world = _world(
      playerBackground:
          'Minjae came to check the emergency generator in the Server Room.',
    ).copyWith(
      characters: const <StoryCharacter>[],
    );
    await repository.createWorld(world);
    final _FakeProvider fakeProvider = _FakeProvider(<String>[
      _soloResult(
          'Minjae came to check the emergency generator in the Server Room. A warning light flickers.'),
    ]);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(repository),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      llmProvider.overrideWithValue(fakeProvider),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await logDirectory.delete(recursive: true);
    });

    final NovelController controller =
        container.read(novelControllerProvider.notifier);
    await controller.saveSettings(const LanguageModelSettings());
    controller.validatePlayableWorld(world);
    expect(world.openingDefinition.startingCharacterIds, ['char_yoon']);
    expect(world.characters, isEmpty);
    await controller.createCampaign(world);

    final Campaign campaign = container.read(novelControllerProvider).campaign!;
    expect(campaign.worldState.presentCharacterIds, isEmpty);
    expect(campaign.currentScene!.dialogue, isEmpty);
    expect(await repository.listCampaigns(world.id), hasLength(1));
  });

  test('local resource profile caps the context sent for story generation',
      () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository worlds = SqliteWorldRepository(db);
    final Directory temporary =
        await Directory.systemTemp.createTemp('continuum-resource-profile-');
    final World world = _world(
      playerBackground:
          'Minjae came to check the emergency generator in the Server Room.',
    );
    await worlds.createWorld(world);
    final File modelFile = File('${temporary.path}/models/story.gguf');
    await modelFile.parent.create(recursive: true);
    await modelFile.writeAsBytes(const <int>[71, 71, 85, 70]);
    final JsonModelManagerRepository models =
        JsonModelManagerRepository(Directory('${temporary.path}/models'));
    await models.saveInstalled(InstalledModel(
      id: 'local-test-model',
      displayName: 'Local test model',
      fileName: 'story.gguf',
      path: modelFile.path,
      sizeBytes: 4,
      source: ModelSource.localImport,
      repository: 'test',
      license: 'Unknown',
      qualityClass: ModelQuality.balanced,
      speedClass: ModelSpeed.balanced,
      contextSize: 8192,
      sha256: null,
      importedAt: DateTime.utc(2026),
    ));
    await models.saveSelection(const ModelSelection(
      kind: ModelProviderKind.local,
      modelId: 'local-test-model',
      displayName: 'Local test model',
    ));
    await models.saveLocalResourceProfile(LocalResourceProfile.conservative);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-resource-log-');
    final _FakeProvider fakeProvider = _FakeProvider(<String>[
      _soloResult(
          'Minjae came to check the emergency generator in the Server Room. A warning light flickers.'),
    ]);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(worlds),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      modelManagerRepositoryProvider.overrideWithValue(models),
      llmProvider.overrideWithValue(fakeProvider),
    ]);
    addTearDown(() async {
      container.dispose();
      await worlds.close();
      await temporary.delete(recursive: true);
      await logDirectory.delete(recursive: true);
    });

    final NovelController controller =
        container.read(novelControllerProvider.notifier);
    await controller.saveSettings(const LanguageModelSettings(
      contextLimit: 8192,
    ));
    await controller.createCampaign(world);

    expect(fakeProvider.lastContextLimit, 2048);
  });

  test('ignores duplicate New Game requests while opening generation runs',
      () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository repository = SqliteWorldRepository(db);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-opening-lock-');
    final World world = _world(
      playerBackground:
          'Minjae came to check the emergency generator in the Server Room.',
    );
    await repository.createWorld(world);
    final _BlockingProvider blockingProvider = _BlockingProvider();
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(repository),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      llmProvider.overrideWithValue(blockingProvider),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await logDirectory.delete(recursive: true);
    });

    final NovelController controller =
        container.read(novelControllerProvider.notifier);
    await controller.saveSettings(const LanguageModelSettings());
    final Future<void> firstStart = controller.createCampaign(world);
    await blockingProvider.requestStarted.future;
    await controller.createCampaign(world);

    expect(blockingProvider.requestCount, 1);
    blockingProvider.response.complete(_soloResult(
        'Minjae came to check the emergency generator in the Server Room. A warning light flickers.'));
    await firstStart;
    expect(container.read(novelControllerProvider).campaign!.history,
        hasLength(1));
  });

  test('failed opening generation clears the uncommitted campaign', () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository repository = SqliteWorldRepository(db);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-failed-opening-');
    final World world = _world();
    await repository.createWorld(world);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(repository),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      llmProvider.overrideWithValue(_FakeProvider(<String>['{}', '{}', '{}'])),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await logDirectory.delete(recursive: true);
    });

    final NovelController controller =
        container.read(novelControllerProvider.notifier);
    await controller.saveSettings(const LanguageModelSettings());
    await expectLater(controller.createCampaign(world), throwsA(anything));

    expect(container.read(novelControllerProvider).campaign, isNull);
    expect(await repository.listCampaigns(world.id), isEmpty);
  });

  test(
      'opening grounds a sparse generated scene with authored identity and purpose',
      () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository repository = SqliteWorldRepository(db);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-opening-agency-');
    final World world = _world(
        playerBackground:
            'Minjae came to check the emergency generator in the Server Room.');
    await repository.createWorld(world);
    await repository.updateWorldDraft(world);
    final _FakeProvider fakeProvider = _FakeProvider(<String>[
      _result('A red warning light blinks twice.'),
      _result(
          'Minjae came to check the emergency generator in the Server Room as emergency lights glow.'),
    ]);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(repository),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      llmProvider.overrideWithValue(fakeProvider),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await logDirectory.delete(recursive: true);
    });

    await container
        .read(novelControllerProvider.notifier)
        .saveSettings(const LanguageModelSettings());
    await container
        .read(novelControllerProvider.notifier)
        .createCampaign(world);

    expect(fakeProvider.nextResponse, 1);
    expect(
      container.read(novelControllerProvider).campaign!.currentScene!.narration,
      'Minjae came to check the emergency generator in the Server Room. A red warning light blinks twice.',
    );
  });

  test('short why questions receive a direct concise NPC answer', () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository repository = SqliteWorldRepository(db);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-short-why-');
    final World world = _world();
    await repository.createWorld(world);
    await repository.updateWorldDraft(world);
    final _FakeProvider fakeProvider = _FakeProvider(<String>[
      _result('Minjae is in the Server Room as the emergency lights glow.'),
      _result('A light flickers once.',
          dialogue: 'I am not sure.',
          choices: ['Check the breaker', 'Look at the access panel']),
    ]);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(repository),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      llmProvider.overrideWithValue(fakeProvider),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await logDirectory.delete(recursive: true);
    });
    final NovelController controller =
        container.read(novelControllerProvider.notifier);
    await controller.saveSettings(const LanguageModelSettings());
    await controller.createCampaign(world);
    await controller.act('Seo Yoon, why?');

    expect(
      container
          .read(novelControllerProvider)
          .campaign!
          .currentScene!
          .dialogue
          .single
          .text,
      'It just bothered me.',
    );
  });

  test('direct access card questions reveal and remember an authored secret',
      () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository repository = SqliteWorldRepository(db);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-card-secret-');
    final World world =
        _world(secretInformation: '실험실 카드키를 빌려준 적이 있지만 아직 그 사실을 말하지 않았다.');
    await repository.createWorld(world);
    await repository.updateWorldDraft(world);
    final _FakeProvider fakeProvider = _FakeProvider(<String>[
      _result(
          'Minjae came to check the emergency generator in the Server Room as the lights flicker.'),
      _result('The access panel light blinks.', dialogue: 'I do not know.'),
      _result('The access panel light blinks.', dialogue: 'I do not know.'),
      _result('The access panel light blinks.', dialogue: 'I do not know.'),
    ]);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(repository),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      llmProvider.overrideWithValue(fakeProvider),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await logDirectory.delete(recursive: true);
    });
    final NovelController controller =
        container.read(novelControllerProvider.notifier);
    await controller.saveSettings(const LanguageModelSettings());
    container.read(gameLanguageProvider.notifier).restoreLanguage('ko');
    await controller.createCampaign(world);
    await controller.act('윤서에게 실험실 카드키를 빌려준 적이 있는지 묻는다.');

    final Campaign updated = container.read(novelControllerProvider).campaign!;
    expect(updated.currentScene!.dialogue.single.text, '응, 실험실 카드키를 빌려준 적 있어.');
    expect(updated.characterMemory['char_yoon']!.knownFacts,
        contains('윤서는 실험실 카드키를 빌려준 적이 있다고 인정했다.'));
    final Campaign restored = (await repository.getCampaign(updated.id))!;
    expect(restored.characterMemory['char_yoon']!.knownFacts,
        contains('윤서는 실험실 카드키를 빌려준 적이 있다고 인정했다.'));
  });

  test('model memory alone cannot fabricate a known card-key holder', () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository repository = SqliteWorldRepository(db);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-untrusted-memory-');
    final World world = _world();
    await repository.createWorld(world);
    await repository.updateWorldDraft(world);
    final _FakeProvider fakeProvider = _FakeProvider(<String>[
      _result(
        'Minjae came to check the emergency generator in the Server Room as the lights flicker.',
        memory: 'Yoon knows who has the lab key card.',
      ),
      _result('The access panel light blinks.',
          dialogue: 'One of the lab assistants has it.',
          choices: ['Inspect the access panel', 'Check the hall door']),
    ]);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(repository),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      llmProvider.overrideWithValue(fakeProvider),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await logDirectory.delete(recursive: true);
    });
    final NovelController controller =
        container.read(novelControllerProvider.notifier);
    await controller.saveSettings(const LanguageModelSettings());
    await controller.createCampaign(world);
    await controller.act('Ask Seo Yoon who holds the lab key card.');

    final Campaign updated = container.read(novelControllerProvider).campaign!;
    expect(updated.characterMemory['char_yoon']!.knownFacts,
        contains('Yoon knows who has the lab key card.'));
    expect(
        updated.currentScene!.dialogue.single.text,
        matches(RegExp(
            r'(?:not sure|do not know|do not remember|cannot remember|never heard)',
            caseSensitive: false)));
  });

  test('OpenAI-compatible provider lists models, streams and tests generation',
      () async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? receivedAuthorization;
    final List<int?> outputLimits = <int?>[];
    final List<Map<String, dynamic>?> responseFormats =
        <Map<String, dynamic>?>[];
    final List<String> receivedPrompts = <String>[];
    final List<List<Map<String, dynamic>>> receivedMessages =
        <List<Map<String, dynamic>>>[];
    final Future<void> serving = () async {
      await for (final HttpRequest request in server) {
        receivedAuthorization =
            request.headers.value(HttpHeaders.authorizationHeader);
        if (request.uri.path == '/v1/models') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'data': [
              {'id': 'fixture-model'}
            ]
          }));
        } else {
          final Map<String, dynamic> body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          outputLimits.add(body['max_tokens'] as int?);
          responseFormats.add(body['response_format'] as Map<String, dynamic>?);
          final List<Map<String, dynamic>> messages =
              (body['messages'] as List).cast<Map<String, dynamic>>();
          receivedMessages.add(messages);
          receivedPrompts.add(messages.last['content'] as String);
          request.response.headers
              .set(HttpHeaders.contentTypeHeader, 'text/event-stream');
          request.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': '{"ok":true}'}
                  }
                ]
              })}\n\ndata: [DONE]\n\n');
        }
        await request.response.close();
      }
    }();
    addTearDown(() async {
      await server.close(force: true);
      await serving;
    });

    final OpenAiCompatibleProvider provider = OpenAiCompatibleProvider();
    addTearDown(provider.close);
    final LanguageModelSettings settings = LanguageModelSettings(
        baseUrl: 'http://127.0.0.1:${server.port}/v1', model: 'fixture-model');
    expect(await provider.listModels(settings, apiKey: 'test-key'),
        ['fixture-model']);
    expect(receivedAuthorization, 'Bearer test-key');
    const String prompt = '등대의 불이 꺼졌다. 바다를 살펴본다.';
    final String streamed = await provider
        .stream(prompt, settings,
            systemPrompt: 'System guidance.', jsonMode: true)
        .join();
    expect(streamed, '{"ok":true}');
    expect(receivedPrompts.first, prompt);
    expect(receivedMessages.first, [
      {'role': 'system', 'content': 'System guidance.'},
      {'role': 'user', 'content': prompt},
    ]);
    await provider.healthCheck(settings);
    expect(outputLimits, [512, 64]);
    expect(responseFormats, [
      {'type': 'json_object'},
      null,
    ]);
    expect(receivedMessages.last, [
      {'role': 'user', 'content': 'Reply with exactly {"ok":true}.'},
    ]);
  });

  test('provider retries transient server failures before streaming output',
      () async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    int requests = 0;
    final Future<void> serving = () async {
      await for (final HttpRequest request in server) {
        await utf8.decoder.bind(request).join();
        requests++;
        if (requests < 4) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"error":"temporary failure"}');
        } else {
          request.response.headers
              .set(HttpHeaders.contentTypeHeader, 'text/event-stream');
          request.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': '{"ok":true}'}
                  }
                ]
              })}\n\ndata: [DONE]\n\n');
        }
        await request.response.close();
      }
    }();
    addTearDown(() async {
      await server.close(force: true);
      await serving;
    });

    final OpenAiCompatibleProvider provider = OpenAiCompatibleProvider();
    addTearDown(provider.close);
    final String result = await provider
        .stream(
          'Continue the story.',
          LanguageModelSettings(
              baseUrl: 'http://127.0.0.1:${server.port}/v1',
              model: 'fixture-model'),
        )
        .join();

    expect(result, '{"ok":true}');
    expect(requests, 4);
  });

  test('provider reports persistent 503 after bounded retries', () async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    int requests = 0;
    final Future<void> serving = () async {
      await for (final HttpRequest request in server) {
        await utf8.decoder.bind(request).join();
        requests++;
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"error":"temporarily unavailable"}');
        await request.response.close();
      }
    }();
    addTearDown(() async {
      await server.close(force: true);
      await serving;
    });

    final OpenAiCompatibleProvider provider = OpenAiCompatibleProvider();
    addTearDown(provider.close);
    await expectLater(
      provider
          .stream(
            'Continue the story.',
            LanguageModelSettings(
                baseUrl: 'http://127.0.0.1:${server.port}/v1',
                model: 'fixture-model'),
          )
          .join(),
      throwsA(isA<LlmException>().having(
          (LlmException error) => error.statusCode,
          'statusCode',
          HttpStatus.serviceUnavailable)),
    );
    expect(requests, 4);
  });

  test('provider retries Gemini 503 errors delivered inside SSE', () async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    int requests = 0;
    final Future<void> serving = () async {
      await for (final HttpRequest request in server) {
        await utf8.decoder.bind(request).join();
        requests++;
        request.response.headers
            .set(HttpHeaders.contentTypeHeader, 'text/event-stream');
        if (requests == 1) {
          request.response.write('data: ${jsonEncode({
                'event_type': 'error',
                'error': {
                  'code': 'service_unavailable',
                  'message': 'Temporarily overloaded.',
                }
              })}\n\n');
        } else {
          request.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': '{"ok":true}'}
                  }
                ]
              })}\n\ndata: [DONE]\n\n');
        }
        await request.response.close();
      }
    }();
    addTearDown(() async {
      await server.close(force: true);
      await serving;
    });

    final OpenAiCompatibleProvider provider = OpenAiCompatibleProvider();
    addTearDown(provider.close);
    final String result = await provider
        .stream(
          'Continue the story.',
          LanguageModelSettings(
              baseUrl: 'http://127.0.0.1:${server.port}/v1',
              model: 'fixture-model'),
        )
        .join();

    expect(result, '{"ok":true}');
    expect(requests, 2);
  });

  test('context includes active scene and trims low-priority lore', () {
    final World world = _world();
    final DateTime now = DateTime.utc(2026);
    final SceneTurn previousScene = SceneTurn(
      id: 'previous_scene',
      narration: 'The lights failed.',
      dialogue: const <SceneDialogue>[
        SceneDialogue(characterId: 'char_yoon', text: 'The breaker clicked.')
      ],
      choices: const <String>['Inspect the panel', 'Ask Yoon'],
      playerAction: 'Check the light.',
      createdAt: now,
    );
    final Campaign campaign = Campaign(
      id: 'campaign_one',
      worldId: world.id,
      name: world.name,
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      worldState: const WorldState(
        currentLocationId: 'loc_server',
        presentCharacterIds: ['char_yoon'],
        facts: {'power': 'unstable'},
        events: [
          GameEvent(
              id: 'event_one',
              kind: 'status',
              description: 'The lights failed.')
        ],
      ),
      currentScene: previousScene,
      history: <SceneTurn>[previousScene],
    );
    final NarrativeContext context = const ContextBuilder(tokenLimit: 1400)
        .build(
            world: world,
            campaign: campaign,
            playerAction: 'Hide by the door.');
    expect(context.sections['System'], contains('Game Master'));
    expect(context.sections['System'], contains('Never repeat or paraphrase'));
    expect(context.systemPrompt, contains('Game Master'));
    expect(context.userPrompt, contains('[Player Intent]'));
    expect(context.userPrompt, isNot(contains('[System]')));
    expect(context.sections['Rules'], contains('No magic'));
    expect(context.sections['Location'], contains('Server Room'));
    expect(context.sections['Characters'], contains('char_yoon'));
    expect(context.sections['Scene State'], contains('power=unstable'));
    expect(context.sections['Scene State'], contains('The lights failed.'));
    expect(context.sections['Recent History'],
        contains('Choices already offered: Inspect the panel; Ask Yoon'));
    expect(context.sections['Player Intent'], 'Hide by the door.');
    final NarrativeContext opening = const ContextBuilder(tokenLimit: 1400)
        .build(
            world: world,
            campaign: campaign,
            playerAction: 'The lights fail.',
            isOpening: true);
    expect(opening.sections['System'], contains('This is the opening'));
    expect(opening.sections['Opening Situation'], 'The lights fail.');
    expect(context.estimatedTokens, lessThanOrEqualTo(1400));
    expect(playableWorldIssues(world), isEmpty);
  });

  test(
      'SQLite round-trips Player, Opening, Campaign history and provider settings',
      () async {
    final Directory temporaryDirectory =
        await Directory.systemTemp.createTemp('continuum-campaign-');
    final String databasePath = '${temporaryDirectory.path}/continuum.sqlite3';
    SqliteWorldRepository repository =
        await SqliteWorldRepository.open(databasePath);
    addTearDown(() async {
      await repository.close();
      await temporaryDirectory.delete(recursive: true);
    });
    final World world = _world();
    await repository.createWorld(world);
    final World restoredWorld = (await repository.getWorld(world.id))!;
    expect(restoredWorld.playerDefinition.name, 'Minjae');
    expect(restoredWorld.playerDefinition.traits, ['Observant', 'Technical']);
    expect(restoredWorld.openingDefinition.startingLocationId, 'loc_server');
    expect(restoredWorld.openingDefinition.startingCharacterIds, ['char_yoon']);

    final DateTime now = DateTime.utc(2026);
    final SceneTurn scene = SceneTurn(
      id: 'scene_one',
      narration: 'The generator coughs.',
      dialogue: const [
        SceneDialogue(characterId: 'char_yoon', text: 'Power is unstable.')
      ],
      choices: const ['Check the switch', 'Call out'],
      playerAction: null,
      createdAt: now,
    );
    final Campaign campaign = Campaign(
      id: 'campaign_one',
      worldId: world.id,
      name: world.name,
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      worldState: const WorldState(
          currentLocationId: 'loc_server',
          presentCharacterIds: ['char_yoon'],
          timeDescription: 'Night',
          atmosphere: 'Uneasy',
          relevantObjects: ['Breaker'],
          turnNumber: 1,
          facts: {'power': 'unstable'}),
      currentScene: scene,
      history: [scene],
      characterMemory: const {
        'char_yoon': CharacterMemory(
            importantMemories: ['The player noticed the outage.'],
            knownFacts: ['The player was here.'],
            relationship: 'Trusts the player cautiously',
            currentEmotion: 'Worried',
            goals: ['Restore power'],
            recentEvents: ['Heard the generator stop'])
      },
    );
    await repository.saveCampaign(campaign);
    final Campaign restored = (await repository.getCampaign(campaign.id))!;
    expect(restored.currentScene!.narration, scene.narration);
    expect(restored.history.single.dialogue.single.text, 'Power is unstable.');
    expect(restored.worldState.facts['power'], 'unstable');
    expect(restored.worldState.timeDescription, 'Night');
    expect(restored.worldState.atmosphere, 'Uneasy');
    expect(restored.worldState.relevantObjects, ['Breaker']);
    expect(restored.characterMemory['char_yoon']!.importantMemories,
        ['The player noticed the outage.']);
    expect(restored.characterMemory['char_yoon']!.relationship,
        'Trusts the player cautiously');
    expect(restored.characterMemory['char_yoon']!.currentEmotion, 'Worried');
    expect(restored.characterMemory['char_yoon']!.goals, ['Restore power']);
    expect(restored.characterMemory['char_yoon']!.recentEvents,
        ['Heard the generator stop']);
    await repository.saveLanguageModelSettings(
        const LanguageModelSettings(model: 'test-model', contextLimit: 3072));
    await repository.close();
    repository = await SqliteWorldRepository.open(databasePath);
    final World reopenedWorld = (await repository.getWorld(world.id))!;
    expect(reopenedWorld.openingDefinition.situation, 'The lights fail again.');
    final Campaign reloadedCampaign =
        (await repository.getCampaign(campaign.id))!;
    expect(reloadedCampaign.history.single.id, scene.id);
    expect(reloadedCampaign.worldState.turnNumber, 1);
    expect((await repository.getLanguageModelSettings()).model, 'test-model');
    expect((await repository.listCampaigns(world.id)).single.id, campaign.id);
  });

  test('New Game, action, regenerate and Continue commit one validated history',
      () async {
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (Database database) =>
            database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database database, int version) =>
            SqliteWorldRepository.openSchemaForTesting(database),
      ),
    );
    final SqliteWorldRepository repository = SqliteWorldRepository(db);
    final Directory logDirectory =
        await Directory.systemTemp.createTemp('continuum-novel-log-');
    final World world = _world();
    await repository.createWorld(world);
    await repository.updateWorldDraft(world);
    final _FakeProvider fakeProvider = _FakeProvider(<String>[
      _result('Minjae is in the Server Room as the breaker hums.',
          memory: 'The player heard the breaker.',
          dialogue: 'The sound came from the breaker.'),
      _result('Minjae는 발전기 패널을 확인했다.',
          dialogue: 'I think it came from the hall.',
          choices: ['Check the access panel', 'Ask Yoon what changed']),
      _result('금속 소리가 떠올랐다.', dialogue: 'I think it came from the hall.'),
      _result('윤서가 관리 복도 쪽을 가리킨다.',
          memory: 'The player heard the breaker.',
          dialogue: 'I hid the spare key.',
          choices: [
            'Check the stairwell door',
            'Check the stairwell door again',
            'Inspect the access control panel',
          ],
          fact: 'panel_checked',
          sceneChanges: {
            'locationId': 'loc_hall',
            'timeDescription': 'After midnight',
            'atmosphere': 'Tense',
            'relevantObjects': ['Loose wire'],
            'presentCharacterIds': <String>[],
          },
          npcChanges: [
            {
              'characterId': 'char_yoon',
              'relationship': 'Trusts Minjae cautiously',
              'currentEmotion': 'Concerned',
              'goals': ['Find the outage source'],
              'recentEvents': ['Checked the breaker panel'],
            }
          ]),
      _result('Seo Yoon finds the loose wire.',
          fact: 'wire_found',
          dialogue: 'This wire should not be disconnected.',
          choices: ['Trace the wire', 'Check the control panel']),
      '{',
      '{',
      '{',
    ]);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      worldRepositoryProvider.overrideWithValue(repository),
      workspaceProvider.overrideWith(() => _TestWorkspaceController(world)),
      appFileLoggerProvider.overrideWithValue(AppFileLogger(logDirectory)),
      llmProvider.overrideWithValue(fakeProvider),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await logDirectory.delete(recursive: true);
    });
    final NovelController controller =
        container.read(novelControllerProvider.notifier);
    container.read(gameLanguageProvider.notifier).restoreLanguage('ko');
    // Model selection belongs to the unified provider. Legacy custom-provider
    // settings may have no model name when a Local or Cloud Story Model is used.
    await controller.saveSettings(const LanguageModelSettings());
    await controller.createCampaign(world);
    expect(fakeProvider.lastMaxTokens, 640);
    final Campaign firstCampaign =
        container.read(novelControllerProvider).campaign!;
    expect(firstCampaign.languageCode, 'ko');
    expect(world.playerDefinition.name, 'Minjae');
    expect(firstCampaign.worldState.turnNumber, 1);
    expect(firstCampaign.history, hasLength(1));

    await controller.act('윤서에게 금속 소리가 어느 쪽에서 났는지 묻는다.');
    expect(fakeProvider.nextResponse, 4,
        reason:
            'Player agency and implied thoughts must be rejected before accepting a grounded result.');
    expect(fakeProvider.lastMaxTokens, 512);
    expect(fakeProvider.lastSystemPrompt, contains('context에 기록된 사실만 근거로 답하고'));
    final Campaign afterAction =
        (await repository.getCampaign(firstCampaign.id))!;
    expect(afterAction.worldState.facts['scene'], 'panel_checked');
    expect(afterAction.worldState.timeDescription, 'After midnight');
    expect(afterAction.worldState.atmosphere, 'Tense');
    expect(afterAction.worldState.relevantObjects, ['Loose wire']);
    expect(afterAction.worldState.currentLocationId, 'loc_server',
        reason:
            'A model proposal cannot move the player without an explicit movement action.');
    expect(afterAction.worldState.presentCharacterIds, ['char_yoon'],
        reason:
            'An NPC stays in the current scene unless the player moves away.');
    expect(afterAction.characterMemory['char_yoon']!.knownFacts,
        ['The player heard the breaker.']);
    expect(afterAction.characterMemory['char_yoon']!.relationship,
        'Trusts Minjae cautiously');
    expect(afterAction.characterMemory['char_yoon']!.goals,
        ['Find the outage source']);
    expect(
        afterAction.currentScene!.dialogue.single.text, 'Server Room 쪽에서 들었어.',
        reason:
            'Use the NPC\'s known location fact instead of an invented answer or secret.');
    expect(afterAction.history, hasLength(2));
    expect(afterAction.currentScene!.narration, '금속 소리는 Server Room에서 났다.');
    expect(afterAction.currentScene!.choices, hasLength(2));
    expect(afterAction.currentScene!.choices,
        isNot(contains('Check the stairwell door again')));

    await controller.regenerate();
    final Campaign regenerated =
        (await repository.getCampaign(firstCampaign.id))!;
    expect(regenerated.currentScene!.narration, '금속 소리는 Server Room에서 났다.');
    expect(regenerated.worldState.facts['scene'], 'wire_found');
    expect(regenerated.worldState.events, hasLength(3));
    expect(regenerated.worldState.turnNumber, 2);
    expect(regenerated.history, hasLength(2));
    await controller.continueCampaign(firstCampaign.id);
    expect(
        container
            .read(novelControllerProvider)
            .campaign!
            .currentScene!
            .narration,
        regenerated.currentScene!.narration);
    await expectLater(
        controller.act('Ask what happened.'), throwsFormatException);
    expect(fakeProvider.nextResponse, 8);
    final Campaign unchanged =
        (await repository.getCampaign(firstCampaign.id))!;
    expect(unchanged.currentScene!.id, regenerated.currentScene!.id);
    expect(unchanged.worldState.turnNumber, 2);
  });

  test('schema version 1 migration adds campaign storage and playable defaults',
      () async {
    final Directory directory =
        await Directory.systemTemp.createTemp('continuum-migration-');
    final String path = '${directory.path}/legacy.sqlite3';
    final Database legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute(
              'CREATE TABLE worlds (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL, genres TEXT NOT NULL, tones TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
          await db.execute(
              'CREATE TABLE world_rules (id TEXT, world_id TEXT, position INTEGER, text TEXT)');
          await db.execute(
              'CREATE TABLE lore_entries (id TEXT, world_id TEXT, created_at TEXT)');
          await db.execute(
              'CREATE TABLE characters (id TEXT, world_id TEXT, created_at TEXT)');
          await db.execute(
              'CREATE TABLE locations (id TEXT, world_id TEXT, created_at TEXT)');
          await db.insert('worlds', {
            'id': 'legacy_world',
            'name': 'Legacy',
            'description': '',
            'genres': '',
            'tones': '',
            'created_at': '2026-01-01T00:00:00.000Z',
            'updated_at': '2026-01-01T00:00:00.000Z',
          });
        },
      ),
    );
    await legacy.close();
    final SqliteWorldRepository migrated =
        await SqliteWorldRepository.open(path);
    addTearDown(() async {
      await migrated.close();
      await directory.delete(recursive: true);
    });
    final World restored = (await migrated.getWorld('legacy_world'))!;
    expect(restored.playerDefinition.name, isEmpty);
    expect(restored.openingDefinition.situation, isEmpty);
    expect(await migrated.listCampaigns('legacy_world'), isEmpty);
    expect((await migrated.getLanguageModelSettings()).contextLimit, 4096);
  });
}

World _world({
  String playerBackground = 'Maintains the server.',
  String secretInformation = 'She hid the spare key.',
}) =>
    World(
      id: 'world_campus',
      name: 'The Last Campus',
      description: 'A campus in a blackout.',
      genre: const ['Mystery'],
      tone: const ['Quiet'],
      rules: const ['No magic'],
      playerDefinition: PlayerDefinition(
          name: 'Minjae',
          description: 'Student',
          background: playerBackground,
          traits: ['Observant', 'Technical']),
      openingDefinition: const OpeningDefinition(
          startingLocationId: 'loc_server',
          startingCharacterIds: ['char_yoon'],
          situation: 'The lights fail again.'),
      locations: const [
        StoryLocation(
            id: 'loc_server',
            name: 'Server Room',
            description: 'A humming room.')
      ],
      characters: [
        StoryCharacter(
            id: 'char_yoon',
            name: 'Seo Yoon',
            role: 'Student',
            description: 'Calm.',
            personality: 'Careful',
            background: 'Lab assistant',
            publicInformation: 'She was on campus. Server Room에서 금속 소리를 들었다.',
            secretInformation: secretInformation)
      ],
      loreEntries: [
        LoreEntry(
            id: 'lore_one',
            title: 'Campus history',
            category: 'History',
            content: List<String>.filled(500, 'Old library.').join(' '))
      ],
    );

String _result(String narration,
        {String? memory,
        String dialogue = 'I heard that.',
        List<String> choices = const ['Look closer', 'Wait a moment'],
        String? fact,
        Map<String, Object?> sceneChanges = const {},
        List<Map<String, Object?>> npcChanges = const []}) =>
    jsonEncode(
      <String, Object?>{
        'schemaVersion': 1,
        'narration': narration,
        'dialogue': <Map<String, String>>[
          {'characterId': 'char_yoon', 'text': dialogue}
        ],
        'choices': choices,
        'events': <Map<String, String>>[
          {'kind': 'sound', 'description': 'A quiet mechanical hum.'}
        ],
        'stateChanges':
            fact != null ? <String, String>{'scene': fact} : <String, String>{},
        'sceneChanges': sceneChanges,
        'npcChanges': npcChanges,
        'memoryUpdates': memory != null
            ? <Map<String, String>>[
                {'characterId': 'char_yoon', 'summary': memory}
              ]
            : <Map<String, String>>[],
      },
    );

String _soloResult(String narration) => jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'narration': narration,
      'choices': ['Inspect the warning light', 'Listen to the room'],
    });

class _TestWorkspaceController extends WorkspaceController {
  _TestWorkspaceController(this.world);
  final World world;
  @override
  WorkspaceState build() => WorkspaceState(
      worlds: <World>[world], loadStatus: WorkspaceLoadStatus.ready);
  @override
  Future<void> refreshCampaigns(String worldId) async {}
}

class _FakeProvider implements LlmProvider {
  _FakeProvider(this.responses);
  final List<String> responses;
  int nextResponse = 0;
  int? lastMaxTokens;
  int? lastContextLimit;
  String? lastSystemPrompt;
  @override
  void cancelCurrentRequest() {}
  @override
  Future<List<String>> listModels(LanguageModelSettings settings,
          {String? apiKey}) async =>
      ['fixture-model'];
  @override
  Stream<String> stream(String prompt, LanguageModelSettings settings,
      {String? apiKey,
      int? maxTokens,
      String? systemPrompt,
      bool jsonMode = false}) async* {
    lastMaxTokens = maxTokens;
    lastContextLimit = settings.contextLimit;
    lastSystemPrompt = systemPrompt;
    yield responses[nextResponse++];
  }

  @override
  Future<void> healthCheck(LanguageModelSettings settings,
      {String? apiKey}) async {}
}

class _BlockingProvider implements LlmProvider {
  final Completer<void> requestStarted = Completer<void>();
  final Completer<String> response = Completer<String>();
  int requestCount = 0;

  @override
  void cancelCurrentRequest() {}

  @override
  Future<List<String>> listModels(LanguageModelSettings settings,
          {String? apiKey}) async =>
      ['fixture-model'];

  @override
  Stream<String> stream(String prompt, LanguageModelSettings settings,
      {String? apiKey,
      int? maxTokens,
      String? systemPrompt,
      bool jsonMode = false}) async* {
    requestCount++;
    if (!requestStarted.isCompleted) requestStarted.complete();
    yield await response.future;
  }

  @override
  Future<void> healthCheck(LanguageModelSettings settings,
      {String? apiKey}) async {}
}

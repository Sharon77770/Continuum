import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:continuum_desktop/features/models/data/llama_runtime_manager.dart';
import 'package:continuum_desktop/features/models/domain/model_catalog.dart';
import 'package:continuum_desktop/features/models/domain/local_runtime_tuning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late _FakeLauncher launcher;
  late LlamaRuntimeManager manager;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('continuum-runtime-test-');
    launcher = _FakeLauncher();
    manager = LlamaRuntimeManager(
      modelsDirectory: Directory('${temp.path}/models'),
      logDirectory: Directory('${temp.path}/logs'),
      installer: _FakeInstaller(),
      launcher: launcher,
      platformSupported: () => true,
    );
  });

  tearDown(() async {
    await manager.dispose();
    await temp.delete(recursive: true);
  });

  test('starts on demand and stops the managed process', () async {
    final InstalledModel model = await _createModel(temp);
    final Uri endpoint = await manager.ensureReady(model);
    expect(endpoint.host, '127.0.0.1');
    expect(manager.snapshot.status, RuntimeStatus.ready);
    expect(manager.snapshot.version, 'runtime-test-1');
    expect(launcher.process?.killed, isFalse);
    expect(launcher.arguments, contains('--reasoning'));
    expect(launcher.arguments![launcher.arguments!.indexOf('--reasoning') + 1],
        'off');
    expect(launcher.arguments![launcher.arguments!.indexOf('--batch-size') + 1],
        '512');
    expect(
        launcher.arguments![launcher.arguments!.indexOf('--ubatch-size') + 1],
        '256');

    await manager.stop();
    expect(launcher.process?.killed, isTrue);
    expect(manager.snapshot.status, RuntimeStatus.stopped);
  });

  test('changing resource profile restarts the runtime with new limits',
      () async {
    final InstalledModel model = await _createModel(temp);
    await manager.ensureReady(model);
    final _FakeRuntimeProcess firstProcess = launcher.process!;

    await manager.ensureReady(model,
        resourceProfile: LocalResourceProfile.performance);

    expect(launcher.launchCount, 2);
    expect(firstProcess.killed, isTrue);
    expect(launcher.arguments![launcher.arguments!.indexOf('--ctx-size') + 1],
        '4096');
    expect(launcher.arguments![launcher.arguments!.indexOf('--batch-size') + 1],
        '2048');
    expect(
        launcher.arguments![launcher.arguments!.indexOf('--ubatch-size') + 1],
        '512');
    expect(
        int.parse(
            launcher.arguments![launcher.arguments!.indexOf('--threads') + 1]),
        Platform.numberOfProcessors);
  });

  test('resource tuning trades CPU, context and batch size', () {
    final LocalRuntimeTuning conservative = LocalRuntimeTuning.forProfile(
      profile: LocalResourceProfile.conservative,
      modelContextSize: 8192,
      logicalProcessors: 8,
    );
    final LocalRuntimeTuning performance = LocalRuntimeTuning.forProfile(
      profile: LocalResourceProfile.performance,
      modelContextSize: 8192,
      logicalProcessors: 8,
    );
    expect(conservative.threads, 4);
    expect(conservative.contextSize, 2048);
    expect(conservative.batchSize, 256);
    expect(performance.threads, 8);
    expect(performance.contextSize, 8192);
    expect(performance.batchSize, 2048);
  });

  test('shares one runtime startup between concurrent callers', () async {
    final InstalledModel model = await _createModel(temp);
    final List<Uri> endpoints = await Future.wait(<Future<Uri>>[
      manager.ensureReady(model),
      manager.ensureReady(model),
      manager.ensureReady(model),
    ]);

    expect(launcher.launchCount, 1);
    expect(endpoints.toSet(), hasLength(1));
    expect(manager.snapshot.status, RuntimeStatus.ready);
  });

  test('detects a runtime crash after becoming ready', () async {
    final InstalledModel model = await _createModel(temp);
    await manager.ensureReady(model);
    launcher.process!.crash(7);
    await launcher.process!.closed;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(manager.snapshot.status, RuntimeStatus.failed);
    expect(manager.snapshot.message, contains('stopped unexpectedly'));
  });

  test('missing model and incompatible file return separate errors', () async {
    final InstalledModel missing = _model('${temp.path}/missing.gguf');
    await expectLater(
      manager.ensureReady(missing),
      throwsA(
          isA<RuntimeFailure>().having((e) => e.kind, 'kind', 'model_missing')),
    );
    final File wrongFile = File('${temp.path}/model.bin');
    await wrongFile.writeAsString('not a GGUF');
    await expectLater(
      manager.ensureReady(_model(wrongFile.path)),
      throwsA(isA<RuntimeFailure>()
          .having((e) => e.kind, 'kind', 'model_incompatible')),
    );
  });

  test('maps a model allocation failure to insufficient memory', () async {
    launcher.startupError = 'failed to allocate memory for model tensors';
    final InstalledModel model = await _createModel(temp);
    await expectLater(
      manager.ensureReady(model),
      throwsA(isA<RuntimeFailure>().having(
          (RuntimeFailure error) => error.kind, 'kind', 'insufficient_memory')),
    );
    expect(manager.snapshot.message, contains('not enough available memory'));
  });
}

Future<InstalledModel> _createModel(Directory temp) async {
  final File file = File('${temp.path}/models/story.gguf');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(utf8.encode('GGUF'));
  return _model(file.path);
}

InstalledModel _model(String file) => InstalledModel(
      id: 'runtime-test-model',
      displayName: 'Runtime Test Model',
      fileName: file.split(Platform.pathSeparator).last,
      path: file,
      sizeBytes: 4,
      source: ModelSource.localImport,
      repository: 'test',
      license: 'Unknown',
      qualityClass: ModelQuality.fast,
      speedClass: ModelSpeed.fast,
      contextSize: 4096,
      sha256: null,
      importedAt: DateTime.utc(2026),
    );

class _FakeInstaller implements RuntimeBinaryInstaller {
  @override
  Future<RuntimeBinary> ensureInstalled() async => const RuntimeBinary(
        executable: 'test-runtime.exe',
        version: 'runtime-test-1',
      );
}

class _FakeLauncher implements RuntimeProcessLauncher {
  _FakeRuntimeProcess? process;
  List<String>? arguments;
  String? startupError;
  int launchCount = 0;

  @override
  Future<RuntimeProcess> start(
      String executable, List<String> arguments) async {
    launchCount++;
    this.arguments = arguments;
    final int port = int.parse(arguments[arguments.indexOf('--port') + 1]);
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.listen((HttpRequest request) {
      request.response.statusCode = HttpStatus.ok;
      request.response.write('ready');
      request.response.close();
    });
    process = _FakeRuntimeProcess(server);
    if (startupError != null) {
      scheduleMicrotask(() {
        process!.writeStderr(startupError!);
        process!.crash(1);
      });
    }
    return process!;
  }
}

class _FakeRuntimeProcess implements RuntimeProcess {
  _FakeRuntimeProcess(this.server);
  final HttpServer server;
  final Completer<int> _exit = Completer<int>();
  final StreamController<List<int>> _stdout = StreamController.broadcast();
  final StreamController<List<int>> _stderr = StreamController.broadcast();
  bool killed = false;
  Future<void>? _closed;
  Future<void> get closed => _closed ??= server.close(force: true);

  @override
  int get pid => 4242;
  @override
  Stream<List<int>> get stdout => _stdout.stream;
  @override
  Stream<List<int>> get stderr => _stderr.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool kill() {
    killed = true;
    _finish(0);
    return true;
  }

  void crash(int code) => _finish(code);

  void writeStderr(String line) => _stderr.add(utf8.encode('$line\n'));

  void _finish(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    unawaited(closed);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }
}

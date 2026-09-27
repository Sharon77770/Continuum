import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../domain/model_catalog.dart';
import '../domain/local_runtime_tuning.dart';
import '../domain/runtime_manager.dart';

class RuntimeBinary {
  const RuntimeBinary({required this.executable, required this.version});
  final String executable;
  final String version;
}

abstract interface class RuntimeBinaryInstaller {
  Future<RuntimeBinary> ensureInstalled();
}

abstract interface class RuntimeProcess {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill();
}

abstract interface class RuntimeProcessLauncher {
  Future<RuntimeProcess> start(String executable, List<String> arguments);
}

class SystemRuntimeProcessLauncher implements RuntimeProcessLauncher {
  @override
  Future<RuntimeProcess> start(
          String executable, List<String> arguments) async =>
      _SystemRuntimeProcess(await Process.start(executable, arguments));
}

class _SystemRuntimeProcess implements RuntimeProcess {
  _SystemRuntimeProcess(this.process);
  final Process process;
  @override
  int get pid => process.pid;
  @override
  Stream<List<int>> get stdout => process.stdout;
  @override
  Stream<List<int>> get stderr => process.stderr;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  bool kill() => process.kill();
}

class GitHubLlamaBinaryInstaller implements RuntimeBinaryInstaller {
  GitHubLlamaBinaryInstaller({
    required this.installDirectory,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Directory installDirectory;
  final HttpClient _client;
  static final Uri _releaseApi = Uri.parse(
      'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest');
  static final Uri _releasesApi = Uri.parse(
      'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=20');

  File get _metadata => File(path.join(installDirectory.path, 'runtime.json'));

  @override
  Future<RuntimeBinary> ensureInstalled() async {
    await installDirectory.create(recursive: true);
    final RuntimeBinary? installed = await _readInstalled();
    if (installed != null) return installed;
    Map<String, dynamic> release =
        await _getJson(_releaseApi) as Map<String, dynamic>;
    Map<String, dynamic>? asset = _windowsCpuAsset(release);
    if (asset == null) {
      final List<dynamic> releases =
          await _getJson(_releasesApi) as List<dynamic>;
      for (final dynamic candidate in releases) {
        if (candidate is! Map<String, dynamic>) continue;
        final Map<String, dynamic>? candidateAsset =
            _windowsCpuAsset(candidate);
        if (candidateAsset == null) continue;
        release = candidate;
        asset = candidateAsset;
        break;
      }
    }
    if (asset == null) {
      throw StateError('A compatible Windows runtime is not available yet.');
    }
    final String version = release['tag_name'] as String? ?? 'unknown';
    final String? digest = asset['digest'] as String?;
    if (digest == null || !digest.startsWith('sha256:')) {
      throw StateError('The runtime publisher did not provide a checksum.');
    }
    final Uri uri = Uri.parse(asset['browser_download_url'] as String);
    final Directory temp = Directory(path.join(installDirectory.path,
        'install-${DateTime.now().microsecondsSinceEpoch}'));
    await temp.create(recursive: true);
    final File archive = File(path.join(temp.path, 'runtime.zip'));
    try {
      await _download(uri, archive, digest.substring('sha256:'.length));
      final Directory extracted = Directory(path.join(temp.path, 'extracted'));
      await extracted.create(recursive: true);
      final String powershell = path.join(
          Platform.environment['WINDIR'] ?? r'C:\Windows',
          'System32',
          'WindowsPowerShell',
          'v1.0',
          'powershell.exe');
      final ProcessResult result = await Process.run(
        powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'Expand-Archive -LiteralPath $env:CONTINUUM_RUNTIME_ARCHIVE -DestinationPath $env:CONTINUUM_RUNTIME_EXTRACT -Force'
        ],
        environment: <String, String>{
          ...Platform.environment,
          'CONTINUUM_RUNTIME_ARCHIVE': archive.path,
          'CONTINUUM_RUNTIME_EXTRACT': extracted.path,
        },
      ).timeout(const Duration(minutes: 2));
      if (result.exitCode != 0) {
        throw StateError('The managed runtime archive could not be unpacked.');
      }
      final File server = Directory(extracted.path)
              .listSync(recursive: true)
              .whereType<File>()
              .where((File file) =>
                  path.basename(file.path).toLowerCase() == 'llama-server.exe')
              .firstOrNull ??
          (throw StateError(
              'The runtime package did not contain llama-server.'));
      final String versionDirectoryName = _safeSegment(version);
      final Directory target =
          Directory(path.join(installDirectory.path, versionDirectoryName));
      if (await target.exists()) await target.delete(recursive: true);
      await Directory(path.dirname(server.path)).rename(target.path);
      final RuntimeBinary resultBinary = RuntimeBinary(
          executable: path.join(target.path, 'llama-server.exe'),
          version: version);
      await _metadata.writeAsString(
          jsonEncode({
            'version': version,
            'executable': resultBinary.executable,
            'sha256': digest.substring('sha256:'.length),
            'asset': asset['name'],
          }),
          flush: true);
      return resultBinary;
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Map<String, dynamic>? _windowsCpuAsset(Map<String, dynamic> release) =>
      (release['assets'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((Map<String, dynamic> item) =>
              (item['name'] as String? ?? '').endsWith('-bin-win-cpu-x64.zip'))
          .firstOrNull;

  Future<RuntimeBinary?> _readInstalled() async {
    if (!await _metadata.exists()) return null;
    try {
      final Map<String, dynamic> data =
          jsonDecode(await _metadata.readAsString()) as Map<String, dynamic>;
      final String executable = data['executable'] as String;
      if (!await File(executable).exists()) return null;
      return RuntimeBinary(
          executable: executable, version: data['version'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _getJson(Uri uri) async {
    final HttpClientRequest request = await _client.getUrl(uri);
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Continuum-Desktop');
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
          'Runtime information could not be downloaded (${response.statusCode}).');
    }
    return jsonDecode(await utf8.decoder.bind(response).join());
  }

  Future<void> _download(Uri uri, File target, String expectedHash) async {
    if (uri.scheme != 'https' || uri.host != 'github.com') {
      throw const HttpException('The runtime release link is not trusted.');
    }
    final HttpClientRequest request = await _client.getUrl(uri);
    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          'The runtime download failed (${response.statusCode}).');
    }
    final IOSink sink = target.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
    final String actual =
        (await sha256.bind(target.openRead()).first).toString();
    if (actual.toLowerCase() != expectedHash.toLowerCase()) {
      await target.delete();
      throw const FileSystemException('Runtime checksum verification failed.');
    }
  }

  String _safeSegment(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

class RuntimeFailure implements Exception {
  const RuntimeFailure(this.kind, this.message);
  final String kind;
  final String message;
  @override
  String toString() => message;
}

class LlamaRuntimeManager implements RuntimeManager {
  LlamaRuntimeManager({
    required this.modelsDirectory,
    required this.logDirectory,
    required RuntimeBinaryInstaller installer,
    RuntimeProcessLauncher? launcher,
    HttpClient? healthClient,
    bool Function()? platformSupported,
  })  : _installer = installer,
        _launcher = launcher ?? SystemRuntimeProcessLauncher(),
        _healthClient = healthClient ?? HttpClient(),
        _platformSupported = platformSupported ?? (() => Platform.isWindows);

  final Directory modelsDirectory;
  final Directory logDirectory;
  final RuntimeBinaryInstaller _installer;
  final RuntimeProcessLauncher _launcher;
  final HttpClient _healthClient;
  final bool Function() _platformSupported;
  RuntimeProcess? _process;
  RuntimeBinary? _binary;
  Uri? _endpoint;
  String? _modelId;
  LocalResourceProfile? _resourceProfile;
  RuntimeSnapshot _snapshot =
      const RuntimeSnapshot(status: RuntimeStatus.stopped);
  final StreamController<RuntimeSnapshot> _changes =
      StreamController<RuntimeSnapshot>.broadcast();
  Future<void>? _starting;
  Future<void> _logWrites = Future<void>.value();
  int _generation = 0;
  String? _lastRuntimeError;

  @override
  RuntimeSnapshot get snapshot => _snapshot;
  @override
  Stream<RuntimeSnapshot> get changes => _changes.stream;
  File get _runtimeLog =>
      File(path.join(logDirectory.path, 'llama-runtime.log'));

  @override
  Future<Uri> ensureReady(InstalledModel model,
      {LocalResourceProfile resourceProfile =
          LocalResourceProfile.balanced}) async {
    if (_snapshot.status == RuntimeStatus.ready &&
        _modelId == model.id &&
        _resourceProfile == resourceProfile &&
        _endpoint != null) {
      return _endpoint!;
    }
    final Future<void>? starting = _starting;
    if (starting != null) {
      await starting;
      if (_snapshot.status == RuntimeStatus.ready &&
          _modelId == model.id &&
          _resourceProfile == resourceProfile &&
          _endpoint != null) {
        return _endpoint!;
      }
    }
    if (_snapshot.status == RuntimeStatus.ready &&
        _modelId == model.id &&
        _resourceProfile == resourceProfile) {
      return _endpoint!;
    }
    // Publish the in-flight Future before its first asynchronous step so
    // concurrent callers cannot both stop/start separate llama-server processes.
    final Future<void> operation = _startIfNeeded(model, resourceProfile);
    _starting = operation;
    try {
      await operation;
      if (_endpoint == null) {
        throw const RuntimeFailure(
            'runtime_cancelled', 'Model loading was cancelled.');
      }
      return _endpoint!;
    } finally {
      if (identical(_starting, operation)) _starting = null;
    }
  }

  Future<void> _startIfNeeded(
      InstalledModel model, LocalResourceProfile resourceProfile) async {
    if (!await File(model.path).exists()) {
      throw const RuntimeFailure('model_missing',
          'Model file is missing. Download or import it again.');
    }
    await stop();
    await _start(model, _generation, resourceProfile);
  }

  Future<void> _start(InstalledModel model, int generation,
      LocalResourceProfile resourceProfile) async {
    if (!_platformSupported()) {
      throw const RuntimeFailure('runtime_unavailable',
          'Local stories are currently supported on Windows.');
    }
    if (!model.path.toLowerCase().endsWith('.gguf')) {
      throw const RuntimeFailure('model_incompatible',
          'This model file cannot run with Continuum. Choose a GGUF model.');
    }
    _publish(const RuntimeSnapshot(
        status: RuntimeStatus.starting, message: 'Loading model'));
    try {
      await modelsDirectory.create(recursive: true);
      await logDirectory.create(recursive: true);
      _binary = await _installer.ensureInstalled();
      if (generation != _generation) return;
      final ServerSocket reservation =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int port = reservation.port;
      await reservation.close();
      _endpoint = Uri.parse('http://127.0.0.1:$port/v1');
      _modelId = model.id;
      _resourceProfile = resourceProfile;
      final LocalRuntimeTuning tuning = LocalRuntimeTuning.forProfile(
        profile: resourceProfile,
        modelContextSize: model.contextSize,
        logicalProcessors: Platform.numberOfProcessors,
      );
      final RuntimeProcess process =
          await _launcher.start(_binary!.executable, [
        '--model',
        model.path,
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
        '--ctx-size',
        '${tuning.contextSize}',
        '--threads',
        '${tuning.threads}',
        '--threads-batch',
        '${tuning.threads}',
        '--batch-size',
        '${tuning.batchSize}',
        '--ubatch-size',
        '${tuning.microBatchSize}',
        '--reasoning',
        'off',
        '--n-gpu-layers',
        '0',
        '--alias',
        model.id,
      ]);
      _process = process;
      _lastRuntimeError = null;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) => _appendRuntimeLog('OUT $line'));
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) {
        _lastRuntimeError = line;
        unawaited(_appendRuntimeLog('ERR $line'));
      });
      unawaited(process.exitCode.then((int code) {
        if (_process == process) {
          _process = null;
          _endpoint = null;
          _publish(RuntimeSnapshot(
            status: RuntimeStatus.failed,
            version: _binary?.version,
            modelId: model.id,
            message: 'The local model stopped unexpectedly. Try again.',
            logPath: _runtimeLog.path,
          ));
          unawaited(_appendRuntimeLog('PROCESS EXIT $code'));
        }
      }));
      if (generation != _generation) {
        process.kill();
        return;
      }
      await _waitUntilHealthy(process, model, generation);
      _publish(RuntimeSnapshot(
        status: RuntimeStatus.ready,
        version: _binary?.version,
        modelId: model.id,
        processId: process.pid,
        endpoint: _endpoint,
        logPath: _runtimeLog.path,
      ));
    } catch (error) {
      final RuntimeFailure failure = _classifyFailure(error);
      final RuntimeProcess? process = _process;
      _process = null;
      process?.kill();
      final String friendly = failure.message;
      _publish(RuntimeSnapshot(
        status: RuntimeStatus.failed,
        version: _binary?.version,
        modelId: model.id,
        message: friendly,
        logPath: _runtimeLog.path,
      ));
      unawaited(_appendRuntimeLog('START FAILED ${error.runtimeType}: $error'));
      throw failure;
    }
  }

  RuntimeFailure _classifyFailure(Object error) {
    final String diagnostic = _lastRuntimeError?.toLowerCase() ?? '';
    if (RegExp(
            r'(out of memory|not enough memory|failed to allocate|cannot allocate memory|allocation failed)')
        .hasMatch(diagnostic)) {
      return const RuntimeFailure('insufficient_memory',
          'There is not enough available memory for this model. Choose a smaller model or close other apps.');
    }
    if (RegExp(
            r'(unsupported.*architecture|unknown.*architecture|invalid gguf|not a gguf|unsupported model format)')
        .hasMatch(diagnostic)) {
      return const RuntimeFailure('model_incompatible',
          'This model is not compatible with Continuum. Choose another GGUF model.');
    }
    if (error is RuntimeFailure) return error;
    return const RuntimeFailure('runtime_start_failed',
        'Continuum could not start this model. Check available memory and try again.');
  }

  Future<void> _waitUntilHealthy(
      RuntimeProcess process, InstalledModel model, int generation) async {
    final DateTime deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (generation != _generation) {
        process.kill();
        throw const RuntimeFailure(
            'runtime_cancelled', 'Model loading was cancelled.');
      }
      if (_process != process) {
        throw const RuntimeFailure('runtime_crashed',
            'The local model stopped while loading. Try again.');
      }
      try {
        final Uri health = _endpoint!.replace(path: '/health');
        final HttpClientRequest request = await _healthClient
            .getUrl(health)
            .timeout(const Duration(seconds: 2));
        final HttpClientResponse response =
            await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == HttpStatus.ok) {
          await response.drain<void>();
          return;
        }
        await response.drain<void>();
      } catch (_) {
        // The server can refuse connections until model loading completes.
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const RuntimeFailure('model_loading_failed',
        'The model took too long to load. Check memory and try again.');
  }

  @override
  Future<void> stop() async {
    _generation++;
    final RuntimeProcess? process = _process;
    _process = null;
    _endpoint = null;
    _modelId = null;
    _resourceProfile = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill();
      }
    }
    if (_snapshot.status != RuntimeStatus.notInstalled) {
      _publish(RuntimeSnapshot(
        status: RuntimeStatus.stopped,
        version: _binary?.version,
        logPath: _runtimeLog.path,
      ));
    }
  }

  Future<void> _appendRuntimeLog(String line) {
    _logWrites = _logWrites.then((_) async {
      await logDirectory.create(recursive: true);
      if (await _runtimeLog.exists() &&
          await _runtimeLog.length() > 2 * 1024 * 1024) {
        final File old = File('${_runtimeLog.path}.1');
        if (await old.exists()) await old.delete();
        await _runtimeLog.rename(old.path);
      }
      await _runtimeLog.writeAsString(
          '${DateTime.now().toUtc().toIso8601String()} $line\n',
          mode: FileMode.append,
          flush: true);
    });
    return _logWrites;
  }

  void _publish(RuntimeSnapshot value) {
    _snapshot = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _logWrites;
    _healthClient.close(force: true);
    await _changes.close();
  }
}

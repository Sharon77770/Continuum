import 'dart:async';

import 'package:continuum_desktop/features/models/data/runtime_lifecycle_adapter.dart';
import 'package:continuum_desktop/features/models/domain/model_catalog.dart';
import 'package:continuum_desktop/features/models/domain/runtime_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authorizes the Windows close only after runtime shutdown completes',
      () async {
    const MethodChannel channel = MethodChannel('continuum/runtime_lifecycle');
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final _FakeRuntime runtime = _FakeRuntime();
    final RuntimeLifecycleAdapter adapter =
        RuntimeLifecycleAdapter(runtime, enabled: true)..register();
    bool closeAuthorized = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'allowClose') closeAuthorized = true;
      return null;
    });

    addTearDown(() {
      adapter.unregister();
      messenger.setMockMethodCallHandler(channel, null);
    });

    final Future<ByteData?> closeRequest = messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('onCloseRequested')),
      (_) {},
    );
    await runtime.stopStarted.future;
    expect(closeAuthorized, isFalse);

    runtime.finishStop.complete();
    await closeRequest;
    await messenger.platformMessagesFinished;
    expect(closeAuthorized, isTrue);
  });
}

class _FakeRuntime implements RuntimeManager {
  final Completer<void> stopStarted = Completer<void>();
  final Completer<void> finishStop = Completer<void>();

  @override
  RuntimeSnapshot get snapshot =>
      const RuntimeSnapshot(status: RuntimeStatus.stopped);

  @override
  Stream<RuntimeSnapshot> get changes => const Stream<RuntimeSnapshot>.empty();

  @override
  Future<Uri> ensureReady(InstalledModel model,
          {LocalResourceProfile resourceProfile =
              LocalResourceProfile.balanced}) async =>
      Uri();

  @override
  Future<void> stop() async {
    stopStarted.complete();
    await finishStop.future;
  }

  @override
  Future<void> dispose() async {}
}

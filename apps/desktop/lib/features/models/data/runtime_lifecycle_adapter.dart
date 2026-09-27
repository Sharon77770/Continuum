import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/runtime_manager.dart';

class RuntimeLifecycleAdapter {
  RuntimeLifecycleAdapter(this._runtime, {bool? enabled})
      : _channel = const MethodChannel('continuum/runtime_lifecycle'),
        _enabled = enabled ?? Platform.isWindows;

  final RuntimeManager _runtime;
  final MethodChannel _channel;
  final bool _enabled;

  void register() {
    if (!_enabled) return;
    _channel.setMethodCallHandler(_handleCall);
  }

  void unregister() {
    if (!_enabled) return;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'onCloseRequested') {
      throw MissingPluginException('Unsupported runtime lifecycle call.');
    }
    try {
      await _runtime.stop();
    } finally {
      await _channel.invokeMethod<void>('allowClose');
    }
  }
}

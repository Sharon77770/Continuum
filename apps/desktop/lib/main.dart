import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/continuum_app.dart';
import 'core/app_file_logger.dart';
import 'core/app_paths.dart';
import 'core/developer_tools_providers.dart';
import 'core/runtime_environment.dart';
import 'features/models/application/model_manager_controller.dart';
import 'state/locale_controller.dart';
import 'state/workspace_controller.dart';

void main() {
  if (Platform.isWindows) {
    sqfliteFfiInit();
  }
  final AppPaths paths = AppPaths.resolve(
    operatingSystem: Platform.operatingSystem,
    environment: Platform.environment,
    homeDirectory: Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path,
    buildMode: RuntimeEnvironmentInfo.current().buildMode,
  );
  final AppFileLogger logger = AppFileLogger(paths.logDirectory);
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.error('Unhandled Flutter error', details.exception,
        details.stack ?? StackTrace.current);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    logger.error('Unhandled platform error', error, stackTrace);
    return true;
  };
  runApp(ProviderScope(
    overrides: [
      appPathsProvider.overrideWithValue(paths),
      appFileLoggerProvider.overrideWithValue(logger),
    ],
    child: const _ContinuumBootstrap(),
  ));
}

class _ContinuumBootstrap extends ConsumerStatefulWidget {
  const _ContinuumBootstrap();

  @override
  ConsumerState<_ContinuumBootstrap> createState() =>
      _ContinuumBootstrapState();
}

class _ContinuumBootstrapState extends ConsumerState<_ContinuumBootstrap> {
  bool _languagePreferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final Map<String, String> languages = await ref
          .read(languagePreferencesRepositoryProvider)
          .load();
      ref
          .read(localeProvider.notifier)
          .restoreLanguage(Locale(languages['uiLanguage'] ?? 'en'));
      ref
          .read(gameLanguageProvider.notifier)
          .restoreLanguage(languages['gameLanguage'] ?? 'en');
    } catch (_) {
      // Defaults remain active if local preferences cannot be read.
    }
    if (!mounted) return;
    setState(() => _languagePreferencesLoaded = true);
    ref.read(workspaceProvider.notifier).initialize();
    ref.read(modelManagerControllerProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) => _languagePreferencesLoaded
      ? const ContinuumApp()
      : const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
}

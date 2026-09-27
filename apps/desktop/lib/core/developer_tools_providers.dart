import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/data/developer_tools_service.dart';
import 'app_file_logger.dart';
import 'app_paths.dart';
import 'runtime_environment.dart';

final appPathsProvider = Provider<AppPaths>((ref) => AppPaths.resolve(
      operatingSystem: Platform.operatingSystem,
      environment: Platform.environment,
      homeDirectory: Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path,
      buildMode: RuntimeEnvironmentInfo.current().buildMode,
    ));

final appFileLoggerProvider = Provider<AppFileLogger>(
    (ref) => AppFileLogger(ref.watch(appPathsProvider).logDirectory));

final runtimeEnvironmentProvider =
    Provider<RuntimeEnvironmentInfo>((ref) => RuntimeEnvironmentInfo.current());

final developerToolsServiceProvider = Provider<DeveloperToolsService>((ref) =>
    DeveloperToolsService(
        paths: ref.watch(appPathsProvider),
        logger: ref.watch(appFileLoggerProvider)));

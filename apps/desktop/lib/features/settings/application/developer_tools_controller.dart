import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/developer_tools_providers.dart';
import '../data/database_snapshot.dart';
import '../data/desktop_directory_opener.dart';

final developerToolsControllerProvider =
    NotifierProvider<DeveloperToolsController, DeveloperToolsState>(
        DeveloperToolsController.new);

/// UI state for the Settings developer section; filesystem work stays in data.
class DeveloperToolsState {
  const DeveloperToolsState({
    this.snapshot,
    this.isBusy = false,
    this.message,
    this.integrityPassed,
  });

  final DatabaseSnapshot? snapshot;
  final bool isBusy;
  final String? message;
  final bool? integrityPassed;

  DeveloperToolsState copyWith({
    DatabaseSnapshot? snapshot,
    bool? isBusy,
    String? message,
    bool clearMessage = false,
    bool? integrityPassed,
  }) =>
      DeveloperToolsState(
        snapshot: snapshot ?? this.snapshot,
        isBusy: isBusy ?? this.isBusy,
        message: clearMessage ? null : message ?? this.message,
        integrityPassed: integrityPassed ?? this.integrityPassed,
      );
}

class DeveloperToolsController extends Notifier<DeveloperToolsState> {
  @override
  DeveloperToolsState build() => const DeveloperToolsState();

  Future<void> refresh() async {
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      state = state.copyWith(
        snapshot: await ref
            .read(developerToolsServiceProvider)
            .readDatabaseSnapshot(),
        isBusy: false,
      );
    } catch (error, stackTrace) {
      await _recordFailure('Read database information', error, stackTrace);
    }
  }

  Future<void> runIntegrityCheck() async {
    await _run('Run database integrity check', () async {
      final bool passed =
          await ref.read(developerToolsServiceProvider).runIntegrityCheck();
      state = state.copyWith(
        integrityPassed: passed,
        message: passed
            ? 'Database integrity check passed.'
            : 'Database integrity check failed. See the application log.',
      );
    });
  }

  Future<void> createBackup() async {
    await _run('Create database backup', () async {
      final backup =
          await ref.read(developerToolsServiceProvider).createDatabaseBackup();
      state =
          state.copyWith(message: 'Backup created: ${backup.absolute.path}');
    });
  }

  Future<void> resetDevelopmentData() async {
    if (!kDebugMode) {
      state =
          state.copyWith(message: 'Reset is available only in Debug builds.');
      return;
    }
    await _run('Reset development data', () async {
      await ref.read(developerToolsServiceProvider).resetDevelopmentData();
      await refresh();
      state = state.copyWith(message: 'Local development Worlds were reset.');
    });
  }

  Future<void> openDataDirectory() =>
      _open(ref.read(appPathsProvider).dataDirectory);
  Future<void> openLogDirectory() =>
      _open(ref.read(appPathsProvider).logDirectory);

  Future<void> _open(Directory directory) async {
    await _run('Open local folder', () async {
      await DesktopDirectoryOpener().open(directory);
      state = state.copyWith(message: 'Opened ${directory.absolute.path}');
    });
  }

  Future<void> _run(String operation, Future<void> Function() action) async {
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      await action();
      state = state.copyWith(isBusy: false);
    } catch (error, stackTrace) {
      await _recordFailure(operation, error, stackTrace);
    }
  }

  Future<void> _recordFailure(
      String operation, Object error, StackTrace stackTrace) async {
    await ref
        .read(appFileLoggerProvider)
        .error('$operation failed', error, stackTrace);
    state = state.copyWith(
      isBusy: false,
      message: '$operation failed. See the application log for details.',
    );
  }
}

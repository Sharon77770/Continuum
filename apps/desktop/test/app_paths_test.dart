import 'dart:io';

import 'package:continuum_desktop/core/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('separates Debug data while keeping Profile and Release paths stable',
      () {
    final AppPaths debugPaths = AppPaths.resolve(
      operatingSystem: 'windows',
      environment: <String, String>{
        'APPDATA': r'C:\Users\writer\AppData\Roaming',
      },
      homeDirectory: r'C:\Users\writer',
      buildMode: 'Debug',
    );
    final AppPaths releasePaths = AppPaths.resolve(
      operatingSystem: 'windows',
      environment: <String, String>{
        'APPDATA': r'C:\Users\writer\AppData\Roaming',
      },
      homeDirectory: r'C:\Users\writer',
      buildMode: 'Release',
    );
    final AppPaths profilePaths = AppPaths.resolve(
      operatingSystem: 'windows',
      environment: <String, String>{
        'APPDATA': r'C:\Users\writer\AppData\Roaming',
      },
      homeDirectory: r'C:\Users\writer',
      buildMode: 'Profile',
    );

    expect(debugPaths.databaseFile.path,
        r'C:\Users\writer\AppData\Roaming\Continuum-Dev\continuum.sqlite3');
    expect(releasePaths.dataDirectory.path, profilePaths.dataDirectory.path);
    expect(releasePaths.databaseFile.path,
        r'C:\Users\writer\AppData\Roaming\Continuum\continuum.sqlite3');
    expect(debugPaths.logDirectory.path,
        r'C:\Users\writer\AppData\Roaming\Continuum-Dev\logs');
  });

  test('initializes storage folders under an isolated temporary directory',
      () async {
    final Directory temporaryDirectory =
        await Directory.systemTemp.createTemp('continuum-paths-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final AppPaths paths = AppPaths(dataDirectory: temporaryDirectory);

    await paths.initialize();

    expect(await paths.dataDirectory.exists(), isTrue);
    expect(await paths.logDirectory.exists(), isTrue);
    expect(await paths.backupDirectory.exists(), isTrue);
    expect(await paths.tempDirectory.exists(), isTrue);
    expect(await paths.databaseFile.exists(), isFalse);
  });
}

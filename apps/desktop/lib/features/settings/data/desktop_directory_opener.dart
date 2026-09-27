import 'dart:io';

/// Opens a local directory with the user's native file manager.
class DesktopDirectoryOpener {
  Future<void> open(Directory directory) async {
    await directory.create(recursive: true);
    final List<String> command = switch (Platform.operatingSystem) {
      'windows' => <String>['explorer.exe', directory.absolute.path],
      'macos' => <String>['open', directory.absolute.path],
      _ => <String>['xdg-open', directory.absolute.path],
    };
    await Process.start(command.first, command.skip(1).toList(),
        mode: ProcessStartMode.detached);
  }
}

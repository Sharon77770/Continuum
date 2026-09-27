import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';
import 'package:world_format/world_format.dart';

import '../domain/scenario_file_repository.dart';

final scenarioFileRepositoryProvider = Provider<ScenarioFileRepository>(
    (Ref ref) => const JsonScenarioFileRepository());

/// Uses native file selection for the versioned JSON scenario format.
class JsonScenarioFileRepository implements ScenarioFileRepository {
  const JsonScenarioFileRepository();

  static const XTypeGroup _scenarioType = XTypeGroup(
    label: 'Continuum scenario',
    extensions: <String>['json'],
  );

  @override
  Future<World?> importScenario() async {
    final XFile? selected =
        await openFile(acceptedTypeGroups: const <XTypeGroup>[_scenarioType]);
    if (selected == null) return null;
    final String content = await File(selected.path).readAsString();
    return const ScenarioPackCodec().decode(content);
  }

  @override
  Future<bool> exportScenario(World world) async {
    final FileSaveLocation? destination = await getSaveLocation(
      suggestedName: '${_safeFileName(world.name)}.json',
      acceptedTypeGroups: const <XTypeGroup>[_scenarioType],
    );
    if (destination == null) return false;
    final String destinationPath = destination.path.toLowerCase().endsWith('.json')
        ? destination.path
        : '${destination.path}.json';
    await File(destinationPath).writeAsString(
      const ScenarioPackCodec().encode(world),
      encoding: utf8,
      flush: true,
    );
    return true;
  }

  String _safeFileName(String name) {
    final String safe = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return safe.isEmpty ? 'scenario' : safe;
  }
}

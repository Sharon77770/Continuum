import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';

import '../../../app/app_strings.dart';
import '../../../app/navigation.dart';
import '../../../app/theme.dart';
import '../../../core/app_paths.dart';
import '../../../core/developer_tools_providers.dart';
import '../../../core/runtime_environment.dart';
import '../../../state/locale_controller.dart';
import '../../../state/workspace_controller.dart';
import '../application/developer_tools_controller.dart';
import '../data/database_snapshot.dart';
import '../../novel/application/novel_controller.dart';
import '../../novel/data/llm_provider.dart';
import '../../novel/domain/language_model_settings.dart';
import '../../models/application/model_manager_controller.dart';
import '../../models/domain/model_catalog.dart';

/// Presents application preferences and local developer diagnostics.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const List<Locale> _supportedLocales = <Locale>[
    Locale('ko'),
    Locale('en'),
    Locale('zh'),
    Locale('ja'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(developerToolsControllerProvider.notifier).refresh();
      ref.read(novelControllerProvider.notifier).loadSettings();
      ref.read(modelManagerControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Locale locale = ref.watch(localeProvider);
    final AppStrings strings = AppStrings(locale);
    final SettingsReturnDestination returnDestination =
        ref.watch(settingsReturnProvider);
    final AppPaths paths = ref.watch(appPathsProvider);
    final RuntimeEnvironmentInfo environment =
        ref.watch(runtimeEnvironmentProvider);
    final DeveloperToolsState developerState =
        ref.watch(developerToolsControllerProvider);
    final NovelState novelState = ref.watch(novelControllerProvider);
    final WorkspaceState workspace = ref.watch(workspaceProvider);
    final ModelManagerState models = ref.watch(modelManagerControllerProvider);
    final World? currentWorld = workspace.currentWorld;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: strings.text('return_library'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => ref.read(navigationProvider.notifier).goTo(
                switch (returnDestination) {
                  SettingsReturnDestination.library => AppDestination.library,
                  SettingsReturnDestination.studio => AppDestination.studio,
                  SettingsReturnDestination.player => AppDestination.player,
                  SettingsReturnDestination.createWorld =>
                    AppDestination.createWorld,
                },
              ),
        ),
        title: Text(strings.text('settings')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(32),
            children: <Widget>[
              Text(strings.text('language'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(strings.text('language_description'),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 20),
              RadioGroup<String>(
                groupValue: locale.languageCode,
                onChanged: (String? value) {
                  if (value != null) {
                    _saveLanguagePreference(() => ref
                        .read(localeProvider.notifier)
                        .setLanguage(Locale(value)));
                  }
                },
                child: Column(
                  children: <Widget>[
                    for (final Locale option in _supportedLocales)
                      RadioListTile<String>(
                        value: option.languageCode,
                        activeColor: ContinuumTheme.accent,
                        title:
                            Text(AppStrings.languageName(option.languageCode)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(strings.text('game_language'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(strings.text('game_language_description'),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: ref.watch(gameLanguageProvider),
                onChanged: (String? value) {
                  if (value != null) {
                    _saveLanguagePreference(() => ref
                        .read(gameLanguageProvider.notifier)
                        .setLanguage(value));
                  }
                },
                child: Column(
                  children: <Widget>[
                    for (final Locale option in _supportedLocales)
                      RadioListTile<String>(
                        value: option.languageCode,
                        activeColor: ContinuumTheme.accent,
                        title:
                            Text(AppStrings.languageName(option.languageCode)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: strings.text('models'),
                children: <Widget>[
                  Text(strings.text('models_description')),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => ref
                          .read(navigationProvider.notifier)
                          .goTo(AppDestination.models),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(strings.text('models')),
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(strings.text('advanced_custom_provider')),
                subtitle: Text(strings.text('for_developers')),
                children: <Widget>[const _LanguageModelSettingsSection()],
              ),
              const SizedBox(height: 32),
              Text(strings.text('developer'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(strings.text('developer_description'),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 20),
              _SettingsSection(
                title: strings.text('environment'),
                children: <Widget>[
                  _InfoRow(strings.text('app_version'), environment.appVersion),
                  _InfoRow(strings.text('build_mode'), environment.buildMode),
                  _InfoRow(strings.text('platform'), environment.platform),
                  _InfoRow(
                      strings.text('dart_version'), environment.dartVersion),
                ],
              ),
              _SettingsSection(
                title: strings.text('storage'),
                children: <Widget>[
                  _PathRow(strings.text('data_directory'),
                      paths.dataDirectory.absolute.path),
                  _PathRow(strings.text('database_path'),
                      paths.databaseFile.absolute.path),
                  _PathRow(strings.text('log_directory'),
                      paths.logDirectory.absolute.path),
                  _PathRow(
                      'Active log file',
                      ref
                          .read(appFileLoggerProvider)
                          .currentLogFile
                          .absolute
                          .path),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: developerState.isBusy
                            ? null
                            : ref
                                .read(developerToolsControllerProvider.notifier)
                                .openDataDirectory,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(strings.text('open_data_directory')),
                      ),
                      OutlinedButton.icon(
                        onPressed: developerState.isBusy
                            ? null
                            : ref
                                .read(developerToolsControllerProvider.notifier)
                                .openLogDirectory,
                        icon: const Icon(Icons.article_outlined),
                        label: Text(strings.text('open_log_directory')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(
                              text: paths.databaseFile.absolute.path));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text(strings.text('copy_database_path'))),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: Text(strings.text('copy_database_path')),
                      ),
                    ],
                  ),
                ],
              ),
              _SettingsSection(
                title: strings.text('database'),
                children: <Widget>[
                  if (developerState.snapshot
                      case final DatabaseSnapshot snapshot) ...<Widget>[
                    _InfoRow(strings.text('database_size'),
                        _formatBytes(snapshot.databaseSizeBytes)),
                    _InfoRow(strings.text('schema_version'),
                        '${snapshot.schemaVersion}'),
                    _InfoRow(
                        strings.text('world_count'), '${snapshot.worldCount}'),
                    _InfoRow(strings.text('character_count'),
                        '${snapshot.characterCount}'),
                    _InfoRow(
                        strings.text('lore_count'), '${snapshot.loreCount}'),
                    _InfoRow(strings.text('location_count'),
                        '${snapshot.locationCount}'),
                  ] else if (developerState.isBusy)
                    const LinearProgressIndicator()
                  else
                    Text(strings.text('db_info_unavailable')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: developerState.isBusy
                            ? null
                            : ref
                                .read(developerToolsControllerProvider.notifier)
                                .runIntegrityCheck,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(strings.text('integrity_check')),
                      ),
                      OutlinedButton.icon(
                        onPressed: developerState.isBusy
                            ? null
                            : ref
                                .read(developerToolsControllerProvider.notifier)
                                .createBackup,
                        icon: const Icon(Icons.backup_outlined),
                        label: Text(strings.text('backup_database')),
                      ),
                    ],
                  ),
                  if (developerState.integrityPassed != null)
                    Text(
                      developerState.integrityPassed!
                          ? strings.text('pass')
                          : strings.text('failure_see_log'),
                      style: TextStyle(
                        color: developerState.integrityPassed!
                            ? ContinuumTheme.accent
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (developerState.message != null)
                    SelectableText(strings.phrase(developerState.message!)),
                ],
              ),
              _SettingsSection(
                title: strings.text('model_runtime'),
                children: <Widget>[
                  _InfoRow(
                    strings.text('status'),
                    switch (models.runtime.status) {
                      RuntimeStatus.notInstalled =>
                        strings.text('not_installed'),
                      RuntimeStatus.stopped => strings.text('stopped'),
                      RuntimeStatus.starting => strings.text('loading'),
                      RuntimeStatus.ready => strings.text('running'),
                      RuntimeStatus.failed => strings.text('unavailable'),
                    },
                  ),
                  if (models.runtime.version != null)
                    _InfoRow(strings.text('runtime_version'),
                        models.runtime.version!),
                  if (models.selection != null)
                    _InfoRow(strings.text('story_model'),
                        models.selection!.displayName),
                  if (models.device != null)
                    _InfoRow(strings.text('system_memory'),
                        _formatBytes(models.device!.systemMemoryBytes)),
                  if (models.runtime.processId != null)
                    _InfoRow(
                        strings.text('pid'), '${models.runtime.processId}'),
                  if (models.runtime.endpoint != null)
                    _InfoRow(strings.text('internal_endpoint'),
                        models.runtime.endpoint.toString()),
                  if (models.runtime.logPath != null)
                    _PathRow(
                        strings.text('runtime_log'), models.runtime.logPath!),
                  if (models.runtime.message != null)
                    Text(strings.phrase(models.runtime.message!)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: models.runtime.status ==
                                RuntimeStatus.starting
                            ? null
                            : ref
                                .read(modelManagerControllerProvider.notifier)
                                .restartRuntime,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(strings.text('restart_runtime')),
                      ),
                      OutlinedButton.icon(
                        onPressed: ref
                            .read(modelManagerControllerProvider.notifier)
                            .openModelDirectory,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(strings.text('open_model_directory')),
                      ),
                      OutlinedButton.icon(
                        onPressed: ref
                            .read(modelManagerControllerProvider.notifier)
                            .openRuntimeLog,
                        icon: const Icon(Icons.article_outlined),
                        label: Text(strings.text('view_runtime_log')),
                      ),
                    ],
                  ),
                ],
              ),
              _SettingsSection(
                title: strings.text('language_model_diagnostics'),
                children: <Widget>[
                  _InfoRow(strings.text('provider'),
                      strings.text('openai_compatible')),
                  _InfoRow(
                      strings.text('endpoint'), novelState.settings.baseUrl),
                  _InfoRow(
                      strings.text('model'),
                      novelState.settings.model.isEmpty
                          ? strings.text('not_selected')
                          : novelState.settings.model),
                  _InfoRow(
                      strings.text('status'),
                      novelState.isGenerating
                          ? strings.text('generating')
                          : strings.phrase(novelState.providerStatus)),
                  if (novelState.lastRequestDuration != null)
                    _InfoRow(strings.text('last_request_duration'),
                        '${novelState.lastRequestDuration!.inMilliseconds} ms'),
                  if (novelState.context != null)
                    _InfoRow(strings.text('last_input_estimate'),
                        '${novelState.context!.estimatedTokens} tokens'),
                  if (novelState.lastOutputCharacters != null)
                    _InfoRow(strings.text('last_output_size'),
                        '${novelState.lastOutputCharacters} characters'),
                  if (kDebugMode && novelState.context != null)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(strings.text('prompt_inspector')),
                      children: <Widget>[
                        for (final MapEntry<String, String> section
                            in novelState.context!.sections.entries)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(strings.phrase(section.key)),
                            children: <Widget>[SelectableText(section.value)],
                          ),
                      ],
                    ),
                ],
              ),
              _SettingsSection(
                title: strings.text('inspection'),
                children: <Widget>[
                  if (currentWorld == null)
                    Text(strings.text('no_world_selected'))
                  else
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                          '${strings.text('inspect_current_world')} · ${currentWorld.name}'),
                      children: <Widget>[
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 360),
                          padding: const EdgeInsets.all(12),
                          color: ContinuumTheme.background,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              const JsonEncoder.withIndent('  ')
                                  .convert(_worldJson(currentWorld)),
                              style: const TextStyle(
                                  fontFamily: 'Consolas', fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (kDebugMode)
                _SettingsSection(
                  title: strings.text('danger_zone'),
                  children: <Widget>[
                    Text(strings.text('reset_description')),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: developerState.isBusy ? null : _confirmReset,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(strings.text('reset_development_data')),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveLanguagePreference(Future<void> Function() save) {
    unawaited(save().catchError((Object _) {
      if (!mounted) return;
      final AppStrings strings = AppStrings(ref.read(localeProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.text('language_save_failed'))),
      );
    }));
  }

  Future<void> _confirmReset() async {
    final AppStrings strings = AppStrings(ref.read(localeProvider));
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(strings.text('reset_title')),
            content: Text(strings.text('reset_description')),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.text('reset_confirm')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await ref.read(workspaceProvider.notifier).flushPendingChanges();
    await ref
        .read(developerToolsControllerProvider.notifier)
        .resetDevelopmentData();
    await ref.read(workspaceProvider.notifier).reloadWorlds();
  }
}

class _LanguageModelSettingsSection extends ConsumerStatefulWidget {
  const _LanguageModelSettingsSection();
  @override
  ConsumerState<_LanguageModelSettingsSection> createState() =>
      _LanguageModelSettingsSectionState();
}

class _LanguageModelSettingsSectionState
    extends ConsumerState<_LanguageModelSettingsSection> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _temperature = TextEditingController();
  final TextEditingController _contextLimit = TextEditingController();
  String? _message;
  bool _busy = false;
  bool _loaded = false;
  bool _dirty = false;
  List<String> _models = <String>[];

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    _temperature.dispose();
    _contextLimit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings(ref.watch(localeProvider));
    final NovelState novel = ref.watch(novelControllerProvider);
    ref.listen<LanguageModelSettings>(
      novelControllerProvider.select((NovelState value) => value.settings),
      (LanguageModelSettings? previous, LanguageModelSettings next) {
        if (!_dirty) _applySettings(next);
      },
    );
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final LanguageModelSettings settings =
            ref.read(novelControllerProvider).settings;
        _applySettings(settings);
      });
    }
    return _SettingsSection(
      title: strings.text('language_model_openai'),
      children: <Widget>[
        TextField(
            controller: _url,
            onChanged: (_) => _dirty = true,
            decoration: InputDecoration(labelText: strings.text('base_url'))),
        TextField(
            controller: _model,
            onChanged: (_) => _dirty = true,
            decoration: InputDecoration(labelText: strings.text('model'))),
        TextField(
            controller: _key,
            obscureText: true,
            decoration:
                InputDecoration(labelText: strings.text('api_key_optional'))),
        Row(children: <Widget>[
          Expanded(
              child: TextField(
                  controller: _temperature,
                  onChanged: (_) => _dirty = true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(labelText: strings.text('temperature')))),
          const SizedBox(width: 14),
          Expanded(
              child: TextField(
                  controller: _contextLimit,
                  onChanged: (_) => _dirty = true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: strings.text('context_limit')))),
        ]),
        if (_models.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _models.contains(_model.text) ? _model.text : null,
            decoration:
                InputDecoration(labelText: strings.text('available_models')),
            items: <DropdownMenuItem<String>>[
              for (final String model in _models)
                DropdownMenuItem<String>(value: model, child: Text(model)),
            ],
            onChanged: (String? model) {
              if (model != null) {
                setState(() {
                  _dirty = true;
                  _model.text = model;
                });
              }
            },
          ),
        Wrap(spacing: 8, children: <Widget>[
          FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(strings.text('save_settings'))),
          OutlinedButton(
              onPressed: _busy ? null : _test,
              child: Text(strings.text('test_connection'))),
          OutlinedButton(
              onPressed: _busy ? null : _loadModels,
              child: Text(strings.text('load_models'))),
          TextButton(
            onPressed: () {
              ref.read(novelControllerProvider.notifier).clearApiKey();
              _key.clear();
              setState(() => _message = strings.text('key_removed'));
            },
            child: Text(strings.text('clear_session_key')),
          ),
        ]),
        if (_message != null) Text(_message!),
        if (novel.context != null)
          Text(
              '${strings.text('prompt_estimate')}: ${novel.context!.estimatedTokens} ${strings.text('prompt_estimate_detail')}'),
      ],
    );
  }

  LanguageModelSettings _settings() => LanguageModelSettings(
        baseUrl: _url.text.trim(),
        model: _model.text.trim(),
        temperature: double.tryParse(_temperature.text) ?? 0.8,
        contextLimit: int.tryParse(_contextLimit.text) ?? 4096,
      );

  void _applySettings(LanguageModelSettings settings) {
    _url.text = settings.baseUrl;
    _model.text = settings.model;
    _temperature.text = settings.temperature.toString();
    _contextLimit.text = settings.contextLimit.toString();
  }

  Future<void> _save() async {
    try {
      final LanguageModelSettings value = _settings();
      if (value.baseUrl.isEmpty ||
          value.contextLimit < 512 ||
          value.temperature < 0 ||
          value.temperature > 2) {
        throw const FormatException('invalid model settings');
      }
      await ref
          .read(novelControllerProvider.notifier)
          .saveSettings(value, apiKey: _key.text);
      _key.clear();
      if (mounted) {
        setState(() => _message =
            AppStrings(ref.read(localeProvider)).text('settings_saved_secret'));
      }
    } catch (error) {
      if (mounted) setState(() => _message = _friendlyError(error));
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(novelControllerProvider.notifier)
          .saveSettings(_settings(), apiKey: _key.text);
      _key.clear();
      final Stopwatch timer = Stopwatch()..start();
      await ref.read(novelControllerProvider.notifier).testConnection();
      if (mounted) {
        final String connected =
            AppStrings(ref.read(localeProvider)).text('connected');
        setState(() => _message =
            '$connected · ${ref.read(novelControllerProvider).settings.model} · ${timer.elapsedMilliseconds} ms');
      }
    } catch (error) {
      if (mounted) setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadModels() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(novelControllerProvider.notifier)
          .saveSettings(_settings(), apiKey: _key.text);
      _key.clear();
      final List<String> models =
          await ref.read(novelControllerProvider.notifier).listModels();
      if (mounted) {
        setState(() => _models = models);
        setState(() => _message = models.isEmpty
            ? AppStrings(ref.read(localeProvider))
                .text('model_list_unavailable')
            : models.join(' · '));
      }
    } catch (error) {
      if (mounted) setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final AppStrings strings = AppStrings(ref.read(localeProvider));
    if (error is FormatException) return strings.text('invalid_model_settings');
    if (error is LlmException) return strings.phrase(error.message);
    return strings.text('endpoint_unreachable');
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ContinuumTheme.surface,
          border: Border.all(color: const Color(0xFF30312C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 14),
            ...children.map((Widget child) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: child,
                )),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
              child:
                  Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 16),
          Flexible(child: SelectableText(value, textAlign: TextAlign.right)),
        ],
      );
}

class _PathRow extends StatelessWidget {
  const _PathRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          SelectableText(value,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
        ],
      );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Map<String, Object?> _worldJson(World world) => <String, Object?>{
      'id': world.id,
      'name': world.name,
      'description': world.description,
      'genre': world.genre,
      'tone': world.tone,
      'rules': world.rules,
      'lore': <Map<String, Object?>>[
        for (final LoreEntry entry in world.loreEntries)
          <String, Object?>{
            'id': entry.id,
            'title': entry.title,
            'category': entry.category,
            'content': entry.content,
          },
      ],
      'characters': <Map<String, Object?>>[
        for (final StoryCharacter character in world.characters)
          <String, Object?>{
            'id': character.id,
            'name': character.name,
            'role': character.role,
            'description': character.description,
            'appearance': character.appearance,
            'personality': character.personality,
            'background': character.background,
            'publicInformation': character.publicInformation,
            'secretInformation': character.secretInformation,
          },
      ],
      'locations': <Map<String, Object?>>[
        for (final StoryLocation location in world.locations)
          <String, Object?>{
            'id': location.id,
            'name': location.name,
            'description': location.description,
            'parentId': location.parentId,
          },
      ],
      'createdAt': world.createdAt?.toIso8601String(),
      'updatedAt': world.updatedAt?.toIso8601String(),
    };

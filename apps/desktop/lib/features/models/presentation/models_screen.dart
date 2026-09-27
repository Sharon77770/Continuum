import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_strings.dart';
import '../../../app/navigation.dart';
import '../../../app/theme.dart';
import '../../../app/ui_phrase.dart';
import '../../../state/locale_controller.dart';
import '../../novel/application/novel_controller.dart';
import '../../novel/domain/language_model_settings.dart';
import '../application/model_manager_controller.dart';
import '../data/hugging_face_catalog.dart';
import '../domain/model_catalog.dart';

class ModelsScreen extends ConsumerStatefulWidget {
  const ModelsScreen({super.key});

  @override
  ConsumerState<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends ConsumerState<ModelsScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _geminiKey = TextEditingController();
  final TextEditingController _customUrl = TextEditingController();
  final TextEditingController _customModel = TextEditingController();
  final TextEditingController _customKey = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref
          .read(modelManagerControllerProvider.notifier)
          .load(refreshCloudModels: true);
      await ref.read(novelControllerProvider.notifier).loadSettings();
      if (!mounted) return;
      final LanguageModelSettings settings =
          ref.read(novelControllerProvider).settings;
      _customUrl.text = settings.baseUrl;
      _customModel.text = settings.model;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _apiKey.dispose();
    _geminiKey.dispose();
    _customUrl.dispose();
    _customModel.dispose();
    _customKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ModelManagerState state = ref.watch(modelManagerControllerProvider);
    final AppStrings strings = AppStrings(ref.watch(localeProvider));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => ref
              .read(navigationProvider.notifier)
              .goTo(AppDestination.settings),
          icon: const Icon(Icons.arrow_back),
          tooltip: strings.text('settings'),
        ),
        title: Text(strings.text('models')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(30, 18, 30, 48),
            children: [
              Text(strings.text('models_description'),
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 18),
              if (state.device != null) _DeviceSummary(device: state.device!),
              if (state.isLoading && state.device == null)
                const LinearProgressIndicator(),
              if (state.errorMessage != null)
                _StatusBanner(
                    message: strings.phrase(state.errorMessage!),
                    isError: true),
              if (state.infoMessage != null)
                _StatusBanner(message: strings.phrase(state.infoMessage!)),
              _SectionHeader(
                  title: strings.text('recommended'),
                  subtitle: strings.text('recommended_models_description')),
              for (final ModelRecommendation recommendation
                  in state.recommendations)
                _RecommendationCard(
                  recommendation: recommendation,
                  installed: state.installed.any((InstalledModel model) =>
                      model.id == recommendation.model.id),
                  progress: state.downloadingModelId == recommendation.model.id
                      ? state.downloadProgress
                      : null,
                  downloading:
                      state.downloadingModelId == recommendation.model.id,
                  onDownload: () => ref
                      .read(modelManagerControllerProvider.notifier)
                      .download(recommendation.model),
                  onCancel: () => ref
                      .read(modelManagerControllerProvider.notifier)
                      .cancelDownload(),
                ),
              _SectionHeader(
                  title: strings.text('on_this_device'),
                  subtitle: strings.text('downloaded_imported_models')),
              _SectionHeader(
                  title: strings.text('local_resource_usage'),
                  subtitle: strings.text('local_resource_usage_description')),
              DropdownButtonFormField<LocalResourceProfile>(
                initialValue: state.localResourceProfile,
                decoration:
                    InputDecoration(labelText: strings.text('resource_level')),
                items: [
                  for (final LocalResourceProfile profile
                      in LocalResourceProfile.values)
                    DropdownMenuItem(
                      value: profile,
                      child: Text(strings.text(switch (profile) {
                        LocalResourceProfile.conservative =>
                          'resource_conservative',
                        LocalResourceProfile.balanced => 'resource_balanced',
                        LocalResourceProfile.performance =>
                          'resource_performance',
                      })),
                    ),
                ],
                onChanged: (LocalResourceProfile? profile) {
                  if (profile != null) {
                    ref
                        .read(modelManagerControllerProvider.notifier)
                        .setLocalResourceProfile(profile);
                  }
                },
              ),
              const SizedBox(height: 6),
              Text(strings.text(switch (state.localResourceProfile) {
                LocalResourceProfile.conservative =>
                  'resource_conservative_detail',
                LocalResourceProfile.balanced => 'resource_balanced_detail',
                LocalResourceProfile.performance =>
                  'resource_performance_detail',
              })),
              if (state.installed.isEmpty)
                _EmptyNotice(text: strings.text('no_models_yet')),
              for (final InstalledModel model in state.installed)
                _InstalledModelCard(
                  model: model,
                  selected: state.selection?.kind == ModelProviderKind.local &&
                      state.selection?.modelId == model.id,
                  runtime: state.runtime,
                  onRetry: () => ref
                      .read(modelManagerControllerProvider.notifier)
                      .startSelectedModel(),
                  onUse: () => ref
                      .read(modelManagerControllerProvider.notifier)
                      .useLocalModel(model),
                  onRemove: () => _removeModel(model),
                ),
              _SectionHeader(
                  title: strings.text('discover'),
                  subtitle: strings.text('discover_description')),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _discover,
                      decoration: InputDecoration(
                          hintText: strings.text('search_models')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: state.isSearching
                        ? null
                        : () => _discover(_search.text),
                    child: state.isSearching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(strings.text('search')),
                  ),
                ],
              ),
              for (final DiscoveredModel model in state.discovered)
                _DiscoveredModelCard(
                  model: model,
                  downloading: state.downloadingModelId
                          ?.startsWith('${model.repository}::') ??
                      false,
                  progress: state.downloadingModelId
                              ?.startsWith('${model.repository}::') ??
                          false
                      ? state.downloadProgress
                      : null,
                  onCancel: () => ref
                      .read(modelManagerControllerProvider.notifier)
                      .cancelDownload(),
                  onDownload: (ModelDescriptor descriptor) => ref
                      .read(modelManagerControllerProvider.notifier)
                      .download(descriptor),
                ),
              _SectionHeader(
                  title: strings.text('cloud'),
                  subtitle: strings.text('cloud_description')),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration:
                    InputDecoration(labelText: strings.text('openai_key')),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: state.isLoading
                      ? null
                      : () async {
                          await ref
                              .read(modelManagerControllerProvider.notifier)
                              .connectOpenAi(_apiKey.text);
                          if (mounted &&
                              ref
                                      .read(modelManagerControllerProvider)
                                      .errorMessage ==
                                  null) {
                            _apiKey.clear();
                          }
                        },
                  child: Text(strings.text('connect_openai')),
                ),
              ),
              if (state.cloudModels.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: state.cloudProvider == state.selection?.kind
                      ? state.selection?.modelId
                      : null,
                  decoration:
                      InputDecoration(labelText: strings.text('story_model')),
                  items: [
                    for (final String model in state.cloudModels)
                      DropdownMenuItem(value: model, child: Text(model)),
                  ],
                  onChanged: (String? model) {
                    if (model != null) {
                      ref
                          .read(modelManagerControllerProvider.notifier)
                          .selectCloudModel(model,
                              provider: state.cloudProvider ??
                                  ModelProviderKind.openAi);
                    }
                  },
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _geminiKey,
                obscureText: true,
                decoration:
                    InputDecoration(labelText: strings.text('gemini_key')),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: state.isLoading
                      ? null
                      : () async {
                          await ref
                              .read(modelManagerControllerProvider.notifier)
                              .connectGemini(_geminiKey.text);
                          if (mounted &&
                              ref
                                      .read(modelManagerControllerProvider)
                                      .errorMessage ==
                                  null) {
                            _geminiKey.clear();
                          }
                        },
                  child: Text(strings.text('connect_gemini')),
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(strings.text('advanced')),
                subtitle: Text(strings.text('custom_provider_description')),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: ref
                          .read(modelManagerControllerProvider.notifier)
                          .importLocalModel,
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(strings.text('import_local_model')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customUrl,
                    decoration: InputDecoration(
                        labelText: strings.text('custom_provider_url')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customModel,
                    decoration:
                        InputDecoration(labelText: strings.text('model')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customKey,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: strings.text('api_key_simple')),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: _saveCustomProvider,
                      child: Text(strings.text('save_use_custom_provider')),
                    ),
                  ),
                  if (state.selection?.kind == ModelProviderKind.local)
                    for (final InstalledModel model in state.installed.where(
                        (InstalledModel item) =>
                            item.id == state.selection!.modelId))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.text('advanced_model_details')),
                        subtitle: Text(model.fileName),
                        trailing: Text(model.license),
                      ),
                ],
              ),
              if (state.selection != null) ...[
                const SizedBox(height: 8),
                _CurrentSelection(selection: state.selection!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _discover(String query) {
    if (query.trim().isNotEmpty) {
      ref.read(modelManagerControllerProvider.notifier).discover(query);
    }
  }

  Future<void> _saveCustomProvider() async {
    final LanguageModelSettings settings = LanguageModelSettings(
      baseUrl: _customUrl.text.trim(),
      model: _customModel.text.trim(),
      temperature: ref.read(novelControllerProvider).settings.temperature,
      contextLimit: ref.read(novelControllerProvider).settings.contextLimit,
    );
    final novel = ref.read(novelControllerProvider.notifier);
    await novel.saveSettings(settings, apiKey: _customKey.text);
    _customKey.clear();
    await ref
        .read(modelManagerControllerProvider.notifier)
        .selectCustomProvider(settings);
  }

  Future<void> _removeModel(InstalledModel model) async {
    final AppStrings strings = AppStrings(ref.read(localeProvider));
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(strings
                .text('remove_model_confirm')
                .replaceAll('{name}', model.displayName)),
            content: Text(strings.text('model_file_delete_details')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings.text('cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(strings.text('remove'))),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await ref
          .read(modelManagerControllerProvider.notifier)
          .removeModel(model);
    }
  }
}

class _DeviceSummary extends StatelessWidget {
  const _DeviceSummary({required this.device});
  final DeviceCapabilities device;

  @override
  Widget build(BuildContext context) => Card(
        color: ContinuumTheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _Fact(
                  label: uiPhrase(context, 'System memory'),
                  value: _formatBytes(device.systemMemoryBytes)),
              _Fact(
                  label: uiPhrase(context, 'CPU'),
                  value: device.cpuArchitecture),
              _Fact(
                label: uiPhrase(context, 'Graphics'),
                value: device.gpuAvailable
                    ? '${device.gpuVendor ?? 'GPU'} · ${device.gpuName ?? 'Available'}'
                    : uiPhrase(context, 'Integrated or unavailable'),
              ),
              if (device.availableVramBytes != null)
                _Fact(
                    label: uiPhrase(context, 'Available video memory'),
                    value: _formatBytes(device.availableVramBytes!)),
              _Fact(
                  label: uiPhrase(context, 'Free storage'),
                  value: _formatBytes(device.availableDiskBytes)),
            ],
          ),
        ),
      );
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.installed,
    required this.progress,
    required this.downloading,
    required this.onDownload,
    required this.onCancel,
  });
  final ModelRecommendation recommendation;
  final bool installed;
  final ModelDownloadProgress? progress;
  final bool downloading;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ModelDescriptor model = recommendation.model;
    return Card(
      color: ContinuumTheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(model.displayName,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              _Pill(label: uiPhrase(context, _quality(model.qualityClass))),
            ]),
            const SizedBox(height: 5),
            Text(model.description),
            const SizedBox(height: 8),
            Text('${_formatBytes(model.downloadSize)} · ${model.license}',
                style: Theme.of(context).textTheme.bodySmall),
            if (recommendation.fits)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(uiPhrase(context, 'Recommended for this device')),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(uiPhrase(context, 'May need more system memory')),
              ),
            if (downloading) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: progress?.fraction),
              const SizedBox(height: 6),
              Text(
                  '${_formatBytes(progress?.receivedBytes ?? 0)} / ${_formatBytes(progress?.totalBytes ?? model.downloadSize)}'),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: downloading
                  ? OutlinedButton(
                      onPressed: onCancel,
                      child: Text(uiPhrase(context, 'Cancel')))
                  : FilledButton(
                      onPressed: installed ? null : onDownload,
                      child: Text(uiPhrase(
                          context, installed ? 'Downloaded' : 'Download')),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstalledModelCard extends StatelessWidget {
  const _InstalledModelCard({
    required this.model,
    required this.selected,
    required this.runtime,
    required this.onRetry,
    required this.onUse,
    required this.onRemove,
  });
  final InstalledModel model;
  final bool selected;
  final RuntimeSnapshot runtime;
  final VoidCallback onRetry;
  final VoidCallback onUse;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        color: ContinuumTheme.surface,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: Text(model.displayName),
          subtitle: Text(
              '${uiPhrase(context, _quality(model.qualityClass))} · ${_formatBytes(model.sizeBytes)} · ${selected ? uiPhrase(context, _runtimeStatus(runtime)) : uiPhrase(context, 'Installed')}'),
          trailing: Wrap(
            spacing: 2,
            children: [
              if (!selected)
                TextButton(
                    onPressed: onUse, child: Text(uiPhrase(context, 'Use')))
              else if (runtime.status == RuntimeStatus.failed)
                TextButton(
                    onPressed: onRetry,
                    child: Text(uiPhrase(context, 'Try again')))
              else
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Text(uiPhrase(context, 'Currently Used')),
                ),
              IconButton(
                  tooltip: uiPhrase(context, 'Remove'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline)),
            ],
          ),
        ),
      );
}

class _DiscoveredModelCard extends StatefulWidget {
  const _DiscoveredModelCard({
    required this.model,
    required this.downloading,
    required this.progress,
    required this.onCancel,
    required this.onDownload,
  });
  final DiscoveredModel model;
  final bool downloading;
  final ModelDownloadProgress? progress;
  final VoidCallback onCancel;
  final ValueChanged<ModelDescriptor> onDownload;

  @override
  State<_DiscoveredModelCard> createState() => _DiscoveredModelCardState();
}

class _DiscoveredModelCardState extends State<_DiscoveredModelCard> {
  ModelQuality _quality = ModelQuality.balanced;

  @override
  Widget build(BuildContext context) {
    final DiscoveredModelFile file = widget.model.fileFor(_quality);
    final ModelDescriptor descriptor = file.descriptor(quality: _quality);
    return Card(
      color: ContinuumTheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(descriptor.displayName,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${_formatBytes(file.sizeBytes)} · ${file.license}'),
          if (widget.model.variants.length > 1) ...[
            const SizedBox(height: 8),
            Text(uiPhrase(context, 'Model Quality')),
            RadioGroup<ModelQuality>(
              groupValue: _quality,
              onChanged: (ModelQuality? value) {
                if (value != null) setState(() => _quality = value);
              },
              child: Column(children: [
                for (final (ModelQuality quality, String title, String detail)
                    in const [
                  (ModelQuality.fast, 'Smaller', 'Uses less memory'),
                  (
                    ModelQuality.balanced,
                    'Recommended',
                    'Best balance for this computer'
                  ),
                  (
                    ModelQuality.higherQuality,
                    'Higher Quality',
                    'Uses more memory'
                  ),
                ])
                  RadioListTile<ModelQuality>(
                    value: quality,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(uiPhrase(context, title)),
                    subtitle: Text(uiPhrase(context, detail)),
                  ),
              ]),
            ),
          ],
          if (widget.downloading) ...[
            LinearProgressIndicator(value: widget.progress?.fraction),
            const SizedBox(height: 4),
            Text(
                '${_formatBytes(widget.progress?.receivedBytes ?? 0)} / ${_formatBytes(widget.progress?.totalBytes ?? file.sizeBytes)}'),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(uiPhrase(context, 'Advanced details')),
            children: [
              ListTile(
                  title: Text(uiPhrase(context, 'File')),
                  subtitle: Text(file.file)),
              ListTile(
                  title: Text(uiPhrase(context, 'Quantization')),
                  subtitle: Text(
                      uiPhrase(context, file.quantization ?? 'Unspecified'))),
              ListTile(
                  title: Text(uiPhrase(context, 'Repository')),
                  subtitle: Text(file.repository)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: widget.downloading
                ? OutlinedButton(
                    onPressed: widget.onCancel,
                    child: Text(uiPhrase(context, 'Cancel')),
                  )
                : FilledButton(
                    onPressed: () => widget.onDownload(descriptor),
                    child: Text(uiPhrase(context, 'Download')),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _CurrentSelection extends StatelessWidget {
  const _CurrentSelection({required this.selection});
  final ModelSelection selection;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border:
              Border.all(color: ContinuumTheme.accent.withValues(alpha: .5)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_outline, color: ContinuumTheme.accent),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  '${uiPhrase(context, 'Story model')} · ${selection.displayName}')),
          _Pill(
              label: switch (selection.kind) {
            ModelProviderKind.local => uiPhrase(context, 'On This Device'),
            ModelProviderKind.openAi => uiPhrase(context, 'Cloud'),
            ModelProviderKind.gemini => 'Gemini',
            ModelProviderKind.custom => uiPhrase(context, 'Advanced'),
          }),
        ]),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF45453F)),
            borderRadius: BorderRadius.circular(18)),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value),
        ],
      );
}

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, this.isError = false});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message,
            style: TextStyle(
                color: isError
                    ? Theme.of(context).colorScheme.error
                    : ContinuumTheme.accent)),
      );
}

String _quality(ModelQuality quality) => switch (quality) {
      ModelQuality.fast => 'Fast',
      ModelQuality.balanced => 'Balanced',
      ModelQuality.higherQuality => 'Higher Quality',
    };

String _runtimeStatus(RuntimeSnapshot runtime) => switch (runtime.status) {
      RuntimeStatus.notInstalled => 'Runtime not installed',
      RuntimeStatus.stopped => 'Ready',
      RuntimeStatus.starting => 'Loading…',
      RuntimeStatus.ready => 'Ready',
      RuntimeStatus.failed => 'Unavailable',
    };

String _formatBytes(int bytes) {
  if (bytes <= 0) return 'Unknown';
  const List<String> units = ['B', 'KB', 'MB', 'GB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1000 && unit < units.length - 1) {
    size /= 1000;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
}

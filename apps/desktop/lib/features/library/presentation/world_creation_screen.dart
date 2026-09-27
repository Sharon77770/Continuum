import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation.dart';
import '../../../app/theme.dart';
import '../../../app/app_strings.dart';
import '../../../app/ui_phrase.dart';
import '../../../state/locale_controller.dart';
import '../../../state/workspace_controller.dart';
import '../../novel/application/novel_controller.dart';
import '../../models/application/model_manager_controller.dart';
import '../application/scenario_template_catalog.dart';

class WorldCreationScreen extends ConsumerStatefulWidget {
  const WorldCreationScreen({super.key});

  @override
  ConsumerState<WorldCreationScreen> createState() =>
      _WorldCreationScreenState();
}

class _WorldCreationScreenState extends ConsumerState<WorldCreationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final Set<String> _genres = {'Modern'};
  final Set<String> _tones = {'Serious'};
  final Set<String> _customGenres = <String>{};
  final Set<String> _customTones = <String>{};
  String? _selectedTemplateId;
  String? _error;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings(ref.watch(localeProvider));
    final WorkspaceState workspace = ref.watch(workspaceProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: _returnToLibrary,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: Text(strings.text('library').toUpperCase()),
                  ),
                  const SizedBox(height: 45),
                  Text(
                    strings.text('create_world'),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 20),
                  Text(strings.text('scenario_templates'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(strings.text('scenario_templates_hint'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 14),
                  for (final ScenarioTemplate template
                      in ScenarioTemplateCatalog.templates)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ScenarioTemplateTile(
                        template: template,
                        selected: _selectedTemplateId == template.id,
                        onTap: () => _selectTemplate(template),
                      ),
                    ),
                  const SizedBox(height: 38),
                  _FieldLabel(strings.text('world_name')),
                  const SizedBox(height: 9),
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: strings.text('give_world_name'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel(strings.text('description')),
                  const SizedBox(height: 9),
                  TextField(
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: strings.text('world_description_hint'),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _FieldLabel(strings.text('genre')),
                  const SizedBox(height: 12),
                  _ChoiceRow(
                    choices: [
                      'Modern',
                      'SF',
                      'Fantasy',
                      'Mystery',
                      ..._customGenres,
                    ],
                    selected: _genres,
                    onToggle: (value) =>
                        setState(() => _toggle(_genres, value)),
                    onAdd: (value) => setState(() {
                      _customGenres.add(value);
                      _genres.add(value);
                    }),
                  ),
                  const SizedBox(height: 23),
                  _FieldLabel(strings.text('tone')),
                  const SizedBox(height: 12),
                  _ChoiceRow(
                    choices: [
                      'Dark',
                      'Serious',
                      'Hopeful',
                      'Quiet',
                      ..._customTones,
                    ],
                    selected: _tones,
                    onToggle: (value) => setState(() => _toggle(_tones, value)),
                    onAdd: (value) => setState(() {
                      _customTones.add(value);
                      _tones.add(value);
                    }),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFE0A38C)),
                    ),
                  ],
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _returnToLibrary,
                        child: Text(strings.text('cancel')),
                      ),
                      const SizedBox(width: 15),
                      if (_selectedTemplateId != null) ...[
                        FilledButton.tonal(
                          onPressed: _isCreating ||
                                  workspace.loadStatus !=
                                      WorkspaceLoadStatus.ready
                              ? null
                              : () => _create(startPlaying: true),
                          child: Text(strings.text('create_and_play')),
                        ),
                        const SizedBox(width: 12),
                      ],
                      FilledButton(
                        onPressed: _isCreating ||
                                workspace.loadStatus !=
                                    WorkspaceLoadStatus.ready
                            ? null
                            : _create,
                        child: Text(strings.text('create_world')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggle(Set<String> values, String value) {
    if (!values.add(value)) values.remove(value);
  }

  void _returnToLibrary() {
    ref.read(navigationProvider.notifier).goTo(AppDestination.library);
  }

  void _selectTemplate(ScenarioTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      _nameController.text = template.name;
      _descriptionController.text = template.description;
      _genres
        ..clear()
        ..addAll(template.genre);
      _tones
        ..clear()
        ..addAll(template.tone);
      _customGenres.addAll(template.genre.where((String value) =>
          !const ['Modern', 'SF', 'Fantasy', 'Mystery'].contains(value)));
      _customTones.addAll(template.tone.where((String value) =>
          !const ['Dark', 'Serious', 'Hopeful', 'Quiet'].contains(value)));
      _error = null;
    });
  }

  Future<void> _create({bool startPlaying = false}) async {
    if (_isCreating) return;
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() =>
          _error = AppStrings(ref.read(localeProvider)).text('name_required'));
      return;
    }
    setState(() => _isCreating = true);
    try {
      await ref.read(workspaceProvider.notifier).createWorld(
            name: name,
            description: _descriptionController.text.trim(),
            genre: _genres.toList(),
            tone: _tones.toList(),
            templateId: _selectedTemplateId,
          );
      if (mounted) {
        if (startPlaying) {
          final ModelManagerController modelController =
              ref.read(modelManagerControllerProvider.notifier);
          if (ref.read(modelManagerControllerProvider).isLoading) {
            await modelController.load();
          }
          if (ref.read(modelManagerControllerProvider).selection == null) {
            modelController.showMessage(
                'Your world was saved. Choose a story model, then start it from Library.');
            ref.read(navigationProvider.notifier).goTo(AppDestination.models);
            return;
          }
          final WorkspaceState updated = ref.read(workspaceProvider);
          final world = updated.currentWorld;
          if (world == null) {
            throw StateError('The new world could not be loaded.');
          }
          final WorkspaceController workspaceController =
              ref.read(workspaceProvider.notifier);
          final novel = ref.read(novelControllerProvider.notifier);
          await novel.loadSettings();
          if (!mounted) return;
          novel.validatePlayableWorld(world);
          await novel.createCampaign(world);
          if (!mounted) return;
          ref.read(navigationProvider.notifier).goTo(AppDestination.player);
          await workspaceController.refreshCampaigns(world.id);
        } else {
          ref.read(navigationProvider.notifier).goTo(AppDestination.studio);
        }
      }
    } catch (error) {
      if (mounted) {
        final WorkspaceState workspace = ref.read(workspaceProvider);
        setState(() => _error = workspace.errorMessage ??
            (error is StateError
                ? error.message
                : 'The world could not be saved to the local database. Check permissions and try again.'));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }
}

class _ScenarioTemplateTile extends StatelessWidget {
  const _ScenarioTemplateTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final ScenarioTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: selected ? ContinuumTheme.surface : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? ContinuumTheme.accent : const Color(0xFF30312C),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(
                    selected ? Icons.check_circle : Icons.auto_stories_outlined,
                    color: selected ? ContinuumTheme.accent : null),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(uiPhrase(context, template.name),
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 3),
                      Text(uiPhrase(context, template.tagline),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(template.genre.map((String value) => uiPhrase(context, value)).join(' · '),
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.3,
          color: ContinuumTheme.muted,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choices,
    required this.selected,
    required this.onToggle,
    required this.onAdd,
  });
  final List<String> choices;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 9,
        runSpacing: 8,
        children: [
          for (final String choice in choices)
            ChoiceChip(
              label: Text(uiPhrase(context, choice)),
              selected: selected.contains(choice),
              onSelected: (_) => onToggle(choice),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 14),
            label: Text(uiPhrase(context, 'Add')),
            onPressed: () async {
              final String? value = await _addChoice(context);
              if (value != null) onAdd(value);
            },
          ),
        ],
      );

  Future<String?> _addChoice(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(AppStrings(Localizations.localeOf(context)).text('add_category')),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (String value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings(Localizations.localeOf(context)).text('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppStrings(Localizations.localeOf(context)).text('add')),
          ),
        ],
      ),
    );
    controller.dispose();
    final String? trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) return null;
    if (choices.any((String choice) =>
        choice.toLowerCase() == trimmedValue.toLowerCase())) {
      return null;
    }
    return trimmedValue;
  }
}

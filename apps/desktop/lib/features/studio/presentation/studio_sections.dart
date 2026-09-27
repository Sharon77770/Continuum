import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';

import '../../../app/theme.dart';
import '../../../app/ui_phrase.dart';

class OverviewEditor extends StatelessWidget {
  const OverviewEditor({
    super.key,
    required this.world,
    required this.onChanged,
  });
  final World world;
  final ValueChanged<World> onChanged;

  @override
  Widget build(BuildContext context) => _EditorPage(
        title: 'A world, in brief',
        subtitle: 'Set the foundations. The details will gather around them.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditableLabel(
              label: 'NAME',
              value: world.name,
              onChanged: (value) => onChanged(world.copyWith(name: value)),
            ),
            _EditableLabel(
              label: 'DESCRIPTION',
              value: world.description,
              maxLines: 3,
              onChanged: (value) =>
                  onChanged(world.copyWith(description: value)),
            ),
            _TagEditor(
              label: 'GENRE',
              values: world.genre,
              onChanged: (value) => onChanged(world.copyWith(genre: value)),
            ),
            _TagEditor(
              label: 'TONE',
              values: world.tone,
              onChanged: (value) => onChanged(world.copyWith(tone: value)),
            ),
            const SizedBox(height: 18),
            _SectionHeading(
              title: 'World Rules',
              description: uiPhrase(context,
                  'The truths every story in this world must respect.'),
            ),
            const SizedBox(height: 12),
            for (int index = 0; index < world.rules.length; index++)
              _RuleRow(
                key: ValueKey<String>('rule-$index'),
                text: world.rules[index],
                onChanged: (value) => _replaceRule(index, value),
              ),
            TextButton.icon(
              onPressed: () => _addRule(context),
              icon: const Icon(Icons.add, size: 15),
              label: Text(uiPhrase(context, 'Add Rule')),
            ),
          ],
        ),
      );

  void _replaceRule(int index, String value) {
    final List<String> updated = List<String>.of(world.rules);
    updated[index] = value;
    onChanged(world.copyWith(rules: updated));
  }

  Future<void> _addRule(BuildContext context) async {
    final String? rule = await _prompt(
      context,
      uiPhrase(context, 'Add a world rule'),
      uiPhrase(context, 'Write a truth about this world.'),
    );
    if (rule != null && rule.trim().isNotEmpty) {
      onChanged(world.copyWith(rules: [...world.rules, rule.trim()]));
    }
  }
}

class LoreEditor extends StatefulWidget {
  const LoreEditor({super.key, required this.world, required this.onChanged});
  final World world;
  final ValueChanged<World> onChanged;
  @override
  State<LoreEditor> createState() => _LoreEditorState();
}

class _LoreEditorState extends State<LoreEditor> {
  String? _selectedId;
  @override
  Widget build(BuildContext context) {
    final List<LoreEntry> entries = widget.world.loreEntries;
    final LoreEntry? selected =
        entries.where((entry) => entry.id == _selectedId).firstOrNull ??
            (entries.isEmpty ? null : entries.first);
    return Row(
      children: [
        SizedBox(
          width: 250,
          child: _EntryList(
            title: uiPhrase(context, 'Lore'),
            count: entries.length,
            onAdd: () => _addEntry(context),
            children: [
              for (final LoreEntry entry in entries)
                _EntryListItem(
                  title: entry.title,
                  subtitle: entry.category,
                  selected: entry.id == selected?.id,
                  onTap: () => setState(() => _selectedId = entry.id),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF292A26)),
        Expanded(
          child: selected == null
              ? _EmptyEditor(
                  title: uiPhrase(context, 'No lore yet'),
                  onAdd: () => _addEntry(context),
                )
              : _LoreDetail(
                  entry: selected,
                  onUpdate: (updated) => _updateEntry(selected, updated),
                  onDelete: () => _deleteEntry(selected),
                ),
        ),
      ],
    );
  }

  Future<void> _addEntry(BuildContext context) async {
    final String? title = await _prompt(
      context,
      uiPhrase(context, 'New lore entry'),
      uiPhrase(context, 'Entry title'),
    );
    if (title == null || title.trim().isEmpty) return;
    final LoreEntry entry = LoreEntry(
      id: createStableId('lore'),
      worldId: widget.world.id,
      title: title.trim(),
      category: 'History',
      content: '',
    );
    widget.onChanged(
      widget.world.copyWith(loreEntries: [...widget.world.loreEntries, entry]),
    );
    setState(() => _selectedId = entry.id);
  }

  void _updateEntry(LoreEntry old, LoreEntry updated) => widget.onChanged(
        widget.world.copyWith(
          loreEntries: [
            for (final LoreEntry entry in widget.world.loreEntries)
              if (entry.id == old.id) updated else entry,
          ],
        ),
      );
  void _deleteEntry(LoreEntry entry) {
    widget.onChanged(
      widget.world.copyWith(
        loreEntries: widget.world.loreEntries
            .where((item) => item.id != entry.id)
            .toList(),
      ),
    );
    setState(() => _selectedId = null);
  }
}

class _LoreDetail extends StatelessWidget {
  const _LoreDetail({
    required this.entry,
    required this.onUpdate,
    required this.onDelete,
  });
  final LoreEntry entry;
  final ValueChanged<LoreEntry> onUpdate;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => _EditorPage(
        title: entry.title,
        subtitle: 'A reference from within the world.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditableLabel(
              key: ValueKey<String>('lore-title-${entry.id}'),
              label: 'TITLE',
              value: entry.title,
              onChanged: (value) => onUpdate(
                LoreEntry(
                  id: entry.id,
                  worldId: entry.worldId,
                  title: value,
                  category: entry.category,
                  content: entry.content,
                ),
              ),
            ),
            _EditableLabel(
              key: ValueKey<String>('lore-category-${entry.id}'),
              label: 'CATEGORY',
              value: entry.category,
              onChanged: (value) => onUpdate(
                LoreEntry(
                  id: entry.id,
                  worldId: entry.worldId,
                  title: entry.title,
                  category: value,
                  content: entry.content,
                ),
              ),
            ),
            _EditableLabel(
              key: ValueKey<String>('lore-content-${entry.id}'),
              label: 'CONTENT',
              value: entry.content,
              maxLines: 9,
              onChanged: (value) => onUpdate(
                LoreEntry(
                  id: entry.id,
                  worldId: entry.worldId,
                  title: entry.title,
                  category: entry.category,
                  content: value,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 15),
              label: Text(uiPhrase(context, 'Remove entry')),
            ),
          ],
        ),
      );
}

class CharactersEditor extends StatefulWidget {
  const CharactersEditor({
    super.key,
    required this.world,
    required this.onChanged,
  });
  final World world;
  final ValueChanged<World> onChanged;
  @override
  State<CharactersEditor> createState() => _CharactersEditorState();
}

class _CharactersEditorState extends State<CharactersEditor> {
  String? _selectedId;
  @override
  Widget build(BuildContext context) {
    final List<StoryCharacter> characters = widget.world.characters;
    final StoryCharacter? selected =
        characters.where((item) => item.id == _selectedId).firstOrNull ??
            (characters.isEmpty ? null : characters.first);
    return Row(
      children: [
        SizedBox(
          width: 250,
          child: _EntryList(
            title: uiPhrase(context, 'Characters'),
            count: characters.length,
            onAdd: () => _addCharacter(context),
            children: [
              for (final StoryCharacter character in characters)
                _EntryListItem(
                  title: character.name,
                  subtitle: character.role,
                  selected: character.id == selected?.id,
                  onTap: () => setState(() => _selectedId = character.id),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF292A26)),
        Expanded(
          child: selected == null
              ? _EmptyEditor(
                  title: uiPhrase(context, 'No characters yet'),
                  onAdd: () => _addCharacter(context),
                )
              : _CharacterDetail(
                  character: selected,
                  onUpdate: (updated) => _updateCharacter(selected, updated),
                  onDelete: () => _deleteCharacter(selected),
                ),
        ),
      ],
    );
  }

  Future<void> _addCharacter(BuildContext context) async {
    final String? name = await _prompt(
      context,
      uiPhrase(context, 'New character'),
      uiPhrase(context, 'Character name'),
    );
    if (name == null || name.trim().isEmpty) return;
    final String id = createStableId('char');
    final StoryCharacter character = StoryCharacter(
      id: id,
      worldId: widget.world.id,
      name: name.trim(),
      role: '',
      description: '',
      personality: '',
      background: '',
      publicInformation: '',
      secretInformation: '',
    );
    widget.onChanged(
      widget.world.copyWith(
        characters: [...widget.world.characters, character],
      ),
    );
    setState(() => _selectedId = id);
  }

  void _updateCharacter(StoryCharacter old, StoryCharacter updated) =>
      widget.onChanged(
        widget.world.copyWith(
          characters: [
            for (final StoryCharacter item in widget.world.characters)
              if (item.id == old.id) updated else item,
          ],
        ),
      );
  void _deleteCharacter(StoryCharacter item) {
    widget.onChanged(
      widget.world.copyWith(
        characters: widget.world.characters
            .where((character) => character.id != item.id)
            .toList(),
        openingDefinition: OpeningDefinition(
          startingLocationId: widget.world.openingDefinition.startingLocationId,
          startingCharacterIds: widget
              .world.openingDefinition.startingCharacterIds
              .where((String id) => id != item.id)
              .toList(),
          situation: widget.world.openingDefinition.situation,
        ),
      ),
    );
    setState(() => _selectedId = null);
  }
}

class _CharacterDetail extends StatelessWidget {
  const _CharacterDetail({
    required this.character,
    required this.onUpdate,
    required this.onDelete,
  });
  final StoryCharacter character;
  final ValueChanged<StoryCharacter> onUpdate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _EditorPage(
        title: character.name,
        subtitle: uiPhrase(context, 'A person who belongs to this world.'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 94,
                  height: 116,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ContinuumTheme.surface,
                    border: Border.all(color: const Color(0xFF30312C)),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 28,
                    color: ContinuumTheme.muted,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _characterField(
                        'NAME',
                        character.name,
                        (value) => _copy(name: value),
                      ),
                      _characterField(
                        'ROLE',
                        character.role,
                        (value) => _copy(role: value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _characterField(
              'DESCRIPTION',
              character.description,
              (value) => _copy(description: value),
              maxLines: 3,
            ),
            _characterField(
              'APPEARANCE',
              character.appearance,
              (value) => _copy(appearance: value),
              maxLines: 3,
            ),
            _characterField(
              'PERSONALITY',
              character.personality,
              (value) => _copy(personality: value),
              maxLines: 3,
            ),
            _characterField(
              'BACKGROUND',
              character.background,
              (value) => _copy(background: value),
              maxLines: 3,
            ),
            _characterField(
              'PUBLIC INFORMATION',
              character.publicInformation,
              (value) => _copy(publicInformation: value),
              maxLines: 3,
            ),
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 4),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: ContinuumTheme.accent, width: 2),
                ),
                color: Color(0xFF1C1C18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uiPhrase(context, 'SECRET INFORMATION'),
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.15,
                      color: ContinuumTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    uiPhrase(context,
                        'Private world notes. These are not shown to players.'),
                    style: const TextStyle(
                        fontSize: 11, color: ContinuumTheme.muted),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: character.secretInformation,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: uiPhrase(context,
                          'Hidden motives, truths, and things yet to be revealed'),
                    ),
                    onChanged: (value) => _copy(secretInformation: value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 15),
              label: Text(uiPhrase(context, 'Remove character')),
            ),
          ],
        ),
      );

  Widget _characterField(
    String label,
    String value,
    ValueChanged<String> changed, {
    int maxLines = 1,
  }) =>
      _EditableLabel(
        key: ValueKey<String>('$label-${character.id}'),
        label: label,
        value: value,
        maxLines: maxLines,
        onChanged: changed,
      );
  void _copy({
    String? name,
    String? role,
    String? appearance,
    String? description,
    String? personality,
    String? background,
    String? publicInformation,
    String? secretInformation,
  }) =>
      onUpdate(
        StoryCharacter(
          id: character.id,
          worldId: character.worldId,
          name: name ?? character.name,
          role: role ?? character.role,
          description: description ?? character.description,
          appearance: appearance ?? character.appearance,
          personality: personality ?? character.personality,
          background: background ?? character.background,
          publicInformation: publicInformation ?? character.publicInformation,
          secretInformation: secretInformation ?? character.secretInformation,
          portraitReference: character.portraitReference,
        ),
      );
}

class LocationsEditor extends StatefulWidget {
  const LocationsEditor({
    super.key,
    required this.world,
    required this.onChanged,
  });
  final World world;
  final ValueChanged<World> onChanged;
  @override
  State<LocationsEditor> createState() => _LocationsEditorState();
}

class _LocationsEditorState extends State<LocationsEditor> {
  String? _selectedId;
  @override
  Widget build(BuildContext context) {
    final List<StoryLocation> locations = widget.world.locations;
    final StoryLocation? selected =
        locations.where((item) => item.id == _selectedId).firstOrNull ??
            (locations.isEmpty ? null : locations.first);
    final Map<String?, List<StoryLocation>> children =
        <String?, List<StoryLocation>>{};
    for (final StoryLocation location in locations) {
      children.putIfAbsent(location.parentId, () => []).add(location);
    }
    final List<({StoryLocation location, int depth})> treeRows =
        _flattenLocationTree(locations, children);
    return Row(
      children: [
        SizedBox(
          width: 270,
          child: _EntryList(
            title: uiPhrase(context, 'Locations'),
            count: locations.length,
            onAdd: () => _addLocation(context),
            children: [
              for (final ({StoryLocation location, int depth}) row in treeRows)
                Padding(
                  key: ValueKey<String>('location-tree-${row.location.id}'),
                  padding: EdgeInsets.only(left: 10 + row.depth * 15),
                  child: ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -3),
                    selected: selected?.id == row.location.id,
                    title: Text(row.location.name,
                        style: const TextStyle(fontSize: 12)),
                    onTap: () => setState(() => _selectedId = row.location.id),
                  ),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF292A26)),
        Expanded(
          child: selected == null
              ? _EmptyEditor(
                  title: uiPhrase(context, 'No locations yet'),
                  onAdd: () => _addLocation(context),
                )
              : _LocationDetail(
                  location: selected,
                  locations: locations,
                  onUpdate: (updated) => _updateLocation(selected, updated),
                  onDelete: () => _deleteLocation(selected),
                ),
        ),
      ],
    );
  }

  Future<void> _addLocation(BuildContext context) async {
    final String? name = await _prompt(
      context,
      uiPhrase(context, 'New location'),
      uiPhrase(context, 'Location name'),
    );
    if (name == null || name.trim().isEmpty) return;
    final String id = createStableId('loc');
    final StoryLocation location = StoryLocation(
      id: id,
      worldId: widget.world.id,
      name: name.trim(),
      description: '',
    );
    widget.onChanged(
      widget.world.copyWith(locations: [...widget.world.locations, location]),
    );
    setState(() => _selectedId = id);
  }

  void _updateLocation(StoryLocation old, StoryLocation updated) =>
      widget.onChanged(
        widget.world.copyWith(
          locations: [
            for (final StoryLocation item in widget.world.locations)
              if (item.id == old.id) updated else item,
          ],
        ),
      );

  List<({StoryLocation location, int depth})> _flattenLocationTree(
    List<StoryLocation> locations,
    Map<String?, List<StoryLocation>> children,
  ) {
    final List<({StoryLocation location, int depth})> rows = [];
    final Set<String> visitedIds = <String>{};
    final List<({StoryLocation location, int depth})> pending = [
      for (final StoryLocation root
          in (children[null] ?? <StoryLocation>[]).reversed)
        (location: root, depth: 0),
    ];

    while (pending.isNotEmpty) {
      final ({StoryLocation location, int depth}) current =
          pending.removeLast();
      if (!visitedIds.add(current.location.id)) continue;
      rows.add(current);
      final List<StoryLocation> nested =
          children[current.location.id] ?? <StoryLocation>[];
      for (final StoryLocation child in nested.reversed) {
        pending.add((location: child, depth: current.depth + 1));
      }
    }

    // Keep orphaned or cyclic components visible without traversing them twice.
    for (final StoryLocation location in locations) {
      if (visitedIds.add(location.id)) {
        rows.add((location: location, depth: 0));
      }
    }
    return rows;
  }

  void _deleteLocation(StoryLocation item) {
    final bool hasChildren = widget.world.locations
        .any((StoryLocation location) => location.parentId == item.id);
    if (hasChildren) {
      return;
    }
    final Set<String> removedIds = {item.id};
    bool changed = true;
    while (changed) {
      changed = false;
      for (final StoryLocation location in widget.world.locations) {
        if (location.parentId != null &&
            removedIds.contains(location.parentId) &&
            removedIds.add(location.id)) {
          changed = true;
        }
      }
    }
    widget.onChanged(
      widget.world.copyWith(
        locations: widget.world.locations
            .where((location) => !removedIds.contains(location.id))
            .toList(),
      ),
    );
    setState(() => _selectedId = null);
  }
}

class _LocationDetail extends StatelessWidget {
  const _LocationDetail({
    required this.location,
    required this.locations,
    required this.onUpdate,
    required this.onDelete,
  });
  final StoryLocation location;
  final List<StoryLocation> locations;
  final ValueChanged<StoryLocation> onUpdate;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => _EditorPage(
        title: location.name,
        subtitle: uiPhrase(context, 'A place within the world.'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditableLabel(
              key: ValueKey<String>('location-name-${location.id}'),
              label: 'NAME',
              value: location.name,
              onChanged: (value) => onUpdate(
                StoryLocation(
                  id: location.id,
                  worldId: location.worldId,
                  name: value,
                  description: location.description,
                  parentId: location.parentId,
                  backgroundReference: location.backgroundReference,
                ),
              ),
            ),
            _EditableLabel(
              key: ValueKey<String>('location-description-${location.id}'),
              label: 'DESCRIPTION',
              value: location.description,
              maxLines: 5,
              onChanged: (value) => onUpdate(
                StoryLocation(
                  id: location.id,
                  worldId: location.worldId,
                  name: location.name,
                  description: value,
                  parentId: location.parentId,
                  backgroundReference: location.backgroundReference,
                ),
              ),
            ),
            _ParentPicker(
              location: location,
              locations: locations,
              onChanged: (parentId) => onUpdate(
                StoryLocation(
                  id: location.id,
                  worldId: location.worldId,
                  name: location.name,
                  description: location.description,
                  parentId: parentId,
                  backgroundReference: location.backgroundReference,
                ),
              ),
            ),
            const SizedBox(height: 15),
            Container(
              height: 142,
              alignment: Alignment.center,
              width: double.infinity,
              decoration: BoxDecoration(
                color: ContinuumTheme.surface,
                border: Border.all(color: const Color(0xFF30312C)),
              ),
              child: Text(
                uiPhrase(context, 'BACKGROUND PLACEHOLDER'),
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  color: ContinuumTheme.muted,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (locations
                .any((StoryLocation item) => item.parentId == location.id))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                    uiPhrase(context,
                        'Move nested places before removing this location.'),
                    style: const TextStyle(
                        color: ContinuumTheme.muted, fontSize: 11)),
              ),
            TextButton.icon(
              onPressed: locations
                      .any((StoryLocation item) => item.parentId == location.id)
                  ? null
                  : onDelete,
              icon: const Icon(Icons.delete_outline, size: 15),
              label: Text(uiPhrase(context, 'Remove location')),
            ),
          ],
        ),
      );
}

class _ParentPicker extends StatelessWidget {
  const _ParentPicker({
    required this.location,
    required this.locations,
    required this.onChanged,
  });
  final StoryLocation location;
  final List<StoryLocation> locations;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    final Set<String> descendantIds = _descendantIds(locations, location.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldCaption('PARENT LOCATION'),
          const SizedBox(height: 7),
          DropdownButtonFormField<String?>(
            initialValue: location.parentId,
            decoration: const InputDecoration(),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(uiPhrase(context, 'World root')),
              ),
              for (final StoryLocation parent in locations.where(
                (item) =>
                    item.id != location.id && !descendantIds.contains(item.id),
              ))
                DropdownMenuItem<String?>(
                  value: parent.id,
                  child: Text(parent.name),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Set<String> _descendantIds(List<StoryLocation> locations, String locationId) {
    final Set<String> descendants = <String>{};
    bool foundNewChild = true;
    while (foundNewChild) {
      foundNewChild = false;
      for (final StoryLocation candidate in locations) {
        final bool isNested = candidate.parentId == locationId ||
            descendants.contains(candidate.parentId);
        if (isNested && descendants.add(candidate.id)) foundNewChild = true;
      }
    }
    return descendants;
  }
}

class _EditorPage extends StatelessWidget {
  const _EditorPage({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        key: ValueKey<String>(title),
        padding: const EdgeInsets.fromLTRB(48, 40, 48, 52),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(uiPhrase(context, title),
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 7),
                Text(uiPhrase(context, subtitle),
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 34),
                child,
              ],
            ),
          ),
        ),
      );
}

class _EditableLabel extends StatefulWidget {
  const _EditableLabel({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;
  @override
  State<_EditableLabel> createState() => _EditableLabelState();
}

class _EditableLabelState extends State<_EditableLabel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _EditableLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value && oldWidget.value != widget.value) {
      _controller.value = TextEditingValue(
          text: widget.value,
          selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldCaption(widget.label),
            const SizedBox(height: 7),
            TextField(
              controller: _controller,
              minLines: widget.maxLines == 1 ? 1 : widget.maxLines,
              maxLines: widget.maxLines,
              onChanged: widget.onChanged,
            ),
          ],
        ),
      );
}

class _TagEditor extends StatelessWidget {
  const _TagEditor({
    required this.label,
    required this.values,
    required this.onChanged,
  });
  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldCaption(label),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 4,
              children: [
                for (int index = 0; index < values.length; index++)
                  InputChip(
                    key: ValueKey<String>('tag-$label-$index-${values[index]}'),
                    label: Text(values[index]),
                    onDeleted: () {
                      final List<String> updated = List<String>.of(values)
                        ..removeAt(index);
                      onChanged(updated);
                    },
                  ),
                ActionChip(
                  key: ValueKey<String>('add-tag-$label'),
                  avatar: const Icon(Icons.add, size: 14),
                  label: Text(uiPhrase(context, 'Add')),
                  onPressed: () async {
                    final String? item = await _prompt(
                      context,
                      '${uiPhrase(context, 'Add')} $label',
                      'Name',
                    );
                    if (item != null && item.trim().isNotEmpty) {
                      onChanged([...values, item.trim()]);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
}

class _FieldCaption extends StatelessWidget {
  const _FieldCaption(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
        uiPhrase(context, label),
        style: const TextStyle(
          fontSize: 9,
          letterSpacing: 1.2,
          color: ContinuumTheme.muted,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.description});
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(uiPhrase(context, title),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 3),
          Text(uiPhrase(context, description),
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({super.key, required this.text, required this.onChanged});
  final String text;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            const Text('•  ', style: TextStyle(color: ContinuumTheme.accent)),
            Expanded(
              child: TextFormField(
                key: key,
                initialValue: text,
                decoration: const InputDecoration(isDense: true),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.title,
    required this.count,
    required this.onAdd,
    required this.children,
  });
  final String title;
  final int count;
  final VoidCallback onAdd;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 22, 12, 17),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                      fontSize: 11, color: ContinuumTheme.muted),
                ),
                IconButton(
                  tooltip: '${uiPhrase(context, 'Add')} $title',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 17),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF292A26)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: children,
            ),
          ),
        ],
      );
}

class _EntryListItem extends StatelessWidget {
  const _EntryListItem({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: const Color(0xFF23231F),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 10, color: ContinuumTheme.muted),
        ),
        onTap: onTap,
      );
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor({required this.title, required this.onAdd});
  final String title;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              uiPhrase(context, 'Begin with a first entry.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 15),
              label: Text(uiPhrase(context, 'Add')),
            ),
          ],
        ),
      );
}

Future<String?> _prompt(BuildContext context, String title, String hint) async {
  final TextEditingController controller = TextEditingController();
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(uiPhrase(context, title)),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: uiPhrase(context, hint)),
        onSubmitted: (String value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(uiPhrase(context, 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(uiPhrase(context, 'Add')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// Edits the protagonist fields used when a Campaign starts.
class PlayerDefinitionEditor extends StatelessWidget {
  const PlayerDefinitionEditor(
      {super.key, required this.world, required this.onChanged});
  final World world;
  final ValueChanged<World> onChanged;
  @override
  Widget build(BuildContext context) {
    final PlayerDefinition player = world.playerDefinition;
    return _EditorPage(
        title: uiPhrase(context, 'Player'),
        subtitle: uiPhrase(context, 'Define who enters the story.'),
        child: Column(children: <Widget>[
          _EditableLabel(
            label: 'Name',
            value: player.name,
            onChanged: (String value) => onChanged(world.copyWith(
              playerDefinition: PlayerDefinition(
                  name: value,
                  description: player.description,
                  background: player.background,
                  traits: player.traits),
            )),
          ),
          _EditableLabel(
            label: 'Description',
            value: player.description,
            maxLines: 3,
            onChanged: (String value) => onChanged(world.copyWith(
              playerDefinition: PlayerDefinition(
                  name: player.name,
                  description: value,
                  background: player.background,
                  traits: player.traits),
            )),
          ),
          _EditableLabel(
            label: 'Background',
            value: player.background,
            maxLines: 4,
            onChanged: (String value) => onChanged(world.copyWith(
              playerDefinition: PlayerDefinition(
                  name: player.name,
                  description: player.description,
                  background: value,
                  traits: player.traits),
            )),
          ),
          _EditableLabel(
            label: 'Traits · comma separated',
            value: player.traits.join(', '),
            onChanged: (String value) => onChanged(world.copyWith(
              playerDefinition: PlayerDefinition(
                name: player.name,
                description: player.description,
                background: player.background,
                traits: value
                    .split(',')
                    .map((String item) => item.trim())
                    .where((String item) => item.isNotEmpty)
                    .toList(),
              ),
            )),
          ),
        ]));
  }
}

/// Selects the opening location, starting cast, and situation.
class OpeningDefinitionEditor extends StatelessWidget {
  const OpeningDefinitionEditor(
      {super.key, required this.world, required this.onChanged});
  final World world;
  final ValueChanged<World> onChanged;
  @override
  Widget build(BuildContext context) {
    final OpeningDefinition opening = world.openingDefinition;
    return _EditorPage(
        title: uiPhrase(context, 'Opening'),
        subtitle:
            uiPhrase(context, 'Choose the first place, cast, and situation.'),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _FieldCaption('STARTING LOCATION'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: world.locations.any((StoryLocation item) =>
                        item.id == opening.startingLocationId)
                    ? opening.startingLocationId
                    : null,
                items: <DropdownMenuItem<String>>[
                  for (final StoryLocation location in world.locations)
                    DropdownMenuItem(
                        value: location.id, child: Text(location.name))
                ],
                onChanged: (String? id) => onChanged(world.copyWith(
                    openingDefinition: OpeningDefinition(
                        startingLocationId: id,
                        startingCharacterIds: opening.startingCharacterIds,
                        situation: opening.situation))),
              ),
              const SizedBox(height: 24),
              const _FieldCaption('STARTING CHARACTERS'),
              for (final StoryCharacter character in world.characters)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(character.name),
                  value: opening.startingCharacterIds.contains(character.id),
                  onChanged: (bool? selected) {
                    final Set<String> ids = {...opening.startingCharacterIds};
                    if (selected == true) {
                      ids.add(character.id);
                    } else {
                      ids.remove(character.id);
                    }
                    onChanged(world.copyWith(
                        openingDefinition: OpeningDefinition(
                            startingLocationId: opening.startingLocationId,
                            startingCharacterIds: ids.toList(),
                            situation: opening.situation)));
                  },
                ),
              const SizedBox(height: 18),
              _EditableLabel(
                  label: uiPhrase(context, 'Opening Situation'),
                  value: opening.situation,
                  maxLines: 8,
                  onChanged: (String value) => onChanged(world.copyWith(
                      openingDefinition: OpeningDefinition(
                          startingLocationId: opening.startingLocationId,
                          startingCharacterIds: opening.startingCharacterIds,
                          situation: value)))),
            ]));
  }
}

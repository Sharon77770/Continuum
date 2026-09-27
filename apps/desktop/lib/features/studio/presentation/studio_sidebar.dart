import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';

import '../../../app/navigation.dart';
import '../../../app/theme.dart';
import '../../../app/ui_phrase.dart';
import 'studio_navigation.dart';

class StudioSidebar extends ConsumerWidget {
  const StudioSidebar({
    super.key,
    required this.world,
    required this.selected,
    required this.onSelect,
  });
  final World world;
  final StudioSection selected;
  final ValueChanged<StudioSection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        width: 224,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFF292A26))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 20, 14, 22),
              child: Row(
                children: [
                  const Text(
                    'CONTINUUM',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2.1,
                      color: ContinuumTheme.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: uiPhrase(context, 'Library'),
                    onPressed: () => ref
                        .read(navigationProvider.notifier)
                        .goTo(AppDestination.library),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 21),
              child: Text(
                world.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 25),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  for (final String group in ['WORLD', 'GAME', 'ASSETS']) ...[
                    _GroupLabel(group),
                    for (final StudioSection section
                        in StudioSection.values.where(
                      (item) => item.group == group,
                    ))
                      _SectionButton(
                        section: section,
                        selected: selected == section,
                        onTap: () => onSelect(section),
                      ),
                    const SizedBox(height: 21),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(21, 0, 14, 8),
        child: Text(
          uiPhrase(context, label),
          style: const TextStyle(
            fontSize: 9,
            letterSpacing: 1.5,
            color: ContinuumTheme.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final StudioSection section;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          selected: selected,
          selectedTileColor: const Color(0xFF23231F),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
          minLeadingWidth: 10,
          leading: selected
              ? const Icon(Icons.remove, size: 10, color: ContinuumTheme.accent)
              : const SizedBox(width: 10),
          title: Text(
            uiPhrase(context, section.label),
            style: TextStyle(
              fontSize: 12,
              color: selected ? ContinuumTheme.text : ContinuumTheme.muted,
            ),
          ),
          onTap: onTap,
        ),
      );
}

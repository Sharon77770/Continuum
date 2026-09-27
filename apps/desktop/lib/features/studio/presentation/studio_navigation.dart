enum StudioSection {
  overview('Overview', 'WORLD'),
  lore('Lore', 'WORLD'),
  characters('Characters', 'WORLD'),
  locations('Locations', 'WORLD'),
  player('Player', 'GAME'),
  opening('Opening', 'GAME'),
  novelSettings('Novel Settings', 'GAME'),
  portraits('Portraits', 'ASSETS'),
  backgrounds('Backgrounds', 'ASSETS');

  const StudioSection(this.label, this.group);
  final String label;
  final String group;
}

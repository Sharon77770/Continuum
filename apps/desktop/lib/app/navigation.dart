import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppDestination { library, createWorld, studio, player, models, settings }

enum SettingsReturnDestination { library, studio, player, createWorld }

final navigationProvider =
    NotifierProvider<NavigationController, AppDestination>(
  NavigationController.new,
);

final settingsReturnProvider = StateProvider<SettingsReturnDestination>(
  (ref) => SettingsReturnDestination.library,
);

class NavigationController extends Notifier<AppDestination> {
  @override
  AppDestination build() => AppDestination.library;

  void goTo(AppDestination destination) => state = destination;

  void openSettings(SettingsReturnDestination returnDestination) {
    ref.read(settingsReturnProvider.notifier).state = returnDestination;
    state = AppDestination.settings;
  }
}

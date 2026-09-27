import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/novel/application/novel_controller.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/library/presentation/world_creation_screen.dart';
import '../features/models/presentation/models_screen.dart';
import '../features/models/application/model_manager_controller.dart';
import '../features/models/domain/runtime_manager.dart';
import '../features/models/data/runtime_lifecycle_adapter.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/studio/presentation/studio_screen.dart';
import '../state/locale_controller.dart';
import '../state/workspace_controller.dart';
import 'app_strings.dart';
import 'navigation.dart';
import 'theme.dart';

class ContinuumApp extends ConsumerStatefulWidget {
  const ContinuumApp({super.key});

  @override
  ConsumerState<ContinuumApp> createState() => _ContinuumAppState();
}

class _ContinuumAppState extends ConsumerState<ContinuumApp>
    with WidgetsBindingObserver {
  late RuntimeManager _runtimeManager;
  late RuntimeLifecycleAdapter _runtimeLifecycle;

  @override
  void initState() {
    super.initState();
    _runtimeManager = ref.read(llamaRuntimeManagerProvider);
    _runtimeLifecycle = RuntimeLifecycleAdapter(_runtimeManager)..register();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_runtimeManager.stop());
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _runtimeManager.stop();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtimeLifecycle.unregister();
    unawaited(_runtimeManager.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WidgetRef ref = this.ref;
    final AppDestination destination = ref.watch(navigationProvider);
    final String? worldId = ref.watch(workspaceProvider).currentWorldId;
    final Locale locale = ref.watch(localeProvider);
    final bool isStartingCampaign =
        ref.watch(novelControllerProvider).isStartingCampaign;
    return MaterialApp(
      title: 'Continuum',
      locale: locale,
      supportedLocales: const <Locale>[
        Locale('ko'),
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        Locale('ja'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: ContinuumTheme.dark,
      builder: (BuildContext context, Widget? child) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          child ?? const SizedBox.expand(),
          if (isStartingCampaign)
            _CampaignStartingOverlay(strings: AppStrings(locale)),
        ],
      ),
      home: switch (destination) {
        AppDestination.library => const LibraryScreen(),
        AppDestination.createWorld => const WorldCreationScreen(),
        AppDestination.studio => StudioScreen(worldId: worldId),
        AppDestination.player => PlayerScreen(worldId: worldId),
        AppDestination.models => const ModelsScreen(),
        AppDestination.settings => const SettingsScreen(),
      },
    );
  }
}

class _CampaignStartingOverlay extends StatelessWidget {
  const _CampaignStartingOverlay({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          const ModalBarrier(
            key: ValueKey<String>('campaign-start-modal-barrier'),
            dismissible: false,
            color: Color(0xDD111210),
          ),
          Center(
            child: Semantics(
              liveRegion: true,
              label: strings.text('starting_game'),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                margin: const EdgeInsets.all(24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
                decoration: BoxDecoration(
                  color: ContinuumTheme.surface,
                  border: Border.all(color: const Color(0xFF3A3931)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 22),
                    Text(
                      strings.text('starting_game'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.text('preparing_opening_scene'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

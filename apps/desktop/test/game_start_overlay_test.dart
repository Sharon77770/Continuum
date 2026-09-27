import 'package:continuum_desktop/app/continuum_app.dart';
import 'package:continuum_desktop/features/novel/application/novel_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:continuum_desktop/state/workspace_controller.dart';

void main() {
  testWidgets('shows a blocking startup overlay until the opening is ready',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        workspaceProvider.overrideWith(() => _TestWorkspaceController()),
        novelControllerProvider.overrideWith(_StartingNovelController.new),
      ],
      child: const ContinuumApp(),
    ));
    await tester.pump();

    expect(find.text('Starting your game'), findsOneWidget);
    expect(
        find.text(
            'Preparing the opening scene. You can switch screens when it is ready.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('campaign-start-modal-barrier')),
        findsOneWidget);

    await tester.tap(find.text('CREATE WORLD'), warnIfMissed: false);
    await tester.pump();

    expect(find.text('Your Worlds'), findsOneWidget);
    expect(find.text('A world, in brief'), findsNothing);
  });
}

class _StartingNovelController extends NovelController {
  @override
  NovelState build() => const NovelState(
        isGenerating: true,
        isStartingCampaign: true,
      );
}

class _TestWorkspaceController extends WorkspaceController {
  @override
  WorkspaceState build() =>
      const WorkspaceState(loadStatus: WorkspaceLoadStatus.ready);
}

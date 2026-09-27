# Windows development

Run commands from the repository root unless a step explicitly changes directory. The workspace contains one Flutter app (`apps/desktop`) and three pure Dart packages (`packages/*`).

## Prerequisites

- Flutter stable with Windows desktop support enabled.
- Visual Studio with **Desktop development with C++** and a Windows SDK. This checkout was built with Visual Studio Build Tools 2026.
- CMake (provided by Visual Studio or installed separately).
- PowerShell 7 or Windows PowerShell 5.1.

`sqflite_common_ffi` provides the SQLite FFI implementation used by Windows and tests. It is already declared by the desktop app; no external SQLite viewer is required. The Windows runner is Flutter's generated C++ host in `apps/desktop/windows/runner`.

## Check the environment and run

```powershell
./scripts/doctor.ps1
dart pub get
cd apps/desktop
flutter run -d windows
```

The doctor script reports Flutter and Dart availability, CMake, the Visual Studio C++ workload, `flutter doctor -v`, Flutter devices, and workspace dependency resolution. It does not install software or alter system configuration. NuGet is reported as optional because Flutter/Visual Studio can provide the client used during native builds.

## Analyze and test

From `apps/desktop`:

```powershell
flutter analyze
flutter test
```

`apps/desktop/test/novel_system_test.dart` covers structured output, context budgeting, OpenAI-compatible streaming limits, campaign commit/regeneration, and SQLite reload. `apps/desktop/test/local_llm_integration_test.dart` is an opt-in Korean player-perspective run: it uses an 8,192-token context, plays 20 turns, checks narration, dialogue, and suggested-action repetition, closes and reopens SQLite, then continues for another turn. Match the dedicated llama.cpp server context window to the test's 8,192-token setting. The Model Platform tests cover registry recommendations, manifest/selection restoration, download cancellation/checksums, provider switching, and managed runtime start/stop/crash/error mapping. Pure Dart packages currently use the desktop Flutter test runner as their test host.

For isolated local gameplay QA, run a dedicated llama.cpp server that is not attached to another Continuum session, then from `apps/desktop` set the endpoint/model and opt in:

```powershell
$env:CONTINUUM_RUN_LOCAL_LLM = '1'
$env:CONTINUUM_LLM_BASE_URL = 'http://127.0.0.1:<port>/v1'
$env:CONTINUUM_LLM_MODEL = '<served-model-id>'
flutter test --no-pub test/local_llm_integration_test.dart
```

The automated Korean scenario follows a campus blackout mystery across 20 actions by default: the player checks a generator warning, card-access records, a loose cable, and traces near the stairwell, then talks with the lab assistant. It checks Korean output, action echoes, repeated narration/dialogue and stale choices, then closes and reopens SQLite before continuing. Set `CONTINUUM_LLM_QA_TURNS` to a value from 1 to 20 for a shorter local smoke run. Also review the generated scenes as a player for clue continuity, NPC voice and knowledge, player agency, natural Korean, scene changes, and whether the story responds to the chosen action; those prose-quality judgments are not fully captured by assertions. Other supported story languages use the same generation and validation path, while real-model prose QA is deliberately run in Korean.

## Build and launch

From the repository root:

```powershell
./scripts/build-windows.ps1 -Configuration Debug
./scripts/build-windows.ps1 -Configuration Release
```

The script resolves the workspace, analyzes and tests the desktop app, builds the selected configuration, and checks that the generated executable remains running for eight seconds. This is only a process launch check; it does not verify visible screens or user input. Flutter places the executable and its required DLL and `data` bundle under `apps/desktop/build/windows/x64/runner/<Configuration>/continuum.exe`. The llama.cpp CPU runtime is not searched for on PATH or bundled into the source tree; on first local inference Continuum checks the latest official GitHub release, then searches the 20 newest official release records if that record has no compatible binary, validates the selected asset SHA-256, and installs it under `%APPDATA%\Continuum\runtime\llama.cpp` (Debug uses `Continuum-Dev`).

Manual smoke checks: open Library, confirm an existing World appears in Profile/Release, open its Studio, open Settings → Developer, open the data and log folders, run the integrity check, and create and inspect a backup. Confirm Debug reports `%APPDATA%\Continuum-Dev` and Profile/Release report `%APPDATA%\Continuum`. In Debug, create a World, close and relaunch, then confirm it remains. Use only disposable data when exercising the reset confirmation.

For scenario creation, open Create World, select each of the four scenario templates, confirm the form is prefilled, then use Create & Play. Confirm the Player opens with a generated first scene and that the new World and Campaign appear in Library. Also verify blank Create World still opens Studio.

For the Novel vertical slice, open Settings → Models and select a local or cloud Story Model. Advanced → Custom Provider retains endpoint configuration for compatibility testing. In Studio, configure Player and Opening with at least one Character and Location. Start New Game from Library, select a choice, submit free text, regenerate a turn, return to Library, then Continue and confirm the last scene/history restore.

## Model Platform manual QA

On a fresh Windows profile with no model manifest, confirm Library still opens and Worlds can be created/edited. The onboarding card opens Models. Confirm the hardware summary reports system memory, CPU architecture, graphics adapter, optional NVIDIA free VRAM, and free model storage; the 4B and 8B recommendations fit only when the conservative RAM rule allows.

Use a disposable user profile for the complete local flow: download a recommended model and confirm progress and byte counts; cancel a second download and confirm no `.part` file remains; finish a download and confirm it appears in On This Device; select it; try Conservative and Performance local resource profiles and confirm the runtime restarts with the selected limits; start a game; confirm runtime installation/model loading progresses to Ready and the opening scene generates. Close Continuum normally and confirm no `llama-server.exe` remains. Relaunch and confirm model selection and runtime version restore, then start another story. Trigger a runtime stop/crash in Developer Tools and verify Unavailable → Try Again recovery. Also import a small invalid `.gguf` and confirm it is rejected, then import a valid GGUF and verify its file/metadata appear in Advanced Details.

For Cloud, connect an OpenAI key, choose a returned text model, restart, and confirm the selection restores without showing the secret. Check OpenAI account/API logs are not written to app/runtime logs. For Discover, search a public repository with several single-file GGUF variants; confirm files are grouped, quality labels choose smaller/recommended/larger variants, and raw filenames/quantization appear only under Advanced Details. Multi-GB downloads are deliberately excluded from automated tests.

## Troubleshooting observed project boundaries

- If `flutter doctor -v` reports no Windows toolchain, install a Flutter-supported Visual Studio C++ desktop workload and a Windows SDK, then rerun the doctor script.
- If the runner fails at CMake configuration, check that CMake is discoverable and Flutter Windows support is enabled before retrying the build.
- If Windows dependency resolution fails while downloading NuGet packages, check the network access to the package source shown in the build output and retry `flutter build windows` after connectivity returns.
- If SQLite reports a locked database, close any external SQLite viewer or second Continuum process and retry after pending autosaves finish.
- If storage operations report access denied, confirm the current Windows user can write to the displayed AppData directory; do not move the database beside the executable.
- If a plugin's Windows implementation is missing at build time, inspect `apps/desktop/windows/flutter/generated_plugins.cmake` and the plugin's declared platform support before changing dependencies.

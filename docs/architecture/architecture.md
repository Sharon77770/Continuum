# Continuum Architecture

## Summary
Continuum is a local-first interactive fiction application. The Flutter Windows desktop app stores writer-authored World definitions and Campaign runtime state in SQLite. The desktop Model Platform manages local GGUF files and a trusted llama.cpp runtime, and exposes local, OpenAI and Gemini cloud, and advanced custom models through one `LlmProvider` interface.

## Workspace
The root `pubspec.yaml` defines a Dart workspace and every member declares `resolution: workspace`.
- `apps/desktop`: Flutter application, navigation, Riverpod application state, presentation, World repository contract and SQLite adapter.
- `packages/game_core`: Pure Dart story-world domain models and value objects.
- `packages/world_format`: Pure Dart world serialization boundary, currently an empty package boundary.
- `packages/novel_system`: Pure Dart narrative schema validation, playable-world validation, and bounded context construction.

## Dependency direction
Desktop widgets call Riverpod application state, which depends on focused `WorldRepository`, `CampaignRepository`, model manager, secret-store, and language model settings contracts. The SQLite implementation maps persistence rows to pure Dart `game_core` domain values. Novel application flow builds distinct bounded Opening or turn context and invokes `LlmProvider`; `ManagedLanguageModel` resolves the selected local/cloud/custom model behind that contract. It parses and validates a structured candidate, including scene IDs and state bounds, and only then commits scene/state/memory and saves the Campaign. `game_core` and `novel_system` must not import Flutter, Riverpod, or storage packages.

## State and data flow
At startup, the desktop application resolves `AppPaths`, creates user data, model, managed runtime, log, backup, and temporary directories, initializes bounded file logging, then opens the versioned SQLite database at `<user data root>/continuum.sqlite3`. On Windows Profile/Release retain `%APPDATA%/Continuum`; Debug uses `%APPDATA%/Continuum-Dev` so its reset cannot erase user data. Models and runtime binaries remain outside the source checkout. Widgets send user intents to Riverpod notifiers. Overview edits update domain values in memory and are debounced before repository persistence; entity CRUD uses the same repository boundary. The notifier exposes loading and failure status to the Library/Studio UI.

Settings → Developer calls a settings application controller which delegates SQLite metadata, integrity, backup, and reset operations to a data service. The data service opens the same database path and uses SQLite `VACUUM INTO` for a consistent live backup. Native folder opening stays behind a desktop data adapter. Developer Tools reads current workspace domain state for a read-only World inspector; no SQL or filesystem paths are composed in widgets.

Campaigns are stored separately from World definitions in `campaigns`; edits to a World do not overwrite a Campaign snapshot of runtime state. Model manifests and selection are stored under the user model directory. OpenAI and Gemini cloud credentials use separate entries in Windows secure storage; advanced custom-provider credentials remain process memory only. Gemini uses Google's OpenAI-compatible endpoint through the common streaming transport. Local inference starts the Continuum-managed, checksum-verified Windows x64 CPU runtime on demand, binds to loopback only, and stops it during app shutdown. Runtime logs are separate and bounded. The common transport supports OpenAI-style model and streaming requests internally; these protocol details are hidden from the regular Models UX. Narrative output gets up to three validation attempts; the parser extracts the first complete JSON object when a model adds trailing chatter. Korean question paraphrases and player-agency narration are checked across common verb forms, action-echo narration gets a short repair, duplicate or action-echo NPC lines are removed, and repeated choices are rebuilt from fresh options before commit. If the model offers no fresh choices, localized actions based on the current location and visible character are generated. A valid single choice may be combined with another distinct option from the same attempts.

The desktop application owns the active UI locale and default story language in Riverpod notifiers. The bundled UI catalogue contains the same 330 keys in Korean, English, Simplified Chinese, and Japanese; `AppStrings.phrase` localizes fixed interface phrases used by existing widgets. Flutter Material, Widgets, and Cupertino localization delegates provide standard framework labels and controls. Both language settings are stored in `language_preferences.json` under the app data directory and loaded before the main app is displayed.

The default story language is a separate Riverpod setting. New Campaigns snapshot its `languageCode` in their JSON payload, and Novel generation includes that language in both initial and repair prompts. Older Campaign payloads without the field load as English; continuing a Campaign retains its saved language.

## Architecture decisions
| Date | Decision | Reason | Impact |
| --- | --- | --- | --- |
| 2026-09-24 | Use a Dart workspace with a Flutter desktop app and three pure Dart packages. | Keep story rules renderer-independent while enabling a runnable Windows shell. | Domain packages remain free of Flutter dependencies. |
| 2026-09-24 | Use Riverpod only in the desktop application state boundary. | Keep UI state management out of domain objects. | Domain packages do not depend on Riverpod. |
| 2026-09-24 | Persist world definitions through a repository and versioned SQLite adapter. | Keep desktop UI and persistence models outside pure Dart domain objects. | SQLite runs through sqflite FFI for Windows desktop; domain models remain storage-agnostic. |
| 2026-09-25 | Manage llama.cpp as a verified child process rather than linking native inference into the Flutter runner. | A versioned upstream Windows CPU package is simpler to update and isolate than custom FFI bindings. | Install under user AppData from the official release API after SHA-256 verification; start by absolute path, use a dynamic loopback port, and stop on app shutdown. The MVP runtime is CPU-only. |
| 2026-09-25 | Persist model metadata and selection in an AppData manifest; keep large GGUF files in the models directory. | Avoid database blobs and keep model lifecycle independent from Campaign storage. | Removing a model deletes its local file and clears its local selection. Campaigns refer to Worlds, not model versions. |
| 2026-09-25 | Route local, OpenAI cloud, and custom provider choices through `ManagedLanguageModel`. | Keep Novel generation independent of provider implementation. | Provider choice is read for each model request; changing the selected model affects later requests without rewriting Campaigns. |

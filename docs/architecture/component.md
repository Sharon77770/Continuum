# Components and Modules

## Separation
- Desktop feature widgets render screens and forward user intent.
- Desktop Riverpod notifiers coordinate persisted world state, debounced edits and navigation-facing selections.
- `ScenarioTemplateCatalog` is an application-layer catalog of four ready-to-play scenarios. It creates a fresh World with new IDs for its character, location and lore on every selection; the create form passes template selection and user-edited summary fields to `WorkspaceController`.
- `features/models` owns the model catalog/selection contracts, AppData manifest repository, secure secret adapter, hardware probe, GGUF discovery/download adapters, llama.cpp binary installer/runtime manager, unified Novel provider adapter, controller, and consumer Models UI.
- `ManagedLanguageModel` is the only provider router. `novel_system` and campaign orchestration see only the `LlmProvider` contract. The local adapter starts the managed runtime only when a local model is requested.
- `OpenAiCompatibleProvider` bounds completion output to one eighth of the configured context limit (64–512 tokens) unless an internal caller provides a stricter cap; connection health checks cap output at 64 tokens.
- `LlamaRuntimeManager` launches the versioned executable by its managed absolute path. It applies the chosen CPU thread, context, and batch limits, reserves a loopback port, waits for the health endpoint, tracks process exit, exposes restartable status, and writes captured stdout/stderr to a separate bounded runtime log.
- `game_core` owns pure Dart world, lore, character, and location values. It has no Flutter dependency.
- `world_format` and `novel_system` are package boundaries only in this bootstrap.
- On a new database, the Library receives one playable sample World, `마지막 등대의 불빛`, with a Player, Opening, Character, Location, rules and a Lore entry. The one-time seed marker prevents it from returning after deletion or developer reset. Existing databases with Worlds are marked as initialized without inserting sample content.

## Contracts
Use typed Dart values between application state and domain. Keep view-only selection and form coordination in the desktop app. World persistence is accessed through the `WorldRepository` contract and SQLite adapter; widgets never execute SQL. Create & Play uses the saved, template-populated World and the same campaign generation/controller flow as New Game in Library. Model files and selection go through `ModelManagerRepository`; provider keys go through `SecretStore`; runtime process and binary operations go through their injectable contracts.

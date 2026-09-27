# Application Flows

## First launch
- Actor: application startup.
- Steps: initialize SQLite; in one transaction, check the persistent seed marker and World count; if this is a new empty database, insert the playable `마지막 등대의 불빛` sample and its definitions; then load Worlds into Library.
- Existing data: when a database already contains Worlds, mark first-run seeding complete without adding sample content.
- Repeat behavior: the marker remains after World deletion or Debug reset, so the sample is inserted only once per database.
- Errors: seed failure rolls back the sample and marker; initialization reports the local database failure.

## Open an existing world
- Actor: writer.
- Entry: Library world row.
- Steps: select a persisted world; desktop state selects it; navigate to Studio Overview.
- Validation and errors: DB initialization errors are surfaced in Library.
- Empty state: show the Library invitation to create a world.
- Side effects: reads the SQLite repository.

## Create a world
- Actor: writer/player.
- Entry: Create World in Library.
- Steps: either enter name, description, genre, and tone for a blank World, or select one of four built-in scenario templates. A selected template fills in the editable World description, genre, tone, rules, player, opening scene, one character, one starting location, and one lore entry. The writer may edit the name, description, genre, and tone before saving. Create World saves and opens Studio; Create & Play saves, creates a Campaign through the existing New Game flow, and opens Player.
- Validation: name is required; invalid submission stays on the form.
- Errors/retry: inline validation; persistence errors are shown and form values remain available.
- Side effects: SQLite transaction for the World; Create & Play additionally creates and saves a Campaign after the opening generation succeeds.

## Import or export a scenario
- Actor: writer.
- Entry: Import Scenario in Library, or Export Scenario in a World's action menu.
- Export writes a UTF-8 JSON file using the versioned `continuum-scenario` format. It contains the authored World, rules, lore, characters, locations, player definition, and opening definition; it does not include Campaign play history or local image assets.
- Import validates the format version, required fields, content IDs, location hierarchy, and opening references before creating a new World. World and content IDs are regenerated and internal references are remapped so the imported scenario is independent of existing Worlds.
- Cancelling either file picker makes no changes. Invalid or unsupported files and file/database failures leave existing Worlds unchanged and show a localized error.
- Side effects: import creates the World and authored definitions in one SQLite transaction; export writes only to the file selected by the writer.

## Edit Studio content
- Actor: writer.
- Entry: Studio section navigation.
- Steps: choose Overview, Lore, Characters, or Locations; edit selected content; notifier persists changes through repository. Overview edits debounce 650ms and are flushed before section change.
- Empty state: each collection offers an add action and an editor prompt.
- Errors/retry: repository errors are logged and shown as save failure; current edits remain visible.
- Side effects: SQLite writes.

## Duplicate or delete a world
- Duplicate creates new IDs for the world and every definition, then remaps location parents to copied locations.
- Delete requires explicit confirmation and cascades to rules, lore, characters and locations.

## New Game and Continue
- Actor: player.
- Entry: New Game or Continue on a Library World.
- New Game validates the Player name, starting Location, and Opening Situation. Starting Characters are optional, including when the World has no Characters; stale selected Character IDs left by older saves are ignored, and deleting a Character clears its starting reference. It initializes the runtime location/cast and requests a structured JSON opening scene (using the provider's JSON response mode when supported); validates speakers and fields; then atomically updates campaign JSON and shows the scene.
- NPC dialogue is optional on every turn. The dialogue field may be omitted or be an empty array; a scene can advance through narration, solitary observation, or environmental changes. The model must not invent a present NPC or player thoughts/actions, and may include the player's monologue only when the player explicitly chose it. When the player directly addresses a present NPC with a question, that NPC still responds using only known facts.
- Opening generation must establish the Player's identity, starting Location, reason for being there, and immediate situation in the first two sentences. It frames the authored purpose as why the Player arrived, without starting a current action the Player has not entered. If the authored opening contains a concise sentence that names the Player, Location, and purpose, the controller uses it to ground an otherwise incomplete generated opening; otherwise it retries.
- New Game displays a blocking progress overlay while the opening scene is generated and saved; the player cannot navigate to another screen during this startup. A failed request leaves the campaign uncommitted, clears the in-memory opening candidate, dismisses the overlay, and keeps the player on the prior screen with a retryable error. The Player screen opens only after the opening scene has been generated and saved successfully. Generation can be cancelled; cancellation does not commit. Invalid output is retried up to three times with a focused repair instruction. The parser extracts the first complete JSON object when a model adds trailing chatter. Repeated/action-echo narration gets a short narration-only repair; Korean question paraphrases and player agency are checked across common verb forms. Repeated NPC lines and dialogue that repeats the current or recent player action are dropped. If choices alone repeat, the valid scene is kept and suggestions from the attempts are merged; when the model offers no new options, localized actions based on the current location and visible character are offered. When a model returns one valid choice, the controller can combine it with another distinct choice from the same attempts before commit. Repaired player-facing text must pass the same player-agency and language checks before commit.
- Choice buttons and free input both call the same `PlayerAction` flow. Opening prompts are separated from turn-intent prompts. A successful response commits scene/history/world state and per-NPC relationship, emotion, goals, known facts and recent events after validation, then saves the Campaign. A model's proposed location alone cannot move the Player; an explicit movement action resolves the transition. NPC presence is carried forward within the same location, so a model cannot silently remove a character from the scene. Arrival at a different location resets presence unless the model supplies a validated cast, and explicit solo movement clears characters left behind. Regenerate uses the pre-turn snapshot and replaces the last candidate without applying it twice.
- NPC answers use only that character's public information and remembered facts. Model-proposed memory or world-state facts alone do not establish who holds an access card; holder questions require an authored fact or a prior NPC disclosure that names a holder. If a specific fact has no support, the NPC says they do not know; directly asking about an authored access-card loan reveals and records that secret. Short direct questions receive concise answers, and a directly addressed question retains an NPC response even when repetition filtering removes the model's line. Unknown replies vary against recent dialogue, and an NPC answer repeated for an unrelated question is replaced with an uncertainty response. An explicit refusal is retained as the player's decision; the NPC acknowledges it and the turn does not proceed as if the request had been accepted.
- An action that explicitly moves to a named World location updates the active location even if the model omits `sceneChanges.locationId`. Unless the action brings someone along, the new scene clears characters left behind, discards generated NPC dialogue for that solo scene, uses the destination's authored description, and offers actions for that location. Turns with no present Characters discard generated dialogue as well, so a model cannot reintroduce an absent speaker after Continue.
- Continue loads the selected World Campaign, restores its current scene, runtime state, history and Character memory. Library displays the most recently played Campaign for each World.
- Player presents the Campaign history as one chronological, scrollable conversation. Player actions and Character dialogue appear as named chat bubbles; narration is shown as plain story text on a subtly distinct background. New turns and Continue open at the latest transcript entry.
- LLM context is deterministic and bounded by a conservative multilingual estimate. System rules are sent as a separate `system` message; current Location, present Characters, memory, recent history, opening/world details and player action are sent as `user` context. Lower-priority Lore/history/memory is trimmed first. NPC answers must use recorded facts; a past sighting time is considered known only when character facts include a sighting, a concrete time expression, and the asked-about subject/place. Otherwise the NPC admits uncertainty. A direct question must not be returned to the player as a similar question, and sound-direction narration and answers are grounded in the NPC's recorded location facts. Suggested actions that repeat the player's question, are phrased as questions, or ask the player to relay information are discarded. Player-facing scene text is checked for internal World IDs, current and earlier repeated actions, and invented player actions or private thoughts. Repeated/action-echo repairs use localized observable fallbacks only after model repair fails, so a malformed scene does not block the turn. Output budgets scale with the configured context window, capped at 768 tokens for ordinary turns and 1,024 for openings; repeated-scene repair is capped at 768 tokens.

## Configure a language model
- Actor: player/developer.
- Entry: Library onboarding or Settings → Models.
- Device details: detect system memory, CPU architecture, graphics adapter, optional NVIDIA free VRAM, and free storage. If Windows device probing is unavailable, show unknown values and a space-check reminder while leaving installed models, discovery, import, and selection usable.
- Local: inspect the conservative RAM recommendation; the bundled catalog includes a 1.7B Q4_K_M model (about 1.28 GB download, estimated 2.5 GB runtime memory) for devices with at least 4 GB system memory, alongside 4B and 8B choices. Check free space; stream a single-file GGUF to a `.part` file; report bytes; remove the partial on cancel/failure; verify SHA-256 when the registry provides it; move the completed model into AppData and add its manifest record. Selecting a model stores it as the Story Model. Choose a persistent conservative, balanced, or performance profile for local CPU threads, context size, and prompt batch sizes; it applies on startup and restarts an already-running local model when changed. Runtime installation and loading are deferred until inference.
- Discover: query Hugging Face text-generation repositories; fetch file metadata; show only compatible single-file GGUF variants with known sizes; group variants by model; let the player choose smaller/recommended/higher quality; show raw file and quantization only in Advanced Details.
- Import: use the native file picker, require `.gguf` and the GGUF magic header, hash and copy it into AppData, then add it to On This Device. Unknown licenses remain labeled Unknown.
- Cloud: fetch the selected provider's model list to verify the API key; only after success store it in OS secure storage. OpenAI and Gemini keys use separate entries. Gemini requests use Google's OpenAI-compatible endpoint. Select an available model. No key appears in logs or regular UI after connection. Generation retries HTTP 408, 429, and 5xx responses, including provider error events inside an SSE stream, up to three times with 1, 2, and 4 second delays before content starts; once content has streamed, the request is not replayed.
- Custom: the advanced section retains base URL, model, and process-memory-only API key for developers. It is not the default provider flow.
- No-model state: Library Worlds and editors remain available. Starting a game routes to Models with a helpful message; after selecting a model, the player can start New Game from Library.
- Errors: distinguish missing model, incompatible GGUF, insufficient memory when reported by llama.cpp, insufficient disk space, checksum failure, download failure/cancellation, runtime startup/load failure, and runtime crash; show an action such as re-download, import another model, free disk/RAM, or retry. Provider/network exceptions are mapped to friendly messages so raw URLs and exception details stay out of the regular UI; runtime diagnostics remain in Developer Tools and the bounded runtime log.
- Runtime: on the first local request, install the official Windows x64 CPU package under AppData if absent; prefer the latest release and fall back to the first of the 20 newest official release records that contains the compatible binary when a stable release has no binary asset; require the GitHub release asset SHA-256; start the absolute managed executable on `127.0.0.1` and a dynamic port with model reasoning disabled so bounded output is available for the story; apply profile-specific CPU thread, context, and prompt batch limits; wait for health; capture stdout/stderr to a rotating 2 MiB log; stop the child on app shutdown. On Windows, the native runner intercepts WM_CLOSE and requests shutdown through the runtime lifecycle platform adapter; the adapter awaits child termination before authorizing the window to close. The app-exit callback and detached lifecycle remain fallback cleanup paths. Runtime crash changes status to failed and exposes a retry action in Models/Developer Tools. Classify reported allocation and GGUF architecture errors as insufficient memory or incompatible model.
- Advanced Developer Tools may show runtime version, status, selected model, PID, internal endpoint, system memory, model directory, and runtime log. Regular Models UI does not show server settings or protocol terms.

## Change application language
- Actor: writer.
- Entry: Settings button in Library or Studio.
- Steps: navigation records the current screen; Settings shows Korean, English, Simplified Chinese, and Japanese; selecting a language updates the app locale, bundled interface text, and Flutter standard widget text; the back button returns to the recorded screen.
- Validation and errors: only the four bundled language codes are accepted.
- Persistence: the selected UI language and default game language are stored in `language_preferences.json` under the app data directory. Startup loads and validates both before showing the main app; missing or invalid values default to English. Each setting change updates the UI immediately and writes the preference file.
- Game language: Settings has a separate story-language choice. New Game copies it to the Campaign; every generation and repair request instructs the model to write player-facing story fields in that language. Continue reads the Campaign language, so changing the default affects only new Campaigns. Older Campaign payloads default to English.
# Local developer tools

1. App startup resolves user-scoped paths, initializes persistent bounded logs and SQLite, and logs version/build/platform/path metadata without World content.
2. Settings → Developer reads DB schema/count/size information through the settings application controller and SQLite data service.
3. Integrity check executes read-only `PRAGMA integrity_check`; detailed errors are written to the local log.
4. Backup uses `VACUUM INTO` and reports the created file path.
5. Debug builds offer reset after explicit confirmation. Reset deletes Worlds through SQLite cascade, then reloads the workspace into the empty Library. Profile and Release hide reset.
6. The current World inspector serializes the in-memory domain value for display only; it does not write to persistence.

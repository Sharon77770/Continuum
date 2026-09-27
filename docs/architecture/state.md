# Application State

## State kinds
| State | Owner | Source of truth | Persisted | Notes |
| --- | --- | --- | --- | --- |
| Library worlds | Desktop application state | SQLite through `WorldRepository`, loaded by Riverpod notifier | Yes | A new database receives one playable sample World. Existing libraries are preserved without sample insertion. |
| Current world and editable lore/characters/locations | Desktop application state | SQLite domain values and Riverpod notifier | Yes | Overview changes debounce for 650ms; entity CRUD persists through repository. |
| Repository initialization/autosave | Desktop application state | Riverpod notifier | No | Loading/ready/failed and idle/saving/saved/failed UI status. |
| Selected Studio section and entry | Desktop presentation state | Widget/Riverpod selection | No | UI-only navigation state. |
| Selected application language | Desktop application state | Locale Riverpod notifier and `language_preferences.json` | Yes | Supports Korean, English, Simplified Chinese, and Japanese. Invalid or missing preferences default to English. |
| New game story language | Desktop application state, copied into Campaign | Game language Riverpod notifier and `language_preferences.json` | Yes | New Campaigns use the selected language; Continue and later turns retain the language saved with that Campaign. Older Campaign payloads default to English. |
| Settings return destination | Desktop application state | Riverpod navigation state | No | Restores the screen from which Settings was opened. |
| Current Campaign and generation | Novel application state | SQLite through `CampaignRepository` and Riverpod notifier | Yes, after validated turn commit | Generation is transient; cancellation/failure leaves committed Campaign unchanged. |
| Language model preferences | Novel settings / SQLite | `language_model_settings` row | Yes, except API key | API key stays in memory for the current process only. |
| Installed models and current Story Model | Model Manager application state | AppData model manifest and files | Yes | Campaigns do not pin a provider or model. Missing local files invalidate that local selection at load. |
| Model download | Model Manager application state | Downloader progress stream | No | Idle has no active model ID; downloading reports bytes/fraction; cancel removes the `.part` file; failure reports a recoverable message. |
| Local resource profile | Model Manager application state | AppData model manifest (`localResourceProfile`) | Yes | Defaults to balanced for existing installs; controls local CPU threads, context size, and batch sizes. |
| Runtime lifecycle | Runtime Manager | Managed child process and runtime manifest | Runtime version persists; process state does not | `notInstalled`, `stopped`, `starting`, `ready`, and `failed`; a crash is surfaced with a retry action. The chosen local resource profile is applied at launch. |
| Provider selection | Model Manager application state | AppData manifest | Yes | `local`, `openAi`, and `custom`; one selection applies to later model requests. |

## Domain values
- `WorldState`: current location and present characters plus optional time, atmosphere and relevant objects, durable facts, recorded events, and turn number. Validated narrative output may update scene fields; location and character IDs must belong to the Campaign's source World.
- `Campaign`: World association, timestamps, runtime WorldState, current SceneTurn, ordered history, and per-character memory.
- `CharacterMemory`: per-character known facts and important memories plus persistent relationship, current emotion, goals and recent events. Only memories for NPCs in the active scene are included in that turn's context.
- `SceneTurn`: narration, character dialogue, generated choices, optional player action, and creation time.
- `PlayerAction` and `GameEvent`: player input and committed state-change events.
- Candidate output does not mutate state; validated commit updates Campaign then persists it.
- `ModelQuality`: `fast` is the smaller-memory recommendation, `balanced` is the recommended balance, and `higherQuality` chooses the largest discovered compatible single-file GGUF variant.
- `RuntimeStatus`: `notInstalled` means no managed runtime is known, `stopped` means installed/not running, `starting` means binary or model loading, `ready` means the health endpoint responds, and `failed` means the managed process or load did not complete. Failed state can be retried or stopped.
- `ModelProviderKind`: `local` reads an installed GGUF, `openAi` and `gemini` read their separately stored secure API keys and provider model IDs, and `custom` uses the advanced compatible endpoint stored in Novel settings.

## State transitions
| From | To | Trigger | Validator | Side effects |
| --- | --- | --- | --- | --- |
| Library | Studio | Open or create world | Desktop state selects/creates a persisted world | Reads or inserts SQLite rows |
| Library | Library | Duplicate or delete | Repository transaction and delete confirmation | Copies definitions with new IDs or cascades delete |
| Studio section | Another Studio section | Select navigation item | None | None |
| Library | Player | New Game | Player/opening/location validation and structured provider result validation | Initialize and persist Campaign after first valid scene |
| Library | Player | Continue | Campaign ID exists in SQLite | Restore current scene and runtime state |
| Player | Player | Select choice or submit free text | Generation idle and nonempty action | Generate, validate, commit and autosave a scene turn |
| Any main screen | Settings | Select settings button | Navigation controller records return destination | None |
| Settings | Previous main screen | Select back button | Navigation controller reads return destination | None |
| Selected language | Another supported language | Select language option | Locale controller accepts `ko`, `en`, `zh`, or `ja` | Rebuilds localized app UI |
| New game story language | Another supported language | Select story language in Settings | Game language controller accepts `ko`, `en`, `zh`, or `ja` | Future Campaigns snapshot it; generated text uses that language |

No authentication state exists.

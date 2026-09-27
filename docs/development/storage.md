# Local storage and developer tools

## Path policy

Windows Profile and Release builds use the existing per-user directory `%APPDATA%\Continuum`, preserving current World data. Debug builds use `%APPDATA%\Continuum-Dev` so the Debug-only destructive reset cannot remove user data used by Release. The active absolute paths are shown in Settings → Developer.

| Item | Debug path | Profile / Release path |
| --- | --- | --- |
| Data root | `%APPDATA%\Continuum-Dev` | `%APPDATA%\Continuum` |
| SQLite database | `%APPDATA%\Continuum-Dev\continuum.sqlite3` | `%APPDATA%\Continuum\continuum.sqlite3` |
| Logs | `<data root>\logs\continuum.log` and one rotated `.1` file | `<data root>\logs\continuum.log` and one rotated `.1` file |
| Backups | `<data root>\backups\continuum-<UTC timestamp>.db` | `<data root>\backups\continuum-<UTC timestamp>.db` |
| Temporary files | `<data root>\temp` | `<data root>\temp` |

On macOS and Linux, `AppPaths` uses the conventional user Application Support or XDG data root, with the same Debug suffix policy. User data is never stored in the repository or beside the executable. The current DB stays at the data root for compatibility; `databaseDirectory` is the same root until a deliberate, documented migration is needed.

## Inspect and back up

Settings → Developer displays the exact database path, database size, SQLite schema version, and World/Character/Lore/Location counts. Use **Copy database path** or **Open data directory** to locate the file. **Open log directory** opens the folder containing persistent logs. Logs include startup/build/path and persistence event metadata, plus error details and stack traces; they do not include World body text or Character secrets.

Use **Run integrity check** to run SQLite's read-only `PRAGMA integrity_check`. Use **Back up database** to create a consistent snapshot with SQLite `VACUUM INTO` while the live database is open. The returned path appears in Developer Tools; open the backups folder to copy it elsewhere. Backups are manual and are not automatically pruned.

The active log is bounded to about 1 MiB; when it reaches the limit it is rotated to `continuum.log.1`, replacing the previous rotated file.

## Reset development data

Settings → Developer exposes Reset development data only in Debug builds. The confirmation dialog states that local Worlds are permanently deleted. Cancel to keep data; confirm to delete Worlds and their dependent records and return to an empty Library. Make a manual backup first if the data matters. Release and Profile builds do not expose this action.

Automated storage tests use isolated temporary directories and never open the user's actual AppData database.

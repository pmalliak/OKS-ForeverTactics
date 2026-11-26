# OKS Forever Tactics

A World of Warcraft: Forever addon from **One Knight Stands**. A pocket reference
for dungeon bosses and trash: their abilities, short tactics and known tricks,
opened from a journal window (`/ft`) or from a button on the target frame.

## Layout

- The repo root is the addon (toc, Lua, `Data/`). The CurseForge packager zips it
  as `ForeverTactics` on every tag (see `.pkgmeta`); `tools/`, `data-src/` and
  `docs/` stay out of the package.
- `data-src/*.json` is the source data. Never edit `Data/` by hand: run
  `python tools/build_data.py` to rebuild it.
- `tools/tactics/part*.py` hold our own-words tactics, merged into `data-src`
  by `tools/apply_tactics.py`.
- `docs/api-findings.md` records what `/ft diag` shows in game.
- `CLAUDE.md` holds the project rules, `HANDOFF.md` the original design.

## Releasing

Add a line to `CHANGELOG.md`, push to `main`, then create a tag `vX.Y.Z` on
`main` (GitHub > Releases > Draft a new release). The CurseForge webhook builds
the zip from the tag.

## Commands

- `/ft` opens or closes the journal. `/ft help` lists commands.
- `/ft button reset` puts the target button back. Shift+drag moves it.
- `/ft diag <label>` records API facts for the current target and place.
- `/ft diag copy` opens a window with all saved runs to copy.
- `/ft diag clear` deletes saved runs.

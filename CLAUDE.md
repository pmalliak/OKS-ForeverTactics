# ForeverTactics (working title)

A World of Warcraft: Forever addon. It shows the abilities of dungeon and raid
bosses and trash mobs, plus short community tactics for handling them (including
known shortcuts and "cheese" tricks). Two entry points: a journal window, and a
button on the target frame that opens the page for the mob you have targeted.

Full research, design and task list: see `HANDOFF.md`. Read it before writing code.

## Target client

- World of Warcraft: Forever (launched 2026-11-04), client version 1.60.1.
- TOC file: `ForeverTactics_Forever.toc` ("Forever" is an accepted alias of the
  internal name "Camelot").
- Interface number: 16001 was used by beta addons. Confirm in game with
  `/dump (select(4, GetBuildInfo()))` before release.
- Forever uses the modern retail (Mainline 12.1.5 era) UI and API, NOT the
  Classic Era API. Do not copy Classic Era addon patterns without checking them.

## Hard constraints (Midnight "secret values" apply in Forever)

- Unit identity (`UnitName`, `UnitGUID`) of NPCs can be a secret value, reported
  as "while in combat". Addon code cannot compare, index, concatenate-and-branch,
  or use a secret as a table key. Always guard with `issecretvalue(v)` or
  `C_Secrets.ShouldUnitIdentityBeSecret(unit)` before touching identity values.
- Assume no combat log access for addons. All mob and ability data ships with the
  addon as static Lua tables. No auto-learning from combat.
- Inside instances, chat is secret and addon comms to other players are blocked.
  Any note sharing must work outside instances (export and import strings).
- Never build anything that reacts to combat state to make decisions for the
  player. This addon is a reference book only.

## Conventions

- Lua 5.1 as embedded by WoW. No external runtime dependencies in v1.
- One addon-private namespace table (`local ADDON, ns = ...`). No new globals
  except the SavedVariables table and slash command globals.
- Data lives in `Data/` as generated Lua, one file per instance. Human-edited
  source lives in `data-src/` (YAML or JSON) and is compiled by a script in
  `tools/`. Never hand-edit generated files.
- Every tactic and trick is written in our own words. Do not paste text from
  Wowhead, Icy Veins, Warcraft Tavern or other guides.
- Every trick carries a `kind`: `clever-use`, `bug-abuse`, or `unverified`, and
  the client build it was last confirmed on.
- No em dashes in user-facing strings, docs, or commit messages.

## Verify, do not assume

Anything marked "UNVERIFIED" in `HANDOFF.md` must be tested in game (use the
`/ft diag` command described there) or checked against warcraft.wiki.gg before
code depends on it. When the wiki and in-game behavior disagree, the game wins.

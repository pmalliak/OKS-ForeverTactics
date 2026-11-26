# ForeverTactics: handoff brief

Research done 2026-11-24 and 2026-11-25 in a Claude chat, handed to Claude Code
to build. Items tagged VERIFIED come from the sources listed at the bottom.
Items tagged UNVERIFIED are assumptions that need an in-game test first.

## 1. What the owner wants

- Have the abilities of every boss and dungeon mob available in game.
- Next to each, a short guide on how players usually handle the mechanics,
  including easy ways and known tricks (example given: resetting the last boss
  of UBRS, General Drakkisath, to deal with his adds separately).
- Form: a journal, and also a button that appears when a boss is targeted so the
  page can be opened and read right away.

## 2. Feasibility summary

Feasible. The only real limit is the target button during combat.

- VERIFIED: Forever shares Mainline WoW's UI architecture, with the vast majority
  of 12.1.5 APIs available.
- VERIFIED: Blizzard stated (2026-09-15) that the Midnight addon disarmament
  changes, including secret values, are active in Forever.
- VERIFIED: `UnitName` and `UnitGUID` carry the `SecretWhenUnitIdentityRestricted`
  predicate. The wiki describes `UnitName` as returning secrets for non-player
  and pet units while in combat.
- VERIFIED: `C_Secrets.ShouldUnitIdentityBeSecret(unit)` returns whether identity
  queries for that unit will be secret. `issecretvalue(v)` tests a value.
- VERIFIED: tainted (addon) code may store secrets and pass them to functions,
  but may not compare them, do arithmetic, use `#`, index them, or use them as
  table keys.
- VERIFIED: creature GUIDs keep their format, but the server ID and spawn ID
  parts are obfuscated (Beta 5). The NPC ID segment should still parse.
  UNVERIFIED that the NPC ID segment is untouched: test it.
- VERIFIED: target, player, pet, focus and target-of-target frames were reskinned
  in Beta 5 and some child frames reorganized. Anchor the button defensively.
- VERIFIED: in instances, chat messages are secret and addons cannot send comms
  to other players.
- UNVERIFIED (believed from Midnight): combat log events are not delivered to
  addons, so abilities cannot be learned automatically in game.
- UNVERIFIED: whether identity is secret only inside encounters and instances,
  or in any combat. One source says "restricted content (arenas, battlegrounds,
  enclosed encounters)", the wiki says "in combat".
- UNVERIFIED: whether `C_EncounterJournal` returns useful data in Forever. One
  addon (Chronicle Forever) shows "available encounter journal data" and falls
  back to previews when it is missing, which suggests partial data at best.
- UNVERIFIED: whether `ENCOUNTER_START` fires with a readable encounter ID.
- UNVERIFIED: AddOns folder. One guide says `World of Warcraft\_forever_\Interface\AddOns`,
  another says Forever shared the retail AddOns folder during beta. Check the
  local install.

## 3. Existing addons (check before building, and to find the gap)

All are on CurseForge and target Forever:

- Absolute Journal: bosses in kill order, abilities, strategy tips, 3D model,
  loot, quests, auto-jump to current instance.
- Dungeon Codex: Adventure Guide style, maps with boss markers, boss abilities
  with who they target and how to handle them, loot with drop chances.
- DFL Dungeon Journal: quests, loot compare, maps.
- Ajax Journal: continues "Lootified" (GPL-3.0), uses data from
  ForeverDungeonJournal by Exehn with permission.
- DungeonMaster: quests, bosses, loot, rare spawns.
- BrokenCodex: boss and loot data from brokenmeta.gg.

None of their pages advertise: trash mob abilities, shortcut or cheese tricks,
or a button on the target frame. That is the niche. Loot and quests are well
covered already, so leave them out of v1.

## 4. Proposed design

### Data model (static Lua, generated)

```lua
ns.Data.instances[instanceKey] = {
  name = "Upper Blackrock Spire",
  mapIDs = { ... },          -- for auto-open by location
  order = { npcID, npcID },  -- display order
}
ns.Data.npcs[npcID] = {
  name = "General Drakkisath",
  instance = instanceKey,
  kind = "boss",             -- boss | trash | rare
  abilities = {
    { spellID = 0, name = "...", tags = { "tank", "avoid", "interrupt", "dispel:magic" }, note = "..." },
  },
  tactics = { general = "...", tank = "...", healer = "...", dps = "..." },
  tricks = {
    { title = "...", text = "...", kind = "clever-use", confirmedBuild = "1.60.1.70938" },
  },
}
```

Key everything by NPC ID, never by name (names are localized and can be secret).

### UI

- Journal window: instance list, mob list (bosses first, then trash), detail pane
  with Abilities, Tactics, Tricks, My notes. Movable, closes with Escape.
- Slash command `/ft`, keybinding, and an optional minimap or LDB button.
- Auto-select the current instance when opened inside one.
- Target button: small button anchored to the target frame.
  - On `PLAYER_TARGET_CHANGED`, if identity is not secret, parse the NPC ID from
    the GUID. If it is in the database, show the button and remember the ID.
  - If identity is secret (combat), do not try to read it. Keep the last
    remembered mob if the target has not changed, otherwise show a generic
    button that opens the current instance page.
  - The button only toggles our own non-protected frame, which should be legal
    in combat. UNVERIFIED: confirm no taint from anchoring to TargetFrame.
- Optional later: a tooltip line "Tactics available" on mobs in the database.

### User content

- "My notes" per NPC, stored in account-wide SavedVariables.
- Export and import of notes as a text string, so groups can share outside
  instances.

### Data pipeline

- `data-src/` holds one YAML or JSON file per instance, hand-edited.
- `tools/build_data` compiles it into `Data/*.lua` and validates: every NPC has
  an ID, every trick has a kind, spell IDs are numbers.
- Later: a helper that pulls spell names for given IDs from a wago.tools DB2 CSV
  export for the current Forever build.

## 5. Where the data comes from

Abilities (facts):
- Wowhead's Forever section: NPC pages list abilities.
- wago.tools DB2 browser, filtered by Forever build (tables such as Spell and
  SpellName). Example URL form:
  `https://wago.tools/db2/SpellName?build=1.60.1.69977&filter[ID]=<id>`
- warcraft.wiki.gg for dungeon and boss pages.
- Caveat: Blizzard deliberately hid or obfuscated parts of Forever's database to
  protect discovery, so datamined data has gaps. Expect manual work.
- Classic Era data is a starting point only. Forever is not a 1:1 copy.

Tactics and tricks (knowledge):
- Classic Era dungeon guides as a baseline (Warcraft Tavern, Icy Veins, Wowhead
  guides and NPC page comments).
- Reddit, YouTube runs, class Discords, and the owner's own dungeon runs.
- Rule: rewrite in our own words, keep it short, and confirm every trick in
  Forever before marking it anything other than `unverified`. Tricks that abuse
  bugs get the `bug-abuse` label because they get hotfixed and can lead to
  action against players.

## 6. First tasks for Claude Code, in order

1. Scaffold: `ForeverTactics_Forever.toc`, `Core.lua`, folder layout from
   CLAUDE.md, a `.luacheckrc`, and a README. Get it loading in game.
2. Build `/ft diag`, a diagnostics command that prints, for the current target
   and situation: `GetBuildInfo()`, `GetInstanceInfo()`, `InCombatLockdown()`,
   `C_Secrets.ShouldUnitIdentityBeSecret("target")`,
   `issecretvalue(UnitGUID("target"))`, the parsed NPC ID when readable, and
   whether `C_EncounterJournal` exists and returns instances. The owner runs it
   in the open world, in a dungeon out of combat, on trash in combat, and on a
   boss in combat. Record results in `docs/api-findings.md`. This settles every
   UNVERIFIED item in section 2 before the design is locked.
3. Data schema plus one full hand-authored instance as the sample (suggest
   Ragefire Chasm for size, or UBRS because of the Drakkisath example).
4. Journal window.
5. Target button, using the findings from task 2.
6. My notes, export and import.
7. Data build script and validation.
8. Packaging for CurseForge and Wago (`.pkgmeta`, BigWigs packager, release
   workflow).

Dev loop tips: `/reload` after changes, `/console scriptErrors 1`, BugSack and
BugGrabber for errors, `/fstack` to inspect frames, `/etrace` for events, `/api`
for in-game API docs. For editor support, use Lua Language Server with WoW API
annotations.

## 7. Kickoff prompt to paste into Claude Code

> Read CLAUDE.md and HANDOFF.md. Then do tasks 1 and 2 from HANDOFF.md section 6:
> scaffold the addon and build the `/ft diag` command. Before writing code that
> uses an API, check its current signature on warcraft.wiki.gg, because Forever
> uses the Midnight-era API with secret values. Tell me exactly where to copy the
> addon folder and what to run in game, then stop so I can report the results.

## 8. Sources

- Forever API notes: https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes
- Secret values: https://warcraft.wiki.gg/wiki/Secret_aspects
- `C_Secrets.ShouldUnitIdentityBeSecret`: https://warcraft.wiki.gg/wiki/API_C_Secrets.ShouldUnitIdentityBeSecret
- `UnitGUID`: https://warcraft.wiki.gg/wiki/API:UnitGUID
- TOC format: https://warcraft.wiki.gg/wiki/.toc
- Midnight API change notes: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes
  and https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes/notes
- Forever overview: https://warcraft.wiki.gg/wiki/WoW_Forever
- Hidden data in Forever (and wago.tools examples): https://www.icy-veins.com/wow-forever/news/blizzard-hid-wow-forevers-first-legendary-but-dataminers-already-found-clues/
- Addon guides with conflicting install paths: https://gamertagmythras.com/blog/world-of-warcraft/wow-forever-addons-guide
  and https://epiccarry.com/blogs/?p=41550
- Existing addons: https://www.curseforge.com/wow/addons/absolute-journal ,
  https://www.curseforge.com/wow/addons/dungeon-codex ,
  https://www.curseforge.com/wow/addons/dfl-dungeon-journal ,
  https://www.curseforge.com/wow/addons/ajax-journal ,
  https://www.curseforge.com/wow/addons/dungeonmaster ,
  https://www.curseforge.com/wow/addons/brokencodex ,
  https://www.curseforge.com/wow/addons/chronicle-forever

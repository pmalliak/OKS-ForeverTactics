# API findings from /ft diag

## Run 1: 2026-11-25, Stormwind Stockade, boss targeted, OUT of combat

Client 1.60.1.71091 (Nov 20 2026), interface 16001 (TOC value is correct).

| Check | Result |
|---|---|
| GetInstanceInfo | works: "Stormwind Stockade", type party, instanceID 34 |
| C_Map.GetBestMapForUnit("player") | nil inside the dungeon |
| InCombatLockdown / in combat | false / false |
| ShouldUnitIdentityBeSecret("target") | true, even out of combat |
| UnitGUID / UnitName (target) | secret, so no NPC ID |
| UnitClassification / UnitLevel | readable: elite, 24 |
| EJ_GetNumTiers | 0, so no encounter journal data |
| ENCOUNTER_START | not seen (boss not pulled yet) |
| Target changes | 13, of which 7 had a secret GUID |
| COMBAT_LOG_EVENT_UNFILTERED | registering it is a blocked action (popup in 0.1.0) |

### Conclusions

- Inside dungeons, NPC identity is secret all the time, not only in combat.
  The target button can never know which mob is targeted inside an instance.
- Instance ID from GetInstanceInfo is readable and is the reliable key for
  "open the page for where I am". Use instanceID, not mapID.
- Level and classification are readable and can rank likely mobs.
- No encounter journal data and no combat log: all data must ship with the addon.

### Still open

- Open world: is identity readable out of combat? (Run /ft diag world on a
  normal NPC outside.)
- Does ENCOUNTER_START fire with a readable encounter ID on a boss pull?
- Can a FontString:SetText show a secret name (to label the button)?

## Run 2: 2026-11-25, Stockade, right after pulling Targorr the Dread

- InCombatLockdown true; identity still secret (same as out of combat).
- ENCOUNTER_START fires with READABLE args: `2756, "Targorr the Dread", 1, 5`
  (encounterID, encounterName, difficultyID, groupSize).

### Conclusion

During a boss fight we know exactly which boss it is: key bosses by
encounterID (and fall back to the encounter name). The target button switches
to that boss on ENCOUNTER_START and back to the dungeon page on ENCOUNTER_END.
The addon also records every encounterID and name it sees in SavedVariables,
so the IDs for other dungeons can be collected by simply playing.

## Run 3: 2026-11-25, open world (Stormwind), Stockade Guard, out of combat

- ShouldUnitIdentityBeSecret false; GUID and name readable.
- GUID `Creature-0-64354-0-7499553-4995-ABF55CC15C`: NPC ID segment (4995) parses.
- mapID 1453 readable outside instances.
- ENCOUNTER_END args: `encounterID, name, difficultyID, groupSize, success, <table>`.

### Conclusion

Open world: identify mobs by NPC ID (works for world bosses, elites, rares).
Instances: identity always secret; use instanceID + level/classification
guess, and the encounterID during boss fights.

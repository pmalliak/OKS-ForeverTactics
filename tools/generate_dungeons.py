#!/usr/bin/env python3
"""Generate data-src/<dungeon>.json for every Classic 5-man dungeon from the
CMaNGOS classic-db world database, then fill stats and timings with
import_classic_stats.py.

Hand-written content already in data-src (tactics, tricks, tags, notes,
phases, encounter IDs) is kept: only facts are refreshed.

Usage:
  python tools/generate_dungeons.py classic-db/Full_DB/ClassicDB_*.sql.gz
"""
import gzip
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_classic_stats as ics  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data-src"

# key, name, map ID (= instanceID from GetInstanceInfo)
DUNGEONS = [
    ("ragefire", "Ragefire Chasm", 389),
    ("deadmines", "The Deadmines", 36),
    ("wailing", "Wailing Caverns", 43),
    ("shadowfang", "Shadowfang Keep", 33),
    ("blackfathom", "Blackfathom Deeps", 48),
    ("stockade", "Stormwind Stockade", 34),
    ("gnomeregan", "Gnomeregan", 90),
    ("kraul", "Razorfen Kraul", 47),
    ("scarlet", "Scarlet Monastery", 189),
    ("downs", "Razorfen Downs", 129),
    ("uldaman", "Uldaman", 70),
    ("zulfarrak", "Zul'Farrak", 209),
    ("maraudon", "Maraudon", 349),
    ("sunken", "Sunken Temple", 109),
    ("brd", "Blackrock Depths", 230),
    ("brs", "Blackrock Spire", 229),
    ("diremaul", "Dire Maul", 429),
    ("scholomance", "Scholomance", 289),
    ("stratholme", "Stratholme", 329),
]
RARE_RANKS = {"2", "4"}
CRITTER = "8"


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    with gzip.open(sys.argv[1], "rt", encoding="utf-8", errors="replace") as f:
        sql = f.read()
    tmpl = ics.rows(sql)
    spawns = ics.rows(sql, "creature", key=None)
    inst_tmpl = ics.rows(sql, "instance_template", key="map")
    encounters = ics.rows(sql, "instance_encounters", key=None)
    ai = {}
    for ev in ics.rows(sql, "creature_ai_scripts", key=None):
        ai.setdefault(int(ev["creature_id"]), []).append(ev)

    per_map = {}
    for s in spawns:
        per_map.setdefault(int(s["map"]), Counter())[int(s["id"])] += 1
    boss_order = {}
    for e in sorted(encounters, key=lambda e: int(e["entry"])):
        if e["creditType"] == "0":
            boss_order.setdefault(int(e["creditEntry"]), int(e["entry"]))

    # Prefetch spell names and icons for every cast in these dungeons.
    from concurrent.futures import ThreadPoolExecutor
    want = set()
    for _, _, mapid in DUNGEONS:
        for entry in per_map.get(mapid, {}):
            for ev in ai.get(entry, []):
                for a in (1, 2, 3):
                    if int(ev[f"action{a}_type"]) == ics.ACT_CAST:
                        want.add(int(ev[f"action{a}_param1"]))
    want -= set(ics._spell_cache)
    print(f"fetching {len(want)} spells")
    with ThreadPoolExecutor(12) as ex:
        list(ex.map(ics.spell_info, sorted(want)))

    # Encounter bosses that are summoned by scripts have no spawn row. Place
    # them with the zone Wowhead reports for the NPC.
    import urllib.request

    def npc_zone(entry):
        try:
            url = f"https://nether.wowhead.com/forever/tooltip/npc/{entry}"
            with urllib.request.urlopen(url, timeout=15) as r:
                return (json.load(r).get("map") or {}).get("zone")
        except Exception:
            return None

    placed = {e for m in per_map.values() for e in m}
    unplaced = [e for e in boss_order if e not in placed and e in tmpl]
    zone_of_map = {}
    for _, _, mapid in DUNGEONS:
        ref = next((e for e in boss_order if e in per_map.get(mapid, {})), None)
        if ref:
            zone_of_map[npc_zone(ref)] = mapid
    with ThreadPoolExecutor(12) as ex:
        zones = dict(zip(unplaced, ex.map(npc_zone, unplaced)))
    extra_bosses = {}
    for e, z in zones.items():
        if z in zone_of_map:
            extra_bosses.setdefault(zone_of_map[z], set()).add(e)
            per_map.setdefault(zone_of_map[z], Counter())[e] += 0
    print(f"placed {sum(len(v) for v in extra_bosses.values())} of {len(unplaced)} summoned bosses by zone")
    for ex_map, ents in extra_bosses.items():
        for e in ents:
            for ev in ai.get(e, []):
                for a in (1, 2, 3):
                    if int(ev[f"action{a}_type"]) == ics.ACT_CAST:
                        ics.spell_info(int(ev[f"action{a}_param1"]))

    SRC.mkdir(exist_ok=True)
    for key, name, mapid in DUNGEONS:
        path = SRC / f"{key}.json"
        old = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        old_npcs = {n["id"]: n for n in old.get("npcs", [])}
        counts = per_map.get(mapid, Counter())
        # Bosses: encounter credit creatures spawned here, plus hand-listed ones.
        npcs = []
        for entry in set(counts) | {i for i, n in old_npcs.items()}:
            t = tmpl.get(entry)
            if not t:
                continue
            is_boss = (entry in boss_order and entry in counts) or old_npcs.get(entry, {}).get("kind") == "boss"
            rank = t["Rank"]
            if not is_boss:
                if t["CreatureType"] == CRITTER or int(t["NpcFlags"]) != 0:
                    continue
                if rank == "0" and entry not in old_npcs:
                    continue  # non-elites inside dungeons are mostly summons and critters
            kind = "boss" if is_boss else ("rare" if rank in RARE_RANKS else "trash")
            n = dict(old_npcs.get(entry, {}))
            n.update({
                "id": entry,
                "name": t["Name"],
                "kind": n.get("kind", kind) if entry in old_npcs else kind,
                "level": [int(t["MinLevel"]), int(t["MaxLevel"])],
                "displayID": int(t["ModelId1"]) or None,
            })
            if t["SubName"]:
                n["subName"] = t["SubName"]
            n.setdefault("abilities", [])
            n.setdefault("tricks", [])
            if is_boss and entry in boss_order:
                n["_order"] = boss_order[entry]
            npcs.append({k: v for k, v in n.items() if v is not None})

        kind_rank = {"boss": 0, "rare": 1, "trash": 2}
        npcs.sort(key=lambda n: (kind_rank[n["kind"]], n.get("_order", 0), n["level"][0], n["name"]))
        for n in npcs:
            n.pop("_order", None)
        it = inst_tmpl.get(mapid, {})
        lv = [n["level"][0] for n in npcs] + [n["level"][1] for n in npcs]
        data = {
            "key": key,
            "name": name,
            "instanceID": mapid,
            "levels": old.get("levels") or ([min(lv), max(lv)] if lv else [int(it.get("levelMin", 0)), int(it.get("levelMax", 0))]),
        }
        for k in ("summary", "tricks"):
            if k in old:
                data[k] = old[k]
        data.setdefault("tricks", [])
        data["npcs"] = npcs
        for n in npcs:
            r = tmpl[n["id"]]
            n["stats"] = ics.stats_for(r, n.get("stats"))
            if n["id"] in ai:
                ics.apply_ai(n, sorted(ai[n["id"]], key=lambda e: int(e["id"])))
            if r["AIName"] != "EventAI" and r["ScriptName"]:
                n["scripted"] = True  # abilities live in C++ scripts, not in the DB
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        nb = sum(1 for n in npcs if n["kind"] == "boss")
        print(f"{key}: {nb} bosses, {len(npcs) - nb} other mobs")
    json.dump({str(k): v for k, v in ics._spell_cache.items()}, open(ROOT / "tools" / ".spell_cache.json", "w"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

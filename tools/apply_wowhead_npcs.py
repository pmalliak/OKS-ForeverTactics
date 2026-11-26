"""Merge Wowhead Forever NPC page facts (displayId, ability list, health) into data-src.

Usage: python tools/apply_wowhead_npcs.py npcs.json
npcs.json: {"<npcID>": {"d": "<displayId>", "hp": "<health or null>", "ab": ["<spellID>:<name>", ...]}}
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import import_classic_stats as ics  # noqa: E402

SKIP = {"Dazed", "Dual Wield", "Defensive Stance", "Battle Stance", "Berserker Stance"}


def main():
    src = {int(k): v for k, v in json.load(open(sys.argv[1])).items()}
    for f in sorted((ROOT / "data-src").glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        changed = False
        for n in d["npcs"]:
            w = src.get(n["id"])
            if not w:
                continue
            changed = True
            if w.get("d") and not n.get("displayID"):
                n["displayID"] = int(w["d"])
            if w.get("hp"):
                st = n.setdefault("stats", {})
                st["health"] = int(w["hp"])
                st["healthSource"] = "wowhead-forever"
            have = {a.get("spellID") for a in n.setdefault("abilities", [])}
            for item in w.get("ab", []):
                sid, name = item.split(":", 1)
                sid = int(sid)
                if sid in have or name in SKIP:
                    continue
                info = ics.spell_info(sid)
                n["abilities"].append({"name": info[0] if info else name, "spellID": sid,
                                       "icon": info[1] if info else "INV_Misc_QuestionMark",
                                       "source": "wowhead-forever"})
                have.add(sid)
        if changed:
            f.write_text(json.dumps(d, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    ics._CACHE_FILE.write_text(json.dumps({str(k): v for k, v in ics._spell_cache.items()}))


if __name__ == "__main__":
    main()

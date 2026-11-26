"""Add NPCs that the Forever journal lists but our CMaNGOS spawn scan missed.

Usage: python tools/add_journal_npcs.py creature_template.json ai.json
(both are JSON dumps of the CMaNGOS classic-db tables).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import import_classic_stats as ics  # noqa: E402

ADD = {
    "shadowfang": {3864: "boss", 3865: "boss"},
    "kraul": {4425: "rare"},
    "sunken": {5712: "boss", 5713: "boss", 5714: "boss", 5715: "boss", 5716: "boss", 5717: "boss"},
    "scarlet": {6488: "rare", 6489: "rare", 6490: "rare"},
    "uldaman": {6907: "boss", 6908: "boss"},
    "downs": {7356: "boss"},
    "zulfarrak": {7604: "boss"},
    "brd": {8923: "rare", 8929: "boss", 9027: "boss", 9028: "boss", 9029: "boss", 9030: "boss",
            9031: "boss", 9032: "boss", 9034: "boss", 9036: "boss", 9037: "boss", 9038: "boss",
            9039: "boss", 9040: "boss"},
    "brs": {10339: "boss", 16080: "boss"},
    "stratholme": {11058: "boss", 11143: "boss"},
    "diremaul": {14354: "boss", 14506: "boss", 16097: "boss"},
    "scholomance": {16118: "boss"},
}


def main():
    tmpl = json.load(open(sys.argv[1]))
    ai = {}
    for ev in json.load(open(sys.argv[2])):
        ai.setdefault(int(ev["creature_id"]), []).append(ev)
    for key, ids in ADD.items():
        path = ROOT / "data-src" / f"{key}.json"
        d = json.loads(path.read_text(encoding="utf-8"))
        have = {n["id"] for n in d["npcs"]}
        for entry, kind in ids.items():
            if entry in have:
                continue
            t = tmpl.get(str(entry))
            if not t:
                print("not in classic-db:", entry)
                continue
            n = {"id": entry, "name": t["Name"], "kind": kind,
                 "level": [int(t["MinLevel"]), int(t["MaxLevel"])],
                 "displayID": int(t["ModelId1"]) or None,
                 "abilities": [], "tricks": []}
            if t.get("SubName") and t["SubName"] != "NULL":
                n["subName"] = t["SubName"]
            n = {k: v for k, v in n.items() if v is not None}
            n["stats"] = ics.stats_for(t, None)
            if entry in ai:
                ics.apply_ai(n, sorted(ai[entry], key=lambda e: int(e["id"])))
            if t.get("AIName") != "EventAI" and t.get("ScriptName"):
                n["scripted"] = True
            d["npcs"].append(n)
            print(key, "added", entry, t["Name"], kind)
        rank = {"boss": 0, "rare": 1, "trash": 2}
        d["npcs"].sort(key=lambda n: rank[n["kind"]])  # stable: keeps boss order
        path.write_text(json.dumps(d, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

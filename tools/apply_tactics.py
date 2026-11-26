"""Merge own-words tactics (tools/tactics/part*.py) into data-src/*.json.

The tactics were written by us after reading the WoW Forever dungeon journal;
no journal text is copied. Hand-written tactics already in data-src win.
Abilities named in the tactics but missing from an NPC are added (name and
icon from Wowhead's Forever tooltip API).
"""
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import import_classic_stats as ics  # noqa: E402

EXTRA_TRICKS = {
    639: [("Stun him at half health", "If VanCleef is stunned at the moment he reaches 50%, the second pair of Blackguards never shows up. Have a stun ready around 51-55%.", "unverified")],
}


def load_parts():
    out = {}
    for p in sorted((ROOT / "tools" / "tactics").glob("part*.py")):
        spec = importlib.util.spec_from_file_location(p.stem, p)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        out.update(m.T)
    return out


def main():
    T = load_parts()
    used = set()
    for f in sorted((ROOT / "data-src").glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        changed = False
        for npc in d["npcs"]:
            t = T.get(npc["id"])
            if not t:
                continue
            used.add(npc["id"])
            changed = True
            if not npc.get("tactics"):
                tac = {"general": t["g"]}
                for k, name in (("t", "tank"), ("h", "healer"), ("d", "dps")):
                    if t.get(k):
                        tac[name] = t[k]
                npc["tactics"] = tac
            tricks = npc.setdefault("tricks", [])
            have = {x["title"] for x in tricks}
            for title, text, kind in list(t.get("tr", [])) + EXTRA_TRICKS.get(npc["id"], []):
                if title not in have:
                    tricks.append({"title": title, "text": text, "kind": kind, "confirmedBuild": None})
            abl = npc.setdefault("abilities", [])
            by_id = {a.get("spellID"): a for a in abl}
            for sid, note in t.get("ab", {}).items():
                a = by_id.get(sid)
                if a is None:
                    info = ics.spell_info(sid)
                    if not info:
                        print("  no tooltip for spell", sid, "on", npc["name"])
                        continue
                    a = {"name": info[0], "spellID": sid, "icon": info[1], "source": "wowhead-forever-journal"}
                    abl.append(a)
                    by_id[sid] = a
                if note and not a.get("note"):
                    a["note"] = note
        if changed:
            f.write_text(json.dumps(d, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    missing = sorted(set(T) - used)
    print("applied", len(used), "missing npcs:", missing)
    ics._CACHE_FILE.write_text(json.dumps({str(k): v for k, v in ics._spell_cache.items()}))


if __name__ == "__main__":
    main()

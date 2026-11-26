#!/usr/bin/env python3
"""Fill stats (armor, mana, melee damage, resistances, immunities) and
ability timings (cooldowns, health % triggers, phases, flee) in
data-src/*.json from the CMaNGOS classic-db world database (EventAI).

These are Classic 1.12 server values. Forever is close to Classic for old
content (health matched Wowhead's Forever pages for the Stockade), but treat
them as a baseline until confirmed in game.

Usage:
  git clone --depth 1 https://github.com/cmangos/classic-db
  python tools/import_classic_stats.py classic-db/Full_DB/ClassicDB_*.sql.gz
Existing health values are kept; everything else in stats is overwritten.
"""
import gzip
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MECHANICS = ["charm", "disorient", "disarm", "distract", "fear", "fumble", "root",
             "pacify", "silence", "sleep", "snare", "stun", "freeze", "knockout",
             "bleed", "bandage", "polymorph", "banish", "shield", "shackle", "mount",
             "persuade", "turn", "horror", "invulnerability", "interrupt", "daze",
             "discovery", "immune shield", "sap"]
# Shown in the journal, in this order. Other mechanics are left out as noise.
SHOWN = ["stun", "fear", "root", "snare", "silence", "sleep", "polymorph", "sap",
         "shackle", "banish", "charm", "disarm", "bleed", "daze"]
SCHOOLS = {"holy": "ResistanceHoly", "fire": "ResistanceFire", "nature": "ResistanceNature",
           "frost": "ResistanceFrost", "shadow": "ResistanceShadow", "arcane": "ResistanceArcane"}
TYPES = {1: "Beast", 2: "Dragonkin", 3: "Demon", 4: "Elemental", 5: "Giant", 6: "Undead",
         7: "Humanoid", 8: "Critter", 9: "Mechanical", 10: "Not specified"}


def rows(sql, table="creature_template", key="Entry"):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\)" % table, sql, re.S)
    cols = re.findall(r"^\s+`(\w+)`", m.group(1), re.M)
    out = {} if key else []
    for st in re.finditer(r"INSERT INTO `%s` (?:\([^)]*\) )?VALUES\s*(.*?);\n" % table, sql, re.S):
        s, i, n = st.group(1), 0, len(st.group(1))
        while i < n:
            if s[i] != "(":
                i += 1
                continue
            vals, cur, j, inq = [], "", i + 1, False
            while True:
                c = s[j]
                if inq:
                    if c == "\\":
                        cur += s[j + 1]
                        j += 2
                        continue
                    if c == "'":
                        inq = False
                    else:
                        cur += c
                elif c == "'":
                    inq = True
                elif c == ",":
                    vals.append(cur)
                    cur = ""
                elif c == ")":
                    vals.append(cur)
                    break
                else:
                    cur += c
                j += 1
            i = j + 1
            if len(vals) == len(cols):
                r = dict(zip(cols, (v.strip() for v in vals)))
                if key:
                    out[int(r[key])] = r
                else:
                    out.append(r)
    return out


def stats_for(r, old):
    mask = int(r["MechanicImmuneMask"])
    immune = [m for m in SHOWN if mask >> MECHANICS.index(m) & 1]
    hp = int(r["MaxLevelHealth"])
    mana = int(r["MaxLevelMana"])
    st = dict(old or {})
    st["type"] = TYPES.get(int(r["CreatureType"]), st.get("type"))
    st.setdefault("health", hp)
    st["mana"] = mana or None
    st["armor"] = int(r["Armor"])
    st["damage"] = f"{int(float(r['MinMeleeDmg']))}-{int(float(r['MaxMeleeDmg']))}"
    st["resist"] = {k: int(r[c]) for k, c in SCHOOLS.items()}
    st["immune"] = immune
    st["statsSource"] = "cmangos-classic"
    return {k: v for k, v in st.items() if v is not None}


# EventAI ---------------------------------------------------------------------

EV_TIMER, EV_HP, EV_AGGRO, EV_RANGE, EV_SPAWN, EV_BEHIND = 0, 2, 4, 9, 11, 33
ACT_CAST, ACT_SET_PHASE, ACT_INC_PHASE, ACT_FLEE = 11, 22, 23, 25
_CACHE_FILE = ROOT / "tools" / ".spell_cache.json"
try:
    _spell_cache = {int(k): (tuple(v) if v else None) for k, v in json.loads(_CACHE_FILE.read_text()).items()}
except Exception:
    _spell_cache = {}


def secs(a, b):
    a, b = round(int(a) / 1000), round(int(b) / 1000)
    return f"{a}s" if a == b else f"{a}-{b}s"


def spell_info(spell_id):
    """Name and icon from Wowhead's Forever tooltip API, or None."""
    if spell_id in _spell_cache:
        return _spell_cache[spell_id]
    info = None
    try:
        url = f"https://nether.wowhead.com/forever/tooltip/spell/{spell_id}"
        with urllib.request.urlopen(url, timeout=15) as r:
            d = json.load(r)
        icon = d.get("icon") or ""
        info = (d["name"], "_".join(w.capitalize() if i == 0 else w for i, w in enumerate(icon.split("_"))))
    except Exception:
        pass
    _spell_cache[spell_id] = info
    return info


def timing_text(ev):
    t = int(ev["event_type"])
    p = [ev[f"event_param{k}"] for k in range(1, 7)]
    chance = int(ev["event_chance"])
    if t == EV_TIMER:
        if int(p[2]) == 0 and int(p[3]) == 0:
            txt = f"once, {secs(p[0], p[1])} into the fight"
        else:
            txt = f"first after {secs(p[0], p[1])}, then every {secs(p[2], p[3])}"
    elif t == EV_RANGE:
        where = "in melee range" if int(p[1]) <= 5 else f"{p[0]}-{p[1]} yards away"
        txt = f"when its target is {where}, every {secs(p[2], p[3])}"
    elif t == EV_HP:
        txt = f"at {p[0]}% health" + (f", repeats every {secs(p[2], p[3])}" if int(p[2]) else "")
    elif t == EV_AGGRO:
        txt = "on pull"
    elif t == EV_SPAWN:
        txt = "always active"
    elif t == EV_BEHIND:
        txt = f"when behind its target, every {secs(p[2], p[3])}"
    else:
        return None
    if chance < 100:
        txt += f" ({chance}% chance)"
    return txt


def apply_ai(npc, events):
    phases_used, transitions = set(), []
    for ev in events:
        mask = int(ev["event_inverse_phase_mask"])
        for b in range(1, 32):
            if mask >> b & 1:
                phases_used.add(b)
        for a in (1, 2, 3):
            at = int(ev[f"action{a}_type"])
            if at in (ACT_SET_PHASE, ACT_INC_PHASE):
                ph = int(ev[f"action{a}_param1"])
                phases_used.add(ph if at == ACT_SET_PHASE else -1)
                if int(ev["event_type"]) == EV_HP:
                    transitions.append((ph, int(ev["event_param1"]), at))
            if at == ACT_FLEE and int(ev["event_type"]) == EV_HP:
                npc["fleesAt"] = int(ev["event_param1"])
    # EventAI often uses phases as internal states (for example "out of mana,
    # switch to melee"), which are not encounter phases. Only treat them as
    # phases when a health % event switches phase. Hand-written "phases" in
    # data-src are kept either way.
    multi = bool(transitions) and -1 not in phases_used
    all_phases = sorted({0} | {p for p in phases_used if p >= 0}) if multi else None

    by_spell = {a.get("spellID"): a for a in npc.get("abilities", [])}
    for ev in events:
        for a in (1, 2, 3):
            if int(ev[f"action{a}_type"]) != ACT_CAST:
                continue
            sid = int(ev[f"action{a}_param1"])
            txt = timing_text(ev)
            if not txt:
                continue
            ab = by_spell.get(sid)
            if ab is None:
                quiet = all(int(ev[f"event_param{k}"]) == 0 for k in range(1, 5))
                if int(ev["event_type"]) in (EV_SPAWN, EV_AGGRO) or quiet:
                    continue  # passives like Dual Wield on pull are noise
                info = spell_info(sid)
                if not info:
                    continue
                ab = {"name": info[0], "spellID": sid, "icon": info[1], "tags": [],
                      "note": "", "source": "cmangos-classic"}
                npc.setdefault("abilities", []).append(ab)
                by_spell[sid] = ab
            ab["timing"] = txt
            if int(ev["event_type"]) == EV_HP:
                ab["atHealth"] = int(ev["event_param1"])
            if all_phases:
                mask = int(ev["event_inverse_phase_mask"])
                ab["phases"] = [p for p in all_phases if not mask >> p & 1]
    if all_phases:
        phases = []
        for p in all_phases:
            ph = next((x for x in npc.get("phases", []) if x.get("id") == p), {"id": p, "name": f"Phase {p + 1}"})
            for (tp, hp, at) in transitions:
                if tp == p and at == ACT_SET_PHASE:
                    ph.setdefault("note", f"Starts at {hp}% health.")
            phases.append(ph)
        npc["phases"] = phases


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    with gzip.open(sys.argv[1], "rt", encoding="utf-8", errors="replace") as f:
        sql = f.read()
    db = rows(sql)
    ai = {}
    for ev in rows(sql, "creature_ai_scripts", key=None):
        ai.setdefault(int(ev["creature_id"]), []).append(ev)
    for path in sorted((ROOT / "data-src").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        missing = []
        for npc in data["npcs"]:
            r = db.get(npc["id"])
            if not r:
                missing.append(npc["name"])
                continue
            npc["stats"] = stats_for(r, npc.get("stats"))
            if npc["id"] in ai:
                apply_ai(npc, sorted(ai[npc["id"]], key=lambda e: int(e["id"])))
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"{path.name}: updated" + (f", not in classic-db: {', '.join(missing)}" if missing else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())

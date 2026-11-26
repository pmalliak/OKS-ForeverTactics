#!/usr/bin/env python3
"""Compile data-src/*.json into ForeverTactics/Data/*.lua and Data.xml.

Run from the repo root:  python tools/build_data.py
Validates the data and fails with a list of problems instead of writing
broken files. Never hand-edit the generated Lua.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data-src"
# Works in both layouts: the dev folder (addon in ForeverTactics/) and the git
# repo (addon files at the root, as the CurseForge packager wants them).
OUT = (ROOT / "ForeverTactics" / "Data") if (ROOT / "ForeverTactics" / "ForeverTactics_Forever.toc").exists() else (ROOT / "Data")

KINDS = {"boss", "trash", "rare"}
SCHOOLS = {"fire", "frost", "nature", "shadow", "arcane", "holy"}
TRICK_KINDS = {"clever-use", "bug-abuse", "unverified"}
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
BANNED = {"\u2014": "em dash", "\u2013": "en dash"}


def lua(v, indent=0):
    pad = "  " * indent
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        s = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return '"' + s + '"'
    if isinstance(v, list):
        if not v:
            return "{}"
        items = [pad + "  " + lua(x, indent + 1) + "," for x in v]
        return "{\n" + "\n".join(items) + "\n" + pad + "}"
    if isinstance(v, dict):
        items = []
        for k, x in v.items():
            if x is None:
                continue
            key = k if IDENT.match(str(k)) else "[" + lua(k) + "]"
            items.append(pad + "  " + key + " = " + lua(x, indent + 1) + ",")
        if not items:
            return "{}"
        return "{\n" + "\n".join(items) + "\n" + pad + "}"
    raise TypeError(type(v))


def check_text(where, v, errors):
    if isinstance(v, str):
        for ch, name in BANNED.items():
            if ch in v:
                errors.append(f"{where}: contains an {name}")
    elif isinstance(v, list):
        for i, x in enumerate(v):
            check_text(f"{where}[{i}]", x, errors)
    elif isinstance(v, dict):
        for k, x in v.items():
            check_text(f"{where}.{k}", x, errors)


def check_trick(where, t, errors):
    for f in ("title", "text", "kind"):
        if not t.get(f):
            errors.append(f"{where}: missing {f}")
    if t.get("kind") and t["kind"] not in TRICK_KINDS:
        errors.append(f"{where}: kind must be one of {sorted(TRICK_KINDS)}")
    if t.get("kind") in ("clever-use", "bug-abuse") and not t.get("confirmedBuild"):
        # Allowed, but shown in game as "not confirmed in Forever yet".
        pass


def validate(inst, fname, seen_ids, errors):
    w = fname
    for f in ("key", "name", "npcs"):
        if f not in inst:
            errors.append(f"{w}: missing {f}")
    if not isinstance(inst.get("instanceID"), int) and not inst.get("instanceNames"):
        errors.append(f"{w}: needs a numeric instanceID or a list of instanceNames")
    for i, t in enumerate(inst.get("tricks", [])):
        check_trick(f"{w} tricks[{i}]", t, errors)
    for n in inst.get("npcs", []):
        nw = f"{w} npc {n.get('name', '?')}"
        if not isinstance(n.get("id"), int):
            errors.append(f"{nw}: id must be a number")
        elif n["id"] in seen_ids:
            errors.append(f"{nw}: duplicate id {n['id']} (also in {seen_ids[n['id']]})")
        else:
            seen_ids[n["id"]] = fname
        if not n.get("name"):
            errors.append(f"{nw}: missing name")
        if n.get("kind") not in KINDS:
            errors.append(f"{nw}: kind must be one of {sorted(KINDS)}")
        lv = n.get("level")
        if not (isinstance(lv, list) and len(lv) == 2 and all(isinstance(x, int) for x in lv)):
            errors.append(f"{nw}: level must be [min, max]")
        if n.get("encounterID") is not None and not isinstance(n["encounterID"], int):
            errors.append(f"{nw}: encounterID must be a number or null")
        st = n.get("stats")
        if st is not None:
            for f in ("health", "mana", "armor"):
                if st.get(f) is not None and not isinstance(st[f], int):
                    errors.append(f"{nw}: stats.{f} must be a number or null")
            for school, val in (st.get("resist") or {}).items():
                if school not in SCHOOLS:
                    errors.append(f"{nw}: unknown resist school {school}")
                elif val is not None and not isinstance(val, int):
                    errors.append(f"{nw}: resist.{school} must be a number or null")
            if st.get("immune") is not None and not isinstance(st["immune"], list):
                errors.append(f"{nw}: stats.immune must be a list")
        phase_ids = set()
        for j, ph in enumerate(n.get("phases", [])):
            if not isinstance(ph.get("id"), int):
                errors.append(f"{nw} phases[{j}]: id must be a number")
            phase_ids.add(ph.get("id"))
        if n.get("fleesAt") is not None and not isinstance(n["fleesAt"], int):
            errors.append(f"{nw}: fleesAt must be a number")
        for a in n.get("abilities", []):
            for ph in a.get("phases", []) or []:
                if ph not in phase_ids:
                    errors.append(f"{nw} ability {a.get('name')}: phase {ph} is not in phases")
        for j, a in enumerate(n.get("abilities", [])):
            if not a.get("name"):
                errors.append(f"{nw} ability {j}: missing name")
            if a.get("spellID") is not None and not isinstance(a["spellID"], int):
                errors.append(f"{nw} ability {a.get('name')}: spellID must be a number")
        for j, t in enumerate(n.get("tricks", [])):
            check_trick(f"{nw} tricks[{j}]", t, errors)
    check_text(w, inst, errors)


def main():
    errors, seen_ids, built = [], {}, []
    files = sorted(SRC.glob("*.json"))
    insts = []
    for f in files:
        try:
            inst = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            errors.append(f"{f.name}: bad JSON: {e}")
            continue
        validate(inst, f.name, seen_ids, errors)
        insts.append((f, inst))
    if errors:
        print("Data has problems, nothing written:")
        for e in errors:
            print("  - " + e)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    for f, inst in insts:
        name = "".join(p.capitalize() for p in re.split(r"[^A-Za-z0-9]", inst["key"]) if p)
        npcs = inst.pop("npcs")
        inst["order"] = [n["id"] for n in npcs]
        lines = [
            f"-- GENERATED by tools/build_data.py from data-src/{f.name}. Do not edit.",
            "local _, ns = ...",
            "local D = ns.Data",
            f"D.instances[{lua(inst['key'])}] = {lua(inst)}",
        ]
        for n in npcs:
            n["instance"] = inst["key"]
            lines.append(f"D.npcs[{n['id']}] = {lua(n)}")
        (OUT / f"{name}.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        built.append(f"{name}.lua")

    xml = ['<Ui xmlns="http://www.blizzard.com/wow/ui/">',
           "  <!-- GENERATED by tools/build_data.py. Do not edit. -->"]
    xml += [f'  <Script file="{b}"/>' for b in built]
    xml.append("</Ui>")
    (OUT / "Data.xml").write_text("\n".join(xml) + "\n", encoding="utf-8", newline="\n")
    print(f"Built {len(built)} instance file(s): {', '.join(built)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

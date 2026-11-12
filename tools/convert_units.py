#!/usr/bin/env python3
"""
Convert Team Yankee unit data into the clean units.json that the Godot project loads.

Two input kinds are accepted (detected automatically):
  * hand-written loose JSON (missing commas / braces / trailing commas are fine)
  * text copied from FowList's list view (see parse_text_units below)

Usage (run from anywhere; files are also looked up in the project's data/ folder):
    python tools/convert_units.py --all                      # every data/*.txt -> data/<name>.json
    python tools/convert_units.py us_units.txt               # -> data/us_units.json
    python tools/convert_units.py ussr_units.txt --nation Soviet -o data/ussr_units.json

Options:
    --all           convert every data/*.txt into its own .json (one file per nation)
    --nation NAME   nation to stamp on units that don't state one (default: guessed from the
                    file name: us_* -> American, ussr_* -> Soviet; extend NATION_BY_PREFIX)
    --append        keep units already in the output file instead of overwriting it
    -v              list every converted unit
    --update-fields only add the army-list fields (max_copies, exclusive_with, formation_only) to every
                    data/*_units.json; values already there are kept. A normal conversion keeps them too.

Normalisation done for every unit:
    * category  -> "armored" | "ground" | "air"   (original text kept as "unit_type")
    * sizes / points -> "options" list: {label, models, points, composition}
    * "AUTO" / "Unlimited" -> -1  (UnitData.AUTO);  "-" / "-+" (not applicable) -> 0
    * infantry_save / aircraft_save / aricraft_save -> save
    * weapons: rof_static / rof_moving (0 = cannot fire), salvo / artillery flags, rules list

Text-only extras:
    * "(14/dynamic: 13 points)" -> points 14, points_dynamic 13 (equal when no dynamic figure is given)
    * an option is the run of size lines up to the next priced line (infantry + their transport)
    * "(TU205)" references -> composition unit_id, and transport_id / transport_name on infantry
    * "Attachment" units (transports) -> is_attachment; "Passengers N" -> passengers
    * a title with several stat cards (HQ formations) -> first card is the unit, the others become
      attachments (part_of / attached_ids) and the price is the sum of the card prices
    * "... for +1 point" lines -> upgrades [{text, cost, per_model}]; other extra lines -> notes
    * "Infantry 3+" / "Tank 5+" / "Aircraft Save 3+" -> save;  "Rally 4+" -> rally
"""
import argparse
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

# --------------------------------------------------------------------------
# Tolerant JSON parser
# --------------------------------------------------------------------------
STRING_RE = re.compile(r'"(?:[^"\\]|\\.)*"')
NUMBER_RE = re.compile(r"-?\d+(?:\.\d+)?")
WORD_RE = re.compile(r"true|false|null")


class LooseParser:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def fail(self, msg):
        line = self.s.count("\n", 0, self.i) + 1
        raise ValueError(f"line {line}: {msg}")

    def peek(self):
        while self.i < len(self.s) and self.s[self.i] in " \t\r\n\ufeff":
            self.i += 1
        return self.s[self.i] if self.i < len(self.s) else ""

    def parse_document(self):
        if self.peek() == '"':                 # object body without its outer braces
            return self.parse_members(end="")
        return self.parse_value()

    def parse_value(self):
        c = self.peek()
        if c == "{":
            self.i += 1
            return self.parse_members("}")
        if c == "[":
            self.i += 1
            return self.parse_items("]")
        if c == '"':
            return self.parse_string()
        m = NUMBER_RE.match(self.s, self.i)
        if m:
            self.i = m.end()
            return float(m.group()) if "." in m.group() else int(m.group())
        m = WORD_RE.match(self.s, self.i)
        if m:
            self.i = m.end()
            return {"true": True, "false": False, "null": None}[m.group()]
        self.fail(f"unexpected {c!r}")

    def parse_string(self):
        m = STRING_RE.match(self.s, self.i)
        if not m:
            self.fail("unterminated string")
        self.i = m.end()
        return json.loads(m.group(), strict=False)

    def parse_members(self, end):
        out = {}
        while True:
            c = self.peek()
            if c == "":
                if end == "":
                    return out
                self.fail("unexpected end of file, missing '}'")
            if c == ",":
                self.i += 1
                continue
            if c == end:
                self.i += 1
                return out
            if c != '"':
                self.fail(f"expected a quoted key, found {c!r}")
            key = self.parse_string()
            if self.peek() != ":":
                self.fail(f"expected ':' after {key!r}")
            self.i += 1
            out[key] = self.parse_value()

    def parse_items(self, end):
        out = []
        while True:
            c = self.peek()
            if c == "":
                self.fail("unexpected end of file, missing ']'")
            if c == ",":
                self.i += 1
                continue
            if c == end:
                self.i += 1
                return out
            out.append(self.parse_value())


# --------------------------------------------------------------------------
# Normalisation
# --------------------------------------------------------------------------
AUTO = -1  # value used for "AUTO" and "Unlimited"
AUTO_FIELDS = ("tactical", "terrain_dash", "cross_dash", "road_dash", "cross_skill")
INT_FIELDS = ("courage", "morale", "rally", "remount", "skill", "assault", "counterattack",
              "is_hit_on", "save", "armour_front", "armour_side", "armour_top")
STR_FIELDS = ("transport_name", "transport_id")
RENAMES = {"infantry_save": "save", "aircraft_save": "save", "aricraft_save": "save"}
HANDLED = {"id", "name", "nation", "category", "special_rules", "points_table", "weapons"}


def to_int(value, field, unit_id, warn):
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    s = str(value).strip()
    if s.lower() in ("auto", "unlimited"):
        return AUTO
    m = re.fullmatch(r"(\d+)\+?", s)          # "3" or "3+"
    if m:
        return int(m.group(1))
    warn(f"{unit_id}: cannot read {field}={value!r} as a number; kept as text")
    return value


def map_category(label, unit_id, warn):
    l = label.lower()
    if any(w in l for w in ("aircraft", "helicopter", "jet")):
        return "air"
    if any(w in l for w in ("tank", "vehicle", "armour", "armor", "self-propelled", "recon", "transport")):
        return "armored"
    if any(w in l for w in ("infantry", "gun", "team", "troop")):
        return "ground"
    warn(f"{unit_id}: unknown category {label!r}; defaulting to 'armored' "
         f"(add a keyword to map_category() in this script)")
    return "armored"


def parse_composition(text):
    """'4x AK-74 team 3x RPG-7 team 4x BMP-2' -> [{count:4,name:'AK-74 team'}, ...]"""
    found = re.findall(r"(\d+)x\s+(.*?)(?=\s+\d+x\s|$)", text.strip())
    return [{"count": int(n), "name": name.strip()} for n, name in found]


def build_options(table):
    options = []
    for key, points in table.items():
        key = key.strip()
        if re.fullmatch(r"\d+", key):                       # plain size: "3": 11
            models = int(key)
            options.append({"label": f"{models} models", "models": models, "transport_models": 0,
                            "points": int(points), "points_dynamic": int(points), "composition": []})
        else:                                               # composition string
            comp = parse_composition(key)
            options.append({"label": key, "models": sum(c["count"] for c in comp), "transport_models": 0,
                            "points": int(points), "points_dynamic": int(points), "composition": comp})
    return options


def normalise_rof(value):
    """Returns (number, is_salvo)."""
    if isinstance(value, str):
        if value.strip().lower() == "salvo":
            return 1, True
        m = re.fullmatch(r"\d+", value.strip())
        return (int(value), False) if m else (1, False)
    return int(value), False


def convert_weapon(w, unit_id, warn):
    name = str(w.get("name", "")).strip()
    rof_s = w.get("rof_static", w.get("rof", 1))
    rof_m = w.get("rof_moving", w.get("rof", 1))
    rof_static, salvo_s = normalise_rof(rof_s)
    rof_moving, salvo_m = normalise_rof(rof_m)
    known = {"name", "range_cm_min", "range_cm", "rof", "rof_static", "rof_moving",
             "anti_tank", "firepower", "weapon_rules"}
    for k in w:
        if k not in known:
            warn(f"{unit_id}/{name}: unknown weapon field {k!r} ignored")
    return {
        "name": name,
        "range_cm_min": int(w.get("range_cm_min", 0)),
        "range_cm": int(w.get("range_cm", 0)),
        "rof_static": rof_static,
        "rof_moving": rof_moving,
        "salvo": salvo_s or salvo_m,
        "artillery": any(str(v).strip().lower() == "artillery" for v in (rof_s, rof_m)),
        "anti_tank": int(w.get("anti_tank", 0)),
        "firepower": int(w.get("firepower", 0)),
        "rules": [str(r).strip() for r in w.get("weapon_rules", [])],
    }


def convert_unit(raw, warn):
    uid = str(raw.get("id", "")).strip()
    label = str(raw.get("category", "")).strip()
    category = map_category(label, uid or "?", warn)

    unit = {
        "id": uid,
        "name": str(raw.get("name", "")).strip(),
        "nation": str(raw.get("nation", "")).strip(),
        "category": category,
        "unit_type": label,
    }
    if category == "air":
        unit["aircraft_type"] = "helicopter" if "helicopter" in label.lower() else "jet"
    unit["special_rules"] = [str(s).strip() for s in raw.get("special_rules", [])]
    unit["options"] = build_options(raw.get("points_table", {}))

    for key, value in raw.items():
        if key in HANDLED:
            continue
        key = RENAMES.get(key, key)
        if key in AUTO_FIELDS or key in INT_FIELDS:
            unit[key] = to_int(value, key, uid, warn)
        elif key in STR_FIELDS:
            unit[key] = str(value).strip()
        else:
            warn(f"{uid}: unrecognised field {key!r} copied through unchanged")
            unit[key] = value.strip() if isinstance(value, str) else value

    unit["weapons"] = [convert_weapon(w, uid, warn) for w in raw.get("weapons", [])]
    if not uid:
        warn(f"unit {unit['name']!r} has no id")
    if not unit["options"]:
        warn(f"{uid}: no points_table, so it can't be added to an army")
    return unit



# --------------------------------------------------------------------------
# FowList "copy text" parser
# --------------------------------------------------------------------------
# Expected layout of each unit (columns may be separated by tabs or spaces):
#
#   HMMWV Fire Support Platoon TU168            <- name + id
#   Tank Unit, Scout, Thermal Imaging           <- category, then special rules
#   TACT. TERR. DASH CROSS C. DASH ROAD DASH CROSS
#   10"/25cm 12"/30cm 20"/50cm 40"/100cm 4+
#       4x HMMWV-TOW (4 points)                 <- size / composition lines
#       Replace 1x ... at no cost.              <- anything else = notes
#   weapon. Range h. ROF m. ROF AT FP Note
#   Improved TOW missile 8"/20cm - 48"/120cm 1 - 21 3+ Guided, HEAT
#   COURAGE 4+ / Morale / Remount / SKILL / Assault / Counterattack / IS HIT ON / FRONT / SIDE / TOP
#
TEXT_TRANSLATE = str.maketrans({"\u201d": '"', "\u201c": '"', "\u2033": '"', "\u00a0": " "})
TITLE_RE = re.compile(r"^(?P<name>\S.*?)\s+(?P<id>[A-Z]{1,3}\d{2,4}[a-z]?)$")
RNG = r'\d+\s*"?\s*/\s*\d+\s*(?i:cm)'
WEAPON_RE = re.compile(
    rf"^(?P<name>.+?)\s+(?P<range>{RNG}(?:\s*-\s*{RNG})?)\s+"
    r"(?P<h>\S+)\s+(?P<m>\S+)\s+(?P<at>\S+)\s+(?P<fp>\S+)(?:\s+(?P<note>.*))?$"
)
# "(4 points)" or "(14/dynamic: 13 points)"
PTS_RE = r"\((?P<static>\d+)(?:\s*/\s*dynamic:\s*(?P<dyn>\d+))?\s*points?\)"
OPT_RE = re.compile(rf"^(?P<count>\d+)\s*x\s+(?P<name>.*?)\s*(?:{PTS_RE})?\s*$", re.I)
# "(TU205)" / "(TBE120)" -> transport / attachment. Any 1-3 capital letters: the old "T[A-Z]" missed the
# three-letter ids of Belgium (TBE), Israel (TIS) and Sweden (TSV), so their infantry lost its transport link.
REF_RE = re.compile(r"\s*[(\[](?P<id>[A-Z]{1,3}\d{2,4}[a-z]?)[)\]]")
COST_RE = re.compile(r"for\s*\+\s*(?P<cost>\d+)\s*points?(?P<each>\s+each)?|(?P<free>at no cost)", re.I)
STAT_RE = re.compile(
    r"^(courage|morale|rally|remount|skill|assault|counterattack|is hit on|front|side|top"
    r"|(?:infantry|tank|aircraft|vehicle)(?: save)?|(?:[a-z]+ )?save)\s+(\S+)$", re.I)
STAT_KEYS = {"courage": "courage", "morale": "morale", "rally": "rally", "remount": "remount",
             "skill": "skill", "assault": "assault", "counterattack": "counterattack",
             "is hit on": "is_hit_on", "front": "armour_front", "side": "armour_side", "top": "armour_top"}
SAVE_WORDS = ("infantry", "tank", "aircraft", "vehicle")      # "Infantry 3+", "Tank 5+", "Aircraft Save 3+" -> save


def stat_value(tok):
    """'4+' -> 4, 'AUTO'/'Unlimited' -> -1, '-' or '-+' (not applicable) -> 0."""
    t = tok.strip().lower()
    if t in ("auto", "unlimited"):
        return AUTO
    m = re.match(r"(\d+)\+?$", t)
    return int(m.group(1)) if m else 0


def move_value(tok):
    """'10"/25cm' -> 25 (the cm figure); otherwise same rules as stat_value."""
    m = re.search(r"/\s*(\d+)\s*(?i:cm)", tok)
    return int(m.group(1)) if m else stat_value(tok)


def rof_value(tok):
    """Returns (number, kind). kind is "", "salvo" or "artillery". '-' = cannot fire -> 0."""
    t = tok.strip().lower()
    if t in ("salvo", "artillery"):
        return 1, t
    return (int(t), "") if re.fullmatch(r"\d+", t) else (0, "")


def find_unit_starts(lines):
    starts = []
    for i, line in enumerate(lines):
        if not TITLE_RE.match(line.strip()):
            continue
        following = [x.strip() for x in lines[i + 1:i + 5] if x.strip()]
        looks_like_unit = (len(following) >= 2 and following[1].lower().startswith("tact")) or \
                          (following and "unit" in following[0].lower())
        if looks_like_unit:
            starts.append(i)
    return starts


def parse_option_line(s):
    """'3x M2 Bradley (TU205) (14/dynamic: 13 points)' -> dict, or None if not a size line."""
    m = OPT_RE.match(s)
    if not m:
        return None
    name, ref = m.group("name").strip(), ""
    r = REF_RE.search(name)
    if r:
        ref = r.group("id")
        name = (name[:r.start()] + name[r.end():]).strip()
    return {"count": int(m.group("count")), "name": name, "ref": ref,
            "points": int(m.group("static")) if m.group("static") else None,
            "dynamic": int(m.group("dyn")) if m.group("dyn") else None}


def parse_upgrade(s, uid=""):
    """'Arm all M109 with Bomblets for +1 point.' -> {text, cost, per_model, ...}; None if no price."""
    m = COST_RE.search(s)
    if not m:
        return None
    return {"text": s, "cost": 0 if m.group("free") else int(m.group("cost")), **classify_upgrade(s, uid)}


NUMBER_WORDS = {"two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "eight": 8, "ten": 10}
PER_RE = re.compile(r"\b(?:per|for every)\s+(?P<n>\d+|two|three|four|five|six|eight|ten)\b", re.I)
PER_MODEL_RE = re.compile(r"\bper\s+(?:tank|team|model|aircraft|vehicle|gun)\b|\bfor every\b", re.I)
REPLACE_TEAMS_RE = re.compile(r"replace (?:the|all) (?P<what>.+?) teams? with", re.I)
# Upgrades the text alone cannot work out: (card id, start of the text) -> extra fields.
# TB105 / TB204: the Milan teams come from the other option "Add two Milan missile teams", not from the size.
UPGRADE_FIXES = {
    ("TB105", "Replace the Milan"): {"count": 2},
    ("TB204", "Replace the Milan"): {"count": 2},
}


def classify_upgrade(s, uid=""):
    """How an upgrade is paid (see UnitData.upgrades in the Godot project):
    once     {"per_model": False}                    "for +1 point" (also "for the battery", "Fit up to three ...")
    choice   {"per_model": True}                     "+1 point each" / "per tank" with "any or all" or "up to N"
    model    {"per_model": False, "per": "model"}    "+1 point per tank / per team", "all ... +1 point each",
             (+ "count_models", "group")             "per two aircraft", "for every eight ... teams"
    """
    m = COST_RE.search(s)
    if not m or m.group("free"):
        return {"per_model": False}
    low = s.lower()
    each = bool(m.group("each")) or bool(PER_MODEL_RE.search(s)) or bool(PER_RE.search(s))
    if not each:
        return {"per_model": False}
    if "any or all" in low or "up to" in low:
        return {"per_model": True}
    if bool(m.group("each")) and not PER_MODEL_RE.search(s) and not PER_RE.search(s) and " all " not in f" {low} ":
        return {"per_model": True}                    # "+1 point each" without "all": the player picks
    out = {"per_model": False, "per": "model"}
    g = PER_RE.search(s)
    if g:
        n = g.group("n").lower()
        out["group"] = int(n) if n.isdigit() else NUMBER_WORDS[n]
    if re.search(r"\bper team\b", low):
        r = REPLACE_TEAMS_RE.search(s)
        if r:
            out["count_models"] = r.group("what").strip()
    for (fid, start), extra in UPGRADE_FIXES.items():
        if fid == uid and s.startswith(start):
            out.update(extra)
    return out


def group_options(entries, uid, warn):
    """A purchasable option is the run of lines up to and including the next line that has a price.
    (A tank unit has one line per size; an infantry company has several lines then the transport's price.)"""
    options, buf = [], []

    def close(points, dynamic):
        comp = []
        for e in buf:
            item = {"count": e["count"], "name": e["name"]}
            if e["ref"]:
                item["unit_id"] = e["ref"]
            comp.append(item)
        models = sum(e["count"] for e in buf if not e["ref"]) or sum(e["count"] for e in buf)
        options.append({
            "label": " + ".join(f"{e['count']}x {e['name']}" for e in buf),
            "models": models,
            "transport_models": sum(e["count"] for e in buf if e["ref"]),
            "points": points,
            "points_dynamic": dynamic if dynamic is not None else points,
            "composition": comp,
        })
        buf.clear()

    for e in entries:
        buf.append(e)
        if e["points"] is not None:
            close(e["points"], e["dynamic"])
    if buf:
        warn(f"{uid}: size lines after the last price have no points; added as a 0-point option - check")
        close(0, None)
    return options


def parse_card(name, uid, rows, nation, warn):
    """Parses ONE stat card: type line, movement, size lines, weapons, stats."""
    if not rows:
        warn(f"{uid}: empty block")
        return None

    parts = [p.strip() for p in rows[0].split(",") if p.strip()]
    label = parts[0] if parts else ""
    category = map_category(label, uid, warn)
    unit = {"id": uid, "name": name, "nation": nation, "category": category, "unit_type": label}
    if category == "air":
        unit["aircraft_type"] = "helicopter" if "helicopter" in label.lower() else "jet"
    unit["special_rules"] = parts[1:]
    if "attachment" in label.lower():
        unit["is_attachment"] = True            # transports etc.: not bought on their own
    for r in unit["special_rules"]:
        pm = re.fullmatch(r"passengers\s+(\d+)", r, re.I)
        if pm:
            unit["passengers"] = int(pm.group(1))

    entries, notes, upgrades, weapons = [], [], [], []
    section, move_next = "pre", False

    for s in rows[1:]:
        low = s.lower()
        if move_next:                                   # the line of movement values
            move_next = False
            tokens = re.findall(rf"{RNG}|\S+", s)
            if len(tokens) >= 5:
                for key, tok in zip(("tactical", "terrain_dash", "cross_dash", "road_dash"), tokens[:4]):
                    unit[key] = move_value(tok)
                unit["cross_skill"] = stat_value(tokens[4])
            else:
                warn(f"{uid}: could not read movement line {s!r}")
            section = "options"
            continue
        if low.startswith("tact"):
            move_next = True
            continue
        if re.match(r"weapon\b", low):
            section = "weapons"
            continue
        sm = STAT_RE.match(s)
        if sm:
            key = sm.group(1).lower()
            is_save = key.endswith("save") or key.split()[0] in SAVE_WORDS
            unit["save" if is_save else STAT_KEYS[key]] = stat_value(sm.group(2))
            section = "stats"
            continue
        if section == "options":
            opt = parse_option_line(s)
            if opt:
                entries.append(opt)
                continue
            up = parse_upgrade(s, uid)
            if up:
                upgrades.append(up)
            else:
                notes.append(s)
        elif section == "weapons":
            wm = WEAPON_RE.match(s)
            if not wm:
                warn(f"{uid}: could not read weapon line {s!r}")
                continue
            cms = re.findall(r"/\s*(\d+)\s*(?i:cm)", wm.group("range"))
            rmin, rmax = (int(cms[0]), int(cms[1])) if len(cms) == 2 else (0, int(cms[0]))
            rof_s, kind_s = rof_value(wm.group("h"))
            rof_m, kind_m = rof_value(wm.group("m"))
            kinds = {kind_s, kind_m}
            weapons.append({
                "name": wm.group("name").strip(), "range_cm_min": rmin, "range_cm": rmax,
                "rof_static": rof_s, "rof_moving": rof_m,
                "salvo": "salvo" in kinds, "artillery": "artillery" in kinds,
                "anti_tank": stat_value(wm.group("at")), "firepower": stat_value(wm.group("fp")),
                "rules": [r.strip() for r in (wm.group("note") or "").split(",") if r.strip()],
            })
        else:
            warn(f"{uid}: ignored line {s!r}")

    unit["options"] = group_options(entries, uid, warn) if entries else []
    if not entries and "passengers" in unit:
        unit["is_attachment"] = True            # a transport with no size lines is bought via its passengers
    if not entries and not unit.get("is_attachment"):
        if "formation" in label.lower():            # HQ cards often list no price line at all
            unit["options"] = [{"label": f"1x {name}", "models": 1, "transport_models": 0,
                                "points": 0, "points_dynamic": 0, "composition": []}]
            warn(f"{uid}: no size/price lines; treated as one free model - check")
        else:
            warn(f"{uid}: no size/composition lines found")
    if upgrades:
        unit["upgrades"] = upgrades
    if notes:
        unit["notes"] = notes

    refs = []                                           # vehicles this company rides in
    for e in entries:
        if e["ref"] and e["ref"] not in [r for r, _ in refs]:
            refs.append((e["ref"], e["name"]))
    if refs and category == "ground":
        unit["transport_id"], unit["transport_name"] = refs[0]       # first / default transport
        unit["transport_ids"] = [r for r, _ in refs]                  # every transport it can ride in

    unit["weapons"] = weapons
    if not weapons and not unit.get("is_attachment"):
        warn(f"{uid}: no weapons found")
    for key in ("tactical", "courage"):
        if key not in unit:
            warn(f"{uid}: missing {key}")
    return unit


def merge_cards(uid, name, cards, warn):
    """A title with several stat cards (e.g. a troop HQ = tank + infantry + scouts).
    The first card is the purchasable unit; the others become attachments linked by part_of / attached_ids."""
    main, subs = cards[0], cards[1:]
    for i, c in enumerate(subs, start=2):
        first = c["options"][0]["composition"][0]["name"] if c["options"] and c["options"][0]["composition"] else f"part {i}"
        c["name"] = f"{name}: {first}"
        c["is_attachment"] = True
        c["part_of"] = uid
    main["attached_ids"] = [c["id"] for c in subs]
    if all(len(c["options"]) == 1 for c in cards):
        opts = [c["options"][0] for c in cards]
        total = sum(o["points"] for o in opts)
        main["options"] = [{
            "label": " + ".join(o["label"] for o in opts),
            "models": sum(o["models"] for o in opts),
            "transport_models": sum(o["transport_models"] for o in opts),
            "points": total,
            "points_dynamic": sum(o["points_dynamic"] for o in opts),
            "composition": [x for o in opts for x in o["composition"]],
        }]
        warn(f"{uid}: made of {len(cards)} stat cards; priced as the SUM of the card prices ({total} pts) - check")
    else:
        warn(f"{uid}: made of {len(cards)} stat cards with several size options each; "
             f"only the first card's options are used - check")
    for c in subs:
        c["options"] = []
    return cards


def parse_block(name, uid, lines, nation, warn):
    rows = [l.strip() for l in lines if l.strip()]
    if not rows:
        warn(f"{uid}: empty block")
        return []
    # every stat card starts at its type line, i.e. the line just before a "TACT." header
    cuts = [i for i in range(len(rows) - 1) if rows[i + 1].lower().startswith("tact")]
    if 0 not in cuts:
        cuts.insert(0, 0)
    cards = []
    for n, start in enumerate(cuts):
        end = cuts[n + 1] if n + 1 < len(cuts) else len(rows)
        card = parse_card(name, uid if n == 0 else f"{uid}-{n + 1}", rows[start:end], nation, warn)
        if card:
            cards.append(card)
    return merge_cards(uid, name, cards, warn) if len(cards) > 1 else cards


def parse_text_units(text, nation, warn):
    lines = text.translate(TEXT_TRANSLATE).splitlines()
    starts = find_unit_starts(lines)
    if not starts:
        warn("no units recognised in text input")
    units = []
    for n, start in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(lines)
        m = TITLE_RE.match(lines[start].strip())
        units.extend(parse_block(m.group("name").strip(), m.group("id"), lines[start + 1:end], nation, warn))
    return units


# --------------------------------------------------------------------------
# Files and command line
# --------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent                 # tools/ lives inside the Godot project
DATA_DIR = PROJECT_DIR / "data"

# file-name prefix -> nation, used when --nation is not given (us_units.txt -> American)
NATION_BY_PREFIX = {"us": "American", "usa": "American", "american": "American",
                    "ussr": "Soviet", "soviet": "Soviet",
                    "belgium": "Belgian", "belgian": "Belgian",
                    "britain": "British", "uk": "British", "british": "British",
                    "egermany": "EastGerman", "wgermany": "WestGerman",
                    "israel": "Israeli", "israeli": "Israeli",
                    "sweden": "Swedish", "swedish": "Swedish"}


def resolve_input(arg):
    """Finds an input file even if you run the script from another folder."""
    p = Path(arg)
    candidates = [p, DATA_DIR / p, PROJECT_DIR / p]
    for c in candidates:
        if c.is_file():
            return c.resolve()
    tried = "\n  ".join(str(c) for c in candidates)
    sys.exit(f"Cannot find input file {arg!r}. Looked in:\n  {tried}\n"
             f"(current folder: {Path.cwd()})")


def guess_nation(path):
    return NATION_BY_PREFIX.get(Path(path).stem.split("_")[0].lower(), "")


def write_json(path, payload):
    """Writes the output file. If the folder refuses a direct write (file locked by another program,
    cloud-sync / antivirus protection, ...), stages it in the temp folder and copies it over instead."""
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return
    except OSError as first:
        tmp = Path(tempfile.gettempdir()) / path.name
        try:
            tmp.write_text(text, encoding="utf-8")
        except OSError as e:
            sys.exit(f"Could not write {path} ({first}) and could not write a temp copy either ({e}).")
        try:
            shutil.copyfile(tmp, path)
            print(f"note: writing {path} directly failed ({first}); copied it from {tmp} instead.",
                  file=sys.stderr)
        except OSError as second:
            sys.exit(
                f"Could not write {path}\n  {second}\n"
                f"The converted data was saved to:\n  {tmp}\n"
                f"Copy that file to {path} by hand. Common causes: the file is open or locked by another "
                f"program, it is read-only, the folder is cloud-synced (OneDrive) or protected by antivirus / "
                f"Windows 'Controlled folder access'.")


# --------------------------------------------------------------------------
# Army-list fields (edited by hand in the JSON, kept when the file is converted again)
#   max_copies     how many times the unit may be taken outside formations when Settings > "Limit unit
#                  quantities" is on: 2 for artillery and AA units, 1 for the rest (by default)
#   exclusive_with ids of units that cannot be in the same army (outside formations) as this one
#   formation_only true = the unit can only be taken inside a formation (never as a support unit)
# --------------------------------------------------------------------------
LIST_FIELDS = ("max_copies", "exclusive_with", "formation_only")
AA_NAME_RE = re.compile(r"\b(AA|SAM|Anti-Aircraft|Flak|Air Defen[cs]e)\b", re.IGNORECASE)
AA_RULES = {"dedicated aa", "guided aa"}


def _support_card(u):
    """Aircraft and HQ cards never count as artillery or AA (their rockets / mortars are not a battery)."""
    return u.get("category") != "air" and not str(u.get("unit_type", "")).lower().endswith("formation")


def is_artillery_unit(u):
    return _support_card(u) and any(w.get("artillery") or w.get("salvo") for w in u.get("weapons", []))


def is_aa_unit(u):
    if not _support_card(u):
        return False
    weapons = u.get("weapons", [])
    if AA_NAME_RE.search(u.get("name", "")):
        return True
    return bool(weapons) and all(any(r.lower() in AA_RULES for r in w.get("rules", [])) for w in weapons)


def default_max_copies(u):
    return 2 if is_artillery_unit(u) or is_aa_unit(u) else 1


def apply_list_fields(units, previous):
    """Gives every unit the army-list fields: the value from `previous` (id -> old unit) when there is one,
    otherwise the default. Returns how many units got a field they did not have."""
    added = 0
    for u in units:
        old = previous.get(u["id"], {})
        for key in LIST_FIELDS:
            if key in u:
                continue
            if key in old:
                u[key] = old[key]
            else:
                u[key] = {"max_copies": default_max_copies(u), "exclusive_with": [], "formation_only": False}[key]
                added += 1
    return added


def update_fields(paths):
    """--update-fields: adds the army-list fields to existing unit JSON files (nothing else changes)."""
    for path in paths:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
        units = doc.get("units", [])
        n = apply_list_fields(units, {})
        two = [u["id"] for u in units if u.get("max_copies") == 2]
        write_json(Path(path), doc)
        print(f"{Path(path).name}: {len(units)} units, {n} field(s) added; max_copies 2: {', '.join(two) or '-'}")


def convert_files(paths, output, nation, append, warn):
    """Converts one or more input files into one output JSON. Returns (all units, units from this run).
    The army-list fields (LIST_FIELDS) of units already in the output file are kept."""
    units = []
    previous = {}
    if Path(output).is_file():
        try:
            with open(output, encoding="utf-8") as f:
                previous = {u["id"]: u for u in json.load(f).get("units", []) if "id" in u}
        except (OSError, ValueError):
            previous = {}
    if append and Path(output).is_file():
        with open(output, encoding="utf-8") as f:
            units = json.load(f).get("units", [])
    seen = {u["id"] for u in units}
    this_run = {}
    added = []

    for path in paths:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if text.lstrip("\ufeff \t\r\n")[:1] in ('{', '[', '"'):          # looks like (loose) JSON
            try:
                doc = LooseParser(text).parse_document()
            except ValueError as e:
                sys.exit(f"{path}: {e}")
            raw_units = doc.get("units", []) if isinstance(doc, dict) else doc
            new_units = [convert_unit(raw, warn) for raw in raw_units]
            for u in new_units:
                if not u["nation"]:
                    u["nation"] = nation
        else:
            new_units = parse_text_units(text, nation, warn)
        for u in new_units:
            prev = this_run.get(u["id"])
            if prev is not None and prev != u:                           # identical repeats are harmless
                warn(f"{u['id']}: appears twice in the input with different data; later entry wins")
            if u["id"] in seen:
                units = [x for x in units if x["id"] != u["id"]]
                added = [x for x in added if x["id"] != u["id"]]
            seen.add(u["id"])
            this_run[u["id"]] = u
            units.append(u)
            added.append(u)
        if not nation and any(not u["nation"] for u in new_units):
            warn(f"{path}: some units have no nation - pass --nation NAME")

    apply_list_fields(units, previous)
    write_json(Path(output), {"units": units})
    return units, added


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="*", help="loose JSON / FowList text files (looked up in data/ too)")
    ap.add_argument("--all", action="store_true",
                    help="convert every data/*.txt into its own data/<name>.json (one file per nation)")
    ap.add_argument("-o", "--output", help="output file (default: input name with .json)")
    ap.add_argument("--nation", default="", help="nation for units that don't state one (default: guessed from file name)")
    ap.add_argument("--append", action="store_true", help="keep units already in the output file")
    ap.add_argument("-v", "--verbose", action="store_true", help="list every converted unit")
    ap.add_argument("--update-fields", action="store_true",
                    help="only add max_copies / exclusive_with / formation_only to every data/*_units.json")
    args = ap.parse_args()

    if args.update_fields:
        update_fields(sorted(DATA_DIR.glob("*_units.json")))
        return 0

    if args.all:
        if args.inputs or args.output:
            sys.exit("--all can't be combined with input files or -o")
        txts = sorted(DATA_DIR.glob("*.txt"))
        if not txts:
            sys.exit(f"No .txt files found in {DATA_DIR}")
        jobs = [([t], t.with_suffix(".json")) for t in txts]
    else:
        if not args.inputs:
            ap.error("give at least one input file, or use --all")
        paths = [resolve_input(x) for x in args.inputs]
        if args.output:
            out = Path(args.output)
        elif len(paths) == 1:
            out = paths[0].with_suffix(".json")
        else:
            out = DATA_DIR / "units.json"
        jobs = [(paths, out)]

    exit_code = 0
    for paths, out in jobs:
        warnings = []
        nation = args.nation or guess_nation(paths[0])
        units, added = convert_files(paths, out, nation, args.append, warnings.append)
        by_cat = {}
        for u in added:
            by_cat[u["category"]] = by_cat.get(u["category"], 0) + 1
        print(f"{', '.join(p.name for p in paths)} -> {out}: {len(units)} units "
              f"[{nation or 'no nation'}] {by_cat}")
        if args.verbose:
            for u in added:
                print(f"  {u['id']:<9} {u['category']:<8} {u['name']}  "
                      f"({len(u['options'])} options, {len(u['weapons'])} weapons)")
        for w in warnings:
            print("  WARNING:", w, file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())

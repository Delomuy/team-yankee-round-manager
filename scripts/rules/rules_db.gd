class_name RulesDB
extends RefCounted
## What does a special rule do? Reads data/rules/special_rules.json (made from the Special Rules PDF by
## tools/extract_special_rules.py) and data/rules/extra_rules.json (descriptions you write yourself) and answers
## look-ups by the rule name printed on a card.
##
## A card says "Assault +1", "Passengers 2", "ERA" or "Infra-Red (IR)" while the PDF says "Assault #",
## "Passengers #", "ERA Armour" and "Infra-Red", so names are compared in a normalised form (see candidates()).
## The nation of the unit decides which national version of a rule is shown first.

const RULE_FILES: Array[String] = [
	"res://data/rules/extra_rules.json",
	"res://data/rules/special_rules.json",
]
const EXTRA_FILE := "extra_rules.json"

## Card name (normalised) -> name used in the PDF (normalised).
const ALIASES: Dictionary = {
	"era": "era armour",
	"advanced stabiliser": "advanced stabilisers",
	"slat": "slat armour",
}
const ACCENTS: Dictionary = {"é": "e", "è": "e", "ê": "e", "á": "a", "à": "a", "â": "a", "ü": "u", "ö": "o", "ä": "a"}
const NATION_LABELS: Dictionary = {"EastGerman": "East German", "WestGerman": "West German"}

static var _loaded: bool = false
static var _by_key: Dictionary = {}      # String -> Array of Dictionary
static var _count: int = 0
static var _re_paren: RegEx
static var _re_num: RegEx


## Loads the files again (e.g. after you edited extra_rules.json).
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func count() -> int:
	_ensure_loaded()
	return _count


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_by_key = {}
	_count = 0
	_re_paren = RegEx.create_from_string(r"\([^)]*\)")
	_re_num = RegEx.create_from_string(r"\s[+\-]?\d+\+?$")
	for path in RULE_FILES:
		_load_file(path)


static func _load_file(path: String) -> void:
	var is_extra: bool = path.ends_with(EXTRA_FILE)
	if not FileAccess.file_exists(path):
		if not is_extra:
			push_warning("Special rules file not found: %s (create it with tools/extract_special_rules.py)" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("rules"):
		push_warning("Skipped %s: no \"rules\" list" % path)
		return
	var list: Array = (parsed as Dictionary)["rules"]
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var rule_name: String = str(d.get("name", "")).strip_edges()
		var text: String = str(d.get("text", "")).strip_edges()
		if rule_name == "" or text == "":
			continue
		var entry: Dictionary = {
			"name": rule_name,
			"nation": str(d.get("nation", "")),
			"scope": str(d.get("scope", "nation" if str(d.get("nation", "")) != "" else "general")),
			"category": str(d.get("category", "")),
			"page": int(d.get("page", 0)),
			"pages": d.get("pages", [int(d.get("page", 0))]),
			"book": str(d.get("book", "")),
			"flavor": str(d.get("flavor", "")),
			"text": text,
			"extra": is_extra,
		}
		var k: String = make_key(rule_name)
		if not _by_key.has(k):
			_by_key[k] = []
		(_by_key[k] as Array).append(entry)
		_count += 1


# ------------------------------------------------------------------ names

## "Appliqué Armour" -> "applique armour", "Infra-Red (IR)" -> "infra-red".
static func make_key(rule_name: String) -> String:
	_ensure_loaded()
	var s: String = _re_paren.sub(rule_name, "", true).to_lower()
	for a in ACCENTS:
		s = s.replace(a, ACCENTS[a])
	return " ".join(s.split(" ", false)).strip_edges()


## Every spelling worth trying for a card name, best first.
static func candidates(rule_name: String) -> Array[String]:
	var k: String = make_key(rule_name)
	var out: Array[String] = [k]
	var generic: String = _re_num.sub(k, " #")        # "assault +1", "assault 5+", "passengers 2" -> "... #"
	if generic != k:
		out.append(generic)
	if ALIASES.has(k):
		out.append(make_key(String(ALIASES[k])))
	if k.ends_with("s"):
		out.append(k.trim_suffix("s"))
	else:
		out.append(k + "s")
	return out


# ------------------------------------------------------------------ look-ups

## All descriptions of a rule, the unit's own nation first, then the general rule. When neither exists, the
## versions other nations have are returned (the card may use a rule the PDF only prints for an ally).
static func find(rule_name: String, nation: String = "") -> Array:
	_ensure_loaded()
	var hits: Array = []
	for k in candidates(rule_name):
		if _by_key.has(k):
			hits = _by_key[k]
			break
	if hits.is_empty():
		return []
	var buckets: Array = [[], [], [], [], []]       # own nation (yours, PDF), general (yours, PDF), other nations
	var others: Array = []
	for item in hits:
		var e: Dictionary = item
		var n: String = String(e["nation"])
		var mine: int = 0 if bool(e["extra"]) else 1
		if n != "" and n == nation:
			(buckets[mine] as Array).append(e)
		elif n == "":
			(buckets[2 + mine] as Array).append(e)
		else:
			others.append(e)
	var out: Array = []
	for b in buckets:
		out.append_array(b as Array)
	if out.is_empty():
		out = others
	return out


static func has(rule_name: String, nation: String = "") -> bool:
	return not find(rule_name, nation).is_empty()


static func nation_label(nation: String) -> String:
	if NATION_LABELS.has(nation):
		return String(NATION_LABELS[nation])
	var added: String = NationDB.label(nation)      # a nation added in the program
	return added if added != "" else nation


# ------------------------------------------------------------------ BBCode

static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


## One clickable rule name. RichTextLabel.meta_clicked receives "rule|<name>|<nation>" (see RulePopup).
## `light_bg`: darker link colours for a white card; `upper`: show the name in capitals.
static func link(rule_name: String, nation: String = "", light_bg: bool = true, upper: bool = false) -> String:
	var meta_name: String = rule_name.replace("[", "").replace("]", "").replace("|", "/")
	var known: bool = has(rule_name, nation)
	var colour: String = ("#1b5fa8" if known else "#777777") if light_bg else ("#8ecbff" if known else "#b0b0b0")
	var shown: String = rule_name.to_upper() if upper else rule_name
	return "[url=rule|%s|%s][color=%s]%s[/color][/url]" % [meta_name, nation, colour, _esc(shown)]


static func links(rules: PackedStringArray, nation: String = "", light_bg: bool = true, upper: bool = false) -> String:
	var parts: PackedStringArray = []
	for r in rules:
		parts.append(link(r, nation, light_bg, upper))
	return ", ".join(parts)


## "Weapon rules: ... / Unit rules: ..." with every rule clickable (used by the battle panels).
static func summary_bbcode(u: UnitData, w: WeaponData = null) -> String:
	var lines: PackedStringArray = []
	if w != null and not w.rules.is_empty():
		lines.append("[b]%s:[/b] %s" % [_esc(w.weapon_name), links(w.rules, u.nation)])
	if not u.special_rules.is_empty():
		lines.append("[b]Unit rules:[/b] %s" % links(u.special_rules, u.nation))
	if lines.is_empty():
		return "[color=#6b6b6b]No special rules.[/color]"
	return "\n".join(lines) + "\n[color=#6b6b6b]Click a rule to read it.[/color]"


static func source_line(e: Dictionary) -> String:
	if bool(e["extra"]):
		return "Your own description (data/rules/extra_rules.json)"
	var s: String
	if String(e["scope"]) == "general":
		s = "General %s rule" % String(e["category"]).to_lower()
	else:
		s = "%s rule" % nation_label(String(e["nation"]))
	if String(e["book"]) != "":
		s += ", " + String(e["book"])
	var pages: PackedStringArray = []
	for pg in (e["pages"] as Array):
		pages.append(str(int(pg)))
	if int(e["page"]) > 0:
		s += " (Special Rules PDF, page%s %s)" % ["s" if pages.size() > 1 else "", ", ".join(pages)]
	return s


## The whole rule pop-up text for a card name.
static func describe_bbcode(rule_name: String, nation: String = "") -> String:
	var entries: Array = find(rule_name, nation)
	if entries.is_empty():
		return "[font_size=22][b]%s[/b][/font_size]\n\n[color=#8a5a00]This rule has no description in the Special Rules PDF.[/color]\n\n" % _esc(rule_name) \
				+ "It is probably a rule from a unit book that is not in that PDF. To read it here, add it to " \
				+ "[b]data/rules/extra_rules.json[/b] (the note at the top of that file shows how)."
	var t: String = ""
	for i in entries.size():
		var e: Dictionary = entries[i]
		if i > 0:
			t += "\n[color=#555555]__________________________________________[/color]\n\n"
		t += "[font_size=22][b]%s[/b][/font_size]\n" % _esc(String(e["name"]))
		t += "[color=#6b6b6b]%s[/color]\n" % _esc(source_line(e))
		if make_key(String(e["name"])) != make_key(rule_name):
			t += "[color=#6b6b6b]Printed on the card as \"%s\"[/color]\n" % _esc(rule_name)
		t += "\n"
		if String(e["flavor"]) != "":
			t += "[i][color=#5c5c5c]%s[/color][/i]\n\n" % _esc(String(e["flavor"]))
		t += _esc(String(e["text"])) + "\n"
	return t

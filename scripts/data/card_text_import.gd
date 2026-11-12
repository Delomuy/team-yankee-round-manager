class_name CardTextImport
extends RefCounted
## Reads unit cards from text copied from FowList's list view - the same logic as parse_text_units in
## tools/convert_units.py, ported so cards of any nation (also new ones) can be made inside the program
## (Cards > Import cards from text..., CardImportDialog). The result is unit-file dictionaries, ready for
## UnitDatabase.save_custom.
##
## The text looks like this (one block per card):
##     2S1 Carnation SP Howitzer Battery TS108        <- name and card id
##     Tank Unit, Amphibious, Infra-Red (IR)           <- card type, then special rules
##     TACT.  TERR. DASH  CROSS C. DASH  ROAD DASH  CROSS
##     10"/25cm  16"/40cm  24"/60cm  28"/70cm  3+
##     6x 2S1 Carnation (10 points)                    <- sizes; "(14/dynamic: 13 points)"; "(TS126)" = a transport card
##     Add ... for +1 point.                           <- options (upgrades); other lines become notes
##     weapon.  Range  h. ROF  m. ROF  AT  FP  Note
##     122mm 2A31 howitzer  88"/220cm  ARTILLERY  ARTILLERY  4  3+  Smoke Bombardment
##     COURAGE 4+ / Morale 3+ / Remount 3+ / SKILL 5+ / Assault 6+ / Counterattack 5+ / IS HIT ON 3+ / FRONT 2 ...
## Differences from the Python script: card references "(XX123)" may use any 1-3 capital letters (new nations have
## their own ids), and the army-list fields (max_copies ...) are filled in at once.

const AUTO := -1
const RNG := "\\d+\\s*\"?\\s*/\\s*\\d+\\s*(?i:cm)"
const PTS := "\\((?P<static>\\d+)(?:\\s*/\\s*dynamic:\\s*(?P<dyn>\\d+))?\\s*points?\\)"
const STAT_KEYS := {"courage": "courage", "morale": "morale", "rally": "rally", "remount": "remount",
		"skill": "skill", "assault": "assault", "counterattack": "counterattack",
		"is hit on": "is_hit_on", "front": "armour_front", "side": "armour_side", "top": "armour_top"}
const SAVE_WORDS := ["infantry", "tank", "aircraft", "vehicle"]
const NUMBER_WORDS := {"two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "eight": 8, "ten": 10}
## Upgrades the text alone cannot work out (same as UPGRADE_FIXES in tools/convert_units.py).
const UPGRADE_FIXES := {"TB105|Replace the Milan": {"count": 2}, "TB204|Replace the Milan": {"count": 2}}

static var _re: Dictionary = {}


static func _rx(key: String) -> RegEx:
	if _re.is_empty():
		var pats: Dictionary = {
			"title": "^(?P<name>\\S.*?)\\s+(?P<id>[A-Z]{1,3}\\d{2,4}[a-z]?)$",
			"weapon": "^(?P<name>.+?)\\s+(?P<range>" + RNG + "(?:\\s*-\\s*" + RNG + ")?)\\s+"
					+ "(?P<h>\\S+)\\s+(?P<m>\\S+)\\s+(?P<at>\\S+)\\s+(?P<fp>\\S+)(?:\\s+(?P<note>.*))?$",
			"option": "(?i)^(?P<count>\\d+)\\s*x\\s+(?P<name>.*?)\\s*(?:" + PTS + ")?\\s*$",
			"ref": "\\s*[(\\[](?P<id>[A-Z]{1,3}\\d{2,4}[a-z]?)[)\\]]",
			"cost": "(?i)for\\s*\\+\\s*(?P<cost>\\d+)\\s*points?(?P<each>\\s+each)?|(?P<free>at no cost)",
			"stat": "(?i)^(courage|morale|rally|remount|skill|assault|counterattack|is hit on|front|side|top"
					+ "|(?:infantry|tank|aircraft|vehicle)(?: save)?|(?:[a-z]+ )?save)\\s+(\\S+)$",
			"tokens": RNG + "|\\S+",
			"cm": "/\\s*(\\d+)\\s*(?i:cm)",
			"stat_num": "^(\\d+)\\+?$",
			"passengers": "(?i)^passengers\\s+(\\d+)$",
			"per": "(?i)\\b(?:per|for every)\\s+(?P<n>\\d+|two|three|four|five|six|eight|ten)\\b",
			"per_model": "(?i)\\bper\\s+(?:tank|team|model|aircraft|vehicle|gun)\\b|\\bfor every\\b",
			"replace_teams": "(?i)replace (?:the|all) (?P<what>.+?) teams? with",
			"per_team": "(?i)\\bper team\\b",
			"weapon_word": "(?i)^weapon\\b",
			"aa_name": "(?i)\\b(AA|SAM|Anti-Aircraft|Flak|Air Defen[cs]e)\\b",
		}
		for k in pats:
			var r: RegEx = RegEx.new()
			var err: Error = r.compile(str(pats[k]))
			if err != OK:
				push_error("CardTextImport: bad pattern %s" % k)
			_re[k] = r
	return _re[key]


## Reads every card in `text` for `nation`. Returns {"units": [unit dictionaries], "warnings": PackedStringArray}.
static func parse(text: String, nation: String) -> Dictionary:
	var warnings: PackedStringArray = []
	var t: String = text.replace("\r", "").replace("”", "\"").replace("“", "\"").replace("″", "\"").replace(" ", " ")
	var lines: PackedStringArray = t.split("\n")
	var starts: Array = _find_unit_starts(lines)
	if starts.is_empty():
		warnings.append("No cards recognised. Each card starts with a line 'Name ID' (e.g. 'T-80 Tank Company TS138') "
				+ "followed by its type line and the TACT. line.")
	var units: Array = []
	for n in starts.size():
		var start: int = starts[n]
		var end: int = starts[n + 1] if n + 1 < starts.size() else lines.size()
		var m: RegExMatch = _rx("title").search(lines[start].strip_edges())
		var block: Array = []
		for i in range(start + 1, end):
			block.append(lines[i])
		units.append_array(_parse_block(m.get_string("name").strip_edges(), m.get_string("id"), block, nation, warnings))
	for u: Dictionary in units:
		u["max_copies"] = 2 if _is_artillery(u) or _is_aa(u) else 1
		u["exclusive_with"] = []
		u["formation_only"] = false
	return {"units": units, "warnings": warnings}


static func _find_unit_starts(lines: PackedStringArray) -> Array:
	var starts: Array = []
	for i in lines.size():
		if _rx("title").search(lines[i].strip_edges()) == null:
			continue
		var following: Array = []
		for j in range(i + 1, mini(i + 5, lines.size())):
			if lines[j].strip_edges() != "":
				following.append(lines[j].strip_edges())
		var looks: bool = (following.size() >= 2 and str(following[1]).to_lower().begins_with("tact")) \
				or (not following.is_empty() and str(following[0]).to_lower().contains("unit"))
		if looks:
			starts.append(i)
	return starts


static func stat_value(tok: String) -> int:
	var t: String = tok.strip_edges().to_lower()
	if t == "auto" or t == "unlimited":
		return AUTO
	var m: RegExMatch = _rx("stat_num").search(t)
	return int(m.get_string(1)) if m != null else 0


static func move_value(tok: String) -> int:
	var m: RegExMatch = _rx("cm").search(tok)
	return int(m.get_string(1)) if m != null else stat_value(tok)


## [number, kind]: kind "", "salvo" or "artillery"; "-" (cannot fire) = 0.
static func rof_value(tok: String) -> Array:
	var t: String = tok.strip_edges().to_lower()
	if t == "salvo" or t == "artillery":
		return [1, t]
	return [int(t), ""] if t.is_valid_int() else [0, ""]


static func map_category(label: String, warnings: PackedStringArray, uid: String) -> String:
	var l: String = label.to_lower()
	for w in ["aircraft", "helicopter", "jet"]:
		if l.contains(w):
			return "air"
	for w in ["tank", "vehicle", "armour", "armor", "self-propelled", "recon", "transport"]:
		if l.contains(w):
			return "armored"
	for w in ["infantry", "gun", "team", "troop"]:
		if l.contains(w):
			return "ground"
	warnings.append("%s: unknown card type '%s'; made Armored - check" % [uid, label])
	return "armored"


static func _parse_option_line(s: String) -> Dictionary:
	var m: RegExMatch = _rx("option").search(s)
	if m == null:
		return {}
	var name: String = m.get_string("name").strip_edges()
	var ref: String = ""
	var r: RegExMatch = _rx("ref").search(name)
	if r != null:
		ref = r.get_string("id")
		name = (name.substr(0, r.get_start()) + name.substr(r.get_end())).strip_edges()
	return {"count": int(m.get_string("count")), "name": name, "ref": ref,
			"points": int(m.get_string("static")) if m.get_string("static") != "" else -1,
			"dynamic": int(m.get_string("dyn")) if m.get_string("dyn") != "" else -1}


## 'Arm all M109 with Bomblets for +1 point.' -> {text, cost, per_model, ...}; {} when the line has no price.
static func parse_upgrade(s: String, uid: String = "") -> Dictionary:
	var m: RegExMatch = _rx("cost").search(s)
	if m == null:
		return {}
	var d: Dictionary = {"text": s, "cost": 0 if m.get_string("free") != "" else int(m.get_string("cost"))}
	d.merge(classify_upgrade(s, uid))
	return d


## How an upgrade is paid (see UnitData.upgrades): once / choice / per model (same rules as convert_units.py).
static func classify_upgrade(s: String, uid: String = "") -> Dictionary:
	var m: RegExMatch = _rx("cost").search(s)
	if m == null or m.get_string("free") != "":
		return {"per_model": false}
	var low: String = s.to_lower()
	var each_word: bool = m.get_string("each") != ""
	var per_model: bool = _rx("per_model").search(s) != null
	var per: RegExMatch = _rx("per").search(s)
	if not (each_word or per_model or per != null):
		return {"per_model": false}
	if low.contains("any or all") or low.contains("up to"):
		return {"per_model": true}
	if each_word and not per_model and per == null and not (" %s " % low).contains(" all "):
		return {"per_model": true}
	var out: Dictionary = {"per_model": false, "per": "model"}
	if per != null:
		var n: String = per.get_string("n").to_lower()
		out["group"] = int(n) if n.is_valid_int() else int(NUMBER_WORDS[n])
	if _rx("per_team").search(s) != null:
		var r: RegExMatch = _rx("replace_teams").search(s)
		if r != null:
			out["count_models"] = r.get_string("what").strip_edges()
	for key in UPGRADE_FIXES:
		var parts: PackedStringArray = str(key).split("|")
		if parts[0] == uid and s.begins_with(parts[1]):
			out.merge(UPGRADE_FIXES[key], true)
	return out


## A purchasable option is the run of size lines up to and including the next line with a price.
static func _group_options(entries: Array, uid: String, warnings: PackedStringArray) -> Array:
	var options: Array = []
	var buf: Array = []
	for e: Dictionary in entries:
		buf.append(e)
		if int(e["points"]) >= 0:
			options.append(_close(buf, int(e["points"]), int(e["dynamic"])))
			buf = []
	if not buf.is_empty():
		warnings.append("%s: size lines after the last price have no points; added as a 0-point size - check" % uid)
		options.append(_close(buf, 0, -1))
	return options


static func _close(buf: Array, points: int, dynamic: int) -> Dictionary:
	var comp: Array = []
	var labels: PackedStringArray = []
	var fighting: int = 0
	var all_models: int = 0
	var vehicles: int = 0
	for e: Dictionary in buf:
		var item: Dictionary = {"count": int(e["count"]), "name": str(e["name"])}
		if str(e["ref"]) != "":
			item["unit_id"] = str(e["ref"])
			vehicles += int(e["count"])
		else:
			fighting += int(e["count"])
		all_models += int(e["count"])
		comp.append(item)
		labels.append("%dx %s" % [int(e["count"]), str(e["name"])])
	return {"label": " + ".join(labels), "models": fighting if fighting > 0 else all_models, "transport_models": vehicles,
			"points": points, "points_dynamic": dynamic if dynamic >= 0 else points, "composition": comp}


## Parses ONE stat card: type line, movement, sizes, weapons, ratings.
static func _parse_card(name: String, uid: String, rows: Array, nation: String, warnings: PackedStringArray) -> Dictionary:
	if rows.is_empty():
		warnings.append("%s: empty card" % uid)
		return {}
	var parts: Array = []
	for p in str(rows[0]).split(","):
		if p.strip_edges() != "":
			parts.append(p.strip_edges())
	var label: String = str(parts[0]) if not parts.is_empty() else ""
	var category: String = map_category(label, warnings, uid)
	var unit: Dictionary = {"id": uid, "name": name, "nation": nation, "category": category, "unit_type": label}
	if category == "air":
		unit["aircraft_type"] = "helicopter" if label.to_lower().contains("helicopter") else "jet"
	unit["special_rules"] = parts.slice(1)
	if label.to_lower().contains("attachment"):
		unit["is_attachment"] = true
	for r in unit["special_rules"]:
		var pm: RegExMatch = _rx("passengers").search(str(r))
		if pm != null:
			unit["passengers"] = int(pm.get_string(1))

	var entries: Array = []
	var notes: Array = []
	var upgrades: Array = []
	var weapons: Array = []
	var section: String = "pre"
	var move_next: bool = false
	for i in range(1, rows.size()):
		var s: String = str(rows[i])
		var low: String = s.to_lower()
		if move_next:
			move_next = false
			var tokens: Array = []
			for tm in _rx("tokens").search_all(s):
				tokens.append(tm.get_string(0))
			if tokens.size() >= 5:
				var keys: Array = ["tactical", "terrain_dash", "cross_dash", "road_dash"]
				for k in 4:
					unit[keys[k]] = move_value(str(tokens[k]))
				unit["cross_skill"] = stat_value(str(tokens[4]))
			else:
				warnings.append("%s: could not read the movement line '%s'" % [uid, s])
			section = "options"
			continue
		if low.begins_with("tact"):
			move_next = true
			continue
		if _rx("weapon_word").search(low) != null:
			section = "weapons"
			continue
		var sm: RegExMatch = _rx("stat").search(s)
		if sm != null:
			var key: String = sm.get_string(1).to_lower()
			var is_save: bool = key.ends_with("save") or SAVE_WORDS.has(key.split(" ")[0])
			unit["save" if is_save else str(STAT_KEYS.get(key, key))] = stat_value(sm.get_string(2))
			section = "stats"
			continue
		if section == "options":
			var opt: Dictionary = _parse_option_line(s)
			if not opt.is_empty():
				entries.append(opt)
				continue
			var up: Dictionary = parse_upgrade(s, uid)
			if not up.is_empty():
				upgrades.append(up)
			else:
				notes.append(s)
		elif section == "weapons":
			var wm: RegExMatch = _rx("weapon").search(s)
			if wm == null:
				warnings.append("%s: could not read the weapon line '%s'" % [uid, s])
				continue
			var cms: Array = []
			for cm in _rx("cm").search_all(wm.get_string("range")):
				cms.append(int(cm.get_string(1)))
			var rmin: int = int(cms[0]) if cms.size() == 2 else 0
			var rmax: int = int(cms[1]) if cms.size() == 2 else (int(cms[0]) if not cms.is_empty() else 0)
			var rs: Array = rof_value(wm.get_string("h"))
			var rm: Array = rof_value(wm.get_string("m"))
			var kinds: Array = [rs[1], rm[1]]
			var rules: Array = []
			for r in wm.get_string("note").split(","):
				if r.strip_edges() != "":
					rules.append(r.strip_edges())
			weapons.append({"name": wm.get_string("name").strip_edges(), "range_cm_min": rmin, "range_cm": rmax,
					"rof_static": int(rs[0]), "rof_moving": int(rm[0]),
					"salvo": kinds.has("salvo"), "artillery": kinds.has("artillery"),
					"anti_tank": stat_value(wm.get_string("at")), "firepower": stat_value(wm.get_string("fp")), "rules": rules})
		else:
			warnings.append("%s: ignored line '%s'" % [uid, s])

	unit["options"] = _group_options(entries, uid, warnings) if not entries.is_empty() else []
	if entries.is_empty() and unit.has("passengers"):
		unit["is_attachment"] = true
	if entries.is_empty() and not bool(unit.get("is_attachment", false)):
		if label.to_lower().contains("formation"):
			unit["options"] = [{"label": "1x %s" % name, "models": 1, "transport_models": 0, "points": 0,
					"points_dynamic": 0, "composition": []}]
			warnings.append("%s: no size or price lines; made one free model - check" % uid)
		else:
			warnings.append("%s: no size lines found" % uid)
	if not upgrades.is_empty():
		unit["upgrades"] = upgrades
	if not notes.is_empty():
		unit["notes"] = notes
	var refs: Array = []
	var ref_names: Dictionary = {}
	for e: Dictionary in entries:
		if str(e["ref"]) != "" and not refs.has(str(e["ref"])):
			refs.append(str(e["ref"]))
			ref_names[str(e["ref"])] = str(e["name"])
	if not refs.is_empty() and category == "ground":
		unit["transport_id"] = refs[0]
		unit["transport_name"] = ref_names[refs[0]]
		unit["transport_ids"] = refs
	unit["weapons"] = weapons
	if weapons.is_empty() and not bool(unit.get("is_attachment", false)):
		warnings.append("%s: no weapons found" % uid)
	for key in ["tactical", "courage"]:
		if not unit.has(key):
			warnings.append("%s: missing %s" % [uid, key])
	return unit


## A title with several stat cards (an HQ of tank + infantry ...): the first card is the unit, the others become
## attachments (part_of / attached_ids) and the price is the sum of the card prices.
static func _merge_cards(uid: String, name: String, cards: Array, warnings: PackedStringArray) -> Array:
	var main: Dictionary = cards[0]
	var subs: Array = cards.slice(1)
	var ids: Array = []
	for i in subs.size():
		var c: Dictionary = subs[i]
		var first: String = "part %d" % (i + 2)
		if not (c["options"] as Array).is_empty() and not (c["options"][0]["composition"] as Array).is_empty():
			first = str(c["options"][0]["composition"][0]["name"])
		c["name"] = "%s: %s" % [name, first]
		c["is_attachment"] = true
		c["part_of"] = uid
		ids.append(c["id"])
	main["attached_ids"] = ids
	var single: bool = true
	for c: Dictionary in cards:
		if (c["options"] as Array).size() != 1:
			single = false
	if single:
		var labels: PackedStringArray = []
		var comp: Array = []
		var tot: Dictionary = {"models": 0, "transport_models": 0, "points": 0, "points_dynamic": 0}
		for c: Dictionary in cards:
			var o: Dictionary = c["options"][0]
			labels.append(str(o["label"]))
			comp.append_array(o["composition"])
			for k in tot:
				tot[k] = int(tot[k]) + int(o[k])
		main["options"] = [{"label": " + ".join(labels), "models": tot["models"], "transport_models": tot["transport_models"],
				"points": tot["points"], "points_dynamic": tot["points_dynamic"], "composition": comp}]
		warnings.append("%s: made of %d stat cards; priced as the SUM of the card prices (%d pts) - check" % [uid, cards.size(), int(tot["points"])])
	else:
		warnings.append("%s: made of %d stat cards with several sizes each; only the first card's sizes are used - check" % [uid, cards.size()])
	for c: Dictionary in subs:
		c["options"] = []
	return cards


static func _parse_block(name: String, uid: String, lines: Array, nation: String, warnings: PackedStringArray) -> Array:
	var rows: Array = []
	for l in lines:
		if str(l).strip_edges() != "":
			rows.append(str(l).strip_edges())
	if rows.is_empty():
		warnings.append("%s: empty card" % uid)
		return []
	var cuts: Array = []
	for i in rows.size() - 1:
		if str(rows[i + 1]).to_lower().begins_with("tact"):
			cuts.append(i)
	if not cuts.has(0):
		cuts.insert(0, 0)
	var cards: Array = []
	for n in cuts.size():
		var end: int = cuts[n + 1] if n + 1 < cuts.size() else rows.size()
		var card: Dictionary = _parse_card(name, uid if n == 0 else "%s-%d" % [uid, n + 1], rows.slice(cuts[n], end), nation, warnings)
		if not card.is_empty():
			cards.append(card)
	return _merge_cards(uid, name, cards, warnings) if cards.size() > 1 else cards


static func _support_card(u: Dictionary) -> bool:
	return str(u.get("category", "")) != "air" and not str(u.get("unit_type", "")).to_lower().ends_with("formation")


static func _is_artillery(u: Dictionary) -> bool:
	if not _support_card(u):
		return false
	for w in u.get("weapons", []):
		if bool((w as Dictionary).get("artillery", false)) or bool((w as Dictionary).get("salvo", false)):
			return true
	return false


static func _is_aa(u: Dictionary) -> bool:
	if not _support_card(u):
		return false
	if _rx("aa_name").search(str(u.get("name", ""))) != null:
		return true
	var weapons: Array = u.get("weapons", [])
	if weapons.is_empty():
		return false
	for w in weapons:
		var aa: bool = false
		for r in (w as Dictionary).get("rules", []):
			if str(r).to_lower() in ["dedicated aa", "guided aa"]:
				aa = true
		if not aa:
			return false
	return true

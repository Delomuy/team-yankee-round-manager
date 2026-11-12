class_name TYRules
extends RefCounted
## Dice and rule helpers for Team Yankee. The core rules follow the rulebook text (Rules_clean.txt: Starting,
## Movement, Transports, Shooting, Saves, Pinned Down, Smoke and Artillery, pages 28-56); the special rules come from
## the Complete Special Rules download. Whenever a special rule changes a number, its name is put in the explanation.

const LONG_RANGE_CM: int = 40        # "range over 16"/40cm"
const STAB_LIMIT_CM: int = 25        # "moves more than 10"/25cm"
const RADAR_BONUS_CM: int = 30       # Radar: +12"/30cm range when shooting at Aircraft
const BAZOOKA_FRONT_NATIONS := ["WestGerman", "Belgian", "Norwegian", "Danish", "Canadian", "Dutch", "ANZAC"]
const AUTO: int = -1                 # same marker the converter uses for AUTO / Unlimited
## Artillery "Number of Weapons Firing" to-hit modifier (rules p.53): [most weapons, modifier], first match wins.
## The scan of the rulebook lost most of this table; the rows are rebuilt from the 5-or-6 = -1 example on p.54.
## Change the numbers here if your rulebook says otherwise.
const WEAPONS_FIRING_TABLE := [[2, 1], [4, 0], [6, -1], [9999, -2]]

static var _aa_regex: RegEx = null
static var _mg_regex: RegEx = null


# ------------------------------------------------------------------ dice

## IMPORTANT: d6(), dice(), roll_to_hit(), score_dice(), roll_test() and cross_test() are coroutines: when
## Settings > "Type in every dice result myself" is on they wait for the user (autoload DiceInput). Always call them
## with `await`, and `await` every function that calls them. With the setting off they return at once.

## One die. `what` / `needed` are shown to the user when the results are typed in.
static func d6(what: String = "", needed: int = 0) -> int:
	if AppSettings.manual_dice():
		var v: Array = await DiceInput.ask(1, what, needed)
		return int(v[0])
	return randi_range(1, 6)


## `count` dice at once (one question to the user for all of them).
static func dice(count: int, what: String = "", needed: int = 0) -> Array:
	if count <= 0:
		return []
	if AppSettings.manual_dice():
		return await DiceInput.ask(count, what, needed)
	var out: Array = []
	for i in count:
		out.append(randi_range(1, 6))
	return out


## Rolls `count` dice needing `needed` or more. Scores of 7+ need a 6 followed by 5+, 8+ needs 6 then 6.
## Returns {"results": [{"roll","second","hit"}...], "hits": int}
static func roll_to_hit(count: int, needed: int, what: String = "To hit") -> Dictionary:
	var results: Array = []
	var rolled: Array = await dice(count, what, needed)
	for r in rolled:
		results.append({"roll": int(r), "second": 0, "hit": false})
	var hits: int = await score_dice(results, needed, what)
	return {"results": results, "hits": hits}


## Scores already rolled dice ({"roll"} entries, changed in place) against `needed`+ and rolls the second dice of
## 7+ / 8+ for every 6 (one batch). Returns the number of hits.
static func score_dice(results: Array, needed: int, what: String = "To hit") -> int:
	var sixes: Array = []
	if needed > 6 and needed <= 8:
		for i in results.size():
			if int(results[i]["roll"]) == 6:
				sixes.append(i)
	var seconds: Array = await dice(sixes.size(), "%s: second roll for each 6" % what, needed - 2)
	for k in sixes.size():
		results[int(sixes[k])]["second"] = int(seconds[k])
	var hits: int = 0
	for res in results:
		var scored: Dictionary = hit_from_roll(int(res["roll"]), needed, int(res.get("second", 0)))
		res["hit"] = scored["hit"]
		if res["hit"]:
			hits += 1
	return hits


## Whether a die that showed `r` hits on `needed`+ (a 3+ is passed by a 3, 4, 5 or 6). For 7+ / 8+ a 6 must be
## followed by a `second` roll of 5+ / 6+ (0 = no second roll made). Returns {"roll", "second", "hit"}. Rolls nothing.
static func hit_from_roll(r: int, needed: int, second: int = 0) -> Dictionary:
	if needed <= 6:
		return {"roll": r, "second": 0, "hit": r >= needed}
	if needed > 8 or r < 6:
		return {"roll": r, "second": 0, "hit": false}
	return {"roll": r, "second": second, "hit": second >= needed - 2}


## Rolls a single test needing `needed`+. needed == AUTO passes automatically, needed <= 0 is "not possible".
static func roll_test(needed: int, what: String = "Test") -> Dictionary:
	if needed == AUTO:
		return {"auto": true, "roll": 0, "needed": needed, "ok": true}
	var r: int = await d6(what, needed)
	return {"auto": false, "roll": r, "needed": needed, "ok": needed > 0 and r >= needed}


## Cross Check for Difficult Going. A Cross Here order reduces the Cross number by 1 (rules p.35).
static func cross_number(u: UnitInstance) -> int:
	var need: int = u.data.cross_skill
	if need > 0 and u.order == "cross_here":
		need = maxi(need - 1, 2)
	return need


static func cross_test(u: UnitInstance) -> Dictionary:
	return await roll_test(cross_number(u), "Cross Check for %s" % u.label)


## To-hit modifier of a Bombardment for the number of weapons firing.
static func weapons_firing_modifier(weapons: int) -> int:
	for row in WEAPONS_FIRING_TABLE:
		if weapons <= int(row[0]):
			return int(row[1])
	return 0


## Score to hit one unit under a Bombardment Template (rules p.53) and how it is made up.
## ctx: attempt (1-3), no_los (target not in Line of Sight of the Spotting Team), smoke, night, gone_to_ground
## (default: what the unit did in its own turn).
static func bombard_needed(shooter: UnitInstance, w: WeaponData, target: UnitInstance, weapons: int, ctx: Dictionary) -> Dictionary:
	var needed: int = target.data.is_hit_on
	var parts: Array = ["Is Hit On %d+" % needed]
	var mod: int = weapons_firing_modifier(weapons)
	if mod != 0:
		needed += mod
		parts.append("%+d for %d weapon(s) firing" % [mod, weapons])
	else:
		parts.append("no modifier for %d weapons firing" % weapons)
	var attempt: int = int(ctx.get("attempt", 1))
	if attempt == 2:
		needed += 1
		parts.append("+1 Ranged In on the second attempt")
	elif attempt >= 3:
		needed += 2
		parts.append("+2 Ranged In on the third attempt")
	if bool(ctx.get("gone_to_ground", target.is_gone_to_ground())):
		needed += 1
		var why: String = ""
		if target.moved() and unit_has(target.data, "Scout"):
			why = " (special rule Scout: still Gone to Ground after moving)"
		parts.append("+1 Gone to Ground" + why)
	if bool(ctx.get("no_los", false)):
		needed += 1
		parts.append("+1 not in Line of Sight of the Spotting Team")
	var thermal: bool = unit_has(shooter.data, "Thermal Imaging") or weapon_has(w, "Thermal Imaging")
	if bool(ctx.get("smoke", false)):
		if thermal:
			parts.append("no Smoke penalty (special rule Thermal Imaging)")
		else:
			needed += 1
			parts.append("+1 through Smoke")
	if bool(ctx.get("night", false)):
		needed += 1
		parts.append("+1 Night")
	if needed <= 1:
		needed = 2
		parts.append("a 1 always misses: 2+")
	return {"needed": needed, "parts": parts}


# ------------------------------------------------------------------ text helpers

static func needed_text(n: int) -> String:
	if n == AUTO:
		return "Auto"
	if n <= 0:
		return "-"
	return "%d+" % n


static func fmt_dice(results: Array) -> String:
	var parts: PackedStringArray = []
	for r in results:
		var s: String = str(r["roll"])
		if int(r["second"]) > 0:
			s += "→" + str(r["second"])
		if r["hit"]:
			parts.append("[color=#1f7a2a][b]%s[/b][/color]" % s)
		else:
			parts.append("[color=#b02222]%s[/color]" % s)
	return " ".join(parts)


static func esc(s: String) -> String:
	return s.replace("[", "[lb]")


# ------------------------------------------------------------------ rule lookups

static func norm(s: String) -> String:
	return s.strip_edges().to_lower()


static func weapon_has(w: WeaponData, rule: String) -> bool:
	var r: String = norm(rule)
	for x in w.rules:
		if norm(x) == r:
			return true
	return false


static func unit_has(u: UnitData, rule: String) -> bool:
	var r: String = norm(rule)
	for x in u.special_rules:
		if norm(x) == r:
			return true
	return false


static func is_aa_weapon(w: WeaponData) -> bool:
	for r in ["AA", "AA MG", "Dedicated AA", "Guided AA"]:
		if weapon_has(w, r):
			return true
	if _aa_regex == null:
		_aa_regex = RegEx.new()
		_aa_regex.compile("\\bAA\\b")
	return _aa_regex.search(w.weapon_name) != null


static func is_mg(w: WeaponData) -> bool:
	if _mg_regex == null:
		_mg_regex = RegEx.new()
		_mg_regex.compile("(?i)(\\bMG\\b|\\bLMG\\b|machine|minigun|coax)")
	return _mg_regex.search(w.weapon_name) != null


static func is_aa_mg(w: WeaponData) -> bool:
	return is_aa_weapon(w) and is_mg(w)


static func is_bombardment(w: WeaponData) -> bool:
	return w.salvo or w.artillery


# ------------------------------------------------------------------ how many teams carry a weapon

static func _tokens(s: String) -> Array:
	var stop := ["team", "with", "the", "and", "gun", "missile", "anti", "tank", "rifle", "assault", "mg", "weapon"]
	var out: Array = []
	var cur: String = ""
	for ch in s.to_lower() + " ":
		var c: String = ch
		var is_alnum: bool = (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		if is_alnum:
			cur += c
		else:
			if cur.length() >= 2 and not stop.has(cur) and not out.has(cur):
				out.append(cur)
			cur = ""
	return out


## Best guess at how many teams of the unit carry this weapon (matching the weapon name against the
## composition, e.g. "RPG-7 anti-tank team"). Falls back to every active team. The player can override it.
static func default_teams_for_weapon(u: UnitInstance, w: WeaponData) -> int:
	var active: int = u.active_teams().size()
	var widx: int = u.data.weapons.find(w)
	if widx >= 0:                                  # the models that carry this weapon (see ModelWeapons)
		return u.teams_with_weapon(widx).size()
	if u.option == null or u.option.composition.is_empty():
		return active
	var wt: Array = _tokens(w.weapon_name)
	var best: int = 0
	var best_count: int = 0
	for item in u.option.composition:
		if str(item.get("unit_id", "")) != "":
			continue
		var score: int = 0
		for t in _tokens(str(item.get("name", ""))):
			if wt.has(t):
				score += 1
		if score > best:
			best = score
			best_count = int(item.get("count", 1))
	if best > 0:
		return mini(best_count, active)
	return active


# ------------------------------------------------------------------ armour

## Special armour only counts against HEAT weapons. The Armour rating is the better of the basic
## rating and the special armour rating (FM101).
static func special_armour_vs_heat(u: UnitInstance, facing: String, w: WeaponData) -> int:
	var best: int = 0
	var tandem: bool = weapon_has(w, "Tandem Warhead")
	for r in u.data.special_rules:
		var n: String = norm(r)
		if n.begins_with("bazooka"):
			if facing == "side" or (facing == "front" and BAZOOKA_FRONT_NATIONS.has(u.data.nation)):
				best = maxi(best, 10)
		elif n.begins_with("bdd"):
			if facing == "side":
				best = maxi(best, 13)
		elif n.begins_with("chobham"):
			if facing == "side":
				best = maxi(best, 16)
		elif n == "era" or n.begins_with("era "):
			if facing == "side" and not tandem:
				best = maxi(best, 16)
		elif n.begins_with("appliqu") or n.begins_with("slat"):
			if facing == "side" or facing == "front":
				best = maxi(best, 13)
	return best


## Which special armour rule gives the rating armour_value() returns ("" = the plain rating of the card).
static func armour_rule(target: UnitInstance, facing: String, w: WeaponData) -> String:
	if not weapon_has(w, "HEAT"):
		return ""
	var special: int = special_armour_vs_heat(target, facing, w)
	if special <= target.armour(facing):
		return ""
	for r in target.data.special_rules:
		var n: String = norm(r)
		for key in ["bazooka", "bdd", "chobham", "era", "appliqu", "slat"]:
			if n.begins_with(key):
				return str(r)
	return "special armour"


static func armour_value(target: UnitInstance, facing: String, w: WeaponData) -> int:
	var base: int = target.armour(facing)
	if weapon_has(w, "HEAT"):
		base = maxi(base, special_armour_vs_heat(target, facing, w))
	return base


# ------------------------------------------------------------------ who can shoot what

## Can this weapon engage this target? Returns {"ok", "reason", "rof_one"}.
## rof_one: Anti-aircraft fire from non-Dedicated weapons is made at ROF 1 (Quick Reference "Shooting at Aircraft").
static func target_eligibility(shooter: UnitInstance, w: WeaponData, target: UnitInstance,
		target_stationary: bool, bulletproof: bool) -> Dictionary:
	var res: Dictionary = {"ok": true, "reason": "", "rof_one": false}
	if target.is_air():
		if weapon_has(w, "Overhead Fire"):
			return {"ok": false, "reason": "Overhead Fire weapons cannot shoot at Aircraft.", "rof_one": false}
		if shooter.is_air():
			if weapon_has(w, "Anti-helicopter") and target.is_helicopter():
				return res
			return {"ok": false, "reason": "Aircraft weapons cannot engage this Aircraft.", "rof_one": false}
		if is_aa_weapon(w):
			res["rof_one"] = not (weapon_has(w, "Dedicated AA") or weapon_has(w, "Guided AA"))
			return res
		if target.is_helicopter():
			if weapon_has(w, "Anti-helicopter"):
				res["rof_one"] = true
				return res
			if weapon_has(w, "Guided"):
				res["rof_one"] = true
				return res
			if shooter.is_ground() and not weapon_has(w, "Heavy Weapon"):
				res["rof_one"] = true
				return res
		return {"ok": false, "reason": "Only Anti-aircraft weapons can shoot at Strike Aircraft (Anti-helicopter, Guided and non-Heavy Infantry weapons can also hit Helicopters).", "rof_one": false}
	# ground target
	if weapon_has(w, "Guided AA"):
		return {"ok": false, "reason": "Guided AA weapons cannot target Tank or Infantry Teams.", "rof_one": false}
	if weapon_has(w, "Guided") and target.is_ground() and not (target_stationary and bulletproof):
		return {"ok": false, "reason": "Guided weapons cannot hit Infantry unless they are stationary and in Bulletproof Cover.", "rof_one": false}
	return res


static func max_range(w: WeaponData, target: UnitInstance) -> int:
	var r: int = w.range_cm
	if target.is_air() and weapon_has(w, "Radar"):
		r += RADAR_BONUS_CM
	return r


## ROF the shooter uses right now. 0 means the weapon cannot fire in this state ("-" on the card).
static func effective_rof(shooter: UnitInstance, w: WeaponData, defensive: bool = false) -> int:
	var rof: int = 0
	if shooter.is_air():
		rof = w.rof_moving if w.rof_moving > 0 else w.rof_static   # aircraft are always moving
	else:
		var as_moving: bool = shooter.fires_as_moving()
		if defensive:
			as_moving = shooter.pinned           # Defensive Fire: Halted ROF (Moving ROF if Pinned Down)
		rof = w.rof_moving if as_moving else w.rof_static
		if shooter.pinned and weapon_has(w, "Pinned ROF 1") and rof > 1:
			rof = 1
	return rof


# ------------------------------------------------------------------ to hit

## Score needed on each die. ctx keys: range_cm, concealed, gone_to_ground, out_of_command, smoke, night.
## Returns {"needed": int, "parts": Array of explanation strings}.
static func to_hit_needed(shooter: UnitInstance, w: WeaponData, target: UnitInstance, ctx: Dictionary,
		rof_one_penalty: bool) -> Dictionary:
	var needed: int = target.data.is_hit_on
	var parts: Array = ["Is Hit On %d+" % needed]
	var rng: int = int(ctx.get("range_cm", 0))
	var thermal: bool = unit_has(shooter.data, "Thermal Imaging") or weapon_has(w, "Thermal Imaging")

	if rng > LONG_RANGE_CM:
		var waived: String = ""
		if weapon_has(w, "Guided") or weapon_has(w, "Guided AA"):
			waived = "Guided"
		elif weapon_has(w, "Laser Rangefinder"):
			waived = "Laser Rangefinder"
		elif weapon_has(w, "NLOS"):
			waived = "NLOS"
		elif weapon_has(w, "Accurate") and not shooter.moved():
			waived = "Accurate"
		elif target.is_air() and weapon_has(w, "Radar"):
			waived = "Radar"
		if waived == "":
			needed += 1
			parts.append("+1 range over %dcm" % LONG_RANGE_CM)
		else:
			parts.append("no range penalty (special rule %s)" % waived)

	var concealed: bool = bool(ctx.get("concealed", false))
	var gone: bool = bool(ctx.get("gone_to_ground", false))
	if concealed and gone:
		needed += 2
		parts.append("+2 Concealed and Gone to Ground")
	elif concealed:
		needed += 1
		parts.append("+1 Concealed")

	if bool(ctx.get("out_of_command", false)):
		needed += 1
		parts.append("+1 moved Out of Command")
	if shooter.order == "blitz" and shooter.order_failed:
		needed += 1
		parts.append("+1 failed Blitz Move")
	if bool(ctx.get("smoke", false)):
		if thermal:
			parts.append("no Smoke penalty (special rule Thermal Imaging)")
		else:
			needed += 1
			parts.append("+1 shooting through Smoke")
	if bool(ctx.get("night", false)):
		if thermal:
			parts.append("no Night penalty (special rule Thermal Imaging)")
		else:
			needed += 1
			parts.append("+1 Night")
	if shooter.moved() and (weapon_has(w, "Slow Firing") or weapon_has(w, "Overworked")):
		needed += 1
		parts.append("+1 moved (special rule %s)" % ("Slow Firing" if weapon_has(w, "Slow Firing") else "Overworked"))
	if shooter.move_mode == UnitInstance.MoveMode.TACTICAL and shooter.move_distance > STAB_LIMIT_CM \
			and weapon_has(w, "Stabiliser"):
		needed += 1
		parts.append("+1 moved more than %dcm (special rule Stabiliser)" % STAB_LIMIT_CM)
	if rof_one_penalty:
		needed += 1
		parts.append("+1 a ROF 1 weapon that is not Dedicated AA shooting at Aircraft")
	return {"needed": needed, "parts": parts}

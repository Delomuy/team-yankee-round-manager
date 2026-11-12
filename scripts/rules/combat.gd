class_name Combat
extends RefCounted
## Resolves shooting, bombardments and assaults. Every function works on UnitInstance / TeamState
## objects and writes what happened to the BattleState log (BBCode).


# =========================================================================== helpers

static func _err(state: BattleState, msg: String) -> Dictionary:
	state.log_line("[color=#b35a00](!) %s[/color]" % TYRules.esc(msg))
	return {"ok": false, "error": msg}


## Hits are spread evenly over the teams, starting with `start` (the target team). Returns
## [{"team": TeamState, "count": int}] ordered by team.
static func _allocate(n_hits: int, teams: Array, start: int) -> Array:
	var out: Array = []
	if teams.is_empty():
		return out
	var counts: Dictionary = {}
	var order: Array = []
	for i in n_hits:
		var idx: int = (start + i) % teams.size()
		if not counts.has(idx):
			counts[idx] = 0
			order.append(idx)
		counts[idx] += 1
	order.sort()
	for idx in order:
		out.append({"team": teams[idx], "count": counts[idx]})
	return out


# ------------------------------------------------------------------ dice shown in the dice tray

## Every save, armour save, Firepower and Remount die rolled since begin_rolls(), for the dice animation:
## [{"group", "roll", "hit" (true = good for the one who rolls), "who"}].
static var rolled: Array = []
const ROLL_GROUPS := [
	["save", "Saves  (green = saved)"],
	["armour", "Armour saves: die + armour against Anti-tank  (green = bounced off)"],
	["firepower", "Firepower  (green = passed)"],
	["remount", "Bailed Out again: Remount  (green = stays in the fight)"],
]


## Call before resolving a shot, bombardment or assault roll, then show roll_groups() in the DiceTray.
static func begin_rolls() -> void:
	rolled = []


static func _note(group: String, roll: int, good: bool, who: String) -> void:
	rolled.append({"group": group, "roll": roll, "hit": good, "second": 0, "who": who})


## The dice of the last resolution as titled groups for DiceTray.play_groups(): the to-hit dice first, then the
## saves, armour saves, Firepower tests and Remount rolls that followed.
static func roll_groups(to_hit: Array, to_hit_title: String = "To hit  (green = hit)") -> Array:
	var out: Array = []
	if not to_hit.is_empty():
		out.append({"title": to_hit_title, "dice": to_hit})
	for g in ROLL_GROUPS:
		var dice: Array = []
		for r in rolled:
			if str(r["group"]) == str(g[0]):
				dice.append(r)
		if not dice.is_empty():
			out.append({"title": str(g[1]), "dice": dice})
	return out


static func _fp_reroll_applies(w: WeaponData, shooter: UnitInstance, target: UnitInstance) -> bool:
	# Infantry (not Heavy Weapons) and AA MGs must re-roll successful Firepower tests against Aircraft.
	if not target.is_air():
		return false
	if TYRules.is_aa_mg(w):
		return true
	return shooter.is_ground() and not TYRules.weapon_has(w, "Heavy Weapon") \
			and not TYRules.weapon_has(w, "Guided") and not TYRules.weapon_has(w, "Guided AA")


static func _fp_test(w: WeaponData, shooter: UnitInstance, target: UnitInstance) -> Dictionary:
	var need: int = w.firepower
	var r: int = await TYRules.d6("Firepower test of %s against %s" % [w.weapon_name, target.label], need)
	var ok: bool = need > 0 and r >= need
	_note("firepower", r, ok, w.weapon_name)
	var text: String = "Firepower %d vs %s" % [r, TYRules.needed_text(need)]
	if ok and _fp_reroll_applies(w, shooter, target):
		var r2: int = await TYRules.d6("Firepower re-roll of %s against Aircraft (successful tests are re-rolled)" % w.weapon_name, need)
		ok = r2 >= need
		_note("firepower", r2, ok, w.weapon_name + " (re-roll)")
		text += " (Infantry and AA MGs re-roll successful Firepower against Aircraft: %d)" % r2
	text += " passed" if ok else " failed"
	return {"ok": ok, "text": text}


static func _bail(state: BattleState, target: UnitInstance, team: TeamState) -> String:
	if team.status == TeamState.Status.BAILED_OUT:
		# "If Bailed Out again, pass Motivation (or Remount) or Destroyed."
		var need: int = target.data.remount if target.data.remount > 0 else target.data.courage
		var r: int = await TYRules.d6("Remount test for %s (Bailed Out again)" % team.code, need)
		_note("remount", r, need > 0 and r >= need, team.code)
		if need > 0 and r >= need:
			state.log_line("     already bailed out: Remount test %d vs %s passed, stays bailed out" % [r, TYRules.needed_text(need)])
			return "bailed"
		team.status = TeamState.Status.DESTROYED
		state.log_line("     already bailed out: Remount test %d vs %s failed -> [color=#b02222][b]DESTROYED[/b][/color]" % [r, TYRules.needed_text(need)])
		return "destroyed"
	team.status = TeamState.Status.BAILED_OUT
	state.log_line("     [color=#8a5a00][b]BAILED OUT[/b][/color]")
	return "bailed"


# =========================================================================== one hit

## Resolves one hit on one team. rctx keys: facing ("front"/"side"/"top"), range_cm, bulletproof,
## reroll_saves, no_save (assault: no saves for Infantry or Unarmoured).
## Returns "destroyed", "bailed", "saved" (no effect) or "skip".
static func resolve_hit(state: BattleState, w: WeaponData, shooter: UnitInstance, target: UnitInstance,
		team: TeamState, rctx: Dictionary) -> String:
	if team.status == TeamState.Status.DESTROYED:
		return "skip"
	var tag: String = "[b]%s[/b]" % TYRules.esc(team.team_name)

	if target.uses_armour():
		return await _armour_save(state, w, shooter, target, team, rctx, tag)

	if bool(rctx.get("no_save", false)):
		team.status = TeamState.Status.DESTROYED
		state.log_line("   - %s: no save allowed -> [color=#b02222][b]DESTROYED[/b][/color]" % tag)
		return "destroyed"

	var save: int = target.save_value()
	if save <= 0:
		team.status = TeamState.Status.DESTROYED
		state.log_line("   - %s: no save -> [color=#b02222][b]DESTROYED[/b][/color]" % tag)
		return "destroyed"
	var r: int = await TYRules.d6("Save for %s (hit by %s)" % [team.code, w.weapon_name], save)
	var saved: bool = r >= save
	_note("save", r, saved, team.code)
	var text: String = "Save %d vs %s" % [r, TYRules.needed_text(save)]
	var reroll: bool = bool(rctx.get("reroll_saves", false))
	var why_reroll: String = "successful save re-rolled"
	if TYRules.weapon_has(w, "Brutal") and (target.is_ground() or target.is_unarmoured()):
		reroll = true
		why_reroll = "special rule Brutal: successful save re-rolled"
	if saved and reroll:
		var r2: int = await TYRules.d6("Save re-roll for %s (%s)" % [team.code, why_reroll], save)
		saved = r2 >= save
		_note("save", r2, saved, team.code + " (re-roll)")
		text += " (%s: %d)" % [why_reroll, r2]
	if saved:
		state.log_line("   - %s: %s -> unharmed" % [tag, text])
		return "saved"
	var covered: bool = target.is_ground() and (bool(rctx.get("bulletproof", false)) or team.in_building or target.foxholes)
	if covered or target.is_air():
		var why: String = ""
		if covered:
			why = "in Bulletproof Cover%s, " % (" (building)" if team.in_building else (" (Foxholes)" if target.foxholes else ""))
		var fp: Dictionary = await _fp_test(w, shooter, target)
		if fp["ok"]:
			team.status = TeamState.Status.DESTROYED
			state.log_line("   - %s: %s failed, %s%s -> [color=#b02222][b]DESTROYED[/b][/color]" % [tag, text, why, str(fp["text"])])
			return "destroyed"
		state.log_line("   - %s: %s failed, %s%s -> survives" % [tag, text, why, str(fp["text"])])
		return "saved"
	team.status = TeamState.Status.DESTROYED
	state.log_line("   - %s: %s failed -> [color=#b02222][b]DESTROYED[/b][/color]" % [tag, text])
	return "destroyed"


static func _armour_save(state: BattleState, w: WeaponData, shooter: UnitInstance, target: UnitInstance,
		team: TeamState, rctx: Dictionary, tag: String) -> String:
	var facing: String = str(rctx.get("facing", "front"))
	var rng: int = int(rctx.get("range_cm", 0))
	var heat: bool = TYRules.weapon_has(w, "HEAT")
	var armour: int = TYRules.armour_value(target, facing, w)
	var bonus: int = 1 if (rng > TYRules.LONG_RANGE_CM and not heat) else 0
	var at: int = w.anti_tank
	var bounce: int = at - armour - bonus + 1          # the die that makes the hit bounce off ("needs" only if 2..6)
	var roll: int = await TYRules.d6("Armour save for %s: die + %s armour %d must beat Anti-tank %d of %s" % [
			team.code, facing, armour + bonus, at, w.weapon_name], bounce if bounce >= 2 and bounce <= 6 else 0)
	var total: int = roll + armour + bonus
	_note("armour", roll, total > at, "%s: %d + %d = %d against %d" % [team.code, roll, armour + bonus, total, at])
	var notes: String = ""
	var special: String = TYRules.armour_rule(target, facing, w)
	if special != "":
		notes += ", special rule %s against HEAT" % special
	if bonus > 0:
		notes += ", +1 range over %dcm" % TYRules.LONG_RANGE_CM
	elif rng > TYRules.LONG_RANGE_CM and heat:
		notes += ", special rule HEAT: no +1 for long range"
	var head: String = "   - %s (%s armour %d%s): D6 %d + %d = %d vs Anti-tank %d" % [
			tag, facing, armour, notes, roll, armour + bonus, total, at]
	if total > at:
		state.log_line(head + " -> [color=#666666]no effect[/color]")
		return "saved"
	var fp: Dictionary = await _fp_test(w, shooter, target)
	if total == at:
		if fp["ok"]:
			state.log_line(head + " -> equal, " + str(fp["text"]))
			return await _bail(state, target, team)
		state.log_line(head + " -> equal, " + str(fp["text"]) + " -> no effect")
		return "saved"
	if fp["ok"]:
		team.status = TeamState.Status.DESTROYED
		state.log_line(head + " -> penetrated, " + str(fp["text"]) + " -> [color=#b02222][b]DESTROYED[/b][/color]")
		return "destroyed"
	state.log_line(head + " -> penetrated, " + str(fp["text"]))
	return await _bail(state, target, team)


static func _resolve_allocation(state: BattleState, w: WeaponData, shooter: UnitInstance, target: UnitInstance,
		alloc: Array, rctx: Dictionary) -> Dictionary:
	var destroyed: int = 0
	var bailed: int = 0
	for entry in alloc:
		var team: TeamState = entry["team"]
		var n: int = entry["count"]
		for h in n:
			var res: String = await resolve_hit(state, w, shooter, target, team, rctx)
			if res == "destroyed":
				destroyed += 1
			elif res == "bailed":
				bailed += 1
			if team.status == TeamState.Status.DESTROYED:
				if h < n - 1:
					state.log_line("     (%d further hit(s) on the destroyed team are wasted)" % (n - 1 - h))
				break
		await _hit_passengers(state, w, shooter, team, n, rctx)
	if target.is_destroyed():
		state.log_line("   [b][color=#b04a10]%s is completely destroyed![/color][/b]" % state.tag(target))
	return {"destroyed": destroyed, "bailed": bailed}


## Rules p.37. Passengers ON a tank are hit every time the tank is hit (Infantry Save, no Bulletproof Cover).
## Passengers of a Destroyed transport each roll one Infantry Save; the survivors get out and are Pinned Down
## (in an aircraft they are Destroyed with it).
static func _hit_passengers(state: BattleState, w: WeaponData, shooter: UnitInstance, carrier: TeamState, hits: int, rctx: Dictionary) -> void:
	if not carrier.is_vehicle:
		return
	var riders: Array = state.passengers(carrier, true) if carrier.is_alive() else []
	for r: TeamState in riders:
		var ru: UnitInstance = state.unit_of(r)
		if ru == null:
			continue
		state.log_line("     %s rides on top of %s: it is hit as well (%d hit(s), Infantry Save, no Bulletproof Cover)" % [
				TYRules.esc(r.code), TYRules.esc(carrier.code), hits])
		var c2: Dictionary = rctx.duplicate()
		c2["bulletproof"] = false
		c2["no_save"] = false
		for h in hits:
			if r.is_alive():
				await resolve_hit(state, w, shooter, ru, r, c2)
		if ru.register_hits(hits):
			state.log_line("     [color=#8a5a00]%s is Pinned Down![/color]" % state.tag(ru))
	if carrier.is_alive():
		return
	var inside: Array = []
	for list in state.units:
		for u: UnitInstance in list:
			for t in u.teams:
				if t.carrier == carrier and t.is_alive():
					inside.append([u, t])
	for pair in inside:
		var pu: UnitInstance = pair[0]
		var pm: TeamState = pair[1]
		if carrier.is_aircraft:
			pm.status = TeamState.Status.DESTROYED
			state.log_line("     passenger %s is [color=#b02222][b]DESTROYED[/b][/color] with its aircraft" % TYRules.esc(pm.code))
			continue
		var save: int = pu.save_value()
		var roll: int = await TYRules.d6("Save for passenger %s (its transport %s is Destroyed)" % [pm.code, carrier.code], save)
		_note("save", roll, save > 0 and roll >= save, pm.code + " (passenger)")
		if save > 0 and roll >= save:
			pm.dismount()
			if pu.can_be_pinned():
				pu.pinned = true
			state.log_line("     passenger %s: its transport is Destroyed, Infantry Save %d vs %s -> survives, gets out and is Pinned Down" % [
					TYRules.esc(pm.code), roll, TYRules.needed_text(save)])
		else:
			pm.status = TeamState.Status.DESTROYED
			state.log_line("     passenger %s: its transport is Destroyed, Infantry Save %d vs %s -> [color=#b02222][b]DESTROYED[/b][/color]" % [
					TYRules.esc(pm.code), roll, TYRules.needed_text(save)])


# =========================================================================== direct fire

## Works out (without rolling or logging) what a shot would need. Used for the live preview and by
## fire_weapon. ctx keys: range_cm, concealed, gone_to_ground, out_of_command, smoke, night,
## bulletproof, target_stationary, defensive, bombard.
## Returns {"ok": false, "error"} or {"ok": true, "w", "rof", "teams", "dice", "needed", "parts", "warnings"}.
static func plan_shot(shooter: UnitInstance, widx: int, teams_firing: int, target: UnitInstance,
		ctx: Dictionary) -> Dictionary:
	if widx < 0 or widx >= shooter.data.weapons.size():
		return {"ok": false, "error": "Pick a weapon first."}
	if target == null:
		return {"ok": false, "error": "Pick a target."}
	var w: WeaponData = shooter.data.weapons[widx]
	var defensive: bool = bool(ctx.get("defensive", false))
	var active: int = shooter.active_teams().size()
	if shooter.is_destroyed() or active == 0:
		return {"ok": false, "error": "%s has no active teams left (all bailed out or destroyed)." % shooter.label}
	if target.is_destroyed():
		return {"ok": false, "error": "%s is already destroyed." % target.label}
	if TYRules.is_bombardment(w) and not bool(ctx.get("bombard", false)):
		return {"ok": false, "error": "%s is a bombardment weapon - use the Artillery step." % w.weapon_name}
	if not defensive:
		if shooter.fired_weapons.has(widx) and not bool(ctx.get("per_model", false)):
			return {"ok": false, "error": "%s already fired this turn." % w.weapon_name}
		if shooter.is_dash():
			return {"ok": false, "error": "%s Dashed this turn and cannot Shoot." % shooter.label}
		if shooter.pinned and shooter.moved() and shooter.can_be_pinned():
			return {"ok": false, "error": "%s is Pinned Down and moved: Pinned Down Infantry and Unarmoured teams that Move cannot Shoot at all." % shooter.label}
		if shooter.order == "follow_me" or shooter.order == "cross_here":
			return {"ok": false, "error": "Teams that used Follow Me! / Cross Here cannot Shoot this turn."}
		if shooter.is_strike_aircraft() and not shooter.air_arrived:
			return {"ok": false, "error": "%s has not arrived yet (roll for Strike Aircraft in the Starting Step)." % shooter.label}
		if shooter.move_mode == UnitInstance.MoveMode.TACTICAL and shooter.move_distance > TYRules.STAB_LIMIT_CM \
				and not (TYRules.weapon_has(w, "Stabiliser") or TYRules.weapon_has(w, "Advanced Stabiliser")):
			return {"ok": false, "error": "Moved more than %dcm: only stabilised weapons can Shoot." % TYRules.STAB_LIMIT_CM}
	if TYRules.weapon_has(w, "One Shot") and shooter.used_once.has(widx):
		return {"ok": false, "error": "%s is One Shot and has already been used." % w.weapon_name}

	var rng: int = int(ctx.get("range_cm", 0))
	var max_r: int = TYRules.max_range(w, target)
	if rng > max_r:
		return {"ok": false, "error": "Out of range: target at %dcm, %s reaches %dcm." % [rng, w.weapon_name, max_r]}
	if rng < w.range_cm_min:
		return {"ok": false, "error": "Inside minimum range: %s needs at least %dcm." % [w.weapon_name, w.range_cm_min]}

	var stationary: bool = bool(ctx.get("target_stationary", target.move_mode == UnitInstance.MoveMode.HALTED))
	var elig: Dictionary = TYRules.target_eligibility(shooter, w, target, stationary, bool(ctx.get("bulletproof", false)))
	if not elig["ok"]:
		return {"ok": false, "error": str(elig["reason"])}

	var rof: int = TYRules.effective_rof(shooter, w, defensive)
	if rof <= 0:
		var state_word: String = "moving" if (shooter.fires_as_moving() or shooter.is_air()) else "halted"
		return {"ok": false, "error": "%s has no ROF while %s ('-' on the card)." % [w.weapon_name, state_word]}
	var rof_one_penalty: bool = false
	if elig["rof_one"]:
		if rof == 1:
			rof_one_penalty = true
		else:
			rof = 1
	var teams: int = clampi(teams_firing, 1, active)
	var th: Dictionary = TYRules.to_hit_needed(shooter, w, target, ctx, rof_one_penalty)

	var warnings: Array = []
	if not defensive and (shooter.is_armored() or shooter.is_air()):
		var fired_mg: bool = false
		var fired_other: bool = false
		for k in shooter.fired_weapons.keys():
			if TYRules.is_mg(shooter.data.weapons[k]):
				fired_mg = true
			else:
				fired_other = true
		if TYRules.is_mg(w) and fired_other:
			warnings.append("Tanks and Aircraft fire all their MGs OR one other weapon - this one already fired a non-MG weapon.")
		elif not TYRules.is_mg(w) and (fired_mg or fired_other):
			warnings.append("Tanks and Aircraft fire all their MGs OR one other weapon - another weapon has already fired.")
	# ---- which special rules shaped this shot (shown in the explanation and in the log)
	var notes: Array = []
	if not defensive and shooter.move_mode == UnitInstance.MoveMode.TACTICAL and shooter.move_distance > TYRules.STAB_LIMIT_CM:
		notes.append("%s: may shoot after moving more than %dcm" % [
				"Advanced Stabiliser" if TYRules.weapon_has(w, "Advanced Stabiliser") else "Stabiliser", TYRules.STAB_LIMIT_CM])
	if shooter.pinned and TYRules.weapon_has(w, "Pinned ROF 1"):
		notes.append("Pinned ROF 1: ROF 1 while Pinned Down")
	if shooter.pinned and not defensive and shooter.can_be_pinned():
		notes.append("Pinned Down: shoots with its Moving ROF")
	if target.is_air() and TYRules.weapon_has(w, "Radar"):
		notes.append("Radar: +%dcm range against Aircraft" % TYRules.RADAR_BONUS_CM)
	if target.is_air():
		if elig["rof_one"]:
			notes.append("not a Dedicated AA weapon: ROF 1 against Aircraft")
		elif TYRules.weapon_has(w, "Dedicated AA") or TYRules.weapon_has(w, "Guided AA"):
			notes.append("%s: full ROF against Aircraft" % ("Dedicated AA" if TYRules.weapon_has(w, "Dedicated AA") else "Guided AA"))
	if TYRules.weapon_has(w, "One Shot"):
		notes.append("One Shot: this weapon fires once per game")
	if TYRules.weapon_has(w, "HEAT"):
		notes.append("HEAT: no +1 armour for long range, special armour counts")
	if TYRules.weapon_has(w, "Tandem Warhead"):
		notes.append("Tandem Warhead: ignores ERA")
	if TYRules.weapon_has(w, "Brutal"):
		notes.append("Brutal: Infantry and Unarmoured re-roll successful saves")
	if shooter.order == "blitz" and not shooter.order_failed and not shooter.moved():
		notes.append("Blitz Move passed and no further move: Halted ROF")
	if shooter.order == "dig_in":
		notes.append("Dig In: shoots with its Moving ROF")
	return {"ok": true, "w": w, "rof": rof, "teams": teams, "dice": rof * teams, "needed": th["needed"],
			"parts": th["parts"], "warnings": warnings, "notes": notes}


static func plan_text(plan: Dictionary) -> String:
	if not plan["ok"]:
		return "[color=#b35a00]%s[/color]" % TYRules.esc(str(plan["error"]))
	var s: String = "[b]%d team(s) x ROF %d = %d dice[/b], hit on [b]%s[/b]  [color=#6b6b6b](%s)[/color]" % [
			plan["teams"], plan["rof"], plan["dice"], TYRules.needed_text(plan["needed"]), ", ".join(plan["parts"])]
	for wmsg in plan["warnings"]:
		s += "\n[color=#b35a00](!) %s[/color]" % TYRules.esc(str(wmsg))
	if not (plan.get("notes", []) as Array).is_empty():
		s += "\n   [color=#1b5fa8]Special rules: %s[/color]" % TYRules.esc("; ".join(plan["notes"]))
	return s


## Rolls and resolves one shot. Also used for Defensive Fire in assaults (ctx.defensive = true).
## target_team_idx: index into target.alive_teams() that receives the first hit.
static func fire_weapon(state: BattleState, shooter: UnitInstance, widx: int, teams_firing: int,
		target: UnitInstance, target_team_idx: int, ctx: Dictionary) -> Dictionary:
	var plan: Dictionary = plan_shot(shooter, widx, teams_firing, target, ctx)
	if not plan["ok"]:
		return _err(state, str(plan["error"]))
	var w: WeaponData = plan["w"]
	var defensive: bool = bool(ctx.get("defensive", false))
	var rng: int = int(ctx.get("range_cm", 0))

	state.log_line("")
	state.log_line("[b]%s[/b] %s %s with %s at %dcm: %s" % [
			state.tag(shooter), "fires Defensive Fire at" if defensive else "shoots at", state.tag(target),
			TYRules.esc(w.weapon_name), rng, Combat.plan_text(plan)])
	var roll: Dictionary = await TYRules.roll_to_hit(plan["dice"], plan["needed"],
			"%s: %s at %s with %s" % ["Defensive Fire" if defensive else "To hit", shooter.label, target.label, w.weapon_name])
	var hits: int = roll["hits"]
	state.log_line("   dice: %s  ->  [b]%d hit(s)[/b]" % [TYRules.fmt_dice(roll["results"]), hits])

	if not defensive:
		shooter.fired_weapons[widx] = true
		shooter.shot_this_turn = true
	if TYRules.weapon_has(w, "One Shot"):
		shooter.used_once[widx] = true

	var destroyed: int = 0
	var bailed: int = 0
	if hits > 0:
		if target.register_hits(hits):
			state.log_line("   [color=#8a5a00]%s is Pinned Down![/color]" % state.tag(target))
		var alive: Array = target.alive_teams()
		var start: int = clampi(target_team_idx, 0, maxi(alive.size() - 1, 0))
		var rctx: Dictionary = {
			"facing": str(ctx.get("facing", "front")), "range_cm": rng,
			"bulletproof": bool(ctx.get("bulletproof", false)), "reroll_saves": false}
		var res: Dictionary = await _resolve_allocation(state, w, shooter, target, _allocate(hits, alive, start), rctx)
		destroyed = res["destroyed"]
		bailed = res["bailed"]
	state.touch()
	return {"ok": true, "hits": hits, "destroyed": destroyed, "bailed": bailed}


## Model-to-model shooting: `models` (models of `shooter` that all have weapon `widx`) shoot at `target_models`
## (models of `target`). ctx.shots (optional) = how many shots (dice) go at each target model, in the same order;
## their total cannot exceed the combined ROF. Without it every die is rolled and the hits are spread over the
## target models in the order given.
## Returns {"ok": false, "error"} or {"ok": true, "plan", "results" (the to-hit dice), "hits", "destroyed", "bailed"}.
static func fire_models(state: BattleState, shooter: UnitInstance, models: Array, widx: int,
		target: UnitInstance, target_models: Array, ctx: Dictionary) -> Dictionary:
	var plan: Dictionary = plan_models(shooter, models, widx, target, target_models, ctx)
	if not plan["ok"]:
		return _err(state, str(plan["error"]))
	var w: WeaponData = plan["w"]
	var rng: int = int(ctx.get("range_cm", 0))
	var codes: PackedStringArray = []
	for m: TeamState in models:
		codes.append(m.code)
	var tcodes: PackedStringArray = []
	for m: TeamState in target_models:
		tcodes.append(m.code)
	state.log_line("")
	var defensive: bool = bool(ctx.get("defensive", false))
	state.log_line("[b]%s[/b] (%s) %s %s (%s) with %s at %dcm: %s" % [
			state.tag(shooter), ", ".join(codes), "fires Defensive Fire at" if defensive else "shoots at", state.tag(target), ", ".join(tcodes),
			TYRules.esc(w.weapon_name), rng, Combat.plan_text(plan)])
	var shots: Array = ctx.get("shots", [])
	var per_target: Array = []                    # hits on each target model (only with ctx.shots)
	var roll: Dictionary = {"results": [], "hits": 0}
	var given: Array = ctx.get("rolls", [])         # first dice already rolled by fire_volley (Combat.volley_dice)
	var what: String = "To hit: %s (%s) at %s with %s" % [shooter.label, ", ".join(codes), target.label, w.weapon_name]
	if shots.size() == target_models.size() and not shots.is_empty():
		var total: int = 0
		for n in shots:
			total += int(n)
		if given.size() < total:                     # all the dice of this shot in one go
			var more: Array = await TYRules.dice(total - given.size(), what, plan["needed"])
			given = given.duplicate()
			given.append_array(more)
		var dice_list: Array = []
		for k in total:
			dice_list.append({"roll": int(given[k]), "second": 0, "hit": false})
		await TYRules.score_dice(dice_list, plan["needed"], what)
		var next_die: int = 0
		for i in target_models.size():
			var part_results: Array = dice_list.slice(next_die, next_die + int(shots[i]))
			next_die += int(shots[i])
			var part_hits: int = 0
			for one in part_results:
				if one["hit"]:
					part_hits += 1
			(roll["results"] as Array).append_array(part_results)
			roll["hits"] = int(roll["hits"]) + part_hits
			per_target.append(part_hits)
			state.log_line("   %d shot(s) at %s: %s  ->  [b]%d hit(s)[/b]" % [int(shots[i]), (target_models[i] as TeamState).code,
					TYRules.fmt_dice(part_results), part_hits])
	else:
		roll = await TYRules.roll_to_hit(plan["dice"], plan["needed"], what)
		state.log_line("   dice: %s  ->  [b]%d hit(s)[/b]" % [TYRules.fmt_dice(roll["results"]), int(roll["hits"])])
	var hits: int = roll["hits"]
	if not defensive:
		for m: TeamState in models:
			m.fired[widx] = true
		shooter.fired_weapons[widx] = true
		shooter.shot_this_turn = true
	if TYRules.weapon_has(w, "One Shot"):
		shooter.used_once[widx] = true
	var destroyed: int = 0
	var bailed: int = 0
	if bool(ctx.get("fire_smoke", false)):            # Firing Smoke (rules p.50): hits place Smoke instead of doing damage
		state.log_line("   [color=#1b5fa8]special rule Smoke: %d hit(s) = %d Smoke ball(s) on the target; no damage. Shots into, through or out of them get +1 to hit. Remove them at the start of your next turn.[/color]" % [hits, hits])
		state.touch()
		return {"ok": true, "plan": plan, "results": roll["results"], "hits": hits, "destroyed": 0, "bailed": 0}
	if hits > 0:
		if target.register_hits(hits):
			state.log_line("   [color=#8a5a00]%s is Pinned Down (%d hits this step)![/color]" % [state.tag(target), target.hits_taken])
		var alive: Array = []
		for m: TeamState in target_models:
			if m.is_alive():
				alive.append(m)
		var rctx: Dictionary = {
			"facing": str(ctx.get("facing", "front")), "range_cm": rng,
			"bulletproof": bool(ctx.get("bulletproof", false)), "reroll_saves": false}
		var alloc: Array = _allocate(hits, alive, 0)
		if not per_target.is_empty():
			alloc = []
			for i in target_models.size():
				if int(per_target[i]) > 0:
					alloc.append({"team": target_models[i], "count": int(per_target[i])})
		var res: Dictionary = await _resolve_allocation(state, w, shooter, target, alloc, rctx)
		destroyed = res["destroyed"]
		bailed = res["bailed"]
	state.touch()
	return {"ok": true, "plan": plan, "results": roll["results"], "hits": hits, "destroyed": destroyed, "bailed": bailed}


## "Which weapons can fire" (rules p.38): a Tank or Aircraft Team fires all of its MGs OR one other weapon; an
## Infantry Team fires only one of its weapons. Returns why model `m` cannot fire weapon `widx` as well ("" = it can).
static func fire_limit(shooter: UnitInstance, m: TeamState, widx: int) -> String:
	if m.fired.is_empty() or m.fired.has(widx):
		return ""
	var w: WeaponData = shooter.data.weapons[widx]
	if shooter.is_ground():
		return "%s already fired a weapon this turn: an Infantry Team may only fire one of its weapons." % m.code
	for k in m.fired:
		if int(k) >= shooter.data.weapons.size():
			continue
		if not TYRules.is_mg(shooter.data.weapons[int(k)]) or not TYRules.is_mg(w):
			return "%s already fired this turn: a Tank or Aircraft fires all of its MGs OR one other weapon." % m.code
	return ""


## The most shots these models can fire with weapon `widx` right now: models x ROF (the ROF of how THEY moved).
static func max_shots(shooter: UnitInstance, models: Array, widx: int) -> int:
	if models.is_empty() or widx < 0 or widx >= shooter.data.weapons.size():
		return 0
	var keep_mode: int = shooter.move_mode
	var mode: int = UnitInstance.MoveMode.HALTED
	for m: TeamState in models:
		mode = maxi(mode, m.move_mode)
	shooter.move_mode = mode
	var rof: int = TYRules.effective_rof(shooter, shooter.data.weapons[widx])
	shooter.move_mode = keep_mode
	return maxi(rof, 0) * models.size()


## plan_shot for chosen models (no rolling). Same result keys as plan_shot.
static func plan_models(shooter: UnitInstance, models: Array, widx: int, target: UnitInstance, target_models: Array,
		ctx: Dictionary) -> Dictionary:
	if models.is_empty():
		return {"ok": false, "error": "Pick the models that shoot."}
	if target == null or target_models.is_empty():
		return {"ok": false, "error": "Pick the models that are shot at."}
	for m: TeamState in models:
		if not m.is_active() or m.mounted():
			return {"ok": false, "error": "%s cannot shoot (bailed out, destroyed or being carried)." % m.code}
		if not m.weapons.has(widx):
			return {"ok": false, "error": "%s does not have that weapon." % m.code}
		if m.bogged():
			return {"ok": false, "error": "%s is Bogged Down and cannot Shoot until its next turn." % m.code}
		# ctx.volley: a later part of a volley planned as a whole by plan_volley (the models are already marked as fired)
		if m.fired.has(widx) and not bool(ctx.get("defensive", false)) and not bool(ctx.get("volley", false)):
			return {"ok": false, "error": "%s already fired that weapon this turn." % m.code}
		if not bool(ctx.get("defensive", false)):
			var limit: String = fire_limit(shooter, m, widx)
			if limit != "":
				return {"ok": false, "error": limit}
	for m: TeamState in target_models:
		if not m.is_alive():
			return {"ok": false, "error": "%s is already destroyed." % m.code}
		if m.mounted():
			return {"ok": false, "error": "%s is being carried by %s: shoot at the vehicle." % [m.code, m.carrier.code]}
	var c2: Dictionary = ctx.duplicate()
	c2["per_model"] = true
	# the shot uses the movement of the models that fire, not of the whole unit
	var keep_mode: int = shooter.move_mode
	var keep_dist: int = shooter.move_distance
	var mode: int = UnitInstance.MoveMode.HALTED
	var dist: int = 0
	for m: TeamState in models:
		mode = maxi(mode, m.move_mode)
		dist = maxi(dist, m.move_distance)
	shooter.move_mode = mode
	shooter.move_distance = dist
	var plan: Dictionary = plan_shot(shooter, widx, models.size(), target, c2)
	shooter.move_mode = keep_mode
	shooter.move_distance = keep_dist
	if plan["ok"]:
		var shots: Array = ctx.get("shots", [])
		var total: int = 0
		for n in shots:
			total += int(n)
		if total > int(plan["dice"]):
			return {"ok": false, "error": "%d shots are assigned but these models only have %d (%d model(s) x ROF %d)." % [
					total, int(plan["dice"]), int(plan["teams"]), int(plan["rof"])]}
	return plan


# =========================================================================== volleys over several units

## The index of the weapon called `weapon_name` among the weapons model `m` of unit `u` can fire (-1 = none).
## Weapons are matched by name so that models of the same kind from different cards fire together.
static func weapon_index(u: UnitInstance, m: TeamState, weapon_name: String) -> int:
	for wi in m.weapons:
		if int(wi) < u.data.weapons.size() and (u.data.weapons[int(wi)] as WeaponData).weapon_name == weapon_name:
			return int(wi)
	return -1


## The shooting models grouped by unit, in the order they were picked:
## [{"unit": UnitInstance, "models": Array, "widx": int, "capacity": int (models x ROF)}].
static func volley_groups(state: BattleState, shooters: Array, weapon_name: String) -> Array:
	var groups: Array = []
	var by_unit: Dictionary = {}
	for m: TeamState in shooters:
		var u: UnitInstance = state.unit_of(m)
		if u == null:
			continue
		if not by_unit.has(u):
			by_unit[u] = groups.size()
			groups.append({"unit": u, "models": [], "widx": weapon_index(u, m, weapon_name), "capacity": 0})
		(groups[int(by_unit[u])]["models"] as Array).append(m)
	for g in groups:
		g["capacity"] = max_shots(g["unit"], g["models"], int(g["widx"])) if int(g["widx"]) >= 0 else 0
	return groups


## Splits a volley into parts with one shooting unit and one target unit each, the shape fire_models takes.
## shooters: models of one kind from any of the player's units; targets: models of any enemy units, shots[i] aimed
## at targets[i]. The shots are handed to the shooting units in the order they were picked, each up to its
## models x ROF. Returns {"ok", "error", "groups" (volley_groups), "parts": [{"group", "shooter", "models", "widx",
## "target", "targets", "shots"}]}.
static func split_volley(state: BattleState, shooters: Array, weapon_name: String, targets: Array, shots: Array) -> Dictionary:
	var groups: Array = volley_groups(state, shooters, weapon_name)
	var out: Dictionary = {"ok": true, "error": "", "groups": groups, "parts": []}
	if groups.is_empty():
		out["ok"] = false
		out["error"] = "Pick the models that shoot."
		return out
	for g in groups:
		if int(g["widx"]) < 0:
			out["ok"] = false
			out["error"] = "%s cannot fire %s." % [(g["unit"] as UnitInstance).label, weapon_name]
			return out
	var lookup: Dictionary = {}
	var gi: int = 0
	var left: int = int(groups[0]["capacity"])
	for i in targets.size():
		var tm: TeamState = targets[i]
		var tu: UnitInstance = state.unit_of(tm)
		var n: int = int(shots[i]) if i < shots.size() else 1
		while n > 0:
			while gi < groups.size() and left <= 0:
				gi += 1
				left = int(groups[gi]["capacity"]) if gi < groups.size() else 0
			if gi >= groups.size():
				out["ok"] = false
				out["error"] = "More shots are aimed than the chosen models have (models x ROF)."
				return out
			var take: int = mini(n, left)
			var key: String = "%d_%d" % [gi, tu.get_instance_id()]
			if not lookup.has(key):
				lookup[key] = (out["parts"] as Array).size()
				var g: Dictionary = groups[gi]
				(out["parts"] as Array).append({"group": gi, "shooter": g["unit"], "models": g["models"], "widx": g["widx"],
						"target": tu, "targets": [], "shots": []})
			var part: Dictionary = out["parts"][int(lookup[key])]
			var at: int = (part["targets"] as Array).find(tm)
			if at < 0:
				(part["targets"] as Array).append(tm)
				(part["shots"] as Array).append(take)
			else:
				part["shots"][at] = int(part["shots"][at]) + take
			n -= take
			left -= take
	return out


## Plans every part of a split volley (no rolling). ctx_for: target UnitInstance -> shooting ctx (range, facing,
## concealed ...) for that target unit. Returns {"ok", "error", "plans" (one per part, same order)}.
static func plan_volley(split: Dictionary, ctx_for: Dictionary) -> Dictionary:
	if not split["ok"]:
		return {"ok": false, "error": split["error"], "plans": []}
	var plans: Array = []
	for part in split["parts"]:
		var c: Dictionary = (ctx_for.get(part["target"], {}) as Dictionary).duplicate()
		c["shots"] = part["shots"]
		var plan: Dictionary = plan_models(part["shooter"], part["models"], int(part["widx"]), part["target"], part["targets"], c)
		if not plan["ok"]:
			var who: String = "%s at %s: " % [(part["shooter"] as UnitInstance).code, (part["target"] as UnitInstance).code] \
					if (split["parts"] as Array).size() > 1 else ""
			return {"ok": false, "error": who + str(plan["error"]), "plans": plans}
		plans.append(plan)
	if plans.is_empty():
		return {"ok": false, "error": "Pick the models that are shot at.", "plans": []}
	return {"ok": true, "error": "", "plans": plans}


## Rolls the to-hit dice of a whole volley at once and hands them out: the highest results go to the part with the
## highest to-hit number, the next to the next, and so on (parts needing the same number keep their order).
## Returns one Array of first-die results per part (same order as `parts`).
static func volley_dice(state: BattleState, parts: Array, plans: Array) -> Array:
	var total: int = 0
	var counts: Array = []
	for part in parts:
		var n: int = 0
		for s in part["shots"]:
			n += int(s)
		counts.append(n)
		total += n
	var asked: PackedStringArray = []
	for i in parts.size():
		asked.append("%d at %s needing %s" % [int(counts[i]), (parts[i]["target"] as UnitInstance).label, TYRules.needed_text(int(plans[i]["needed"]))])
	var one_need: int = int(plans[0]["needed"]) if not plans.is_empty() else 0
	for pl in plans:
		if int(pl["needed"]) != one_need:
			one_need = 0                                  # several numbers: no single "needs" line
	var pool: Array = await TYRules.dice(total, "To hit, the whole volley: %s. The highest results go to the hardest numbers." % "; ".join(asked), one_need)
	pool = pool.duplicate()
	pool.sort()
	pool.reverse()
	var order: Array = range(parts.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var na: int = int(plans[a]["needed"])
		var nb: int = int(plans[b]["needed"])
		return na > nb if na != nb else a < b)
	var out: Array = []
	out.resize(parts.size())
	var at: int = 0
	var needs: Array = []
	for idx: int in order:
		var mine: Array = pool.slice(at, at + int(counts[idx]))
		mine.shuffle()            # same to-hit number inside a part: no target model should get the best dice first
		out[idx] = mine
		at += int(counts[idx])
		needs.append(int(plans[idx]["needed"]))
	var distinct: Dictionary = {}
	for n in needs:
		distinct[n] = true
	if distinct.size() > 1:
		var shown: PackedStringArray = []
		for r in pool:
			shown.append(str(r))
		state.log_line("")
		state.log_line("[b]Volley:[/b] %d dice rolled together: %s. The highest results go to the hardest to-hit numbers first." % [
				total, " ".join(shown)])
	return out


## Rolls a whole volley: checks every part first, then fires them one after the other. Shooting models that got no
## shot are marked as fired as well (they were chosen to shoot). Call Combat.begin_rolls() first.
## Returns {"ok", "error", "plans", "results" (all to-hit dice), "hits", "destroyed", "bailed"}.
static func fire_volley(state: BattleState, split: Dictionary, ctx_for: Dictionary) -> Dictionary:
	var check: Dictionary = plan_volley(split, ctx_for)
	if not check["ok"]:
		return _err(state, str(check["error"]))
	var out: Dictionary = {"ok": true, "error": "", "plans": check["plans"], "results": [], "hits": 0, "destroyed": 0, "bailed": 0}
	var rolls_for: Array = await volley_dice(state, split["parts"], check["plans"])
	for i in (split["parts"] as Array).size():
		var part: Dictionary = split["parts"][i]
		var c: Dictionary = (ctx_for.get(part["target"], {}) as Dictionary).duplicate()
		c["shots"] = part["shots"]
		c["volley"] = true
		c["rolls"] = rolls_for[i]
		var res: Dictionary = await fire_models(state, part["shooter"], part["models"], int(part["widx"]), part["target"], part["targets"], c)
		if not res["ok"]:
			continue
		(out["results"] as Array).append_array(res["results"])
		out["hits"] = int(out["hits"]) + int(res["hits"])
		out["destroyed"] = int(out["destroyed"]) + int(res["destroyed"])
		out["bailed"] = int(out["bailed"]) + int(res["bailed"])
	for g in split["groups"]:
		var u: UnitInstance = g["unit"]
		var wi: int = int(g["widx"])
		for m: TeamState in g["models"]:
			m.fired[wi] = true
		u.fired_weapons[wi] = true
		u.shot_this_turn = true
	state.touch()
	return out


## Defensive Fire against an assaulting unit: Halted ROF (Moving if Pinned Down), hits Side armour.
static func defensive_fire(state: BattleState, defender: UnitInstance, widx: int, teams: int,
		attacker: UnitInstance) -> Dictionary:
	var ctx: Dictionary = {"defensive": true, "range_cm": 10, "facing": "side", "concealed": false,
			"gone_to_ground": false, "target_stationary": false}
	return await fire_weapon(state, defender, widx, teams, attacker, 0, ctx)


# =========================================================================== artillery

## Rolls to Range In: up to three attempts on the spotter's Skill. Returns {"attempt": 1..3, or 0 if failed}.
static func range_in(state: BattleState, spotter: UnitInstance, needed: int, label: String) -> int:
	state.log_line("")
	state.log_line("[b]%s[/b] tries to Range In (%s): needs %s per attempt" % [state.tag(spotter), TYRules.esc(label), TYRules.needed_text(needed)])
	for attempt in range(1, 4):
		var t: Dictionary = await TYRules.roll_test(needed, "Range In, attempt %d of 3: %s spots (%s)" % [attempt, spotter.label, label])
		if t["ok"]:
			state.log_line("   attempt %d: rolled %d -> [color=#1f7a2a][b]Ranged In[/b][/color]%s" % [
					attempt, t["roll"], "" if attempt == 1 else " (To Hit +%d)" % (attempt - 1)])
			return attempt
		state.log_line("   attempt %d: rolled %d -> [color=#b02222]missed[/color]" % [attempt, t["roll"]])
	state.log_line("   [color=#b02222]Failed to Range In - the battery fired ranging shots only.[/color]")
	return 0


## One group of teams under the Template. ctx: attempt (1-3), no_spotter (bool), repeat (bool).
static func bombard_group(state: BattleState, shooter: UnitInstance, widx: int, weapons_firing: int,
		target: UnitInstance, teams_under: int, ctx: Dictionary) -> Dictionary:
	if target == null or target.is_destroyed():
		return _err(state, "Pick a living target.")
	var alive: Array = target.alive_teams()
	return await bombard_under(state, shooter, widx, weapons_firing, target, alive.slice(0, clampi(teams_under, 1, alive.size())), ctx)


## Model-based bombardment: `models` of `shooter` fire bombardment weapon `widx`; `under` = the models of `target`
## that are under the Template (one die each). Call once per enemy unit under the Template (ctx.continue = true for
## the second and later units, so One Shot weapons are not refused).
static func bombard_models(state: BattleState, shooter: UnitInstance, models: Array, widx: int,
		target: UnitInstance, under: Array, ctx: Dictionary) -> Dictionary:
	if models.is_empty():
		return _err(state, "Pick the models that bombard.")
	for m: TeamState in models:
		if not m.is_active() or m.mounted():
			return _err(state, "%s cannot bombard (bailed out, destroyed or being carried)." % m.code)
		if not m.weapons.has(widx):
			return _err(state, "%s does not have that weapon." % m.code)
	var firing: int = models.size()
	if TYRules.unit_has(shooter.data, "MLRS"):
		firing *= 2                                   # each MLRS launcher counts as two weapons firing
	var res: Dictionary = await bombard_under(state, shooter, widx, firing, target, under, ctx)
	if res["ok"]:
		for m: TeamState in models:
			m.fired[widx] = true
	return res


## The models of `target` in `under_models` are under the Template: one die each (rules p.53-54).
## ctx: attempt (1-3), no_los, smoke, night, gone_to_ground, continue (second and later units of one bombardment).
static func bombard_under(state: BattleState, shooter: UnitInstance, widx: int, weapons_firing: int,
		target: UnitInstance, under_models: Array, ctx: Dictionary) -> Dictionary:
	if widx < 0 or widx >= shooter.data.weapons.size():
		return _err(state, "Pick a bombardment weapon first.")
	if target == null or target.is_destroyed():
		return _err(state, "Pick a living target.")
	var alive: Array = []
	for um: TeamState in under_models:
		if um.is_alive():
			alive.append(um)
	if alive.is_empty():
		return _err(state, "No living model of %s is under the Template." % target.label)
	var w: WeaponData = shooter.data.weapons[widx]
	if target.is_air():
		return _err(state, "A Bombardment only hits Tank, Infantry and Landed Aircraft teams, not flying Aircraft.")
	var problem: String = bombard_problem(shooter)
	if problem != "":
		return _err(state, problem)
	if TYRules.weapon_has(w, "One Shot") and shooter.used_once.has(widx) and not bool(ctx.get("continue", false)):
		return _err(state, "%s is One Shot and has already been used." % w.weapon_name)

	var th: Dictionary = TYRules.bombard_needed(shooter, w, target, weapons_firing, ctx)
	var needed: int = th["needed"]
	var under: int = alive.size()
	state.log_line("")
	state.log_line("[b]%s[/b] bombards %s with %s (%d weapon(s) firing): %d model(s) under the Template, one die each, hit on [b]%s[/b] [color=#6b6b6b](%s)[/color]" % [
			state.tag(shooter), state.tag(target), TYRules.esc(w.weapon_name), weapons_firing,
			under, TYRules.needed_text(needed), TYRules.esc(", ".join(th["parts"]))])
	if TYRules.unit_has(shooter.data, "MLRS"):
		state.log_line("   [color=#1b5fa8]Special rule MLRS: each launcher counts as two weapons firing.[/color]")
	var roll: Dictionary = await TYRules.roll_to_hit(under, needed, "Bombardment to hit: %s with %s, one die per model of %s under the Template" % [
			shooter.label, w.weapon_name, target.label])
	var hits: int = roll["hits"]
	state.log_line("   dice: %s  ->  [b]%d hit(s)[/b]" % [TYRules.fmt_dice(roll["results"]), hits])

	shooter.bombarded_this_turn = true
	shooter.shot_this_turn = true
	shooter.fired_weapons[widx] = true
	if TYRules.weapon_has(w, "One Shot"):
		shooter.used_once[widx] = true

	var destroyed: int = 0
	var bailed: int = 0
	if hits > 0:
		target.register_hits(hits)
		if target.can_be_pinned() and not target.pinned:
			target.pinned = true               # Infantry and Unarmoured Tank Units hit by a Bombardment are Pinned Down
			state.log_line("   [color=#8a5a00]%s is hit by a Bombardment: automatically Pinned Down.[/color]" % state.tag(target))
		var alloc: Array = []
		for i in under:
			if roll["results"][i]["hit"]:
				alloc.append({"team": alive[i], "count": 1})
		var rctx: Dictionary = {"facing": "top", "range_cm": 0, "bulletproof": bool(ctx.get("bulletproof", false)), "reroll_saves": false}
		if target.uses_armour():
			state.log_line("   Armoured Tank Teams use their Top armour against a Bombardment.")
		var res: Dictionary = await _resolve_allocation(state, w, shooter, target, alloc, rctx)
		destroyed = res["destroyed"]
		bailed = res["bailed"]
	state.touch()
	return {"ok": true, "hits": hits, "destroyed": destroyed, "bailed": bailed, "results": roll["results"], "needed": needed}


## Why this unit cannot fire a Bombardment now ("" = it can). Rules p.51: not after Moving (unless Aircraft), not
## while Pinned Down (unless an Armoured Tank Team), not after a Dig In order.
static func bombard_problem(shooter: UnitInstance) -> String:
	if shooter.is_strike_aircraft() and not shooter.air_arrived:
		return "%s has not arrived yet (Starting Step)." % shooter.label
	if shooter.active_teams().is_empty():
		return "%s has no active teams left." % shooter.label
	if shooter.moved() and not shooter.is_air():
		return "%s Moved this turn: teams that Moved cannot fire a Bombardment (only Aircraft can)." % shooter.label
	if shooter.pinned and not shooter.uses_armour():
		return "%s is Pinned Down and cannot fire a Bombardment." % shooter.label
	if shooter.order == "dig_in":
		return "%s tried to Dig In this turn and cannot fire a Bombardment." % shooter.label
	return ""


## Score the Spotting Team needs to Range In (rules p.53): the worse Skill of the spotter and the artillery unit,
## one less for an Observer. Returns {"needed", "parts"}; needed 0 = this team cannot spot (see "error").
static func range_in_needed(spotter: UnitInstance, battery: UnitInstance) -> Dictionary:
	if spotter.data.skill <= 0:
		return {"needed": 0, "parts": [], "error": "%s has no Skill rating, so it cannot spot." % spotter.label}
	if spotter.spotted_this_turn:
		return {"needed": 0, "parts": [], "error": "%s already spotted for a Bombardment this turn." % spotter.label}
	if spotter != battery and (spotter.moved() or spotter.order == "dig_in"):
		return {"needed": 0, "parts": [], "error": "%s Moved or tried to Dig In: it cannot spot this turn." % spotter.label}
	if spotter != battery and (spotter.shot_this_turn or spotter.assaulted_this_turn):
		return {"needed": 0, "parts": [], "error": "%s already shot: a Spotting Team cannot Shoot or Assault." % spotter.label}
	var needed: int = spotter.data.skill
	var parts: Array = ["Skill %d+ of the Spotting Team" % needed]
	if battery.data.skill > needed:
		needed = battery.data.skill
		parts = ["the worse Skill is used: %d+ of the artillery unit" % needed]
	if TYRules.unit_has(spotter.data, "Observer"):
		needed -= 1
		parts.append("-1 special rule Observer")
	needed = maxi(needed, 2)
	return {"needed": needed, "parts": parts}


static func smoke_bombard(state: BattleState, shooter: UnitInstance, widx: int, weapons_firing: int) -> Dictionary:
	if widx < 0 or widx >= shooter.data.weapons.size():
		return _err(state, "Pick a weapon first.")
	var w: WeaponData = shooter.data.weapons[widx]
	if shooter.used_once.has(widx):
		return _err(state, "%s can only fire a Smoke Bombardment once per game." % w.weapon_name)
	shooter.used_once[widx] = true
	shooter.fired_weapons[widx] = true
	shooter.bombarded_this_turn = true
	shooter.shot_this_turn = true
	state.log_line("")
	state.log_line("[b]%s[/b] fires a Smoke Bombardment with %s: smoke screen %dcm wide (10cm per weapon x %d). It blocks Line of Sight unless the range is 15cm or less." % [
			state.tag(shooter), TYRules.esc(w.weapon_name), weapons_firing * 10, weapons_firing])
	state.touch()
	return {"ok": true}


# =========================================================================== assault

## The Top-armour attack every Infantry team can make in an Assault: Anti-tank 2, Firepower 1+.
static func assault_top_weapon() -> WeaponData:
	var w := WeaponData.new()
	w.weapon_name = "Assault (Top armour)"
	w.anti_tank = 2
	w.firepower = 1
	return w


static func contact_remaining(contact: Array) -> int:
	var n: int = 0
	for t in contact:
		if t.status == TeamState.Status.OK:
			n += 1
	return n


## Assaulting teams roll to hit and the hits are resolved against the defenders in contact.
## w / facing: the weapon an attack on a tank uses ("side" with its Anti-tank, or "top" with AT 2 / FP 1+).
static func assault_attack(state: BattleState, attacker: UnitInstance, att_teams: int, defender: UnitInstance,
		contact: Array, needed: int, w: WeaponData, facing: String) -> Dictionary:
	if needed <= 0:
		return _err(state, "%s has no Assault rating and cannot fight in an Assault." % attacker.label)
	var alive_contact: Array = []
	for t in contact:
		if t.is_alive():
			alive_contact.append(t)
	state.log_line("")
	if alive_contact.is_empty():
		state.log_line("[b]%s[/b] finds no defenders left in contact." % state.tag(attacker))
		return {"ok": true, "hits": 0}
	var dice: int = clampi(att_teams, 1, maxi(attacker.active_teams().size(), 1))
	state.log_line("[b]%s[/b] assaults %s: %d team(s) roll to hit on [b]%s[/b]; hits on tanks use %s" % [
			state.tag(attacker), state.tag(defender), dice, TYRules.needed_text(needed),
			"Side armour with %s (AT %d, FP %s)" % [TYRules.esc(w.weapon_name), w.anti_tank, TYRules.needed_text(w.firepower)]
			if facing == "side" else "Top armour (Anti-tank 2, Firepower 1+)"])
	var roll: Dictionary = await TYRules.roll_to_hit(dice, needed, "Assault to hit: %s against %s" % [attacker.label, defender.label])
	var hits: int = roll["hits"]
	state.log_line("   dice: %s  ->  [b]%d hit(s)[/b]" % [TYRules.fmt_dice(roll["results"]), hits])
	var destroyed: int = 0
	var bailed: int = 0
	if hits > 0:
		var rctx: Dictionary = {"facing": facing, "range_cm": 0, "no_save": true, "bulletproof": false}
		var res: Dictionary = await _resolve_allocation(state, w, attacker, defender, _allocate(hits, alive_contact, 0), rctx)
		destroyed = res["destroyed"]
		bailed = res["bailed"]
	state.touch()
	return {"ok": true, "hits": hits, "destroyed": destroyed, "bailed": bailed, "results": roll["results"]}

class_name CardView
extends RefCounted
## Plain-text (BBCode) version of a unit card, the number formatting helpers the card sheet uses, and the card pop-up.
## Special rules on the card are links (RulesDB.link); connect the label with RulePopup.connect_label().


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


static func _stat(v: int) -> String:
	if v == UnitData.AUTO:
		return "Auto"
	if v <= 0:
		return "-"
	return "%d+" % v


static func _move(cm: int) -> String:
	if cm == UnitData.AUTO:
		return "Unlimited"
	if cm <= 0:
		return "-"
	return "%d\"/%dcm" % [int(round(cm / 2.5)), cm]


static func _rof(w: WeaponData, moving: bool) -> String:
	if w.artillery:
		return "Artillery"
	if w.salvo:
		return "Salvo"
	var v: int = w.rof_moving if moving else w.rof_static
	return "-" if v <= 0 else str(v)


static func _cells(cells: Array, bold: bool = false) -> String:
	var s: String = ""
	for c in cells:
		s += "[cell]%s[/cell]" % (("[b]%s[/b]" % str(c)) if bold else str(c))
	return s


static func build_bbcode(u: UnitData, dynamic: bool = false) -> String:
	var t: String = ""
	t += "[font_size=24][b]%s[/b][/font_size]  [color=#6b6b6b]%s  -  %s[/color]\n" % [_esc(u.display_name), _esc(String(u.id)), u.nation]
	var kind: String = _esc(u.unit_type)
	if not u.special_rules.is_empty():
		kind += ", " + RulesDB.links(u.special_rules, u.nation)       # clickable: see RulePopup
	t += "[i]%s[/i]\n" % kind
	if u.is_attachment:
		t += "[color=#8a5a00]Attachment: not bought on its own.[/color]\n"
	if u.passengers > 0:
		t += "Carries %d passenger team(s)\n" % u.passengers
	t += "\n"

	t += "[table=5]"
	t += _cells(["Tactical", "Terrain Dash", "Cross C. Dash", "Road Dash", "Cross"], true)
	t += _cells([_move(u.tactical), _move(u.terrain_dash), _move(u.cross_dash), _move(u.road_dash), _stat(u.cross_skill)])
	t += "[/table]\n"

	var heads: Array = ["Courage", "Morale"]
	var vals: Array = [_stat(u.courage), _stat(u.morale)]
	if u.rally > 0:
		heads.append("Rally")
		vals.append(_stat(u.rally))
	if u.remount > 0:
		heads.append("Remount")
		vals.append(_stat(u.remount))
	heads.append("Skill")
	vals.append(_stat(u.skill))
	if u.category != UnitData.Category.AIR:
		heads.append_array(["Assault", "Counterattack"])
		vals.append_array([_stat(u.assault), _stat(u.counterattack)])
	heads.append("Is Hit On")
	vals.append(_stat(u.is_hit_on))
	var save = u.get("save")
	if save != null and int(save) > 0:
		heads.append("Save")
		vals.append(_stat(int(save)))
	if u.get("armour_front") != null:
		heads.append_array(["Front", "Side", "Top"])
		vals.append_array([str(u.get("armour_front")), str(u.get("armour_side")), str(u.get("armour_top"))])
	t += "[table=%d]" % heads.size()
	t += _cells(heads, true)
	t += _cells(vals)
	t += "[/table]\n"

	t += "[b]Weapons[/b]\n[table=7]"
	t += _cells(["Weapon", "Range", "h. ROF", "m. ROF", "AT", "FP", "Notes"], true)
	for w in u.weapons:
		var rng: String = "%dcm" % w.range_cm
		if w.range_cm_min > 0:
			rng = "%d-%dcm" % [w.range_cm_min, w.range_cm]
		t += _cells([_esc(w.weapon_name), rng, _rof(w, false), _rof(w, true),
				str(w.anti_tank) if w.anti_tank > 0 else "-", _stat(w.firepower), RulesDB.links(w.rules, u.nation)])
	t += "[/table]\n"

	t += "[b]Options[/b]  [color=#6b6b6b](%s points)[/color]\n[table=3]" % ("dynamic" if dynamic else "standard")
	t += _cells(["Teams", "Models", "Points"], true)
	for o in u.options:
		t += _cells([_esc(o.label), str(o.models), "%d" % o.cost(dynamic)])
	t += "[/table]\n"

	if not u.upgrades.is_empty():
		t += "[b]Upgrades[/b]\n"
		for i in u.upgrades.size():
			t += "- %s  [color=#6b6b6b](%s)[/color]\n" % [_esc(str((u.upgrades[i] as Dictionary).get("text", ""))),
					u.upgrade_price_text(i)]
	if not u.notes.is_empty():
		t += "[b]Notes[/b]\n"
		for n in u.notes:
			t += "- %s\n" % _esc(n)
	return t


## Opens the card in a pop-up (the same sheet as the Cards tab). `host` is any node already in the scene tree.
static func popup(u: UnitData, host: Node) -> void:
	var dlg: AcceptDialog = AcceptDialog.new()
	dlg.title = u.display_name
	dlg.ok_button_text = "Close"
	var room: Vector2 = host.get_viewport().get_visible_rect().size
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(minf(1060.0, room.x - 80.0), minf(700.0, room.y - 140.0))
	var sheet: UnitSheet = UnitSheet.new().setup(u, ArmyManager.use_dynamic_points)
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sheet)
	dlg.add_child(scroll)
	host.add_child(dlg)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()
	UIUtil.fit_popup(dlg, scroll, sheet, room.y - 140.0)       # no empty space under a short card

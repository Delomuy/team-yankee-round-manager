class_name DiceTray
extends VBoxContainer
## Rows of dice that tumble for a moment and then show what was rolled: green = good for whoever rolls, red = bad.
## play(results) shows one row (the "results" list of TYRules.roll_to_hit). play_groups(groups) shows several titled
## rows one after the other: the to-hit dice, then the saves / armour saves, then the Firepower tests
## (see Combat.roll_groups). Each die is {"roll", "hit", optional "second", optional "who" (tooltip)}.

const ROLL_TIME := 0.7                     # seconds one row tumbles
const ROW_DELAY := 0.55                    # each row starts this much after the one before
const DIE := Vector2(34, 34)

var _dice: Array = []                      # [{"data", "label", "panel", "start", "done"}]
var _t: float = 0.0
var _last_tick: int = -1


func _init() -> void:
	add_theme_constant_override("separation", 4)
	set_process(false)


func play(results: Array) -> void:
	play_groups([{"title": "", "dice": results}] if not results.is_empty() else [])


func play_groups(groups: Array) -> void:
	_dice.clear()
	UIUtil.clear_children(self)
	var row_index: int = 0
	for g in groups:
		var dice: Array = g.get("dice", [])
		if dice.is_empty():
			continue
		var row: HFlowContainer = HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 5)
		row.add_theme_constant_override("v_separation", 5)
		if str(g.get("title", "")) != "":
			var title: Label = UIUtil.bold_label(str(g["title"]), 12, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
			title.custom_minimum_size = Vector2(0, DIE.y)
			title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(title)
		for d in dice:
			var p: PanelContainer = PanelContainer.new()
			p.custom_minimum_size = DIE
			p.pivot_offset = DIE * 0.5
			p.add_theme_stylebox_override("panel", AppTheme.box(Color(0.99, 0.98, 0.95), Color(0.25, 0.2, 0.15), 2, 6, 2, 2))
			p.tooltip_text = str((d as Dictionary).get("who", ""))
			var l: Label = UIUtil.bold_label("?", 17, UIUtil.INK)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			p.add_child(l)
			row.add_child(p)
			_dice.append({"data": d, "label": l, "panel": p, "start": ROW_DELAY * row_index, "done": false})
		add_child(row)
		row_index += 1
	_t = 0.0
	_last_tick = -1
	set_process(not _dice.is_empty())


func die_count() -> int:
	return _dice.size()


## Shows every final face at once (also what happens when the tumbling is over).
func finish() -> void:
	set_process(false)
	for d in _dice:
		_settle(d)


func _settle(d: Dictionary) -> void:
	if bool(d["done"]):
		return
	d["done"] = true
	var r: Dictionary = d["data"]
	var text: String = str(int(r["roll"]))
	if int(r.get("second", 0)) > 0:
		text += ">" + str(int(r["second"]))            # a 7+ or 8+: a 6 followed by a second roll
	var label: Label = d["label"]
	var panel: PanelContainer = d["panel"]
	label.text = text
	label.add_theme_color_override("font_color", Color.WHITE)
	panel.rotation = 0.0
	panel.add_theme_stylebox_override("panel", AppTheme.box(UIUtil.GOOD if bool(r["hit"]) else UIUtil.BAD, Color(0.1, 0.1, 0.1), 2, 6, 2, 2))


func _process(delta: float) -> void:
	_t += delta
	var tick: int = int(_t * 18.0)
	var tumble: bool = tick != _last_tick
	_last_tick = tick
	var all_done: bool = true
	for d in _dice:
		if bool(d["done"]):
			continue
		var since: float = _t - float(d["start"])
		if since >= ROLL_TIME:
			_settle(d)
			continue
		all_done = false
		if since >= 0.0 and tumble:                     # rows that have not started yet keep showing "?"
			(d["label"] as Label).text = str(randi_range(1, 6))
			(d["panel"] as PanelContainer).rotation = randf_range(-0.35, 0.35)
	if all_done:
		set_process(false)

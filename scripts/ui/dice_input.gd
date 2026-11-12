extends Node
## Autoload DiceInput: asks the user for the results of real dice when Settings > "Type in every dice result myself"
## is on. TYRules.d6() / TYRules.dice() call ask() and await it, so every rule that rolls waits for the answer.
##   var values: Array = await DiceInput.ask(5, "To hit: 2 x M1A1 at T-72 (needs 4+)", 4)
## The window shows what the dice are for and what they need; buttons 1-6 (or typing digits) enter the results.
## A single die is taken as soon as its button is pressed. "Roll for me" (or closing the window) lets the program
## roll the dice still missing.

signal _answered(values: Array)

var _dialog: AcceptDialog
var _what: Label
var _field: LineEdit
var _status: Label
var _count: int = 0
var _open: bool = false
var _busy: bool = false


## Asks for `count` dice. `what` says what they are for; `needed` (> 0) is shown as "needs N+". Returns the results.
func ask(count: int, what: String, needed: int = 0) -> Array:
	if count <= 0:
		return []
	while _busy:                                   # one question at a time
		await _answered
	_busy = true
	_build()
	_count = count
	var need: String = ""
	if needed > 6:
		need = "\nNeeds a 6, then %d+ on a second roll." % (needed - 2)
	elif needed > 0:
		need = "\nEach die needs %d+ (a %d or more passes)." % [needed, needed]
	_what.text = "%s%s\nEnter %d result%s." % [what if what != "" else "Dice roll", need, count, "" if count == 1 else "s"]
	_field.text = ""
	_update()
	_open = true
	_dialog.reset_size()                             # shrink to the text of this question
	_dialog.popup_centered()
	_field.grab_focus()
	var values: Array = await _answered
	_busy = false
	return values


func _build() -> void:
	if _dialog != null:
		return
	_dialog = AcceptDialog.new()
	_dialog.title = "Enter the dice you rolled"
	_dialog.exclusive = true
	_dialog.theme = AppTheme.build()
	_dialog.ok_button_text = "Use these results"
	_dialog.confirmed.connect(_on_confirmed)
	_dialog.canceled.connect(_on_canceled)
	var col: VBoxContainer = UIUtil.vbox(8)
	col.custom_minimum_size = Vector2(560, 0)
	_what = UIUtil.label("")
	_what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_what.custom_minimum_size = Vector2(560, 0)      # a width before the first layout, or the window grows full height
	col.add_child(_what)
	var keys: HBoxContainer = UIUtil.hbox(6)
	for n in range(1, 7):
		var b: Button = UIUtil.button(str(n), _on_key.bind(n))
		b.custom_minimum_size = Vector2(56, 48)
		b.add_theme_font_size_override("font_size", 22)
		keys.add_child(b)
	col.add_child(keys)
	_field = LineEdit.new()
	_field.placeholder_text = "or type the results, e.g. 6 5 3 1"
	_field.text_changed.connect(_on_text_changed)
	_field.text_submitted.connect(_on_submitted)
	col.add_child(_field)
	var row: HBoxContainer = UIUtil.hbox(6)
	row.add_child(UIUtil.button("Undo last", _on_undo))
	row.add_child(UIUtil.button("Clear", _on_clear))
	row.add_child(UIUtil.button("Roll for me", _on_roll_for_me))
	col.add_child(row)
	_status = UIUtil.label("")
	col.add_child(_status)
	_dialog.add_child(col)
	add_child(_dialog)


## The results typed so far: every digit 1-6 in the field, anything else is ignored.
func _values() -> Array:
	var out: Array = []
	for ch in _field.text:
		if ch >= "1" and ch <= "6":
			out.append(int(ch))
	return out


func _update() -> void:
	var n: int = _values().size()
	if n > _count:
		_status.text = "%d results entered but only %d dice were rolled: remove %d." % [n, _count, n - _count]
	else:
		_status.text = "%d of %d entered." % [n, _count]
	_dialog.get_ok_button().disabled = n != _count


func _on_key(n: int) -> void:
	_field.text = (_field.text.strip_edges() + " " + str(n)).strip_edges()
	_field.caret_column = _field.text.length()
	_update()
	if _count == 1 and _values().size() == 1:      # one die: take it at once
		_dialog.hide()
		_finish(_values())


func _on_undo() -> void:
	var v: Array = _values()
	if not v.is_empty():
		v.pop_back()
	_field.text = " ".join(PackedStringArray(v.map(func(x: int) -> String: return str(x))))
	_update()


func _on_clear() -> void:
	_field.text = ""
	_update()


func _on_roll_for_me() -> void:
	_dialog.hide()
	_finish(_filled(_values()))


func _on_text_changed(_t: String) -> void:
	_update()


func _on_submitted(_t: String) -> void:
	if _values().size() == _count:
		_dialog.hide()
		_finish(_values())


func _on_confirmed() -> void:
	_finish(_values())


## Closing the window (or Escape) rolls the missing dice instead, so a battle step never stays half done.
func _on_canceled() -> void:
	_finish(_filled(_values()))


## `values` cut to _count and topped up with random dice.
func _filled(values: Array) -> Array:
	var out: Array = values.slice(0, _count)
	while out.size() < _count:
		out.append(randi_range(1, 6))
	return out


func _finish(values: Array) -> void:
	if not _open:
		return
	_open = false
	_answered.emit(_filled(values))

class_name UnitEditDialog
extends AcceptDialog
## The full unit card in a window where the unit is configured: click the size on the card, tick the upgrades
## (check boxes with their points) and set how many copies. Used by the army editor to add a card to the army
## (add mode) and to change a card already in the army (edit mode). There are no picture buttons here.

signal applied(option_index: int, upgrades: Dictionary, count: int)

var unit: UnitData
var _sheet: UnitSheet
var _qty: SpinBox
var _price: Label
var _scroll: ScrollContainer


func setup(u: UnitData, option_index: int = 0, upgrades: Dictionary = {}, count: int = 1, add_mode: bool = true) -> UnitEditDialog:
	unit = u
	title = ("Add %s" % u.display_name) if add_mode else ("Change %s" % u.display_name)
	ok_button_text = "Add to army" if add_mode else "Apply changes"
	add_cancel_button("Cancel")
	var room: Vector2 = Vector2(DisplayServer.window_get_size())
	var v: VBoxContainer = UIUtil.vbox(8)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(minf(1060.0, room.x - 120.0), minf(600.0, room.y - 200.0))
	_sheet = UnitSheet.new().setup(u, ArmyManager.use_dynamic_points, true, option_index)
	_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet.set_upgrades(upgrades)
	_sheet.option_chosen.connect(_on_sheet_changed)
	_sheet.upgrades_changed.connect(_update_price)
	scroll.add_child(_sheet)
	v.add_child(scroll)

	var row: HBoxContainer = UIUtil.hbox(10)
	row.add_child(UIUtil.label("Copies of this unit:"))
	_qty = UIUtil.spin(1, 30, maxi(count, 1))
	_qty.value_changed.connect(_on_qty_changed)
	row.add_child(_qty)
	_price = UIUtil.bold_label("", 15, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_price)
	v.add_child(row)
	add_child(v)
	confirmed.connect(_on_confirmed)
	_update_price()
	_scroll = scroll
	about_to_popup.connect(func() -> void: UIUtil.fit_popup.call_deferred(self, _scroll, _sheet, room.y - 220.0))
	return self


## Caps the number of copies (Settings > Limit unit quantities, or 1 in a formation slot). With a cap of 1 the
## copies row only shows the price.
func set_max_copies(n: int) -> void:
	n = maxi(n, 1)
	_qty.max_value = n
	if _qty.value > n:
		_qty.value = n
	_qty.editable = n > 1
	_qty.tooltip_text = "" if n > 1 else "Only one copy can be taken here."
	_update_price()


func chosen_option() -> int:
	return _sheet.selected_option()


func chosen_upgrades() -> Dictionary:
	return _sheet.chosen_upgrades()


## Cost of one copy: size plus the ticked upgrades.
func price_each() -> int:
	var o: UnitOption = unit.get_option(chosen_option())
	var total: int = o.cost(ArmyManager.use_dynamic_points) if o != null else 0
	var ups: Dictionary = chosen_upgrades()
	for idx in ups:
		total += unit.upgrade_cost(int(idx), int(ups[idx]), o)
	return total


func _update_price() -> void:
	var each: int = price_each()
	var n: int = int(_qty.value)
	var o: UnitOption = unit.get_option(chosen_option())
	var base: int = o.cost(ArmyManager.use_dynamic_points) if o != null else 0
	var text: String = "One copy: %d pts" % each
	if each != base:
		text = "One copy: %d + %d upgrades = %d pts" % [base, each - base, each]
	if n > 1:
		text += "      %d copies: %d pts" % [n, each * n]
	_price.text = text


func _on_sheet_changed(_index: int) -> void:
	_update_price()


func _on_qty_changed(_v: float) -> void:
	_update_price()


func _on_confirmed() -> void:
	applied.emit(chosen_option(), chosen_upgrades(), int(_qty.value))

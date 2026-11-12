class_name SettingsScreen
extends MarginContainer
## The Settings section: typing in dice results by hand, the game options (no Morale, limit unit quantities, use
## formations) and the picture shown on the start menu instead of the program name. Every change is saved at once
## (AppSettings). "Hide HQ units" lives in the Cards section (CardBrowser).

signal title_changed

var _chk_manual: CheckBox
var _chk_no_morale: CheckBox
var _chk_formations: CheckBox
var _formations_msg: Label
var _chk_limit: CheckBox
var _title_preview: TextureRect
var _title_note: Label
var _file_dialog: FileDialog


func _init() -> void:
	add_theme_constant_override("margin_left", 24)
	add_theme_constant_override("margin_right", 24)
	add_theme_constant_override("margin_top", 16)
	add_theme_constant_override("margin_bottom", 16)
	var col: VBoxContainer = UIUtil.vbox(10)
	col.add_child(UIUtil.heading("Settings"))

	# ---- dice
	var dice: VBoxContainer = UIUtil.vbox(6)
	dice.add_child(UIUtil.bold_label("Dice", 16, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	_chk_manual = _ink(UIUtil.check("Type in every dice result myself (roll real dice)", AppSettings.manual_dice()))
	_chk_manual.toggled.connect(_on_manual_toggled)
	dice.add_child(_chk_manual)
	dice.add_child(UIUtil.note("When ticked, every roll the program makes (to hit, saves, armour, Firepower, Remount, Rally, "
			+ "Cross Checks, tests, Range In ...) stops and asks for the results you rolled. The window says what the dice "
			+ "are for and what they need. 'Roll for me' lets the program roll that batch."))
	col.add_child(UIUtil.paper_frame(dice, AppTheme.EDGE, 8, 12, 10, 2))

	# ---- game options
	var game: VBoxContainer = UIUtil.vbox(6)
	game.add_child(UIUtil.bold_label("Game options", 16, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	game.add_child(UIUtil.note("'Hide HQ units' is now a tick box in the Cards section, above the cards."))
	_chk_no_morale = _ink(UIUtil.check("Don't use Morale", AppSettings.no_morale()))
	_chk_no_morale.toggled.connect(_on_no_morale_toggled)
	game.add_child(_chk_no_morale)
	game.add_child(UIUtil.note("Play without Unit and Formation Morale checks. (Morale is not programmed yet, so for now "
			+ "this is only remembered.)"))
	_chk_limit = _ink(UIUtil.check("Limit unit quantities", AppSettings.limit_units()))
	_chk_limit.toggled.connect(_on_limit_toggled)
	game.add_child(_chk_limit)
	game.add_child(UIUtil.note("Outside formations, artillery and AA units can be taken at most 2 times each and every other "
			+ "unit once; units marked as exclusive cannot be taken together. The numbers are in the unit files "
			+ "(max_copies, exclusive_with). Units inside a formation do not count: the formation's slots are their limit."))
	_chk_formations = _ink(UIUtil.check("Use formations (every army must have one)", AppSettings.use_formations()))
	_chk_formations.toggled.connect(_on_formations_toggled)
	game.add_child(_chk_formations)
	_formations_msg = UIUtil.label("", UIUtil.BAD)
	_formations_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_formations_msg.visible = false
	game.add_child(_formations_msg)
	game.add_child(UIUtil.note("When ticked, every army is made with a formation (Armies > Players / main armies) and armies "
			+ "without one cannot be loaded from the saved armies. It can only be ticked when no army without a formation "
			+ "has unsaved units: save those armies first (Armies > Saved armies); when you tick it, the armies without a "
			+ "formation are closed (they stay in their saved files). Anatomy of a Formation:\n"
			+ "  •  HQ Unit: every formation is led by a Headquarters unit that commands the platoons of that formation.\n"
			+ "  •  Compulsory Units: the minimum combat platoons or companies you must field to unlock the formation.\n"
			+ "  •  Optional Units: extra combat or support platoons that scale the formation up (extra tank platoons, "
			+ "anti-tank sections, mortar carriers, scout teams ...).\n"
			+ "  •  Formation Command: the formation commander only gives leadership bonuses to units of their own formation."))
	col.add_child(UIUtil.paper_frame(game, AppTheme.EDGE, 8, 12, 10, 2))

	# ---- title picture
	var title: VBoxContainer = UIUtil.vbox(6)
	title.add_child(UIUtil.bold_label("Start menu title", 16, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	title.add_child(UIUtil.note("The start menu shows the name \"%s\". Choose a picture to show instead (PNG, JPG or WEBP)." % AppSettings.PROGRAM_NAME))
	var row: HBoxContainer = UIUtil.hbox(8)
	row.add_child(UIUtil.button("Choose picture...", _on_choose))
	row.add_child(UIUtil.button("Remove picture", _on_remove))
	title.add_child(row)
	_title_note = UIUtil.label("")
	title.add_child(_title_note)
	_title_preview = TextureRect.new()
	_title_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_title_preview.custom_minimum_size = Vector2(360, 140)
	title.add_child(_title_preview)
	col.add_child(UIUtil.paper_frame(title, AppTheme.EDGE, 8, 12, 10, 2))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.custom_minimum_size = Vector2(980, 0)              # readable line length; the rest of the page stays empty
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(col)
	add_child(scroll)
	_show_title()


func _show_title() -> void:
	var tex: Texture2D = AppSettings.title_texture()
	_title_preview.texture = tex
	_title_preview.visible = tex != null
	_title_note.text = "Current title: picture" if tex != null else "Current title: the name \"%s\"" % AppSettings.PROGRAM_NAME


## Dark text on the parchment in every state of a check box.
func _ink(c: CheckBox) -> CheckBox:
	for key in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		c.add_theme_color_override(key, UIUtil.INK)
	return c


func _on_manual_toggled(on: bool) -> void:
	AppSettings.set_manual_dice(on)


func _on_no_morale_toggled(on: bool) -> void:
	AppSettings.set_no_morale(on)


func _on_limit_toggled(on: bool) -> void:
	AppSettings.set_limit_units(on)


## Ticking is refused while an army without a formation has unsaved units; otherwise the armies without a
## formation are closed and every army left gets a formation (ArmyManager.apply_use_formations).
func _on_formations_toggled(on: bool) -> void:
	_formations_msg.visible = false
	if not on:
		AppSettings.set_use_formations(false)
		ArmyManager.roster_changed.emit()          # the Armies page lets formations be unticked again
		return
	var blocking: Array = ArmyManager.armies_blocking_formations()
	if not blocking.is_empty():
		var names: PackedStringArray = []
		for a: Army in blocking:
			names.append("%s (%s)" % [a.army_name, SavedArmiesPage.saved_text(a).to_lower()])
		_chk_formations.set_pressed_no_signal(false)
		_show_formations_msg("Not switched on. These armies have no formation and units that are not saved: %s. "
				% ", ".join(names) + "Save them (Armies > Saved armies) or give them a formation first.", true)
		return
	AppSettings.set_use_formations(true)
	var closed: PackedStringArray = ArmyManager.apply_use_formations()
	_show_formations_msg("Switched on." + ("" if closed.is_empty() else
			" Closed the armies without a formation (they stay in their saved files): %s." % ", ".join(closed)), false)


func _show_formations_msg(text: String, bad: bool) -> void:
	_formations_msg.text = text
	UIUtil.set_color(_formations_msg, UIUtil.BAD if bad else UIUtil.GOOD)
	_formations_msg.visible = true


func _on_choose() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.title = "Choose the title picture"
		_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		_file_dialog.use_native_dialog = true
		_file_dialog.file_selected.connect(_on_file_chosen)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.7)


func _on_file_chosen(path: String) -> void:
	var err: Error = AppSettings.set_title_image(path)
	_show_title()
	if err != OK:
		_title_note.text = "Could not use that file as a picture (error %d)." % err
	title_changed.emit()


func _on_remove() -> void:
	AppSettings.clear_title_image()
	_show_title()
	title_changed.emit()

class_name MainMenu
extends CenterContainer
## The start menu: the program name "TY helper" (or the title picture chosen in Settings) and one big button per
## section. A press emits open_requested with the section name ("Cards", "Formations", "Armies", "Battle", "Test range", "Settings").

signal open_requested(section: String)

const SECTIONS := ["Cards", "Formations", "Armies", "Battle", "Test range", "Settings"]
const HINTS := {
	"Cards": "Browse every unit card",
	"Formations": "Every nation's formations: look at them, try them out, edit them",
	"Armies": "Build the armies of 2 to 8 players",
	"Battle": "Run the battle step by step",
	"Test range": "Try any rule with two test units",
	"Settings": "Dice input and title picture",
}

var _title_box: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col: VBoxContainer = UIUtil.vbox(14)
	col.custom_minimum_size = Vector2(460, 0)
	_title_box = UIUtil.vbox(0)
	col.add_child(_title_box)
	col.add_child(UIUtil.bold_label("Team Yankee unit, army and battle manager", 15, UIUtil.INK))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	col.add_child(gap)
	for s: String in SECTIONS:
		var b: Button = UIUtil.button(s, _on_pressed.bind(s))
		b.custom_minimum_size = Vector2(460, 54)
		b.add_theme_font_size_override("font_size", 22)
		b.tooltip_text = str(HINTS[s])
		col.add_child(b)
	add_child(col)
	refresh_title()


## Shows the title picture if there is one, else the program name.
func refresh_title() -> void:
	UIUtil.clear_children(_title_box)
	var tex: Texture2D = AppSettings.title_texture()
	if tex != null:
		var pic: TextureRect = TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var w: float = 460.0
		var h: float = clampf(w * float(tex.get_height()) / maxf(float(tex.get_width()), 1.0), 60.0, 300.0)
		pic.custom_minimum_size = Vector2(w, h)
		_title_box.add_child(pic)
	else:
		_title_box.add_child(UIUtil.bold_label(AppSettings.PROGRAM_NAME, 64, AppTheme.BROWN))


func _on_pressed(section: String) -> void:
	open_requested.emit(section)

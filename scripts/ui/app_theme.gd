class_name AppTheme
extends RefCounted
## The look of the whole app, copied from the card sheet: parchment pages, dark ink text,
## brown buttons with a red pressed state and brown tabs. Built once by Main and set as its theme.

const INK := Color(0.07, 0.07, 0.07)
const BROWN := Color(0.30, 0.235, 0.153)
const BROWN_LIGHT := Color(0.46, 0.37, 0.25)
const BROWN_HOVER := Color(0.40, 0.31, 0.20)
const RED := Color(0.745, 0.122, 0.141)
const EDGE := Color(0.39, 0.32, 0.24)
const FIELD := Color(1, 1, 1, 0.55)
const CLEAR := Color(0, 0, 0, 0)


static func box(bg: Color, border: Color = CLEAR, border_w: int = 0, radius: int = 6, margin_h: int = 10, margin_v: int = 5) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s


static func build() -> Theme:
	var t: Theme = Theme.new()
	var white: Color = Color.WHITE
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()

	# ---- text on parchment
	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	for type in ["CheckBox", "CheckButton"]:
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(key, type, INK)
		t.set_color("font_disabled_color", type, Color(0.4, 0.4, 0.4))
		t.set_stylebox("normal", type, empty)
		t.set_stylebox("pressed", type, empty)
		t.set_stylebox("hover", type, empty)
		t.set_stylebox("hover_pressed", type, empty)
		t.set_stylebox("focus", type, empty)
		t.set_stylebox("disabled", type, empty)
	t.set_icon("unchecked", "CheckBox", _check_icon(false, false))
	t.set_icon("checked", "CheckBox", _check_icon(false, true))
	t.set_icon("radio_unchecked", "CheckBox", _check_icon(true, false))
	t.set_icon("radio_checked", "CheckBox", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(false, true))
	t.set_icon("radio_unchecked_disabled", "CheckBox", _check_icon(true, false))
	t.set_icon("radio_checked_disabled", "CheckBox", _check_icon(true, true))

	# ---- buttons: brown, lighter on hover, red when pressed
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(BROWN, Color(0.17, 0.12, 0.07), 1, 6, 12, 6))
		t.set_stylebox("hover", type, box(BROWN_HOVER, Color(0.17, 0.12, 0.07), 1, 6, 12, 6))
		t.set_stylebox("pressed", type, box(RED, Color(0.35, 0.05, 0.06), 1, 6, 12, 6))
		t.set_stylebox("hover_pressed", type, box(Color(0.82, 0.16, 0.18), Color(0.35, 0.05, 0.06), 1, 6, 12, 6))
		t.set_stylebox("disabled", type, box(Color(0.55, 0.5, 0.44, 0.7), CLEAR, 0, 6, 12, 6))
		t.set_stylebox("focus", type, box(CLEAR, Color(0.88, 0.66, 0.05), 2, 6, 12, 6))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(key, type, white)
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.55))

	# ---- tooltips: dark text on a light card
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.99, 0.97, 0.90), Color(0.17, 0.12, 0.07), 2, 6, 10, 6))
	t.set_color("font_color", "TooltipLabel", Color(0.06, 0.06, 0.06))
	t.set_color("font_shadow_color", "TooltipLabel", CLEAR)
	t.set_font_size("font_size", "TooltipLabel", 14)

	# ---- sliders
	t.set_stylebox("slider", "HSlider", box(Color(0.72, 0.66, 0.56), EDGE, 1, 4, 0, 4))
	t.set_stylebox("grabber_area", "HSlider", box(BROWN, CLEAR, 0, 4, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(RED, CLEAR, 0, 4, 0, 4))

	# ---- text fields and lists
	for type in ["LineEdit"]:
		t.set_stylebox("normal", type, box(FIELD, EDGE, 1, 4, 6, 4))
		t.set_stylebox("focus", type, box(Color(1, 1, 1, 0.8), RED, 2, 4, 6, 4))
		t.set_stylebox("read_only", type, box(Color(1, 1, 1, 0.3), EDGE, 1, 4, 6, 4))
		t.set_color("font_color", type, INK)
		t.set_color("font_uneditable_color", type, Color(0.3, 0.3, 0.3))
		t.set_color("font_placeholder_color", type, Color(0.4, 0.4, 0.4, 0.8))
		t.set_color("caret_color", type, INK)
		t.set_color("selection_color", type, Color(0.88, 0.66, 0.05, 0.5))
	t.set_stylebox("panel", "ItemList", box(FIELD, EDGE, 1, 4, 4, 4))
	t.set_stylebox("focus", "ItemList", box(CLEAR, RED, 1, 4, 0, 0))
	t.set_stylebox("selected", "ItemList", box(Color(0.88, 0.66, 0.05, 0.45), CLEAR, 0, 3, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", box(Color(0.88, 0.66, 0.05, 0.6), CLEAR, 0, 3, 4, 2))
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_color("font_hovered_color", "ItemList", INK)
	t.set_color("font_hovered_selected_color", "ItemList", INK)
	t.set_color("guide_color", "ItemList", Color(0, 0, 0, 0.08))

	# ---- tabs
	t.set_stylebox("panel", "TabContainer", box(CLEAR, CLEAR, 0, 0, 8, 8))
	t.set_stylebox("tab_selected", "TabContainer", box(BROWN, CLEAR, 0, 6, 16, 8))
	t.set_stylebox("tab_unselected", "TabContainer", box(BROWN_LIGHT, CLEAR, 0, 6, 16, 8))
	t.set_stylebox("tab_hovered", "TabContainer", box(BROWN_HOVER, CLEAR, 0, 6, 16, 8))
	t.set_stylebox("tab_disabled", "TabContainer", box(Color(0.5, 0.45, 0.4, 0.5), CLEAR, 0, 6, 16, 8))
	t.set_color("font_selected_color", "TabContainer", white)
	t.set_color("font_unselected_color", "TabContainer", Color(1, 1, 1, 0.85))
	t.set_color("font_hovered_color", "TabContainer", white)
	t.set_font_size("font_size", "TabContainer", 16)

	# ---- containers draw nothing unless a screen gives them a style
	t.set_stylebox("panel", "PanelContainer", empty)
	t.set_stylebox("panel", "Panel", empty)

	# ---- popup windows: a brown frame and title bar (instead of Godot's dark grey) around a parchment page
	var frame: StyleBoxFlat = box(BROWN, Color(0.17, 0.12, 0.07), 2, 8, 0, 0)
	frame.expand_margin_left = 5
	frame.expand_margin_right = 5
	frame.expand_margin_bottom = 5
	frame.expand_margin_top = 32                  # the title bar is drawn inside this margin
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 10
	t.set_stylebox("embedded_border", "Window", frame)
	var frame_off: StyleBoxFlat = frame.duplicate()
	frame_off.bg_color = BROWN_LIGHT
	t.set_stylebox("embedded_unfocused_border", "Window", frame_off)
	t.set_constant("title_height", "Window", 32)
	t.set_color("title_color", "Window", white)
	t.set_font_size("title_font_size", "Window", 17)
	t.set_color("title_outline_modulate", "Window", CLEAR)
	t.set_stylebox("panel", "AcceptDialog", Paper.style(Color(0.97, 0.96, 0.93), 10, 8))
	t.set_constant("buttons_separation", "AcceptDialog", 16)
	return t


## A box or a radio button drawn for the parchment (the default icons are pale).
static func _check_icon(radio: bool, checked: bool) -> ImageTexture:
	var n: int = 20
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var mid: float = n / 2.0 - 0.5
	for y in n:
		for x in n:
			var inside: bool
			var edge: bool
			var dot: bool
			if radio:
				var d: float = Vector2(x, y).distance_to(Vector2(mid, mid))
				inside = d <= 8.5
				edge = inside and d > 6.8
				dot = d <= 4.2
			else:
				var m: float = maxf(absf(x - mid), absf(y - mid))
				inside = m <= 8.0
				edge = inside and m > 6.4
				dot = m <= 4.4
			var col: Color = CLEAR
			if inside:
				col = Color(1, 1, 1, 0.75)
			if edge:
				col = EDGE
			elif checked and dot:
				col = RED if radio else INK
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

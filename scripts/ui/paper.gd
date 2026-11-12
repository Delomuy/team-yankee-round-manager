class_name Paper
extends RefCounted
## The parchment picture (assets/parchment.jpg) used behind the card sheet, the card pictures and the card grid.
## If the file is missing everything falls back to a plain paper colour.

const PATH := "res://assets/parchment.jpg"
const FALLBACK := Color(0.95, 0.93, 0.88)

static var _tex: Texture2D
static var _looked: bool = false


static func texture() -> Texture2D:
	if not _looked:
		_looked = true
		if ResourceLoader.exists(PATH):
			_tex = load(PATH) as Texture2D
	return _tex


## A panel background with the parchment stretched over it. `tint` darkens it (white = as is).
static func style(tint: Color = Color.WHITE, margin_h: int = 0, margin_v: int = 0) -> StyleBox:
	var t: Texture2D = texture()
	if t == null:
		var flat: StyleBoxFlat = StyleBoxFlat.new()
		flat.bg_color = FALLBACK * tint
		flat.content_margin_left = margin_h
		flat.content_margin_right = margin_h
		flat.content_margin_top = margin_v
		flat.content_margin_bottom = margin_v
		return flat
	var s: StyleBoxTexture = StyleBoxTexture.new()
	s.texture = t
	s.modulate_color = tint
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s

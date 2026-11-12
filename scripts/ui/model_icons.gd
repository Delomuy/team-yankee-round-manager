class_name ModelIcons
extends RefCounted
## The configurable icon of a model in the Battle tab. Pictures live in the model_icons folder and are named after a
## card id ("TU102.png": every model of that card) or a type letter ("I.png": every infantry model without a card
## icon). Looked up in user://model_icons first, then res://model_icons. No picture = a drawn symbol (ModelSymbol).

const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const RES_DIR := "res://model_icons"
const USER_DIR := "user://model_icons"
const MAX_SIDE := 128

static var _cache: Dictionary = {}       # key -> Texture2D (or null: looked, nothing found)


static func save_dir() -> String:
	return RES_DIR if OS.has_feature("editor") else USER_DIR


static func _candidates(key: String) -> Array:
	var out: Array = []
	for dir in [USER_DIR, RES_DIR]:
		for ext in EXTENSIONS:
			out.append("%s/%s.%s" % [dir, key, ext])
	return out


static func _texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	for p in _candidates(key):
		if FileAccess.file_exists(p):
			var img: Image = Image.load_from_file(p)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
				break
		elif ResourceLoader.exists(p):
			var res: Resource = load(p)
			if res is Texture2D:
				tex = res
				break
	_cache[key] = tex
	return tex


## The icon for a model: the card's own picture, else the picture of its type letter, else null.
static func get_icon(card_id: String, letter: String) -> Texture2D:
	var tex: Texture2D = _texture(card_id)
	if tex == null and letter != "":
		tex = _texture(letter)
	return tex


static func has_icon(key: String) -> bool:
	return _texture(key) != null


## Copies (and shrinks) a picture into the icon folder under `key` (a card id or a type letter).
static func set_icon(key: String, source_path: String) -> Error:
	var img: Image = Image.load_from_file(source_path)
	if img == null or img.is_empty():
		return ERR_FILE_CANT_READ
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest > MAX_SIDE:
		var f: float = float(MAX_SIDE) / float(longest)
		img.resize(maxi(int(img.get_width() * f), 1), maxi(int(img.get_height() * f), 1), Image.INTERPOLATE_LANCZOS)
	clear_icon(key)
	DirAccess.make_dir_recursive_absolute(save_dir())
	var err: Error = img.save_png("%s/%s.png" % [save_dir(), key])
	_cache.erase(key)
	return err


static func clear_icon(key: String) -> void:
	for p in _candidates(key):
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		if FileAccess.file_exists(p + ".import"):
			DirAccess.remove_absolute(p + ".import")
	_cache.erase(key)

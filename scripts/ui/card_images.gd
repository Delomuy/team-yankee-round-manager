class_name CardImages
extends RefCounted
## Optional picture for each card. The file is named after the card id (TU102.png, TS114a.jpg ...).
## Pictures are looked up in user://card_images first, then in res://card_images.
## While running from the Godot editor new pictures are saved into res://card_images so they live in
## the project; in an exported game they go to user://card_images.

const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const RES_DIR := "res://card_images"
const USER_DIR := "user://card_images"
const MAX_SIDE := 1024
const THUMB_WIDTH := 440                # card tiles use a smaller copy so many pictures stay cheap

static var _cache: Dictionary = {}      # card id -> Texture2D (or null: looked, nothing found)
static var _thumbs: Dictionary = {}     # card id -> small Texture2D (or null)


static func save_dir() -> String:
	return RES_DIR if OS.has_feature("editor") else USER_DIR


static func _candidates(id: String) -> Array:
	var out: Array = []
	for dir in [USER_DIR, RES_DIR]:
		for ext in EXTENSIONS:
			out.append("%s/%s.%s" % [dir, id, ext])
	return out


static func find_path(id: String) -> String:
	for p in _candidates(id):
		if FileAccess.file_exists(p) or ResourceLoader.exists(p):
			return p
	return ""


static func has_image(id: String) -> bool:
	return get_texture(id) != null


static func get_texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex: Texture2D = null
	var path: String = find_path(id)
	if path != "":
		tex = _load(path)
	_cache[id] = tex
	return tex


## Small version of the picture for the card tiles.
static func get_thumbnail(id: String) -> Texture2D:
	if _thumbs.has(id):
		return _thumbs[id]
	var full: Texture2D = get_texture(id)
	var thumb: Texture2D = full
	if full != null and full.get_width() > THUMB_WIDTH:
		var img: Image = full.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var k: float = float(THUMB_WIDTH) / float(img.get_width())
			img.resize(THUMB_WIDTH, maxi(int(img.get_height() * k), 1), Image.INTERPOLATE_BILINEAR)
			thumb = ImageTexture.create_from_image(img)
	_thumbs[id] = thumb
	return thumb


static func _load(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var img: Image = Image.load_from_file(path)       # works for imported and not-yet-imported files
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
		return null
	if ResourceLoader.exists(path):                       # exported game: only the imported version exists
		var res = load(path)
		if res is Texture2D:
			return res
	return null


## Copies any image file onto a card (re-saved as PNG, shrunk to MAX_SIDE). Returns an Error code.
static func set_image(id: String, source_path: String) -> Error:
	var img: Image = Image.load_from_file(source_path)
	if img == null or img.is_empty():
		return ERR_FILE_UNRECOGNIZED
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest > MAX_SIDE:
		var f: float = float(MAX_SIDE) / float(longest)
		img.resize(maxi(int(img.get_width() * f), 1), maxi(int(img.get_height() * f), 1), Image.INTERPOLATE_LANCZOS)
	clear_image(id)
	var dir: String = save_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var err: Error = img.save_png("%s/%s.png" % [dir, id])
	_forget(id)
	return err


## Removes the picture (every extension, in both folders).
static func clear_image(id: String) -> void:
	for p in _candidates(id):
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		if FileAccess.file_exists(p + ".import"):
			DirAccess.remove_absolute(p + ".import")
	_forget(id)


static func _forget(id: String) -> void:
	_cache.erase(id)
	_thumbs.erase(id)

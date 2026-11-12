class_name AppSettings
extends RefCounted
## The user's settings, kept in user://settings.cfg: whether dice results are typed in by the user, the game options
## (hide HQ cards, no morale, formations) and the optional picture shown on the start menu instead of the program name.
## Game options: hide_hq() is applied by the card lists (CardBrowser; its tick box is in the Cards section),
## limit_units() by the army list (Army). no_morale() is only stored (Morale is not programmed yet).
## use_formations() forces a formation on every army (Army.require_formation, ArmyManager.apply_use_formations,
## ArmyFiles.load_file, Army.list_problems).

const PROGRAM_NAME := "TY helper"
const FILE := "user://settings.cfg"
const TITLE_IMAGE := "user://title_image.png"
const TITLE_MAX_SIDE := 1600

static var _loaded: bool = false
static var _manual_dice: bool = false
static var _hide_hq: bool = false
static var _no_morale: bool = false
static var _use_formations: bool = false
static var _limit_units: bool = true


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(FILE) == OK:
		_manual_dice = bool(cfg.get_value("dice", "manual", false))
		_hide_hq = bool(cfg.get_value("game", "hide_hq", false))
		_no_morale = bool(cfg.get_value("game", "no_morale", false))
		_use_formations = bool(cfg.get_value("game", "use_formations", false))
		_limit_units = bool(cfg.get_value("game", "limit_units", true))


static func save() -> void:
	_ensure()
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("dice", "manual", _manual_dice)
	cfg.set_value("game", "hide_hq", _hide_hq)
	cfg.set_value("game", "no_morale", _no_morale)
	cfg.set_value("game", "use_formations", _use_formations)
	cfg.set_value("game", "limit_units", _limit_units)
	cfg.save(FILE)


# ------------------------------------------------------------------ game options

## true = HQ (commander) cards are left out of the card lists (Cards and the army editor). Armies keep the HQ cards
## they already have.
static func hide_hq() -> bool:
	_ensure()
	return _hide_hq


static func set_hide_hq(on: bool, store: bool = true) -> void:
	_ensure()
	_hide_hq = on
	if store:
		save()


## true = play without Unit and Formation Morale. Stored only: Morale is not programmed yet.
static func no_morale() -> bool:
	_ensure()
	return _no_morale


static func set_no_morale(on: bool, store: bool = true) -> void:
	_ensure()
	_no_morale = on
	if store:
		save()


## true = each army may take a support unit only UnitData.max_copies times (2 for artillery and AA, 1 for the rest
## by default) and never together with a unit it is exclusive with (UnitData.exclusive_with). Formation units do
## not count. Used by Army.support_problem / room_for / list_problems.
static func limit_units() -> bool:
	_ensure()
	return _limit_units


static func set_limit_units(on: bool, store: bool = true) -> void:
	_ensure()
	_limit_units = on
	if store:
		save()


## true = every army must have a formation: new armies get one, armies without one cannot be loaded or fielded.
## Switched on in Settings only when no army without a formation has unsaved units (ArmyManager).
static func use_formations() -> bool:
	_ensure()
	return _use_formations


static func set_use_formations(on: bool, store: bool = true) -> void:
	_ensure()
	_use_formations = on
	if store:
		save()


## true = every dice roll asks the user for the result (real dice on the table).
static func manual_dice() -> bool:
	_ensure()
	return _manual_dice


## Changes the setting. `store` = false changes it for this run only (the smoke test uses that).
static func set_manual_dice(on: bool, store: bool = true) -> void:
	_ensure()
	_manual_dice = on
	if store:
		save()


# ------------------------------------------------------------------ title picture

static func has_title_image() -> bool:
	return FileAccess.file_exists(TITLE_IMAGE)


static func title_texture() -> Texture2D:
	if not has_title_image():
		return null
	var img: Image = Image.load_from_file(TITLE_IMAGE)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## Copies any image file to be the title picture (re-saved as PNG, shrunk to TITLE_MAX_SIDE). Returns an Error code.
static func set_title_image(source_path: String) -> Error:
	var img: Image = Image.load_from_file(source_path)
	if img == null or img.is_empty():
		return ERR_FILE_UNRECOGNIZED
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest > TITLE_MAX_SIDE:
		var f: float = float(TITLE_MAX_SIDE) / float(longest)
		img.resize(maxi(int(img.get_width() * f), 1), maxi(int(img.get_height() * f), 1), Image.INTERPOLATE_LANCZOS)
	return img.save_png(TITLE_IMAGE)


static func clear_title_image() -> void:
	if has_title_image():
		DirAccess.remove_absolute(TITLE_IMAGE)

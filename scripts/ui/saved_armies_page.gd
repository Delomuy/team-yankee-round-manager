class_name SavedArmiesPage
extends VBoxContainer
## The Saved armies page of the Armies section (ArmyFiles: one NAME_NATION_army.json per army in saved_army/).
##   top:     Back, Import file..., Open folder
##   left:    the players' armies with whether each is saved, and Save / Save all
##   right:   every saved army (name, nation, formation, points, units, date) with Load as player N / as a new
##            player, and Delete
## Loading over an army with unsaved changes asks first. With Settings > Use formations on, armies without a
## formation are refused.

signal back_requested
## The roster changed (an army was loaded): the Armies screen redraws its pages.
signal roster_changed
## An army was saved (the overview shows "Saved as ...").
signal army_saved

var _status: Label
var _players: VBoxContainer
var _list: VBoxContainer
var _folder_note: Label
var _file_dialog: FileDialog


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var top: HBoxContainer = UIUtil.hbox(10)
	top.add_child(UIUtil.button("< Back to armies", func() -> void: back_requested.emit()))
	var h: Label = UIUtil.heading("Saved armies")
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(h)
	var imp: Button = UIUtil.button("Import file...", _on_import)
	imp.tooltip_text = "Copy a saved army file from anywhere (another computer, a friend ...) into the saved_army folder"
	top.add_child(imp)
	top.add_child(UIUtil.button("Open folder", func() -> void:
		if not DirAccess.dir_exists_absolute(ArmyFiles.folder()):
			DirAccess.make_dir_recursive_absolute(ArmyFiles.folder())
		OS.shell_open(ArmyFiles.folder_global())))
	add_child(top)
	_folder_note = UIUtil.note("")
	add_child(_folder_note)
	_status = UIUtil.label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	var body: HBoxContainer = UIUtil.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left: VBoxContainer = UIUtil.vbox(6)
	left.custom_minimum_size = Vector2(470, 0)
	left.add_child(UIUtil.bold_label("THE PLAYERS' ARMIES", 18, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	_players = UIUtil.vbox(6)
	left.add_child(_players)
	body.add_child(UIUtil.paper_frame(left, AppTheme.EDGE, 8, 12, 10, 2))
	var right: VBoxContainer = UIUtil.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UIUtil.bold_label("SAVED ARMIES", 18, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = UIUtil.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	right.add_child(scroll)
	var right_frame: Control = UIUtil.paper_frame(right, AppTheme.EDGE, 8, 12, 10, 2)
	right_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right_frame)
	add_child(body)


## Redraws both lists.
func refresh() -> void:
	_folder_note.text = "Each army is one file NAME_NATION_army.json in %s" % ArmyFiles.folder_global()
	UIUtil.clear_children(_players)
	for i in ArmyManager.roster.size():
		_players.add_child(_player_row(i))
	var all: Button = UIUtil.button("Save all", _on_save_all)
	_players.add_child(all)
	UIUtil.clear_children(_list)
	var files: Array = ArmyFiles.list()
	if files.is_empty():
		_list.add_child(UIUtil.note("No saved armies yet. Save one on the left (or on the armies overview)."))
	for info: Dictionary in files:
		_list.add_child(_file_row(info))


func _player_row(i: int) -> Control:
	var a: Army = ArmyManager.roster[i]
	var v: VBoxContainer = UIUtil.vbox(2)
	var row: HBoxContainer = UIUtil.hbox(8)
	var lbl: Label = UIUtil.bold_label("Player %d: %s (%s)" % [i + 1, a.army_name, RulesDB.nation_label(a.nation)], 14,
			UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)
	row.add_child(UIUtil.button("Save", save_player.bind(i)))
	v.add_child(row)
	v.add_child(UIUtil.label(saved_text(a), UIUtil.GOOD if a.is_saved() else Color(0.35, 0.35, 0.35)))
	return v


## "Saved as ...", "Changed since it was saved" or "Not saved yet".
static func saved_text(a: Army) -> String:
	if a.is_saved():
		return "Saved as %s" % a.saved_path.get_file()
	if a.saved_path != "":
		return "Changed since it was saved (%s)" % a.saved_path.get_file()
	return "Not saved yet" + ("" if not a.entries.is_empty() else " (no units)")


func _file_row(info: Dictionary) -> Control:
	var v: VBoxContainer = UIUtil.vbox(2)
	var row: HBoxContainer = UIUtil.hbox(8)
	var head: Label = UIUtil.bold_label("%s  -  %s" % [str(info["name"]), RulesDB.nation_label(str(info["nation"]))], 15,
			UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(head)
	var target: OptionButton = OptionButton.new()
	for i in ArmyManager.roster.size():
		target.add_item("as player %d (%s)" % [i + 1, (ArmyManager.roster[i] as Army).army_name])
	if ArmyManager.roster.size() < ArmyManager.MAX_PLAYERS:
		target.add_item("as a new player")
	target.disabled = str(info["error"]) != ""
	row.add_child(target)
	var load_btn: Button = UIUtil.button("Load", func() -> void: load_into(str(info["path"]), target.selected))
	load_btn.disabled = str(info["error"]) != ""
	row.add_child(load_btn)
	row.add_child(UIUtil.button("Delete", _on_delete.bind(info)))
	v.add_child(row)
	var when: String = Time.get_datetime_string_from_unix_time(int(info["modified"]), true)
	var detail: String
	if str(info["error"]) != "":
		detail = "%s: %s" % [str(info["file"]), str(info["error"])]
	else:
		detail = "%d pts, %d units, %s   -   %s   -   saved %s" % [int(info["points"]), int(info["units"]),
				("formation: " + str(info["formation"])) if str(info["formation"]) != "" else "no formation",
				str(info["file"]), when]
	var d: Label = UIUtil.label(detail, UIUtil.BAD if str(info["error"]) != "" else Color(0.3, 0.3, 0.3))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	return UIUtil.paper_frame(v, AppTheme.EDGE, 6, 8, 6, 1)


# ------------------------------------------------------------------ saving

## Saves player `i`'s army (asks first when it would replace the file of another army).
func save_player(i: int) -> void:
	var a: Army = ArmyManager.roster[i]
	if ArmyFiles.would_replace_other(a):
		_confirm("Replace saved army",
				"There is already a saved army called %s.\nReplace it with %s's army?" % [ArmyFiles.file_name(a), a.army_name],
				"Replace", _do_save.bind(i))
		return
	_do_save(i)


func _do_save(i: int) -> void:
	var a: Army = ArmyManager.roster[i]
	var err: String = ArmyFiles.save(a)
	_set_status(err if err != "" else "Saved %s's army as %s." % [a.army_name, a.saved_path.get_file()], err != "")
	refresh()
	army_saved.emit()


func _on_save_all() -> void:
	var done: PackedStringArray = []
	var skipped: PackedStringArray = []
	for a: Army in ArmyManager.roster:
		if ArmyFiles.would_replace_other(a):
			skipped.append(a.army_name)
			continue
		var err: String = ArmyFiles.save(a)
		if err != "":
			_set_status(err, true)
			refresh()
			return
		done.append(a.army_name)
	var text: String = "Saved: %s." % ", ".join(done) if not done.is_empty() else "Nothing saved."
	if not skipped.is_empty():
		text += " Not saved, a saved army with the same name and nation exists (use its own Save button to replace it): %s." % ", ".join(skipped)
	_set_status(text, not skipped.is_empty())
	refresh()


# ------------------------------------------------------------------ loading

## Loads a saved army file into roster slot `slot` (== roster size: as a new player).
func load_into(path: String, slot: int) -> void:
	if slot < 0:
		return
	var res: Dictionary = ArmyFiles.load_file(path)
	var a: Army = res["army"]
	if a == null:
		_set_status(str(res["error"]), true)
		return
	if slot < ArmyManager.roster.size():
		var old: Army = ArmyManager.roster[slot]
		if not old.entries.is_empty() and not old.is_saved():
			_confirm("Replace an army that is not saved",
					"Player %d's army (%s) has changes that are not saved.\nLoad %s over it anyway?" % [slot + 1, old.army_name, a.army_name],
					"Load anyway", _put.bind(a, slot, res["warnings"]))
			return
	_put(a, slot, res["warnings"])


func _put(a: Army, slot: int, warnings: PackedStringArray) -> void:
	if slot >= ArmyManager.roster.size():
		if ArmyManager.roster.size() >= ArmyManager.MAX_PLAYERS:
			_set_status("There are already %d players." % ArmyManager.MAX_PLAYERS, true)
			return
		ArmyManager.roster.append(a)
		slot = ArmyManager.roster.size() - 1
	else:
		ArmyManager.roster[slot] = a
	var text: String = "Loaded %s as player %d." % [a.army_name, slot + 1]
	if not warnings.is_empty():
		text += " " + " ".join(warnings)
	_set_status(text, not warnings.is_empty())
	roster_changed.emit()
	refresh()


func _on_delete(info: Dictionary) -> void:
	_confirm("Delete saved army", "Delete the saved army %s (%s)?\nThis cannot be undone; the players' armies are not changed."
			% [str(info["name"]), str(info["file"])], "Delete", func() -> void:
				ArmyFiles.delete(str(info["path"]))
				for a: Army in ArmyManager.roster:
					if a.saved_path == str(info["path"]):
						a.saved_path = ""
						a.saved_json = ""
				_set_status("Deleted %s." % str(info["file"]), false)
				refresh())


# ------------------------------------------------------------------ import from anywhere

func _on_import() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.title = "Import a saved army"
		_file_dialog.filters = PackedStringArray(["*.json ; Saved armies"])
		_file_dialog.use_native_dialog = true
		_file_dialog.file_selected.connect(import_from)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.7)


## Copies a saved army file into the saved_army folder (asks before replacing one with the same name and nation).
func import_from(source: String) -> void:
	var res: Dictionary = ArmyFiles.load_file(source)
	var a: Army = res["army"]
	if a == null:
		_set_status(str(res["error"]), true)
		return
	var target: String = ArmyFiles.path_for(a)
	if ProjectSettings.globalize_path(target) == ProjectSettings.globalize_path(source):
		_set_status("That file is already in the saved_army folder.", false)
		return
	if FileAccess.file_exists(target):
		_confirm("Replace saved army", "There is already a saved army called %s.\nReplace it with the imported one?" % target.get_file(),
				"Replace", _do_import.bind(source))
		return
	_do_import(source)


func _do_import(source: String) -> void:
	var r: Dictionary = ArmyFiles.import_file(source)
	if str(r["error"]) != "":
		_set_status(str(r["error"]), true)
	else:
		_set_status("Imported as %s. Load it into a player below." % str(r["path"]).get_file(), false)
	refresh()


# ------------------------------------------------------------------ small helpers

func _set_status(text: String, bad: bool) -> void:
	_status.text = text
	UIUtil.set_color(_status, UIUtil.BAD if bad else UIUtil.GOOD)


func _confirm(title_text: String, text: String, ok: String, action: Callable) -> void:
	var dlg: ConfirmationDialog = ConfirmationDialog.new()
	dlg.title = title_text
	dlg.dialog_text = text
	dlg.ok_button_text = ok
	dlg.confirmed.connect(action)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	(get_tree().root if is_inside_tree() else self as Node).add_child(dlg)   # also when the page is hidden (overview)
	dlg.popup_centered()

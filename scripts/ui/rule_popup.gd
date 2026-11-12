class_name RulePopup
extends RefCounted
## Shows what a special rule does. Any RichTextLabel that contains RulesDB.link(...) text becomes clickable
## after RulePopup.connect_label(label).


## Makes the rule links inside `label` open the pop-up.
static func connect_label(label: RichTextLabel) -> void:
	label.meta_underlined = true
	label.meta_clicked.connect(func(meta: Variant) -> void: RulePopup.handle_meta(meta, label))


## Opens the pop-up if `meta` is a rule link (returns false for any other link).
static func handle_meta(meta: Variant, host: Node) -> bool:
	var s: String = str(meta)
	if not s.begins_with("rule|"):
		return false
	var parts: PackedStringArray = s.split("|")
	if parts.size() < 2:
		return false
	open(parts[1], parts[2] if parts.size() > 2 else "", host)
	return true


## `host` must be a node inside the window the pop-up should sit on top of (e.g. the label that was clicked),
## so it also works from inside the large card pop-up.
static func open(rule_name: String, nation: String, host: Node) -> void:
	var dlg: AcceptDialog = AcceptDialog.new()
	dlg.title = rule_name
	dlg.ok_button_text = "Close"
	var r: RichTextLabel = RichTextLabel.new()
	r.bbcode_enabled = true
	r.selection_enabled = true
	r.text = RulesDB.describe_bbcode(rule_name, nation)
	r.custom_minimum_size = Vector2(580, 320)
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_color_override("default_color", UIUtil.INK)
	dlg.add_child(UIUtil.paper_frame(r, AppTheme.EDGE, 6, 8, 6, 2))
	host.add_child(dlg)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()

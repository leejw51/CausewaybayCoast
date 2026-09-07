## Cozy cream HUD in the style of the reference: portrait card, visitor card, big icon buttons,
## item palette with Grok icons, chat, portal-link popup, login sign.
class_name HUD
extends CanvasLayer

signal login_requested(name: String, url: String)
signal decorate_toggled(on: bool)
signal remove_toggled(on: bool)
signal kind_picked(kind: String)
signal rotate_pressed
signal home_pressed
signal islands_pressed
signal chat_sent(text: String)
signal room_chosen(room_id: int)
signal mute_toggled(muted: bool)
signal zoom_requested(steps: float)
signal camera_rotated(radians: float)
signal ui_focus_requested
signal view_toggled
signal dialogue_choice(npc_id: int, choice: int)

const CREAM := Color("#f6f4eb")
const CREAM_DARK := Color("#e7ecdf")
const BROWN := Color("#6d877b")
const INK := Color("#294a45")
const ORANGE := Color("#dfc58e")
const GREEN := Color("#adc6a3")
const PINK := Color("#b8d4cf")
const BLUE := Color("#9fc7d9")

var root: Control
var login_panel: Control
var name_edit: LineEdit
var url_edit: LineEdit
var player_label: Label
var island_label: Label
var visitors_box: VBoxContainer
var decorate_btn: Button
var remove_btn: Button
var palette_panel: PanelContainer
var palette: GridContainer
var chat_log: RichTextLabel
var chat_edit: LineEdit
var toast: Label
var toast_panel: PanelContainer
var rooms_popup: PanelContainer
var rooms_list: VBoxContainer
var rooms_title: Label
var hint: Label
var flash: ColorRect
var mute_btn: Button
var view_btn: Button
var zoom_label: Label
var crosshair: Label
var _flash_tween: Tween
var dialogue_panel: PanelContainer
var dialogue_name: Label
var dialogue_text: Label
var dialogue_options: GridContainer
var dialogue_npc := 0
var _toast_t := 0.0
var _group := ButtonGroup.new()
var _tweens := {}

const EASE_T := 0.28


## Cosine ease in/out fade + slide for any panel. Every menu goes through this.
func reveal(ctrl: Control, on: bool, slide := Vector2(0, 18)) -> void:
	if _tweens.has(ctrl) and is_instance_valid(_tweens[ctrl]):
		_tweens[ctrl].kill()
	var base: Vector2 = ctrl.get_meta("base_pos", ctrl.position)
	ctrl.set_meta("base_pos", base)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel(
		true
	)
	_tweens[ctrl] = tw
	if on:
		ctrl.visible = true
		ctrl.modulate.a = 0.0
		ctrl.position = base + slide
		tw.tween_property(ctrl, "modulate:a", 1.0, EASE_T)
		tw.tween_property(ctrl, "position", base, EASE_T)
	else:
		tw.tween_property(ctrl, "modulate:a", 0.0, EASE_T)
		tw.tween_property(ctrl, "position", base + slide, EASE_T)
		tw.chain().tween_callback(
			func():
				ctrl.visible = false
				ctrl.position = base
		)


## Buttons breathe on hover (scale around their centre) with the same cosine curve.
func _hoverable(b: Control) -> void:
	b.mouse_entered.connect(
		func():
			b.pivot_offset = b.size / 2.0
			create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).tween_property(
				b, "scale", Vector2(1.06, 1.06), 0.18
			)
	)
	b.mouse_exited.connect(
		func():
			create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).tween_property(
				b, "scale", Vector2.ONE, 0.18
			)
	)


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)

	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	_build_player_card()
	_build_visitor_card()
	_build_camera_controls()
	_build_bottom_bar()
	_build_palette()
	_build_chat()
	_build_toast()
	_build_rooms_popup()
	_build_dialogue()
	_build_login()


# ---------------------------------------------------------------- cards
func _build_player_card() -> void:
	var card := _panel()
	card.position = Vector2(18, 18)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	card.add_child(hb)
	var portrait := _portrait(64)
	hb.add_child(portrait)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	hb.add_child(vb)
	player_label = Label.new()
	player_label.text = "not connected"
	player_label.add_theme_font_size_override("font_size", 24)
	vb.add_child(player_label)
	island_label = Label.new()
	island_label.text = "Causeway Bay Coast"
	island_label.add_theme_color_override("font_color", BROWN)
	island_label.add_theme_font_size_override("font_size", 15)
	vb.add_child(island_label)
	root.add_child(card)


func _portrait(px: int) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sb(CREAM_DARK, BROWN, px / 2, 3, 3))
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	var t := Assets.icon("adventurer_portrait", 128, false)
	if t:
		tr.texture = t
	else:
		var l := Label.new()
		l.text = "🏝"
		l.add_theme_font_size_override("font_size", px - 20)
		frame.add_child(l)
	frame.add_child(tr)
	return frame


func _build_visitor_card() -> void:
	var card := _panel()
	card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.position = Vector2(-18, 18)
	card.custom_minimum_size = Vector2(230, 0)
	var vb := VBoxContainer.new()
	card.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := Label.new()
	t.text = "On this island"
	t.add_theme_font_size_override("font_size", 18)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	view_btn = Button.new()
	view_btn.text = "👁 iso"
	view_btn.flat = true
	view_btn.tooltip_text = "Toggle isometric / first-person  (V)"
	view_btn.pressed.connect(
		func():
			Sfx.play("click")
			view_toggled.emit()
	)
	hb.add_child(view_btn)
	mute_btn = Button.new()
	mute_btn.text = "🔊"
	mute_btn.flat = true
	mute_btn.toggle_mode = true
	mute_btn.toggled.connect(
		func(on):
			mute_btn.text = "🔇" if on else "🔊"
			mute_toggled.emit(on)
	)
	hb.add_child(mute_btn)
	visitors_box = VBoxContainer.new()
	visitors_box.add_theme_constant_override("separation", 2)
	vb.add_child(visitors_box)
	root.add_child(card)


func set_visitors(players: Array, my_id: int) -> void:
	for c in visitors_box.get_children():
		c.queue_free()
	for p in players:
		var l := Label.new()
		var me := int(p["id"]) == my_id
		var npc := bool(p.get("is_npc", false))
		l.text = (
			"%s  %s%s"
			% ["✦" if npc else "●", p["name"], "  (you)" if me else ("  islander" if npc else "")]
		)
		l.add_theme_color_override(
			"font_color", Color.html(str(p.get("colour", "#ffcc66"))).darkened(0.25)
		)
		l.add_theme_font_size_override("font_size", 16)
		visitors_box.add_child(l)


# ---------------------------------------------------------------- bottom bar
func _big_button(icon_name: String, emoji: String, text: String, tint: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(116, 64)
	b.text = text
	b.add_theme_font_size_override("font_size", 17)
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 24)
	var ic: Texture2D = null
	if ic:
		b.icon = ic
	else:
		b.text = text
	_style_button(b, tint, 18)
	_hoverable(b)
	return b


func _build_bottom_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position = Vector2(0, -18)
	bar.add_theme_constant_override("separation", 14)
	decorate_btn = _big_button("btn_decorate", "🛠", "Decorate", ORANGE)
	decorate_btn.toggle_mode = true
	decorate_btn.toggled.connect(
		func(on):
			Sfx.play("click")
			decorate_toggled.emit(on)
	)
	bar.add_child(decorate_btn)
	remove_btn = _big_button("", "", "Remove", PINK)
	remove_btn.toggle_mode = true
	remove_btn.tooltip_text = "Click a decoration to remove it · Esc exits"
	remove_btn.toggled.connect(
		func(on):
			Sfx.play("click")
			remove_toggled.emit(on)
	)
	bar.add_child(remove_btn)
	var islands := _big_button("btn_islands", "🗺", "Islands", GREEN)
	islands.pressed.connect(
		func():
			Sfx.play("click")
			islands_pressed.emit()
	)
	bar.add_child(islands)
	var home := _big_button("btn_home", "🏠", "Home", PINK)
	home.pressed.connect(
		func():
			Sfx.play("click")
			home_pressed.emit()
	)
	bar.add_child(home)
	root.add_child(bar)

	hint = Label.new()
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position = Vector2(140, -96)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", CREAM)
	hint.add_theme_color_override("font_outline_color", INK)
	hint.add_theme_constant_override("outline_size", 2)
	hint.add_theme_font_size_override("font_size", 14)
	hint.text = "WASD move   ·   E talk   ·   Tab decorate   ·   Enter chat   ·   V view"
	root.add_child(hint)


func _build_palette() -> void:
	palette_panel = _panel()
	palette_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	palette_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	palette_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	palette_panel.position = Vector2(-18, -100)
	var vb := VBoxContainer.new()
	palette_panel.add_child(vb)
	var title := HBoxContainer.new()
	vb.add_child(title)
	var l := Label.new()
	l.text = "Furnish"
	l.add_theme_font_size_override("font_size", 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(l)
	var rot := Button.new()
	rot.text = "↻ rotate  (R)"
	_style_button(rot, BLUE, 10)
	rot.pressed.connect(
		func():
			Sfx.play("click")
			rotate_pressed.emit()
	)
	title.add_child(rot)
	palette = GridContainer.new()
	palette.columns = 2
	palette.add_theme_constant_override("h_separation", 8)
	palette.add_theme_constant_override("v_separation", 8)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(228, 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	scroll.add_child(palette)
	for k in Assets.ITEM_KINDS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(104, 74)
		b.toggle_mode = true
		b.button_group = _group
		b.text = Assets.ITEM_LABELS[k]
		b.add_theme_font_size_override("font_size", 14)
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 60)
		var ic := Assets.icon("item_" + k, 120)
		if ic:
			b.icon = ic
		else:
			b.text = Assets.ITEM_EMOJI[k] + "\n" + Assets.ITEM_LABELS[k]
		_style_button(b, CREAM_DARK, 14)
		_hoverable(b)
		b.pressed.connect(
			func():
				Sfx.play("click")
				kind_picked.emit(k)
		)
		palette.add_child(b)
	palette_panel.visible = false
	root.add_child(palette_panel)


# ---------------------------------------------------------------- chat
func _build_chat() -> void:
	var chat := _panel()
	chat.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat.position = Vector2(18, -18)
	chat.custom_minimum_size = Vector2(330, 0)
	var vb := VBoxContainer.new()
	chat.add_child(vb)
	chat_log = RichTextLabel.new()
	chat_log.custom_minimum_size = Vector2(300, 110)
	chat_log.scroll_following = true
	chat_log.bbcode_enabled = true
	chat_log.add_theme_color_override("default_color", INK)
	chat_log.add_theme_font_size_override("normal_font_size", 15)
	vb.add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "say something…"
	chat_edit.focus_entered.connect(func(): ui_focus_requested.emit())
	chat_edit.text_submitted.connect(
		func(t):
			if t.strip_edges() != "":
				chat_sent.emit(t)
			chat_edit.text = ""
			chat_edit.release_focus()
	)
	vb.add_child(chat_edit)
	root.add_child(chat)


func add_chat(name: String, text: String, system := false) -> void:
	if system:
		chat_log.append_text("[color=#6d877b][i]%s[/i][/color]\n" % text.replace("[", "[lb]"))
	else:
		chat_log.append_text(
			(
				"[b][color=#c97a5a]%s[/color][/b]  %s\n"
				% [name.replace("[", "[lb]"), text.replace("[", "[lb]")]
			)
		)


# ---------------------------------------------------------------- toast / popups / login
func _build_toast() -> void:
	toast_panel = _panel(Color("#294a45"), Color("#2e2019"))
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.position = Vector2(0, 22)
	toast_panel.custom_minimum_size = Vector2(560, 0)
	toast = Label.new()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 17)
	toast.add_theme_color_override("font_color", CREAM)
	toast_panel.add_child(toast)
	toast_panel.visible = false
	root.add_child(toast_panel)


func _build_rooms_popup() -> void:
	rooms_popup = _panel()
	rooms_popup.set_anchors_preset(Control.PRESET_CENTER)
	rooms_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rooms_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	rooms_popup.custom_minimum_size = Vector2(380, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	rooms_popup.add_child(vb)
	rooms_title = Label.new()
	rooms_title.text = "Islands"
	rooms_title.add_theme_font_size_override("font_size", 22)
	vb.add_child(rooms_title)
	rooms_list = VBoxContainer.new()
	rooms_list.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	scroll.add_child(rooms_list)
	var close := Button.new()
	close.text = "Close"
	_style_button(close, CREAM_DARK, 12)
	close.pressed.connect(func(): reveal(rooms_popup, false))
	vb.add_child(close)
	rooms_popup.visible = false
	root.add_child(rooms_popup)


func show_rooms(rooms: Array, exclude_id: int, linking: bool) -> void:
	ui_focus_requested.emit()
	for c in rooms_list.get_children():
		rooms_list.remove_child(c)
		c.queue_free()
	rooms_title.text = "Link your portal to…" if linking else "Visit an island"
	for r in rooms:
		if int(r["id"]) == exclude_id:
			continue
		var b := Button.new()
		b.text = "🏝  %s   ·  %s   ·  👥 %d" % [r["name"], r["owner"], int(r["visitors"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_button(b, CREAM_DARK if not linking else Color("#d9c8f0"), 12)
		var rid := int(r["id"])
		b.pressed.connect(
			func():
				reveal(rooms_popup, false)
				room_chosen.emit(rid)
		)
		rooms_list.add_child(b)
	if rooms_list.get_child_count() == 0:
		var l := Label.new()
		l.text = "No other islands yet. Invite a friend to join the server!"
		rooms_list.add_child(l)
	reveal(rooms_popup, true)


func _build_dialogue() -> void:
	dialogue_panel = _panel()
	dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialogue_panel.position = Vector2(60, -215)
	dialogue_panel.custom_minimum_size = Vector2(560, 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	dialogue_panel.add_child(hb)
	var face := Label.new()
	face.text = "✦"
	face.add_theme_font_size_override("font_size", 40)
	face.add_theme_color_override("font_color", GREEN)
	hb.add_child(face)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	dialogue_name = Label.new()
	dialogue_name.add_theme_font_size_override("font_size", 18)
	dialogue_name.add_theme_color_override("font_color", BROWN)
	vb.add_child(dialogue_name)
	dialogue_text = Label.new()
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.custom_minimum_size = Vector2(440, 0)
	dialogue_text.add_theme_font_size_override("font_size", 18)
	vb.add_child(dialogue_text)
	dialogue_options = GridContainer.new()
	dialogue_options.columns = 2
	dialogue_options.add_theme_constant_override("h_separation", 6)
	dialogue_options.add_theme_constant_override("v_separation", 4)
	vb.add_child(dialogue_options)
	dialogue_panel.visible = false
	root.add_child(dialogue_panel)


func show_dialogue(npc_id: int, name: String, text: String, options: Array) -> void:
	ui_focus_requested.emit()
	dialogue_npc = npc_id
	dialogue_name.text = name
	dialogue_text.text = text
	for c in dialogue_options.get_children():
		c.queue_free()
	for i in options.size():
		var b := Button.new()
		b.text = "%d.  %s" % [i + 1, options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		_style_button(b, CREAM_DARK, 10)
		_hoverable(b)
		var idx := i
		b.pressed.connect(
			func():
				Sfx.play("click")
				dialogue_choice.emit(npc_id, idx)
		)
		dialogue_options.add_child(b)
	if not dialogue_panel.visible:
		reveal(dialogue_panel, true, Vector2(0, 20))
	hint.visible = false
	if options.is_empty():
		get_tree().create_timer(2.2).timeout.connect(
			func():
				if dialogue_panel.visible and dialogue_options.get_child_count() == 0:
					reveal(dialogue_panel, false, Vector2(0, 20))
		)


func hide_dialogue() -> void:
	hint.visible = true
	if dialogue_panel.visible:
		reveal(dialogue_panel, false, Vector2(0, 20))


## Keyboard shortcut for a dialogue option (1-9). Returns true if consumed.
func dialogue_key(n: int) -> bool:
	if not dialogue_panel.visible or n < 1 or n > dialogue_options.get_child_count():
		return false
	dialogue_options.get_child(n - 1).pressed.emit()
	return true


func palette_key(n: int) -> bool:
	if not palette_panel.visible or n < 1 or n > palette.get_child_count():
		return false
	var b: Button = palette.get_child(n - 1)
	b.button_pressed = true
	b.pressed.emit()
	return true


func set_view_label(fps: bool) -> void:
	view_btn.text = "👁 fps" if fps else "👁 iso"


func _build_login() -> void:
	login_panel = Control.new()
	login_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	login_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.16, 0.14, 0.46)
	login_panel.add_child(dim)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.add_theme_constant_override("separation", 6)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	login_panel.add_child(center)

	var sign: Texture2D = null
	var sign_box := Control.new()
	sign_box.custom_minimum_size = Vector2(640, 160)
	if sign:
		var tr := TextureRect.new()
		tr.texture = sign
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sign_box.add_child(tr)
	var title := Label.new()
	title.text = "Causeway Bay Coast"
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.grow_vertical = Control.GROW_DIRECTION_BOTH
	title.position.y += 6
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("#fff6e3"))
	title.add_theme_color_override("font_outline_color", Color("#6b4426"))
	title.add_theme_constant_override("outline_size", 0)
	sign_box.add_child(title)
	var sub := Label.new()
	sub.text = "A little island. A place to belong."
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.position.y += 52
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", CREAM)
	sign_box.add_child(sub)
	center.add_child(sign_box)

	var card := _panel()
	card.custom_minimum_size = Vector2(380, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "your name"
	name_edit.text = (
		str(Settings.data.get("name", ""))
		if str(Settings.data.get("name", "")) != ""
		else "islander%d" % (randi() % 1000)
	)
	name_edit.add_theme_font_size_override("font_size", 20)
	vb.add_child(name_edit)
	url_edit = LineEdit.new()
	url_edit.text = (
		str(Settings.data.get("url", ""))
		if str(Settings.data.get("url", "")) != ""
		else Net.DEFAULT_URL
	)
	if OS.get_environment("COAST_SERVER_URL") != "":
		url_edit.text = OS.get_environment("COAST_SERVER_URL")
	url_edit.add_theme_font_size_override("font_size", 14)
	vb.add_child(url_edit)
	var go := Button.new()
	go.text = "⛵  Sail to my island"
	go.add_theme_font_size_override("font_size", 22)
	_style_button(go, ORANGE, 16)
	_hoverable(go)
	go.pressed.connect(func(): login_requested.emit(name_edit.text, url_edit.text))
	name_edit.text_submitted.connect(func(_t): login_requested.emit(name_edit.text, url_edit.text))
	vb.add_child(go)
	var wrap := CenterContainer.new()
	wrap.add_child(card)
	center.add_child(wrap)
	root.add_child(login_panel)


# ---------------------------------------------------------------- behaviour
func _process(delta: float) -> void:
	if toast_panel.visible and _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			reveal(toast_panel, false, Vector2(0, -12))


func show_toast(text: String, secs := 2.5) -> void:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		if line.length() + word.length() > 60:
			lines.append(line)
			line = ""
		line += (" " if line != "" else "") + word
	lines.append(line)
	toast.text = "\n".join(lines)
	toast_panel.reset_size()
	_toast_t = secs
	toast_panel.size = Vector2(560, toast_panel.get_combined_minimum_size().y)
	toast_panel.position = Vector2((root.size.x - 560) * 0.5, 22)
	toast_panel.set_meta("base_pos", toast_panel.position)
	reveal(toast_panel, true, Vector2(0, -12))


## Fade the screen to white (cosine ease in), hold, then back (cosine ease out).
func fade_out(secs := 0.3) -> Tween:
	stop_portal_transition()
	_flash_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_flash_tween.tween_property(flash, "color:a", 1.0, secs)
	return _flash_tween


func fade_in(secs := 0.6) -> void:
	stop_portal_transition()
	_flash_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(flash, "color:a", 0.0, secs)


func portal_transition() -> void:
	stop_portal_transition()
	flash.color = Color(0.82, 0.76, 0.96, 0.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash, "color:a", 0.3, 0.5)


func stop_portal_transition() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()


func flash_screen() -> void:
	flash.color = Color(1, 1, 1, 1.0)
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "color:a", 0.0, 0.7)
	tween.tween_callback(func(): flash.color.a = 0.0)


func set_room(room: Dictionary, my_id: int, my_name: String) -> void:
	var mine := int(room.get("owner_id", -1)) == my_id
	player_label.text = my_name
	island_label.text = (
		"%s  ·  island #%d%s"
		% [room.get("name", "?"), int(room.get("id", 0)), "" if mine else "  (visiting)"]
	)
	set_visitors(room.get("players", []), my_id)
	if decorate_btn.visible != mine:
		reveal(decorate_btn, mine)
	if not mine and decorate_btn.button_pressed:
		decorate_btn.button_pressed = false
	remove_btn.visible = mine
	if not mine:
		remove_btn.button_pressed = false


func set_decorate(on: bool) -> void:
	reveal(palette_panel, on, Vector2(0, 24))
	hint.text = (
		"place: click tile or E  ·  remove: right-click  ·  rotate: R  ·  pick: 1-9  ·  click a portal to link  ·  Tab closes"
		if on
		else "WASD move   ·   E talk   ·   Tab decorate   ·   Enter chat   ·   V view"
	)


# ---------------------------------------------------------------- styling
func _sb(bg: Color, border: Color = BROWN, radius := 14, bw := 1, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin + 2
	sb.content_margin_right = margin + 2
	sb.content_margin_top = margin - 2
	sb.content_margin_bottom = margin - 2
	sb.shadow_color = Color(0.08, 0.20, 0.18, 0.13)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	return sb


func _panel(bg: Color = CREAM, border: Color = BROWN) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border))
	return p


func _style_button(b: Button, bg: Color, radius: int) -> void:
	b.add_theme_stylebox_override("normal", _sb(bg, BROWN, radius, 1, 10))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.12), BROWN, radius, 1, 10))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.12), INK, radius, 2, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for st in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color"
	]:
		b.add_theme_color_override(st, INK)


func _theme() -> Theme:
	var t := Theme.new()
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", 16)
	t.set_stylebox("normal", "LineEdit", _sb(Color.WHITE, Color("#d8c4a0"), 12, 2, 10))
	t.set_stylebox("focus", "LineEdit", _sb(Color.WHITE, ORANGE, 12, 3, 10))
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("normal", "RichTextLabel", _sb(Color("#fffdf6"), Color("#e6d5b3"), 12, 2, 8))
	t.set_stylebox("normal", "Button", _sb(CREAM_DARK, BROWN, 12, 3, 10))
	return t


func _build_camera_controls() -> void:
	var card := _panel()
	card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.position = Vector2(-18, -18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var zoom_out := Button.new()
	zoom_out.text = "−"
	zoom_out.custom_minimum_size = Vector2(36, 32)
	_style_button(zoom_out, CREAM_DARK, 8)
	zoom_out.tooltip_text = "Zoom out (mouse wheel / −)"
	zoom_out.pressed.connect(func(): zoom_requested.emit(1.0))
	row.add_child(zoom_out)
	zoom_label = Label.new()
	zoom_label.custom_minimum_size.x = 62
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(zoom_label)
	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.custom_minimum_size = Vector2(36, 32)
	_style_button(zoom_in, CREAM_DARK, 8)
	zoom_in.tooltip_text = "Zoom in (mouse wheel / +)"
	zoom_in.pressed.connect(func(): zoom_requested.emit(-1.0))
	row.add_child(zoom_in)
	for direction in [-1, 1]:
		var orbit := Button.new()
		orbit.text = "↶" if direction < 0 else "↷"
		orbit.tooltip_text = "Rotate island view (Q / C or right-drag)"
		orbit.custom_minimum_size = Vector2(32, 32)
		_style_button(orbit, CREAM_DARK, 8)
		orbit.pressed.connect(func(): camera_rotated.emit(direction * PI / 4.0))
		row.add_child(orbit)
	root.add_child(card)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.add_theme_color_override("font_color", CREAM)
	crosshair.add_theme_color_override("font_outline_color", INK)
	crosshair.add_theme_constant_override("outline_size", 3)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.visible = false
	root.add_child(crosshair)


func set_zoom_value(value: float, fps: bool) -> void:
	zoom_label.text = "%d°" % int(value) if fps else "%d%%" % int(2500.0 / value)


func set_mouse_look(captured: bool) -> void:
	if crosshair:
		crosshair.visible = captured

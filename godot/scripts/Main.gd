## Entry point: isometric camera, island, clouds, current room, input, and server message routing.
class_name Main
extends Node3D

const GRID := 14
const HALF := 7.0
const PORTAL_COOLDOWN := 1.5
const CLOUD_COUNT := 7
const WALK_RADIUS := 12.0

var room: Room
var hud: HUD
var camera: Camera3D
var my_id := -1
var my_name := ""
var decorate := false
var remove_mode := false
var pick_kind := ""
var pick_rot := 0
var ghost: Node3D
var hover_tile := Vector2i(-1, -1)
var link_portal_id := -1
var _portal_cd := 0.0
var _shot_path := ""
var _clouds: Array[Node3D] = []
var _zoom_target := 23.0
var _ghost_t := 0.0
var fps_view := false
var _cam_yaw := 0.0
var _cam_pitch := -0.1
var _looking := false
var _view_tween: Tween
var _iso_yaw := 0.0
var _orbit_dragging := false
var _zoom_tween: Tween
var _fps_fov := 72.0
var _portal_busy := false
var _portal_elapsed := 0.0
var _portal_generation := 0
var _portal_inside := -1
var _walk_to_portal := -1
const ZOOM_MIN := 10.0
const ZOOM_MAX := 36.0
const FOV_MIN := 40.0
const FOV_MAX := 95.0
const MOUSE_SENSITIVITY := 0.0025
const ISO_POS := Vector3(25, 24, 25)
const ISO_TARGET := Vector3(-1.0, 1.4, -1.0)
const EYE := 1.55


static func tile_to_world(tx: int, ty: int) -> Vector3:
	return Vector3(tx - HALF + 0.5, 0.0, ty - HALF + 0.5)


static func server_to_world(x: float, y: float) -> Vector3:
	return Vector3(x - HALF, 0.0, y - HALF)


static func clamp_walk(at: Vector3) -> Vector3:
	var flat := Vector2(at.x, at.z).limit_length(WALK_RADIUS)
	return Vector3(flat.x, 0.0, flat.y)


static func walk_height(at: Vector3) -> float:
	# Local height relative to the Players node's 0.22m offset.
	if at.x >= -7.2 and at.x <= 1.2 and at.z >= -7.2 and at.z <= 1.2:
		return 0.0
	return -0.12 if Vector2(at.x, at.z).length() > 9.8 else -0.09


func _iso_position() -> Vector3:
	return ISO_TARGET + (ISO_POS - ISO_TARGET).rotated(Vector3.UP, _iso_yaw)


func rotate_camera(radians: float) -> void:
	if fps_view or _portal_busy:
		return
	_iso_yaw = wrapf(_iso_yaw + radians, -PI, PI)
	if _view_tween and _view_tween.is_valid():
		_view_tween.kill()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.look_at_from_position(_iso_position(), ISO_TARGET, Vector3.UP)


static func is_pond(tx: int, ty: int) -> bool:
	return Vector2(tx + 0.5, ty + 0.5).distance_to(Vector2(11.5, 10.5)) < 2.1


func _ready() -> void:
	_build_scene()
	hud = HUD.new()
	add_child(hud)
	hud.login_requested.connect(_on_login)
	hud.decorate_toggled.connect(_on_decorate)
	hud.remove_toggled.connect(_on_remove)
	hud.kind_picked.connect(
		func(k):
			pick_kind = k
			_refresh_ghost()
	)
	hud.rotate_pressed.connect(
		func():
			pick_rot = (pick_rot + 1) % 4
			_refresh_ghost()
	)
	hud.home_pressed.connect(func(): Net.send({"type": "go_home"}))
	hud.islands_pressed.connect(
		func():
			link_portal_id = -1
			Net.send({"type": "list_rooms"})
	)
	hud.chat_sent.connect(func(t): Net.send({"type": "chat", "text": t}))
	hud.room_chosen.connect(_on_room_chosen)
	hud.view_toggled.connect(toggle_view)
	hud.zoom_requested.connect(zoom_by)
	hud.camera_rotated.connect(rotate_camera)
	hud.ui_focus_requested.connect(func(): _set_mouse_capture(false))
	hud.chat_edit.text_submitted.connect(func(_text): call_deferred("_resume_fps_mouse"))
	hud.dialogue_choice.connect(
		func(npc_id, choice): Net.send({"type": "talk", "npc_id": npc_id, "choice": choice})
	)
	hud.mute_toggled.connect(
		func(m):
			AudioServer.set_bus_mute(0, m)
			Settings.data["muted"] = m
			Settings.save()
	)
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(
		func():
			hud.remove_btn.button_pressed = false
			_cancel_portal()
			_set_mouse_capture(false)
			my_id = -1
			hud.show_toast("Could not reach the island. Check the server and try again.", 5.0)
			hud.reveal(hud.login_panel, true)
	)
	Net.message.connect(_on_message)

	_zoom_target = clampf(float(Settings.data.get("zoom", 25.0)), ZOOM_MIN, ZOOM_MAX)
	if OS.get_environment("COAST_SHOT_ZOOM") != "":
		_zoom_target = float(OS.get_environment("COAST_SHOT_ZOOM"))
	_fps_fov = clampf(float(Settings.data.get("fps_fov", 72.0)), FOV_MIN, FOV_MAX)
	hud.set_zoom_value(_zoom_target, false)
	camera.size = _zoom_target + 8.0  # intro zoom-in (cosine ease)
	_zoom_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(camera, "size", _zoom_target, 1.6)
	if bool(Settings.data.get("muted", false)):
		hud.mute_btn.button_pressed = true

	# Screenshot mode for automated visual checks: COAST_SHOT=/path/out.png
	_shot_path = OS.get_environment("COAST_SHOT")
	if _shot_path != "":
		hud.name_edit.text = "shotbot"
		_on_login("shotbot", Net.DEFAULT_URL)
		var delay := (
			float(OS.get_environment("COAST_SHOT_DELAY"))
			if OS.get_environment("COAST_SHOT_DELAY") != ""
			else 3.5
		)
		get_tree().create_timer(delay).timeout.connect(_take_shot)


func _demo_decorate() -> void:
	var demo := [
		["bed", 1, 0, 0],
		["bookshelf", 3, 0, 0],
		["table", 1, 3, 0],
		["chair", 1, 4, 2],
		["lamp", 5, 1, 0],
		["monstera", 6, 3, 0],
		["cactus", 0, 6, 0],
		["flower_pot", 5, 6, 0],
		["tree", 12, 2, 0],
		["tree", 3, 11, 0],
		["bench", 6, 10, 1],
		["flower_bed", 9, 1, 0],
		["flower_bed", 1, 9, 0]
	]
	for d in demo:
		Net.send({"type": "place_item", "kind": d[0], "tx": d[1], "ty": d[2], "rot": d[3]})
	Net.send({"type": "chat", "text": "aloha from the tiny island!"})
	if OS.get_environment("COAST_SHOT_HOP") != "":
		Net.send({"type": "list_rooms"})
	var me: Avatar = room.avatars.get(my_id)
	if me:
		me.set_target(tile_to_world(6, 8))
	if OS.get_environment("COAST_SHOT_ZOOM") != "" and me:
		get_tree().create_timer(2.5).timeout.connect(
			func():
				camera.look_at_from_position(
					me.global_position + Vector3(10, 9.5, 10),
					me.global_position + Vector3(0, 1.0, 0),
					Vector3.UP
				)
		)
	if OS.get_environment("COAST_SHOT_FPS") != "":
		get_tree().create_timer(1.6).timeout.connect(toggle_view)
	if OS.get_environment("COAST_SHOT_TALK") != "":
		get_tree().create_timer(1.8).timeout.connect(
			func():
				var npc := _npc_near(Vector3.ZERO, 100.0)
				if npc:
					Net.send({"type": "talk", "npc_id": npc.player_id})
		)


func _demo_hop(rooms: Array) -> void:
	var here := int(room.state.get("id", -1))
	var portal := {}
	for it in room.state.get("items", []):
		if str(it["kind"]) == "portal":
			portal = it
	for r in rooms:
		if int(r["id"]) != here and portal.size() > 0:
			Net.send({"type": "link_portal", "id": int(portal["id"]), "target_room": int(r["id"])})
			Net.send({"type": "enter_portal", "id": int(portal["id"])})
			return


func _probe_materials(n: Node, label: String) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			if n.get_active_material(i) == null:
				print("NULL MATERIAL in ", label, " node ", n.name, " surface ", i)
	for c in n.get_children():
		_probe_materials(c, label)


func _take_shot() -> void:
	if my_id < 0:
		push_error("Screenshot check requires a running server")
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path)
	print("screenshot saved to ", _shot_path)
	get_tree().quit()


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.background_color = Color("#76b7bb")
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/coastal_sky.gdshader")
	sky.sky_material = sky_material
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#cedfe3")
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_hdr_threshold = 1.4
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color("#fff4e0")
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.shadow_blur = 3.0
	sun.light_angular_distance = 4.0
	sun.directional_shadow_max_distance = 60
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25.0
	camera.near = 0.1
	camera.far = 300.0
	add_child(camera)
	camera.look_at_from_position(Vector3(25, 24, 25), Vector3(-1.0, 1.4, -1.0), Vector3.UP)

	add_child(Assets.spawn("island", {}, false))
	var house := Assets.spawn("house")
	house.position = Vector3(-3.0, 0.0, -3.0)  # floor = tiles 0..8 in the back corner
	add_child(house)
	# beach palms on the sand ring outside the garden
	for p in [
		[-9.5, 4.0, 1.0, 0.3],
		[9.8, -3.5, 0.9, 2.2],
		[-4.0, 10.0, 0.85, 4.0],
		[10.2, 6.5, 0.8, 1.0],
		[3.5, -10.2, 0.9, 5.2]
	]:
		var palm := Assets.spawn("palm")
		palm.position = Vector3(p[0], 0.0, p[1])
		palm.scale = Vector3.ONE * p[2]
		palm.rotation.y = p[3]
		add_child(palm)
	# drifting clouds (they cast soft shadows over the island)
	for i in CLOUD_COUNT:
		var c := Assets.spawn("cloud", {}, false)
		var a := TAU * i / CLOUD_COUNT + randf() * 0.4
		var r := randf_range(24.0, 30.0)
		c.position = Vector3(cos(a) * r, randf_range(2.0, 3.2), sin(a) * r)
		c.scale = Vector3.ONE * randf_range(0.9, 1.5)
		c.rotation.y = randf() * TAU
		c.set_meta("a", a)
		c.set_meta("r", r)
		add_child(c)
		_clouds.append(c)

	room = Room.new()
	add_child(room)


# ---------------------------------------------------------------- networking
func _on_login(name: String, url: String) -> void:
	my_name = name.strip_edges()
	if my_name == "":
		hud.show_toast("pick a name first")
		return
	Settings.data["name"] = my_name
	Settings.data["url"] = url
	Settings.save()
	hud.show_toast("sailing…", 3.0)
	Net.open(url)


func _on_connected() -> void:
	var colours := ["#3fbf5a", "#4d7cff", "#ff6fa5", "#f2a23a", "#9b6bf2", "#f04e4e", "#5ee1e8"]
	Net.send({"type": "hello", "name": my_name, "colour": colours[hash(my_name) % colours.size()]})


func _on_message(m: Dictionary) -> void:
	match str(m.get("type", "")):
		"welcome":
			my_id = int(m["player_id"])
			Net.player_id = my_id
			hud.reveal(hud.login_panel, false, Vector2(0, -30))
			Sfx.play("hello")
			_load_room(m["room"])
			hud.add_chat("", "welcome to %s" % m["room"]["name"], true)
			if _shot_path != "":
				_demo_decorate()
		"room_state":
			var travelled := _portal_busy
			_portal_busy = false
			_portal_generation += 1
			hud.flash_screen()
			_load_room(m["room"])
			if travelled:
				var arrived: Avatar = room.avatars.get(my_id)
				if arrived:
					_spawn_portal_burst(arrived.global_position, true)
				Sfx.play("hello")
				hud.show_toast("Arrived at " + str(m["room"]["name"]), 3.0)
			hud.add_chat("", "you arrived at %s" % m["room"]["name"], true)
		"player_joined":
			room.add_player(m["player"], false)
			_refresh_visitors()
			hud.add_chat("", "%s hopped in" % m["player"]["name"], true)
		"player_left":
			room.remove_player(int(m["player_id"]))
			_refresh_visitors()
		"player_moved":
			room.move_player(int(m["player_id"]), float(m["x"]), float(m["y"]))
		"item_placed":
			room.add_item(m["item"])
		"item_removed":
			room.remove_item(int(m["id"]))
		"portal_linked":
			room.link_portal(int(m["id"]), int(m["target_room"]))
			hud.show_toast(
				"Portal ready — walk into it to visit island #%d" % int(m["target_room"])
			)
			if _walk_to_portal == int(m["id"]):
				_walk_to_portal = -1
				var me: Avatar = room.avatars.get(my_id)
				for it in room.state.get("items", []):
					if me and int(it["id"]) == int(m["id"]):
						_set_mouse_capture(false)
						hud.decorate_btn.button_pressed = false
						me.set_target(tile_to_world(int(it["tx"]), int(it["ty"])))
						_portal_inside = -1
		"chat":
			hud.add_chat(str(m["name"]), str(m["text"]))
			Settings.log_chat(int(room.state.get("id", 0)), str(m["name"]), str(m["text"]))
			var a: Avatar = room.avatars.get(int(m["player_id"]))
			if a:
				a.say(str(m["text"]))
			Sfx.play("chat")
		"dialogue":
			hud.show_dialogue(
				int(m["npc_id"]), str(m["name"]), str(m["text"]), m.get("options", [])
			)
			var a: Avatar = room.avatars.get(int(m["npc_id"]))
			if a and m.get("options", []).size() > 0:
				a.wave()
		"rooms":
			if _shot_path != "" and OS.get_environment("COAST_SHOT_HOP") != "":
				_demo_hop(m["rooms"])
			else:
				hud.show_rooms(m["rooms"], int(room.state.get("id", -1)), link_portal_id >= 0)
		"error":
			_cancel_portal()
			_walk_to_portal = -1
			hud.show_toast("⚠ " + str(m["message"]))
			Sfx.play("error")
		"pong":
			pass


func _refresh_visitors() -> void:
	var players := []
	for a in room.avatars.values():
		for p in room.state.get("players", []):
			if int(p["id"]) == a.player_id:
				players.append(p)
	hud.set_visitors(_current_players(), my_id)


func _current_players() -> Array:
	var out := []
	for p in room.state.get("players", []):
		if room.avatars.has(int(p["id"])):
			out.append(p)
	for a in room.avatars.values():
		if not out.any(func(p): return int(p["id"]) == a.player_id):
			out.append({"id": a.player_id, "name": a._label.text, "colour": "#ffcc66"})
	return out


func _load_room(r: Dictionary) -> void:
	hud.remove_btn.button_pressed = false
	if _view_tween and _view_tween.is_valid():
		_view_tween.kill()
	_set_mouse_capture(false)
	_portal_inside = -1
	_walk_to_portal = -1
	hud.hide_dialogue()
	if fps_view:
		fps_view = false
		hud.set_view_label(false)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = _zoom_target
		camera.look_at_from_position(_iso_position(), ISO_TARGET, Vector3.UP)
	room.load_state(r, my_id)
	hud.set_zoom_value(_zoom_target, false)
	hud.set_room(r, my_id, my_name)
	_portal_cd = PORTAL_COOLDOWN
	if decorate and not room.is_owner(my_id):
		hud.decorate_btn.button_pressed = false
	var me: Avatar = room.avatars.get(my_id)
	if me:
		me.arrived.connect(_on_arrived)


func _on_room_chosen(rid: int) -> void:
	if _portal_busy or rid == int(room.state.get("id", -1)):
		return
	var portal_id := link_portal_id
	link_portal_id = -1
	if portal_id < 0:
		if not room.is_owner(my_id):
			hud.show_toast("Return home to choose a new destination for your portal.")
			return
		for it in room.state.get("items", []):
			if str(it["kind"]) == "portal":
				portal_id = int(it["id"])
				break
		if portal_id < 0:
			hud.show_toast("Place a portal from the furniture menu first.")
			return
		_walk_to_portal = portal_id
	Net.send({"type": "link_portal", "id": portal_id, "target_room": rid})


# ---------------------------------------------------------------- decorate mode
func _on_decorate(on: bool) -> void:
	if on:
		hud.remove_btn.button_pressed = false
		_set_mouse_capture(false)
	decorate = on
	hud.set_decorate(on)
	if not on:
		pick_kind = ""
	_refresh_ghost()


func _on_remove(on: bool) -> void:
	if on and not room.is_owner(my_id):
		hud.remove_btn.set_pressed_no_signal(false)
		return
	remove_mode = on
	if on:
		hud.decorate_btn.button_pressed = false
		_set_mouse_capture(false)
		_walk_to_portal = -1
		hud.hint.text = "REMOVE MODE · Click a decoration to remove it · Esc exits"
	else:
		hud.set_decorate(decorate)
	hud.remove_btn.text = "Done" if on else "Remove"
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if on else Input.CURSOR_ARROW)


func _removable_at_screen(screen: Vector2) -> int:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest := INF
	var selected := -1
	for id in room.items:
		var node: Node3D = room.items[id]
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if not mesh.is_visible_in_tree() or mesh.mesh == null:
				continue
			var inverse := mesh.global_transform.affine_inverse()
			var hit = mesh.get_aabb().intersects_ray(inverse * origin, inverse.basis * direction)
			if hit is Vector3:
				var depth: float = ((mesh.global_transform * hit) - origin).dot(direction)
				if depth >= 0.0 and depth < nearest:
					nearest = depth
					selected = int(id)
	if selected < 0:
		var portal := _portal_at_screen(screen)
		if not portal.is_empty():
			selected = int(portal.id)
	return selected


func _refresh_ghost() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
	if decorate and pick_kind != "":
		ghost = Assets.spawn(pick_kind)
		Assets.set_ghost(ghost, true)
		ghost.visible = false
		add_child(ghost)


# ---------------------------------------------------------------- input
func _ground_point(screen: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	return Plane(Vector3.UP, Room.FLOOR_Y).intersects_ray(from, dir)


func _tile_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x + HALF), floori(p.z + HALF))


## Third-person isometric  <->  first-person. Cosine-eased camera flight between the two.
func toggle_view() -> void:
	var me: Avatar = room.avatars.get(my_id)
	if me == null or _portal_busy:
		return
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	fps_view = not fps_view
	hud.set_view_label(fps_view)
	if _view_tween and _view_tween.is_valid():
		_view_tween.kill()
	_view_tween = (
		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
	)
	if fps_view:
		_cam_yaw = me.rotation.y
		_cam_pitch = -0.1
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = _fps_fov
		var xf := _fps_transform(me)
		_view_tween.tween_property(camera, "position", xf.origin, 0.7)
		_view_tween.tween_property(camera, "quaternion", xf.basis.get_rotation_quaternion(), 0.7)
		me._model.visible = false
		me._label.visible = false
		hud.set_zoom_value(_fps_fov, true)
		_set_mouse_capture(
			(
				not decorate
				and not remove_mode
				and not hud.rooms_popup.visible
				and not hud.dialogue_panel.visible
			)
		)
		hud.show_toast(
			"Mouse to look · WASD to move · E to interact · Esc for cursor · V for island view", 4.0
		)
	else:
		_set_mouse_capture(false)
		hud.set_zoom_value(_zoom_target, false)
		me._model.visible = true
		me._label.visible = true
		var iso := Transform3D.IDENTITY.translated(_iso_position()).looking_at(
			ISO_TARGET, Vector3.UP
		)
		_view_tween.tween_property(camera, "position", _iso_position(), 0.7)
		_view_tween.tween_property(camera, "quaternion", iso.basis.get_rotation_quaternion(), 0.7)
		_view_tween.chain().tween_callback(
			func():
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = _zoom_target
		)


func _fps_transform(me: Avatar) -> Transform3D:
	var origin := me.global_position + Vector3(0, EYE, 0)
	var basis := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw + PI, 0.0))
	return Transform3D(basis, origin)


func _key_move_dir() -> Vector3:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if not fps_view:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1
	else:
		if Input.is_key_pressed(KEY_A):
			v.x -= 1
		if Input.is_key_pressed(KEY_D):
			v.x += 1
	if v == Vector2.ZERO:
		return Vector3.ZERO
	var fwd: Vector3
	var right: Vector3
	if fps_view:
		fwd = Vector3(sin(_cam_yaw), 0, cos(_cam_yaw))
		right = Vector3(-fwd.z, 0, fwd.x)
	else:
		fwd = -camera.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		right = camera.global_basis.x
		right.y = 0
		right = right.normalized()
	return (fwd * -v.y + right * v.x).normalized()


func _typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


func _process(delta: float) -> void:
	_portal_cd = max(0.0, _portal_cd - delta)
	var me: Avatar = room.avatars.get(my_id)
	if me and not _typing() and not _portal_busy and (not fps_view or _looking):
		if not fps_view:
			var orbit := float(Input.is_key_pressed(KEY_C)) - float(Input.is_key_pressed(KEY_Q))
			if orbit != 0.0:
				rotate_camera(orbit * delta * 1.2)
		var dir := _key_move_dir()
		me.drive(dir)
		if fps_view:
			var turn := 0.0
			if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
				turn += 1
			if Input.is_key_pressed(KEY_RIGHT):
				turn -= 1
			_cam_yaw += turn * delta * 2.2
			if dir != Vector3.ZERO:
				me._face_yaw = _cam_yaw
	elif me:
		me.drive(Vector3.ZERO)
	if fps_view and me and not (_view_tween and _view_tween.is_running()):
		camera.global_transform = _fps_transform(me)
	for c in _clouds:
		var a: float = c.get_meta("a") + delta * 0.03
		c.set_meta("a", a)
		var r: float = c.get_meta("r")
		c.position.x = cos(a) * r
		c.position.z = sin(a) * r
	if _portal_busy:
		_portal_elapsed += delta
		if _portal_elapsed > 8.0:
			_cancel_portal()
			hud.show_toast("Travel timed out. Please try the portal again.")
	else:
		_check_portal_entry()
	if ghost:
		_ghost_t += delta
		var p = _ground_point(
			(
				get_viewport().get_visible_rect().size * 0.5
				if fps_view and _looking
				else get_viewport().get_mouse_position()
			)
		)
		if p != null:
			var t := _tile_of(p)
			var inside := t.x >= 0 and t.x < GRID and t.y >= 0 and t.y < GRID
			ghost.visible = inside
			if inside:
				hover_tile = t
				ghost.position = (
					tile_to_world(t.x, t.y)
					+ Vector3(0, Room.FLOOR_Y + 0.08 + sin(_ghost_t * 4.0) * 0.05, 0)
				)
				ghost.rotation.y = pick_rot * PI / 2.0


func _unhandled_input(ev: InputEvent) -> void:
	if my_id < 0 or _portal_busy:
		return
	if (
		not fps_view
		and ev is InputEventMouseButton
		and (
			ev.button_index == MOUSE_BUTTON_MIDDLE
			or (ev.button_index == MOUSE_BUTTON_RIGHT and not decorate)
		)
	):
		_orbit_dragging = ev.pressed
		return
	if ev is InputEventMagnifyGesture:
		zoom_by((1.0 - ev.factor) * 4.0)
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and not _typing():
		match ev.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom_by(-1.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_by(1.0)
			KEY_R:
				if decorate:
					pick_rot = (pick_rot + 1) % 4
			KEY_TAB:
				if hud.decorate_btn.visible:
					hud.decorate_btn.button_pressed = not hud.decorate_btn.button_pressed
			KEY_V:
				toggle_view()
			KEY_H:
				Net.send({"type": "go_home"})
			KEY_I:
				link_portal_id = -1
				Net.send({"type": "list_rooms"})
			KEY_ENTER, KEY_KP_ENTER:
				_set_mouse_capture(false)
				hud.chat_edit.grab_focus()
			KEY_ESCAPE:
				hud.remove_btn.button_pressed = false
				hud.hide_dialogue()
				if hud.rooms_popup.visible:
					hud.reveal(hud.rooms_popup, false)
			KEY_E:
				_interact()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var n: int = ev.keycode - KEY_0
				if not hud.dialogue_key(n):
					hud.palette_key(n)
		return
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and _typing():
		hud.chat_edit.release_focus()
		return
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(-1.0 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
			return
		if remove_mode and ev.button_index == MOUSE_BUTTON_LEFT:
			if room.is_owner(my_id):
				var id := _removable_at_screen(ev.position)
				if id >= 0:
					Net.send({"type": "remove_item", "id": id})
			return
		if ev.button_index == MOUSE_BUTTON_LEFT and (not fps_view or _looking):
			var screen: Vector2 = (
				get_viewport().get_visible_rect().size * 0.5 if fps_view else ev.position
			)
			var clicked_portal := _portal_at_screen(screen)
			if not clicked_portal.is_empty():
				_open_portal_islands(clicked_portal)
				return
		if fps_view:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				if not _looking:
					_resume_fps_mouse()
				else:
					_interact()
			return
		var p = _ground_point(ev.position)
		if p == null:
			return
		var t := _tile_of(p)
		var inside := t.x >= 0 and t.x < GRID and t.y >= 0 and t.y < GRID
		if decorate:
			if not inside:
				return
			var existing := room.item_at(t.x, t.y)
			if ev.button_index == MOUSE_BUTTON_RIGHT:
				if existing.size() > 0:
					Net.send({"type": "remove_item", "id": int(existing["id"])})
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				if existing.size() > 0 and str(existing["kind"]) == "portal":
					link_portal_id = int(existing["id"])
					Net.send({"type": "list_rooms"})
				elif existing.size() == 0 and pick_kind != "" and is_pond(t.x, t.y):
					hud.show_toast("the pond is for the fish 🐟")
				elif existing.size() == 0 and pick_kind != "":
					Net.send(
						{
							"type": "place_item",
							"kind": pick_kind,
							"tx": t.x,
							"ty": t.y,
							"rot": pick_rot
						}
					)
				elif pick_kind == "":
					hud.show_toast("pick an item from the palette first")
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			var me: Avatar = room.avatars.get(my_id)
			if me == null:
				return
			var npc := _npc_near(p, 0.9)
			if npc:
				Net.send({"type": "talk", "npc_id": npc.player_id})
				return
			var dest := clamp_walk(p)
			if inside:
				var it := room.item_at(t.x, t.y)
				if it.size() > 0 and str(it["kind"]) == "portal":
					dest = tile_to_world(t.x, t.y)
			me.set_target(dest)
			_spawn_click_marker(dest)


func _portal_at_screen(screen: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest := INF
	var result := {}
	for it in room.state.get("items", []):
		if str(it["kind"]) != "portal":
			continue
		var center := (
			tile_to_world(int(it["tx"]), int(it["ty"])) + Vector3(0, Room.FLOOR_Y + 1.2, 0)
		)
		var along := (center - origin).dot(direction)
		if (
			along > 0.0
			and along < nearest
			and center.distance_to(origin + direction * along) < 0.95
		):
			nearest = along
			result = it
	return result


func _open_portal_islands(it: Dictionary) -> void:
	var me: Avatar = room.avatars.get(my_id)
	if me:
		me.moving = false
		me.drive(Vector3.ZERO)
	link_portal_id = int(it["id"]) if room.is_owner(my_id) else -1
	_walk_to_portal = link_portal_id
	_portal_inside = int(it["id"])
	_set_mouse_capture(false)
	Net.send({"type": "list_rooms"})


func _npc_near(at: Vector3, radius: float) -> Avatar:
	var best: Avatar = null
	var best_d := radius
	for a in room.avatars.values():
		if a.is_npc:
			var d: float = Vector2(a.position.x, a.position.z).distance_to(Vector2(at.x, at.z))
			if d < best_d:
				best_d = d
				best = a
	return best


## E key: talk to the nearest islander, place the picked item in front of you, or use the portal.
func _interact() -> void:
	if remove_mode:
		return
	var me: Avatar = room.avatars.get(my_id)
	if me == null:
		return
	var fwd := Vector3(sin(me._face_yaw), 0, cos(me._face_yaw))
	if decorate and pick_kind != "":
		var t := _tile_of(me.position + fwd * 1.2)
		if (
			t.x >= 0
			and t.x < GRID
			and t.y >= 0
			and t.y < GRID
			and room.item_at(t.x, t.y).is_empty()
			and not is_pond(t.x, t.y)
		):
			Net.send(
				{"type": "place_item", "kind": pick_kind, "tx": t.x, "ty": t.y, "rot": pick_rot}
			)
		else:
			hud.show_toast("no free tile in front of you")
		return
	var t := _tile_of(me.position)
	var it := room.item_at(t.x, t.y)
	if it.is_empty():
		it = room.item_at(t.x + int(round(fwd.x)), t.y + int(round(fwd.z)))
	if not it.is_empty() and str(it["kind"]) == "portal":
		_portal_cd = 0.0
		_use_portal(it)
		return
	var npc := _npc_near(me.position, 2.2)
	if npc:
		Net.send({"type": "talk", "npc_id": npc.player_id})
	else:
		hud.show_toast("Move closer to an islander or a portal, then press E.")


func _spawn_click_marker(at: Vector3) -> void:
	var m := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#fff6dd")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	m.mesh = ring
	m.position = at + Vector3(0, Room.FLOOR_Y + 0.03, 0)
	add_child(m)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(m, "scale", Vector3(2.2, 1, 2.2), 0.45)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.tween_callback(m.queue_free)


func _on_arrived() -> void:
	_check_portal_entry()


func _check_portal_entry() -> void:
	var me: Avatar = room.avatars.get(my_id)
	if me == null or decorate or remove_mode or _portal_busy:
		return
	var portal := {}
	for it in room.state.get("items", []):
		if (
			str(it["kind"]) == "portal"
			and me.position.distance_to(tile_to_world(int(it["tx"]), int(it["ty"]))) < 0.65
		):
			portal = it
			break
	if portal.is_empty():
		_portal_inside = -1
	elif int(portal["id"]) != _portal_inside and _portal_cd <= 0.0:
		_portal_inside = int(portal["id"])
		_use_portal(portal)


func _use_portal(it: Dictionary) -> void:
	if _portal_busy:
		return
	if it.get("target_room") == null:
		if room.is_owner(my_id):
			link_portal_id = int(it["id"])
			_walk_to_portal = link_portal_id
			_set_mouse_capture(false)
			Net.send({"type": "list_rooms"})
		else:
			hud.show_toast("The owner has not linked this portal yet.")
		return
	_portal_busy = true
	_portal_elapsed = 0.0
	_portal_generation += 1
	var generation := _portal_generation
	_portal_cd = PORTAL_COOLDOWN
	_set_mouse_capture(false)
	var me: Avatar = room.avatars.get(my_id)
	if me:
		me.drive(Vector3.ZERO)
		me.moving = false
		me.target = me.position
		_spawn_portal_burst(me.global_position, false)
	hud.show_toast("Sailing through the portal…", 3.0)
	Sfx.play("portal")
	var portal_node: Node3D = room.items.get(int(it["id"]))
	if portal_node and portal_node.has_node("PortalFX"):
		portal_node.get_node("PortalFX").pulse()
	hud.portal_transition()
	# Let the world-space burst read before the screen fades and the server switches rooms.
	await get_tree().create_timer(0.55).timeout
	if not _portal_busy or generation != _portal_generation:
		return
	await hud.fade_out(0.25).finished
	if _portal_busy and generation == _portal_generation:
		Net.send({"type": "enter_portal", "id": int(it["id"])})


func _cancel_portal() -> void:
	_portal_busy = false
	_portal_generation += 1
	_portal_cd = PORTAL_COOLDOWN
	hud.stop_portal_transition()
	hud.fade_in(0.2)


func _spawn_portal_burst(at: Vector3, arriving: bool) -> void:
	var burst := preload("res://scripts/PortalBurst.gd").new()
	add_child(burst)
	burst.position = at
	burst.start(arriving)


func zoom_by(steps: float) -> void:
	if my_id < 0 or _portal_busy:
		return
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if fps_view:
		_fps_fov = clampf(_fps_fov + steps * 5.0, FOV_MIN, FOV_MAX)
		_zoom_tween.tween_property(camera, "fov", _fps_fov, 0.18)
		Settings.data["fps_fov"] = _fps_fov
		hud.set_zoom_value(_fps_fov, true)
	else:
		_zoom_target = clampf(_zoom_target + steps * 1.5, ZOOM_MIN, ZOOM_MAX)
		_zoom_tween.tween_property(camera, "size", _zoom_target, 0.22)
		Settings.data["zoom"] = _zoom_target
		hud.set_zoom_value(_zoom_target, false)
	Settings.save()


func _set_mouse_capture(captured: bool) -> void:
	_looking = captured and fps_view and my_id >= 0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	if hud:
		hud.set_mouse_look(_looking)


func _resume_fps_mouse() -> void:
	if (
		fps_view
		and not decorate
		and not remove_mode
		and not _typing()
		and not hud.rooms_popup.visible
		and not hud.dialogue_panel.visible
		and not _portal_busy
	):
		_set_mouse_capture(true)


func _input(ev: InputEvent) -> void:
	if (
		ev is InputEventMouseButton
		and not ev.pressed
		and ev.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	):
		_orbit_dragging = false
	if ev is InputEventMouseMotion and _orbit_dragging and not fps_view:
		rotate_camera(-ev.relative.x * 0.006)
		get_viewport().set_input_as_handled()
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and fps_view:
		_set_mouse_capture(false)
	if ev is InputEventMouseMotion and fps_view and _looking and not _portal_busy:
		_cam_yaw -= ev.relative.x * MOUSE_SENSITIVITY
		_cam_pitch = clampf(_cam_pitch - ev.relative.y * MOUSE_SENSITIVITY, -1.35, 1.35)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_orbit_dragging = false
		_set_mouse_capture(false)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

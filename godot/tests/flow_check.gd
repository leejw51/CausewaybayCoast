extends Node

var game: Main
var net: Node
var failures := 0
var test_url := "ws://127.0.0.1:8794/ws"


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	print("[PASS] " if ok else "[FAIL] ", label)
	if not ok:
		failures += 1


func pause(seconds := 0.4) -> void:
	await get_tree().create_timer(seconds).timeout


func snapshot(label: String) -> void:
	var folder := OS.get_environment("COAST_FLOW_SHOTS")
	if folder == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))


func run() -> void:
	net = get_tree().root.get_node("Net")
	game = load("res://scenes/Main.tscn").instantiate()
	add_child(game)
	await pause()
	check(game.hud.login_panel.visible, "login screen visible")
	await snapshot("login")
	test_url = (
		OS.get_environment("COAST_TEST_URL")
		if OS.get_environment("COAST_TEST_URL") != ""
		else "ws://127.0.0.1:8787/ws"
	)
	game.hud.login_requested.emit("flow_%d" % int(Time.get_unix_time_from_system()), test_url)
	for i in 40:
		if game.my_id >= 0:
			break
		await pause(0.1)
	check(game.my_id >= 0, "login creates a local player")
	if game.my_id < 0:
		get_tree().quit(1)
		return
	await pause()
	check(not game.hud.login_panel.visible, "login overlay dismisses")
	game.hud.flash.color.a = 1.0
	game._cancel_portal()
	await pause()
	check(game.hud.flash.color.a < 0.01, "cancelled portal travel restores screen")
	var me: Avatar = game.room.avatars[game.my_id]
	check(me._anim != null, "adventurer contains AnimationPlayer")
	for clip in ["Idle", "Walk", "Wave"]:
		check(me._anim.has_animation(clip), "adventurer clip " + clip)
	var initial := me.position
	me.set_target(initial + Vector3(1, 0, 0))
	await pause(0.8)
	check(
		Vector2(me.position.x, me.position.z).distance_to(Vector2(initial.x + 1, initial.z)) < 0.05,
		"click-walk reaches destination"
	)
	check(Main.clamp_walk(Vector3(11, 0, 0)).x == 11.0, "beach lies inside walking boundary")
	check(Main.clamp_walk(Vector3(30, 0, 0)).length() <= 12.0, "walking stops at shoreline")
	var old_camera := game.camera.position
	game.rotate_camera(PI / 2)
	check(game.camera.position.distance_to(old_camera) > 10.0, "third-person camera orbits island")
	game.rotate_camera(-PI / 2)
	game.hud.chat_edit.text_submitted.emit("Hello island!")
	await pause()
	check(
		game.hud.chat_log.get_parsed_text().contains("Hello island!"),
		"chat submission appears in chat history"
	)
	game.hud.decorate_btn.button_pressed = true
	await pause()
	check(game.decorate and game.hud.palette_panel.visible, "decorate opens palette")
	game.hud.kind_picked.emit("chair")
	check(game.ghost != null, "palette selection creates placement preview")
	game.hud.rotate_pressed.emit()
	check(game.pick_rot == 1, "rotation control rotates placement")
	await snapshot("decorate")
	net.send({"type": "place_item", "kind": "chair", "tx": 2, "ty": 2, "rot": 1})
	await pause()
	var item := game.room.item_at(2, 2)
	check(not item.is_empty(), "placed item arrives in Godot scene")
	if not item.is_empty():
		game.hud.remove_btn.button_pressed = true
		check(
			game.remove_mode and not game.decorate and game.ghost == null,
			"remove mode closes decorate and clears preview"
		)
		var point := Main.tile_to_world(2, 2) + Vector3(0, Room.FLOOR_Y + 0.35, 0)
		var screen := game.camera.unproject_position(point)
		check(
			game._removable_at_screen(screen) == int(item.id), "remove mode picks decoration mesh"
		)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = screen
		game._unhandled_input(click)
		await pause(0.2)
		check(game.room.item_at(2, 2).is_empty(), "remove updates Godot scene")
		check(
			get_tree().get_nodes_in_group("removal_effects").size() == 1,
			"confirmed removal creates particle burst"
		)
		await snapshot("remove-effect")
		await pause(1.2)
		check(
			get_tree().get_nodes_in_group("removal_effects").is_empty(),
			"removal particles clean themselves up"
		)
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		game._unhandled_input(escape)
		check(
			not game.remove_mode and not game.hud.remove_btn.button_pressed,
			"Escape exits removal mode"
		)
	game.hud.decorate_btn.button_pressed = false
	await pause()
	check(not game.decorate and game.ghost == null, "closing decorate clears preview")
	game.hud.islands_pressed.emit()
	await pause()
	check(game.hud.rooms_popup.visible, "island directory opens")
	game.hud.reveal(game.hud.rooms_popup, false)
	await pause()
	game.hud.view_toggled.emit()
	await pause(0.9)
	check(game.fps_view and not me._model.visible, "first-person hides local avatar")
	check(game._looking, "first-person activates mouse look")
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(40, 10)
	var old_yaw := game._cam_yaw
	game._input(look)
	check(game._cam_yaw != old_yaw, "mouse motion turns FPS camera")
	var fps_fov := game.camera.fov
	game.zoom_by(-1.0)
	await pause(0.25)
	check(game.camera.fov < fps_fov, "FPS zoom narrows field of view")
	game.zoom_by(1.0)
	await snapshot("first-person")
	game.hud.view_toggled.emit()
	await pause(0.9)
	check(not game.fps_view and me._model.visible, "isometric view restores avatar")
	var iso_size := game.camera.size
	game.zoom_by(-1.0)
	await pause(0.25)
	check(game.camera.size < iso_size, "isometric zoom moves camera closer")
	game.zoom_by(1.0)
	game.hud.mute_btn.button_pressed = true
	check(AudioServer.is_bus_mute(0), "mute control")
	game.hud.mute_btn.button_pressed = false
	for i in 40:
		if game._npc_near(Vector3.ZERO, 100) != null:
			break
		await pause(0.1)
	var npc := game._npc_near(Vector3.ZERO, 100)
	check(npc != null, "NPC spawns in scene")
	if npc:
		net.send({"type": "talk", "npc_id": npc.player_id})
		await pause()
		check(game.hud.dialogue_panel.visible, "NPC dialogue opens")
		check(game.hud.dialogue_options.get_child_count() >= 3, "NPC reply choices available")
		await snapshot("dialogue")
		game.hud.dialogue_key(1)
		await pause()
		game.hud.hide_dialogue()
	game.hud.home_pressed.emit()
	await pause()
	check(game.room.is_owner(game.my_id), "home control loads owned island")
	check(
		game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "home restores isometric camera"
	)
	# A second real WebSocket session gives the UI portal flow an independent island.
	var demo_portal := {}
	for candidate in game.room.state.items:
		if candidate.kind == "portal":
			demo_portal = candidate
	check(demo_portal.get("target_room") != null, "starter portal links to a default friend")
	if demo_portal.get("target_room") != null:
		var demo_destination := int(demo_portal.target_room)
		game._open_portal_islands(demo_portal)
		await pause()
		game.hud.reveal(game.hud.rooms_popup, false)
		game.hud.room_chosen.emit(demo_destination)
		for i in 100:
			if int(game.room.state.id) == demo_destination:
				break
			await pause(0.1)
		await pause(0.8)
		check(
			(
				int(game.room.state.id) == demo_destination
				and str(game.room.state.name).contains("(demo)")
			),
			"portal visits default friend without a second player"
		)
		game.hud.home_pressed.emit()
		await pause(0.8)
		check(game.room.is_owner(game.my_id), "Home returns from default friend's island")
	game.hud.add_chat("[b]name[/b]", "[color=red]literal[/color]")
	check(
		game.hud.chat_log.get_parsed_text().contains("[color=red]literal[/color]"),
		"chat displays user markup as literal text"
	)
	var friend := WebSocketPeer.new()
	friend.connect_to_url(test_url)
	for i in 40:
		friend.poll()
		if friend.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await pause(0.1)
	friend.send_text(
		JSON.stringify(
			{"type": "hello", "name": "neighbor_%d" % int(Time.get_unix_time_from_system())}
		)
	)
	var destination := -1
	for i in 40:
		friend.poll()
		while friend.get_available_packet_count() > 0:
			var msg: Dictionary = JSON.parse_string(friend.get_packet().get_string_from_utf8())
			if msg.get("type") == "welcome":
				destination = int(msg.room.id)
		if destination >= 0:
			break
		await pause(0.1)
	check(destination >= 0, "second player gets an island")
	var portal := {}
	for candidate in game.room.state.items:
		if candidate.kind == "portal":
			portal = candidate
	check(not portal.is_empty(), "home contains a usable portal")
	if not portal.is_empty() and OS.get_environment("COAST_FLOW_SHOTS") != "":
		var saved_camera := game.camera.transform
		var saved_size := game.camera.size
		var center := Main.tile_to_world(int(portal.tx), int(portal.ty)) + Vector3(0, 1.45, 0)
		game.camera.size = 5.5
		game.camera.look_at_from_position(center + Vector3(3, 1.6, 4), center, Vector3.UP)
		await pause(0.8)
		await snapshot("portal-closeup")
		game.camera.transform = saved_camera
		game.camera.size = saved_size
	if destination >= 0 and not portal.is_empty():
		var portal_center := (
			Main.tile_to_world(int(portal.tx), int(portal.ty)) + Vector3(0, Room.FLOOR_Y + 1.2, 0)
		)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = game.camera.unproject_position(portal_center)
		game._unhandled_input(click)
		await pause()
		check(
			game.hud.rooms_popup.visible and game.link_portal_id == int(portal.id),
			"clicking portal opens island selector"
		)
		game.hud.reveal(game.hud.rooms_popup, false)
		game.hud.room_chosen.emit(destination)
		await pause()
		check(int(portal.get("target_room", -1)) == destination, "directory selection links portal")
		for i in 100:
			if int(game.room.state.id) == destination:
				break
			await pause(0.1)
		await pause(0.8)
		check(int(game.room.state.id) == destination, "walking onto portal loads friend's island")
		check(not game.hud.decorate_btn.visible, "visitors cannot open decoration controls")
		check(
			not game.hud.remove_btn.visible and not game.remove_mode,
			"visitors cannot use removal mode"
		)
		check(game.hud.flash.color.a < 0.01, "portal transition fades back into gameplay")
		var beach_walker: Avatar = game.room.avatars[game.my_id]
		beach_walker.set_target(Vector3(11, 0, 0))
		await pause(4.2)
		check(beach_walker.position.x > 10.9, "player walks across garden onto beach")
		friend.poll()
		var beach_seen := false
		while friend.get_available_packet_count() > 0:
			var movement: Dictionary = JSON.parse_string(friend.get_packet().get_string_from_utf8())
			if (
				movement.get("type") == "player_moved"
				and int(movement.player_id) == game.my_id
				and float(movement.x) > 17.9
			):
				beach_seen = true
		check(beach_seen, "second player receives beach movement beyond furniture grid")
		await snapshot("beach-walking")
		if OS.get_environment("COAST_FLOW_SHOTS") != "":
			game.hud.view_toggled.emit()
			await pause(0.9)
			game._cam_yaw = PI / 2.0
			game._cam_pitch = 0.12
			await pause(0.5)
			await snapshot("skybox-sea")
			game.hud.view_toggled.emit()
			await pause(0.9)
			game.rotate_camera(PI / 3.0)
			await pause(0.4)
			await snapshot("rotated-island")
			game.rotate_camera(-PI / 3.0)
		game.hud.home_pressed.emit()
		await pause(0.8)
		check(game.room.is_owner(game.my_id), "home returns from friend's island")
	friend.close()
	var player_id := game.my_id
	var player_name := game.my_name
	net.ws.close()
	await pause(0.8)
	check(game.hud.login_panel.visible and game.my_id == -1, "disconnect returns to login")
	game.hud.login_requested.emit(player_name, test_url)
	await pause(0.8)
	check(game.my_id == player_id, "reconnect restores same player")
	check(not game.hud.login_panel.visible, "reconnect dismisses login")
	await snapshot("gameplay")
	print("FLOW CHECK: ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)

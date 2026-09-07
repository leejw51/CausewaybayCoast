## A player on the island: walks with swinging arms/legs, faces where it goes, shows a name tag + chat bubbles.
class_name Avatar
extends Node3D

signal arrived

const SPEED := 3.0
const SEND_INTERVAL := 0.1
const HAIR := ["#f2c94c", "#e07b39", "#5a3b2e", "#3a6fd8", "#c94c8a", "#2f2a2a", "#4fb46b"]
const SHORTS := ["#6f8fc9", "#c97a5a", "#7fb069", "#9b86c8", "#e8a0b4", "#ebcb6e"]

var player_id := -1
var is_local := false
var is_npc := false
var display_name := ""
var _drive := Vector3.ZERO
var _driving := false
var target: Vector3
var moving := false
var _walk_from: Vector3
var _walk_len := 0.0
var _walk_dur := 0.0
var _walk_elapsed := 0.0
var _walk_t := 0.0
var _send_t := 0.0
var _model: Node3D
var _label: Label3D
var _bubble: Label3D
var _bubble_t := 0.0
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _body: Node3D
var _head: Node3D
var _face_yaw := 0.0
var _anim: AnimationPlayer
var _current_anim := ""


func setup(p: Dictionary, local: bool) -> void:
	player_id = int(p["id"])
	is_local = local
	is_npc = bool(p.get("is_npc", false))
	var name_s := str(p["name"])
	display_name = name_s
	var h := hash(name_s)
	var col := Color.html(str(p.get("colour", "#ffcc66")))
	_model = (
		Assets
		. spawn(
			"adventurer",
			{
				"Lagoon teal cloth": col.lerp(Color("#518e87"), 0.75),
				"M_body": col,
				"M_hair": Color.html(HAIR[h % HAIR.size()]),
				"M_shorts": Color.html(SHORTS[(h / 7) % SHORTS.size()]),
			}
		)
	)
	_model.rotation.y = 0.0  # Blender -Y front exports to Godot +Z
	add_child(_model)
	_assemble(h)
	_arm_l = _model.find_child("ArmL", true, false)
	_arm_r = _model.find_child("ArmR", true, false)
	_leg_l = _model.find_child("LegL", true, false)
	_leg_r = _model.find_child("LegR", true, false)
	_body = _model.find_child("Body", true, false)
	_head = _model.find_child("Head", true, false)
	_anim = _model.find_child("AnimationPlayer", true, false)
	if _anim:
		for n in ["Walk", "Idle"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_play("Idle")

	_label = Label3D.new()
	_label.text = ("✦ " + name_s) if is_npc else name_s
	_label.font_size = 40
	_label.pixel_size = 0.009
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.modulate = Color("#d9f7c8") if is_npc else Color("#fff6dd")
	_label.outline_modulate = Color("#2f5a3b") if is_npc else Color("#5a3b2e")
	_label.outline_size = 5
	_label.position.y = 2.5
	add_child(_label)

	_bubble = Label3D.new()
	_bubble.font_size = 32
	_bubble.pixel_size = 0.009
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.modulate = Color("#3b2a1e")
	_bubble.outline_modulate = Color("#fff6dd")
	_bubble.outline_size = 9
	_bubble.position.y = 3.15
	_bubble.visible = false
	add_child(_bubble)

	position = Main.server_to_world(float(p.get("x", 4.0)), float(p.get("y", 4.0)))
	target = position
	# pop-in
	_model.scale = Vector3(0.01, 0.01, 0.01)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_model, "scale", Vector3.ONE, 0.45)


## Randomly assemble the look from the interchangeable Var_<category>_<name> parts baked into
## player.glb. Seeded by the name hash so the same islander looks the same on every client.
func _assemble(seed_: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var groups := {}
	for n in _model.find_children("Var_*", "", true, false):
		var bits: PackedStringArray = n.name.split("_")
		if bits.size() < 3:
			continue
		var cat := bits[1]
		if not groups.has(cat):
			groups[cat] = []
		groups[cat].append(n)
		n.visible = false
	# hair: 50% keep the spiky core hair, else one of the styles; others: 60% chance of one item
	for cat in groups:
		var opts: Array = groups[cat]
		var chance := 0.5 if cat == "hair" else 0.6
		if rng.randf() < chance:
			opts[rng.randi_range(0, opts.size() - 1)].visible = true
	# NPCs get a stable signature look on top: islanders always wear something on their head
	if is_npc and groups.has("hat"):
		var hats: Array = groups["hat"]
		if not hats.any(func(n): return n.visible):
			hats[abs(seed_) % hats.size()].visible = true


func _play(name: String, blend := 0.15) -> void:
	if _anim == null or _current_anim == name or not _anim.has_animation(name):
		return
	_current_anim = name
	_anim.play(name, blend)


func wave() -> void:
	if _anim and _anim.has_animation("Wave"):
		_current_anim = "Wave"
		_anim.play("Wave", 0.1)
		_anim.animation_finished.connect(
			func(_n):
				_current_anim = ""
				_play("Idle"),
			CONNECT_ONE_SHOT
		)


func say(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_t = 4.0
	_bubble.scale = Vector3(0.2, 0.2, 0.2)
	_bubble.modulate.a = 0.0
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel(
		true
	)
	tw.tween_property(_bubble, "scale", Vector3.ONE, 0.25)
	tw.tween_property(_bubble, "modulate:a", 1.0, 0.25)


## Walk along a straight line with a cosine ease in/out speed profile.
func set_target(world: Vector3) -> void:
	target = Main.clamp_walk(world)
	_walk_from = Vector3(position.x, 0.0, position.z)
	_walk_len = _walk_from.distance_to(target)
	_walk_dur = maxf(0.25, _walk_len / SPEED)
	_walk_elapsed = 0.0
	moving = _walk_len > 0.01


## Keyboard driving: a world-space direction held this frame (zero when released).
func drive(dir: Vector3) -> void:
	_drive = Vector3(dir.x, 0.0, dir.z)


static func ease_sine(t: float) -> float:
	return 0.5 - 0.5 * cos(clampf(t, 0.0, 1.0) * PI)


func _process(delta: float) -> void:
	if _bubble.visible:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble_t = 0.0
			var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(_bubble, "modulate:a", 0.0, 0.3)
			tw.tween_callback(
				func():
					if _bubble_t <= 0.0:
						_bubble.visible = false
			)
	if _drive.length_squared() > 0.0:
		# direct control overrides any eased click-walk
		moving = true
		_driving = true
		var dir := _drive.normalized()
		position += dir * SPEED * delta
		position = Main.clamp_walk(position)
		position.y = 0.0
		target = position
		_face_yaw = atan2(dir.x, dir.z)
		_walk_t += delta * 11.0
		if _anim:
			_anim.speed_scale = 1.1
		if is_local:
			_send_t += delta
			if _send_t >= SEND_INTERVAL:
				_send_t = 0.0
				Net.send({"type": "move", "x": position.x + Main.HALF, "y": position.z + Main.HALF})
	elif _driving:
		_driving = false
		moving = false
		if is_local:
			Net.send({"type": "move", "x": position.x + Main.HALF, "y": position.z + Main.HALF})
			arrived.emit()
	elif moving:
		_walk_elapsed += delta
		var p := _walk_elapsed / _walk_dur
		var prev := Vector3(position.x, 0.0, position.z)
		if p >= 1.0:
			position = target
			moving = false
			if is_local:
				Net.send({"type": "move", "x": position.x + Main.HALF, "y": position.z + Main.HALF})
				arrived.emit()
		else:
			position = _walk_from.lerp(target, ease_sine(p))
			var dir := (target - _walk_from).normalized()
			_face_yaw = atan2(dir.x, dir.z)
			# animation speed follows the eased velocity (cosine bell)
			var v := sin(p * PI)
			_walk_t += delta * 11.0 * maxf(v, 0.2)
			if _anim:
				_anim.speed_scale = 0.4 + 0.9 * v
			if is_local:
				_send_t += delta
				if _send_t >= SEND_INTERVAL:
					_send_t = 0.0
					Net.send(
						{"type": "move", "x": position.x + Main.HALF, "y": position.z + Main.HALF}
					)
	position.y = Main.walk_height(position)
	# smooth turning
	rotation.y = lerp_angle(rotation.y, _face_yaw, minf(1.0, delta * 12.0))
	_animate(delta)


func _animate(delta: float) -> void:
	if _anim:
		# Blender-authored Walk / Idle clips drive the skeleton
		if moving:
			_play("Walk")
		elif _current_anim != "Wave":
			_anim.speed_scale = 1.0
			_play("Idle")
		return
	var swing := sin(_walk_t)
	var amount := 0.75 if moving else 0.0
	# limbs pivot around their local Z (Blender Y) axis; arms and legs alternate
	if _leg_l:
		_leg_l.rotation.z = lerpf(_leg_l.rotation.z, swing * amount, delta * 14.0)
	if _leg_r:
		_leg_r.rotation.z = lerpf(_leg_r.rotation.z, -swing * amount, delta * 14.0)
	if _arm_l:
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -swing * amount * 0.8, delta * 14.0)
	if _arm_r:
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, swing * amount * 0.8, delta * 14.0)
	if moving:
		_model.position.y = abs(sin(_walk_t)) * 0.06
		if _body:
			_body.rotation.x = sin(_walk_t * 2.0) * 0.04
		if _head:
			_head.rotation.z = sin(_walk_t) * 0.06
	else:
		_model.position.y = lerpf(_model.position.y, 0.0, delta * 10.0)
		var breathe := sin(Time.get_ticks_msec() / 500.0 + player_id) * 0.02
		if _body:
			_body.scale.y = 1.0 + breathe
		if _head:
			_head.rotation.z = lerpf(_head.rotation.z, breathe * 1.5, delta * 4.0)

## Holds the decorations and avatars of the room the player is currently in.
class_name Room
extends Node3D

const FLOOR_Y := 0.22  # top of the plank floor in island.glb

var state := {}
var items := {}  # id -> Node3D
var avatars := {}  # player_id -> Avatar
var _items_root: Node3D
var _players_root: Node3D


func _ready() -> void:
	_items_root = Node3D.new()
	_items_root.name = "Items"
	_items_root.position.y = FLOOR_Y
	_players_root = Node3D.new()
	_players_root.name = "Players"
	_players_root.position.y = FLOOR_Y
	add_child(_items_root)
	add_child(_players_root)


func load_state(room: Dictionary, local_id: int) -> void:
	state = room
	for c in _items_root.get_children():
		c.queue_free()
	for c in _players_root.get_children():
		c.queue_free()
	items.clear()
	avatars.clear()
	var i := 0
	for it in room.get("items", []):
		add_item(it, false, i * 0.03)
		i += 1
	for p in room.get("players", []):
		add_player(p, int(p["id"]) == local_id)


func is_owner(pid: int) -> bool:
	return int(state.get("owner_id", -1)) == pid


func item_at(tx: int, ty: int) -> Dictionary:
	for it in state.get("items", []):
		if int(it["tx"]) == tx and int(it["ty"]) == ty:
			return it
	return {}


func add_item(it: Dictionary, sfx: bool = true, delay: float = 0.0) -> void:
	var id := int(it["id"])
	if items.has(id):
		return
	var node := Assets.spawn(str(it["kind"]))
	node.position = Main.tile_to_world(int(it["tx"]), int(it["ty"]))
	node.rotation.y = int(it.get("rot", 0)) * PI / 2.0
	node.set_meta("item", it)
	_items_root.add_child(node)
	items[id] = node
	if not state.get("items", []).any(func(x): return int(x["id"]) == id):
		state["items"].append(it)
	if str(it["kind"]) == "portal":
		_decorate_portal(node, it.get("target_room") != null)
	# pop-in
	node.scale = Vector3(0.01, 0.01, 0.01)
	var rest := node.position
	node.position.y += 0.8
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	node.set_meta("placement_tween", tw)
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector3.ONE, 0.4)
	tw.tween_property(node, "position", rest, 0.4)
	if sfx:
		Sfx.play("place")


func remove_item(id: int) -> void:
	if items.has(id):
		var node: Node3D = items[id]
		items.erase(id)
		var placement: Tween = node.get_meta("placement_tween", null)
		if placement and placement.is_valid():
			placement.kill()
		var burst := preload("res://scripts/RemoveBurst.gd").new()
		add_child(burst)
		burst.global_position = node.global_position + Vector3(0, 0.45, 0)
		var tw := (
			create_tween()
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
			. set_parallel(true)
		)
		tw.tween_property(node, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
		tw.tween_property(node, "position:y", node.position.y + 0.6, 0.3)
		tw.chain().tween_callback(node.queue_free)
		Sfx.play("remove")
	var arr: Array = state.get("items", [])
	for i in arr.size():
		if int(arr[i]["id"]) == id:
			arr.remove_at(i)
			break


func link_portal(id: int, target: int) -> void:
	for it in state.get("items", []):
		if int(it["id"]) == id:
			it["target_room"] = target
	if items.has(id):
		_decorate_portal(items[id], true)


func _decorate_portal(node: Node3D, linked: bool) -> void:
	var lbl: Label3D = node.get_node_or_null("Tag")
	if lbl == null:
		lbl = Label3D.new()
		lbl.name = "Tag"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.font_size = 34
		lbl.pixel_size = 0.005
		lbl.outline_size = 12
		lbl.outline_modulate = Color("#3b2a5a")
		lbl.position.y = 2.5
		node.add_child(lbl)
	lbl.text = "Visit island" if linked else "Choose island"
	lbl.modulate = Color("#d6ccf5") if linked else Color("#ffd6a0")
	var effect := node.get_node_or_null("PortalFX")
	if effect:
		effect.set_linked(linked)


func add_player(p: Dictionary, local: bool) -> Avatar:
	var id := int(p["id"])
	if avatars.has(id):
		return avatars[id]
	var a := Avatar.new()
	_players_root.add_child(a)
	a.setup(p, local)
	avatars[id] = a
	return a


func remove_player(id: int) -> void:
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)


func move_player(id: int, x: float, y: float) -> void:
	if avatars.has(id):
		avatars[id].set_target(Main.server_to_world(x, y))

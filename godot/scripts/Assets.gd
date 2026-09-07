## Loads Blender-exported GLBs, applies the toon shader + Grok textures, and keys UI icons.
extends Node

const MODEL_DIR := "res://assets/models/"
const TEX_DIR := "res://assets/textures/"
const UI_DIR := "res://assets/ui/"
const ITEM_KINDS := [
	"palm",
	"tree",
	"monstera",
	"flower_pot",
	"flower_bed",
	"cactus",
	"bed",
	"table",
	"chair",
	"bench",
	"lamp",
	"rug",
	"bookshelf",
	"portal"
]
const ITEM_LABELS := {
	"palm": "Palm",
	"monstera": "Monstera",
	"flower_pot": "Flowers",
	"cactus": "Cactus",
	"bed": "Bed",
	"table": "Table",
	"chair": "Chair",
	"lamp": "Lamp",
	"rug": "Rug",
	"bookshelf": "Shelf",
	"portal": "Portal",
	"tree": "Tree",
	"bench": "Bench",
	"flower_bed": "Flower bed",
}
const ITEM_EMOJI := {
	"palm": "🌴",
	"monstera": "🪴",
	"flower_pot": "🌸",
	"cactus": "🌵",
	"bed": "🛏",
	"table": "🪑",
	"chair": "💺",
	"lamp": "💡",
	"rug": "🟥",
	"bookshelf": "📚",
	"portal": "🌀",
	"tree": "🌳",
	"bench": "🪑",
	"flower_bed": "🌷",
}
## material name -> [texture, world scale, mix, scroll]
const TEX := {
	"M_plank": ["wood", 0.9, 0.55, Vector2.ZERO, 0.2],
	"M_wood_light": ["wood", 0.9, 0.5, Vector2.ZERO, 0.2],
	"M_sand": ["beach_sand", 0.3, 0.75],
	"M_sand_dark": ["beach_sand", 0.3, 0.55],
	"M_water": ["ocean_caustics", 0.11, 0.8, Vector2(0.012, 0.008), 0.15],
	"M_water_deep": ["ocean_caustics", 0.09, 0.65, Vector2(0.008, 0.005), 0.1],
	"M_roof": ["thatch", 0.7, 0.85],
	"M_roof_dark": ["thatch", 0.7, 0.6],
	"M_wall": ["sand", 0.7, 0.3, Vector2.ZERO, 0.0],
	"M_rug_base": ["rug", 0.52, 0.95, Vector2.ZERO, 0.8],
	"M_leaf_light": ["grass", 1.2, 0.5, Vector2.ZERO, 0.2],
	"M_grass": ["grass", 0.9, 0.55, Vector2.ZERO, 0.25],
	"M_pond": ["water", 0.25, 0.7, Vector2(0.01, 0.006), 0.15],
	"M_hedge": ["grass", 1.4, 0.6, Vector2.ZERO, 0.2],
	"M_hedge_dark": ["grass", 1.4, 0.6, Vector2.ZERO, 0.2],
	"M_trunk": ["bark", 0.9, 0.7],
	"M_trunk_dark": ["bark", 0.9, 0.5],
	"M_wood": ["wood", 0.9, 0.6],
	"M_wood_dark": ["wood", 0.9, 0.45],
	"M_leaf": ["leaf", 0.9, 0.35],
	"M_leaf_dark": ["leaf", 0.9, 0.3],
	"M_stone": ["stone", 0.9, 0.7],
	"M_stone_dark": ["stone", 0.9, 0.5],
	"M_blue": ["fabric", 1.6, 0.75],
}

var toon_shader: Shader = preload("res://shaders/toon.gdshader")
var outline_shader: Shader = preload("res://shaders/outline.gdshader")
var _outline_mat: ShaderMaterial
var _scenes := {}
var _textures := {}
var _icons := {}
var _materials := {}
var _preview_material: StandardMaterial3D


func _ready() -> void:
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = outline_shader


func scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var path := MODEL_DIR + name + ".glb"
		_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[name]


func texture(name: String) -> Texture2D:
	if not _textures.has(name):
		var t: Texture2D = null
		for ext in [".jpg", ".png"]:
			var path: String = TEX_DIR + name + ext
			if ResourceLoader.exists(path):
				t = load(path)
				break
		_textures[name] = t
	return _textures[name]


## Instantiate a model. `tints` recolours materials by prefix, e.g. {"M_body": Color.RED}.
func spawn(name: String, tints: Dictionary = {}, outline: bool = true) -> Node3D:
	var ps := scene(name)
	var inst: Node3D
	if ps == null:
		push_warning("missing model %s, using placeholder" % name)
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.position.y = 0.5
		inst = Node3D.new()
		inst.add_child(mi)
	else:
		inst = ps.instantiate()
	_toonify(inst, tints, outline)
	if name == "portal":
		var effect := preload("res://scripts/PortalFX.gd").new()
		effect.name = "PortalFX"
		inst.add_child(effect)
	return inst


static func _base_name(n: String) -> String:
	# "M_wood.001" -> "M_wood"
	var dot := n.find(".")
	return n.substr(0, dot) if dot >= 0 else n


const COAST_PALETTE := {
	"M_grass": "#91ad79",
	"M_hedge": "#6e956d",
	"M_hedge_dark": "#52765a",
	"M_leaf": "#78996b",
	"M_leaf_light": "#a5b981",
	"M_leaf_dark": "#527b60",
	"M_sand": "#e4d3b0",
	"M_sand_dark": "#c5ae87",
	"M_roof": "#658e88",
	"M_roof_dark": "#416c69",
	"M_wall": "#f0e6d1",
	"M_wall_trim": "#a77858",
	"M_pond": "#64aaa7",
	"M_water": "#76b7bb",
	"M_water_deep": "#76b7bb",
}


func _toonify(n: Node, tints: Dictionary, _outline: bool) -> void:
	if n is MeshInstance3D and n.mesh != null:
		for i in n.mesh.get_surface_count():
			var src: Material = n.get_active_material(i)
			var key := str(src.get_instance_id() if src else 0) + str(tints)
			if _materials.has(key):
				n.set_surface_override_material(i, _materials[key])
				continue
			var mat := StandardMaterial3D.new()
			var mname := ""
			if src is BaseMaterial3D:
				mat = src.duplicate()
				mname = _base_name(src.resource_name)
			if COAST_PALETTE.has(mname):
				mat.albedo_color = Color(COAST_PALETTE[mname])
			for prefix in tints:
				if mname.begins_with(prefix):
					mat.albedo_color = tints[prefix]
			mat.roughness = 0.83
			mat.metallic_specular = 0.25
			mat.cull_mode = (
				BaseMaterial3D.CULL_DISABLED
				if mname in ["Ivory", "Espresso eyes"]
				else BaseMaterial3D.CULL_BACK
			)
			if TEX.has(mname) and str(TEX[mname][0]) in ["beach_sand"]:
				var detail: Texture2D = texture(str(TEX[mname][0]))
				if detail:
					mat.albedo_texture = detail
					mat.uv1_scale = Vector3(float(TEX[mname][1]), float(TEX[mname][1]), 1.0)
			if mname.begins_with("M_water") or mname == "M_pond":
				var water := ShaderMaterial.new()
				water.shader = preload("res://shaders/water.gdshader")
				water.set_shader_parameter("water_color", mat.albedo_color)
				water.set_shader_parameter("is_pond", mname == "M_pond")
				water.set_shader_parameter("caustics", texture("ocean_caustics"))
				_materials[key] = water
				n.set_surface_override_material(i, water)
			else:
				_materials[key] = mat
				n.set_surface_override_material(i, mat)
	for c in n.get_children():
		_toonify(c, tints, false)


## Tint every toon material of an already-spawned node (used for ghost previews).
func set_ghost(n: Node, on: bool) -> void:
	if n is MeshInstance3D and n.mesh != null:
		for i in n.mesh.get_surface_count():
			if on:
				if _preview_material == null:
					_preview_material = StandardMaterial3D.new()
					_preview_material.albedo_color = Color(0.65, 0.92, 0.89, 0.5)
					_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				n.set_surface_override_material(i, _preview_material)
	for c in n.get_children():
		set_ghost(c, on)


## UI image generated by Grok on a magenta background; the background colour (sampled from a
## corner) is keyed to alpha here so icons sit on the cream panels.
func icon(name: String, size: int = 160, key: bool = true) -> Texture2D:
	var cache := name + str(size)
	if _icons.has(cache):
		return _icons[cache]
	var tex: Texture2D = null
	for ext in [".png", ".jpg"]:
		var path: String = UI_DIR + name + ext
		if ResourceLoader.exists(path):
			tex = load(path)
			break
	if tex == null:
		_icons[cache] = null
		return null
	var img: Image = tex.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var h := int(round(float(size) * img.get_height() / img.get_width()))
	img.resize(size, h, Image.INTERPOLATE_LANCZOS)
	if key:
		var bg := img.get_pixel(2, 2)
		for y in h:
			for x in size:
				var c := img.get_pixel(x, y)
				var d := Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b).length()
				var a := clampf((d - 0.10) / 0.18, 0.0, 1.0)
				if a < 1.0:
					# de-fringe: push the edge colour away from the magenta key
					var g := maxf(c.g, (c.r + c.b) * 0.5 - 0.05)
					img.set_pixel(x, y, Color(c.r, g, c.b, a) if a > 0.0 else Color(0, 0, 0, 0))
	var out := ImageTexture.create_from_image(img)
	_icons[cache] = out
	return out

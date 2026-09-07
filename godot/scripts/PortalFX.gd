## Godot-native orbital GPU trails, spark motes and a refractive aperture.
extends Node3D

var _materials: Array[ShaderMaterial] = []
var _linked := false
var _boost := 0.0


func _ready() -> void:
	position.y = 1.3
	var aperture := MeshInstance3D.new()
	aperture.name = "RefractiveAperture"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.58, 1.58)
	var warp := ShaderMaterial.new()
	warp.shader = preload("res://shaders/portal_aperture.gdshader")
	quad.material = warp
	aperture.mesh = quad
	aperture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aperture)
	_materials.append(warp)
	_add_particles("OrbitalTrails", 9, true, false)
	_add_particles("OrbitSparks", 52, false, false)
	_add_particles("InteriorSparks", 24, false, true)


func _add_particles(label: String, count: int, trails: bool, interior: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.amount = count
	particles.lifetime = 3.4
	particles.preprocess = 3.4
	particles.local_coords = true
	particles.fixed_fps = 60
	particles.visibility_aabb = AABB(Vector3(-2, -2, -1), Vector3(4, 4, 2))
	var process := ShaderMaterial.new()
	process.shader = preload("res://shaders/portal_orbit.gdshader")
	process.set_shader_parameter("interior", interior)
	process.set_shader_parameter("orbit_radius", 0.68 if interior else 0.83)
	process.set_shader_parameter(
		"particle_scale", 1.0 if trails else (0.027 if interior else 0.035)
	)
	particles.process_material = process
	_materials.append(process)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	if trails:
		particles.trail_enabled = true
		particles.trail_lifetime = 0.32
		var ribbon := RibbonTrailMesh.new()
		ribbon.size = 0.028
		ribbon.sections = 6
		ribbon.section_segments = 4
		ribbon.section_length = 0.12
		var taper := Curve.new()
		taper.add_point(Vector2(0, 1))
		taper.add_point(Vector2(0.4, 0.6))
		taper.add_point(Vector2(1, 0))
		ribbon.curve = taper
		glow.use_particle_trails = true
		ribbon.material = glow
		particles.draw_pass_1 = ribbon
	else:
		var spark := SphereMesh.new()
		spark.radius = 0.5
		spark.height = 1.0
		spark.radial_segments = 8
		spark.rings = 4
		spark.material = glow
		particles.draw_pass_1 = spark
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)


func set_linked(linked: bool) -> void:
	_linked = linked


func pulse() -> void:
	_boost = 1.5


func _process(delta: float) -> void:
	_boost = maxf(0.0, _boost - delta * 1.5)
	var camera := get_viewport().get_camera_3d()
	if camera:
		var toward := camera.global_position - global_position
		global_rotation.y = atan2(toward.x, toward.z)
	for material in _materials:
		material.set_shader_parameter("energy", (1.15 if _linked else 0.75) + _boost)

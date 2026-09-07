extends Node3D
## A short, self-cleaning burst shared by everyone who sees a removal.


func _ready() -> void:
	add_to_group("removal_effects")
	for layer in 2:
		var particles := GPUParticles3D.new()
		particles.amount = 32 if layer == 0 else 18
		particles.lifetime = 0.85
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 6, 6))
		var material := ParticleProcessMaterial.new()
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		material.emission_sphere_radius = 0.35
		material.direction = Vector3.UP
		material.spread = 130.0
		material.initial_velocity_min = 1.0
		material.initial_velocity_max = 2.7
		material.gravity = Vector3(0, -2.0, 0)
		material.damping_min = 1.0
		material.damping_max = 2.0
		material.scale_min = 0.45
		material.scale_max = 1.0
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(0.6, 0.65))
		curve.add_point(Vector2(1, 0))
		var curve_texture := CurveTexture.new()
		curve_texture.curve = curve
		material.scale_curve = curve_texture
		particles.process_material = material
		var mesh := SphereMesh.new()
		mesh.radius = 0.065 if layer == 0 else 0.11
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		var surface := StandardMaterial3D.new()
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		surface.albedo_color = Color("91dfc1") if layer == 0 else Color("ffdda1")
		mesh.material = surface
		particles.draw_pass_1 = mesh
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(particles)
		particles.restart()
	get_tree().create_timer(1.2).timeout.connect(queue_free)

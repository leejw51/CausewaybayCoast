## Short-lived orbital trails and motes at departure/arrival.
extends Node3D


func start(arriving: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#b5f4eb") if arriving else Color("#d2b8ff")
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 1.4
	var vortex := preload("res://scripts/PortalFX.gd").new()
	add_child(vortex)
	vortex.get_node("RefractiveAperture").hide()
	vortex.set_linked(true)
	vortex.pulse()
	vortex.scale = Vector3.ONE * (1.8 if arriving else 0.3)
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(vortex, "scale", Vector3.ONE * (0.02 if arriving else 2.2), 0.9)
	tween.tween_callback(vortex.queue_free)
	var motes := CPUParticles3D.new()
	motes.amount = 64
	motes.one_shot = true
	motes.explosiveness = 0.9
	motes.lifetime = 1.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.7
	motes.position.y = 1.0
	motes.direction = Vector3.UP
	motes.spread = 150.0
	motes.initial_velocity_min = 1.2
	motes.initial_velocity_max = 3.0
	motes.gravity = Vector3(0, -0.6, 0)
	motes.scale_amount_min = 0.025
	motes.scale_amount_max = 0.065
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = mat
	motes.mesh = sphere
	add_child(motes)
	motes.emitting = true
	get_tree().create_timer(1.5).timeout.connect(queue_free)

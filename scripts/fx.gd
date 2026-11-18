extends Node
## Визуальные эффекты: искры, взрывы, дым, пыль, вспышки. Всё процедурное.

var _mats := {}
var _spark_mesh: BoxMesh
var _chunk_mesh: BoxMesh
var _smoke_mesh: SphereMesh
var _fire_mesh: SphereMesh
var _ring_mesh: TorusMesh


func _ready() -> void:
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.025, 0.025, 0.14)
	_spark_mesh.material = glow_mat(Color(1.0, 0.75, 0.3), 9.0)
	_chunk_mesh = BoxMesh.new()
	_chunk_mesh.size = Vector3(0.07, 0.07, 0.07)
	_chunk_mesh.material = solid_mat(Color(0.2, 0.2, 0.22), 0.8, 0.5)
	_smoke_mesh = SphereMesh.new()
	_smoke_mesh.radius = 0.5
	_smoke_mesh.height = 1.0
	_smoke_mesh.radial_segments = 10
	_smoke_mesh.rings = 6
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.16, 0.15, 0.15, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	sm.roughness = 1.0
	sm.vertex_color_use_as_albedo = true
	sm.billboard_keep_scale = true
	_smoke_mesh.material = sm
	_fire_mesh = SphereMesh.new()
	_fire_mesh.radius = 0.5
	_fire_mesh.height = 1.0
	_fire_mesh.radial_segments = 16
	_fire_mesh.rings = 8
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.9
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 32
	_ring_mesh.ring_segments = 6


# ------------------------------------------------------------- материалы

func solid_mat(c: Color, metal: float = 0.0, rough: float = 0.7) -> StandardMaterial3D:
	var key := "s%s_%s_%s" % [c.to_html(), metal, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	_mats[key] = m
	return m


func glow_mat(c: Color, energy: float = 4.0) -> StandardMaterial3D:
	var key := "g%s_%s" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


func additive_mat(c: Color, energy: float = 3.0) -> StandardMaterial3D:
	var key := "a%s_%s" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c * energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.vertex_color_use_as_albedo = true
	_mats[key] = m
	return m


# ------------------------------------------------------------- частицы

func _particles(pos: Vector3, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = max(amount, 1)
	p.lifetime = life
	p.local_coords = false
	G.world.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.6, false).timeout.connect(p.queue_free)
	return p


func sparks(pos: Vector3, normal: Vector3, amount: int = 14, speed: float = 7.0, color: Color = Color(1, 0.75, 0.3)) -> void:
	if G.world == null:
		return
	var p := _particles(pos, amount, 0.55)
	p.mesh = _spark_mesh
	if color != Color(1, 0.75, 0.3):
		var m := _spark_mesh.duplicate()
		m.material = glow_mat(color, 9.0)
		p.mesh = m
	p.direction = normal if normal.length() > 0.1 else Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14, 0)
	p.particle_flag_align_y = false
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.damping_min = 1.0
	p.damping_max = 3.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve


func chips(pos: Vector3, normal: Vector3, amount: int = 8, color: Color = Color(0.45, 0.43, 0.4)) -> void:
	if G.world == null:
		return
	var p := _particles(pos, amount, 0.9)
	var m := _chunk_mesh.duplicate()
	m.material = solid_mat(color, 0.0, 0.9)
	p.mesh = m
	p.direction = normal
	p.spread = 45.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -16, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6


func smoke(pos: Vector3, amount: int = 8, size: float = 1.0, life: float = 2.2, color: Color = Color(0.2, 0.19, 0.18)) -> void:
	if G.world == null:
		return
	var p := _particles(pos, amount, life)
	p.explosiveness = 0.7
	p.mesh = _smoke_mesh
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.5 * size
	p.initial_velocity_max = 2.5 * size
	p.gravity = Vector3(0, 1.2, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.6 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.7))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad


func dust(pos: Vector3, size: float = 1.0) -> void:
	smoke(pos, 10, size, 1.4, Color(0.42, 0.38, 0.33))


func flash(pos: Vector3, color: Color, energy: float, rng: float, dur: float) -> void:
	if G.world == null:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	G.world.add_child(l)
	l.global_position = pos
	var t := l.create_tween()
	t.tween_property(l, "light_energy", 0.0, dur)
	t.tween_callback(l.queue_free)


func explosion(pos: Vector3, radius: float, big: bool = true) -> void:
	if G.world == null:
		return
	# огненный шар
	var fire := MeshInstance3D.new()
	fire.mesh = _fire_mesh
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.55, 0.15, 1.0) * 3.0
	fire.material_override = fm
	G.world.add_child(fire)
	fire.global_position = pos
	fire.scale = Vector3.ONE * 0.3
	var t := fire.create_tween().set_parallel(true)
	t.tween_property(fire, "scale", Vector3.ONE * radius * 1.5, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(fm, "albedo_color", Color(0.6, 0.1, 0.02, 0.0), 0.45)
	t.chain().tween_callback(fire.queue_free)
	# ударная волна
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(1.0, 0.8, 0.5, 0.8)
	ring.material_override = rm
	G.world.add_child(ring)
	ring.global_position = pos + Vector3(0, 0.1, 0)
	ring.scale = Vector3(0.5, 0.2, 0.5)
	var t2 := ring.create_tween().set_parallel(true)
	t2.tween_property(ring, "scale", Vector3(radius * 2.2, 0.4, radius * 2.2), 0.35).set_ease(Tween.EASE_OUT)
	t2.tween_property(rm, "albedo_color", Color(1, 0.5, 0.2, 0.0), 0.35)
	t2.chain().tween_callback(ring.queue_free)

	flash(pos + Vector3(0, 0.5, 0), Color(1.0, 0.6, 0.25), 14.0 if big else 6.0, radius * 4.0, 0.5)
	sparks(pos, Vector3.UP, 40 if big else 18, 16.0)
	smoke(pos, 16 if big else 7, radius * 0.6, 3.0)
	chips(pos, Vector3.UP, 14 if big else 6, Color(0.15, 0.14, 0.13))


## Постоянный эмиттер искр (на месте оторванной конечности).
func spark_emitter(parent: Node3D, local_pos: Vector3, life: float = 6.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 0.5
	p.explosiveness = 0.0
	p.randomness = 1.0
	p.local_coords = false
	p.mesh = _spark_mesh
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	parent.add_child(p)
	p.position = local_pos
	p.emitting = true
	if life > 0.0:
		_expire(p, life, 1.0)
	return p


func smoke_emitter(parent: Node3D, local_pos: Vector3, life: float = 8.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.6
	p.local_coords = false
	p.mesh = _smoke_mesh
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.12, 0.12, 0.12, 0.6))
	grad.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	p.color_ramp = grad
	parent.add_child(p)
	p.position = local_pos
	p.emitting = true
	if life > 0.0:
		_expire(p, life, 2.0)
	return p


## Выключает эмиттер через life секунд и удаляет его. Твин живёт вместе с узлом,
## поэтому если узел удалён раньше — ничего не ломается.
func _expire(p: CPUParticles3D, life: float, tail: float) -> void:
	var tw := p.create_tween()
	tw.tween_interval(life)
	tw.tween_property(p, "emitting", false, 0.0)
	tw.tween_interval(tail)
	tw.tween_callback(p.queue_free)


## Короткая светящаяся полоска (трассер / луч).
func beam(from: Vector3, to: Vector3, color: Color, width: float, dur: float) -> void:
	if G.world == null:
		return
	var ln := from.distance_to(to)
	if ln < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, ln)
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	mi.material_override = m
	G.world.add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at_from_position(mi.global_position, to, Vector3.UP if abs((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var t := mi.create_tween()
	t.tween_property(m, "albedo_color", Color(color.r, color.g, color.b, 0.0), dur)
	t.tween_callback(mi.queue_free)

extends Node
## Визуальные эффекты: искры, взрывы, дым, пыль, вспышки. Всё процедурное.

var _mats := {}
var _spark_mesh: BoxMesh
var _chunk_mesh: BoxMesh
var _smoke_mesh: QuadMesh
var _fire_mesh: SphereMesh
var _ring_mesh: TorusMesh
var _fire_quad: QuadMesh
var _muzzle_tex: Texture2D
var _hole_tex: Texture2D
var _scorch_tex: Texture2D
var _decals: Array = []
var _shells: Array = []
var _shell_mesh: CylinderMesh


func _ready() -> void:
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.025, 0.025, 0.14)
	_spark_mesh.material = glow_mat(Color(1.0, 0.75, 0.3), 9.0)
	_chunk_mesh = BoxMesh.new()
	_chunk_mesh.size = Vector3(0.07, 0.07, 0.07)
	_chunk_mesh.material = solid_mat(Color(0.2, 0.2, 0.22), 0.8, 0.5)
	_smoke_mesh = QuadMesh.new()
	_smoke_mesh.size = Vector2(1.0, 1.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load("res://assets/fx/smoke.png")
	sm.albedo_color = Color(1, 1, 1, 1)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 1.0
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.proximity_fade_enabled = true
	sm.proximity_fade_distance = 0.6
	_smoke_mesh.material = sm
	_fire_quad = QuadMesh.new()
	_fire_quad.size = Vector2(1.0, 1.0)
	var fq := StandardMaterial3D.new()
	fq.albedo_texture = load("res://assets/fx/fire.png")
	fq.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fq.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fq.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fq.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fq.billboard_keep_scale = true
	fq.vertex_color_use_as_albedo = true
	fq.albedo_color = Color(2.5, 2.0, 1.6, 1.0)
	_fire_quad.material = fq
	_muzzle_tex = load("res://assets/fx/muzzle.png")
	_hole_tex = load("res://assets/fx/bullet_hole.png")
	_scorch_tex = load("res://assets/fx/scorch.png")
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
	p.scale_amount_min = 1.2 * size
	p.scale_amount_max = 2.6 * size
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	var c2 := color * 2.0
	grad.set_color(0, Color(c2.r, c2.g, c2.b, 0.0))
	grad.add_point(0.08, Color(c2.r, c2.g, c2.b, 0.75))
	grad.set_color(grad.get_point_count() - 1, Color(c2.r, c2.g, c2.b, 0.0))
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
	# огненные клубы
	var f := _particles(pos, 14 if big else 7, 0.55)
	f.mesh = _fire_quad
	f.explosiveness = 1.0
	f.direction = Vector3.UP
	f.spread = 180.0
	f.initial_velocity_min = radius * 0.8
	f.initial_velocity_max = radius * 2.2
	f.damping_min = radius * 3.0
	f.damping_max = radius * 5.0
	f.gravity = Vector3(0, 2.0, 0)
	f.angle_min = -180.0
	f.angle_max = 180.0
	f.scale_amount_min = radius * 0.8
	f.scale_amount_max = radius * 1.6
	var fc := Curve.new()
	fc.add_point(Vector2(0, 0.4))
	fc.add_point(Vector2(0.25, 1.0))
	fc.add_point(Vector2(1, 1.2))
	f.scale_amount_curve = fc
	var fg := Gradient.new()
	fg.set_color(0, Color(1.0, 0.9, 0.7, 1.0))
	fg.add_point(0.35, Color(1.0, 0.45, 0.12, 0.8))
	fg.set_color(fg.get_point_count() - 1, Color(0.3, 0.08, 0.02, 0.0))
	f.color_ramp = fg
	# ударная волна
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(1.0, 0.85, 0.6, 0.35)
	ring.material_override = rm
	G.world.add_child(ring)
	ring.global_position = pos + Vector3(0, 0.1, 0)
	ring.scale = Vector3(0.5, 0.15, 0.5)
	var t2 := ring.create_tween().set_parallel(true)
	t2.tween_property(ring, "scale", Vector3(radius * 2.4, 0.3, radius * 2.4), 0.3).set_ease(Tween.EASE_OUT)
	t2.tween_property(rm, "albedo_color", Color(1, 0.5, 0.2, 0.0), 0.3)
	t2.chain().tween_callback(ring.queue_free)

	flash(pos + Vector3(0, 0.8, 0), Color(1.0, 0.62, 0.3), 16.0 if big else 7.0, radius * 4.5, 0.55)
	sparks(pos, Vector3.UP, 45 if big else 20, 18.0)
	smoke(pos + Vector3(0, radius * 0.3, 0), 18 if big else 8, radius * 0.75, 4.5 if big else 2.8, Color(0.16, 0.15, 0.14))
	dust(pos, radius * 0.6)
	chips(pos, Vector3.UP, 18 if big else 8, Color(0.18, 0.16, 0.14))
	# копоть на земле
	var hit := G.ray(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 3.0, G.L_WORLD, [], false)
	if not hit.is_empty():
		decal(hit.position, hit.normal, _scorch_tex, radius * (1.4 if big else 0.9), 40.0)


## След на поверхности (пулевое отверстие, копоть).
func decal(pos: Vector3, normal: Vector3, tex: Texture2D, size: float, life: float = 25.0) -> void:
	if G.world == null:
		return
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(size, 0.4, size)
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.normal_fade = 0.3
	G.world.add_child(d)
	var y := normal.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	d.global_transform = Transform3D(Basis(x, y, z).rotated(y, randf() * TAU), pos)
	_decals.append(d)
	while _decals.size() > 160:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := d.create_tween()
	tw.tween_interval(life)
	tw.tween_property(d, "modulate:a", 0.0, 2.0)
	tw.tween_callback(d.queue_free)


## Попадание пули в окружение: отверстие, крошка, пыль, искры.
func impact(pos: Vector3, normal: Vector3, collider: Object) -> void:
	var stat: bool = collider is StaticBody3D or (collider is WallChunk and not collider.broken)
	if stat and not (collider is WallChunk):
		decal(pos, normal, _hole_tex, randf_range(0.12, 0.2), 30.0)
	if collider is StaticBody3D or collider is WallChunk:
		chips(pos, normal, 4, Color(0.38, 0.36, 0.33))
		var p := _particles(pos + normal * 0.05, 3, 0.9)
		p.mesh = _smoke_mesh
		p.direction = normal
		p.spread = 25.0
		p.initial_velocity_min = 0.8
		p.initial_velocity_max = 2.0
		p.damping_min = 2.0
		p.damping_max = 3.0
		p.scale_amount_min = 0.25
		p.scale_amount_max = 0.5
		var g := Gradient.new()
		g.set_color(0, Color(0.75, 0.7, 0.65, 0.5))
		g.set_color(1, Color(0.75, 0.7, 0.65, 0.0))
		p.color_ramp = g
	else:
		sparks(pos, normal, 6, 5.0)


## Вспышка у дула (в мире).
func muzzle_flash(pos: Vector3, size: float = 0.35) -> void:
	if G.world == null:
		return
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = _muzzle_tex
	m.albedo_color = Color(3.0, 2.4, 1.6, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = 10
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	G.world.add_child(q)
	q.global_position = pos
	q.rotate_object_local(Vector3.BACK, randf() * TAU)
	get_tree().create_timer(0.045, false).timeout.connect(q.queue_free)


## Гильза вылетает из оружия.
func shell(pos: Vector3, vel: Vector3, big: bool = false) -> void:
	if G.world == null:
		return
	if _shell_mesh == null:
		_shell_mesh = CylinderMesh.new()
		_shell_mesh.top_radius = 0.006
		_shell_mesh.bottom_radius = 0.006
		_shell_mesh.height = 0.03
		_shell_mesh.radial_segments = 8
		_shell_mesh.material = Mats.robot("brass")
	var rb := RigidBody3D.new()
	rb.collision_layer = G.L_DEBRIS
	rb.collision_mask = G.L_WORLD | G.L_PROPS
	rb.mass = 0.02
	rb.continuous_cd = true
	var mi := MeshInstance3D.new()
	mi.mesh = _shell_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if big:
		mi.scale = Vector3(2.2, 1.6, 2.2)
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.014, 0.03, 0.014) * (1.8 if big else 1.0)
	cs.shape = bs
	rb.add_child(cs)
	G.world.add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	_shells.append(rb)
	while _shells.size() > 50:
		var o = _shells.pop_front()
		if is_instance_valid(o):
			o.queue_free()
	var tw := rb.create_tween()
	tw.tween_interval(randf_range(0.35, 0.6))
	tw.tween_callback(func(): Sfx.play3d("lever", rb.global_position, -22.0, randf_range(2.2, 2.8)))
	tw.tween_interval(6.0)
	tw.tween_callback(rb.queue_free)


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
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	p.angle_min = -180.0
	p.angle_max = 180.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.25, 0.24, 0.23, 0.55))
	grad.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
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


## Красный круг на земле, куда упадёт снаряд.
func warning_ring(pos: Vector3, radius: float, dur: float) -> Node3D:
	if G.world == null:
		return null
	var hit := G.ray(pos + Vector3.UP * 4.0, pos + Vector3.DOWN * 10.0, G.L_WORLD, [], false)
	var gp: Vector3 = hit.position if not hit.is_empty() else pos
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.92
	tm.outer_radius = radius
	tm.rings = 40
	tm.ring_segments = 4
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.15, 0.05, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	G.world.add_child(mi)
	mi.global_position = gp + Vector3(0, 0.06, 0)
	mi.scale = Vector3(1, 0.05, 1)
	var t := mi.create_tween().set_loops(int(dur / 0.3) + 1)
	t.tween_property(m, "albedo_color:a", 0.25, 0.15)
	t.tween_property(m, "albedo_color:a", 0.9, 0.15)
	mi.create_tween().tween_callback(mi.queue_free).set_delay(dur + 0.6)
	return mi

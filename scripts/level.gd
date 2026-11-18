class_name Level
extends RefCounted
## Строит арену: промзона-свалка на закате.

static var _main: Node3D


static func build(main: Node3D) -> void:
	_main = main
	var concrete := StandardMaterial3D.new()
	concrete.albedo_texture = main.concrete_tex
	concrete.normal_enabled = true
	concrete.normal_texture = main.concrete_nrm
	concrete.normal_scale = 0.6
	concrete.roughness = 0.9
	concrete.uv1_triplanar = true
	concrete.uv1_world_triplanar = true
	concrete.uv1_scale = Vector3(0.12, 0.12, 0.12)
	var rust := StandardMaterial3D.new()
	rust.albedo_texture = main.rust_tex
	rust.metallic = 0.5
	rust.roughness = 0.75
	rust.uv1_triplanar = true
	rust.uv1_world_triplanar = true
	rust.uv1_scale = Vector3(0.18, 0.18, 0.18)
	rust.normal_enabled = true
	rust.normal_texture = main.concrete_nrm
	rust.normal_scale = 0.4

	# --- пол
	_static_box(Vector3(0, -0.5, 0), Vector3(220, 1, 220), concrete)
	# разметка
	var paint := Fx.solid_mat(Color(0.75, 0.6, 0.15), 0.0, 0.8)
	for i in 8:
		var a := i * TAU / 8.0
		_deco_box(Vector3(cos(a) * 14.0, 0.005, sin(a) * 14.0), Vector3(3.0, 0.01, 0.35), paint, a)
	_deco_ring(Vector3.ZERO, 22.0, paint)

	# --- периметр
	var wall_h := 9.0
	for i in 4:
		var a := i * PI * 0.5
		var pos := Vector3(sin(a) * 47.0, wall_h * 0.5, cos(a) * 47.0)
		var b := _static_box(pos, Vector3(96, wall_h, 2.0), rust)
		b.rotation.y = a
		for k in 9:
			var off := -44.0 + k * 11.0
			var pp := pos + Vector3(cos(a), 0, -sin(a)) * off
			var col := _static_box(Vector3(pp.x, wall_h * 0.5 + 0.3, pp.z) - Vector3(sin(a), 0, cos(a)) * 1.2, Vector3(1.0, wall_h + 0.6, 1.0), Fx.solid_mat(Color(0.12, 0.12, 0.13), 0.7, 0.4))
			col.rotation.y = a
		# полоса предупреждения
		var stripe := _deco_box(pos + Vector3(0, -wall_h * 0.5 + 0.6, 0) - Vector3(sin(a), 0, cos(a)) * 1.02, Vector3(96, 0.5, 0.05), Fx.solid_mat(Color(0.9, 0.65, 0.05), 0.2, 0.6), a)
		stripe.rotation.y = a

	# --- контейнеры
	var cols := [Color(0.55, 0.12, 0.08), Color(0.1, 0.25, 0.45), Color(0.15, 0.35, 0.18), Color(0.8, 0.45, 0.1), Color(0.35, 0.36, 0.38)]
	_container(Vector3(-30, 0, -28), 0.2, cols[0])
	_container(Vector3(-30.3, 2.6, -28.2), 0.28, cols[1])
	_container(Vector3(-34, 0, -21), 1.5, cols[4])
	_container(Vector3(33, 0, -20), 1.4, cols[2])
	_container(Vector3(-35, 0, 22), -0.3, cols[1])
	_container(Vector3(29, 0, 31), 0.1, cols[0])
	_container(Vector3(29.4, 2.6, 30.8), 0.05, cols[3])
	_container(Vector3(-3, 0, -39), 0.0, cols[3])
	_container(Vector3(3.5, 0, -38.6), 0.06, cols[4])
	_container(Vector3(-14, 0, 38), 1.57, cols[2])
	_container(Vector3(38, 0, 6), 1.62, cols[1])

	# --- мостки с пандусами
	_platform(Vector3(-18, 3.4, -6), 0.0)
	_platform(Vector3(19, 3.4, 8), PI)

	# --- колонны
	var pillar := concrete
	for p in [Vector3(8, 0, 9), Vector3(-9, 0, -15), Vector3(15, 0, -12), Vector3(-7, 0, 13), Vector3(-24, 0, 8), Vector3(25, 0, -6)]:
		_static_box(p + Vector3(0, 3.5, 0), Vector3(1.3, 7, 1.3), pillar)
		_static_box(p + Vector3(0, 7.2, 0), Vector3(2.2, 0.4, 2.2), Fx.solid_mat(Color(0.15, 0.15, 0.16), 0.7, 0.4))

	# --- разрушаемые стены
	var grey := Color(0.6, 0.58, 0.55)
	var brick := Color(0.62, 0.3, 0.2)
	var dark := Color(0.4, 0.4, 0.42)
	_wall(Vector3(0, 0, 0), 0.0, 12, 8, grey)
	_wall(Vector3(-12, 0, 8), 1.2, 9, 6, brick)
	_wall(Vector3(12, 0, -4), -0.6, 10, 6, grey)
	_wall(Vector3(-20, 0, -18), 0.4, 10, 9, brick)
	_wall(Vector3(22, 0, 19), 2.0, 10, 7, dark)
	_wall(Vector3(6, 0, -23), 0.0, 8, 5, brick)
	_wall(Vector3(-25, 0, 31), 0.9, 8, 6, grey)
	_wall(Vector3(31, 0, -4), 1.57, 8, 7, brick)
	_wall(Vector3(-6, 0, 25), 0.0, 7, 5, dark)

	# --- ящики
	_crates(Vector3(-5, 0, -8), 5)
	_crates(Vector3(16, 0, 11), 6)
	_crates(Vector3(-27, 0, 3), 4)
	_crates(Vector3(24, 0, -31), 6)
	_crates(Vector3(-15, 0, 26), 4)
	_crates(Vector3(9, 0, 30), 3)

	# --- бочки
	for p in [Vector3(-3, 0, -6), Vector3(-2.2, 0, -6.6), Vector3(14, 0, 13), Vector3(-26, 0, 6),
			Vector3(3, 0, 2.2), Vector3(-10, 0, 10.5), Vector3(20, 0, -2), Vector3(-19, 0, -14),
			Vector3(26, 0, 25), Vector3(-30, 0, -24), Vector3(5, 0, -20), Vector3(-6.6, 0, 27)]:
		Prop.barrel(p + Vector3(0, 0.6, 0))

	# --- фонари
	for p in [Vector3(-28, 0, -10), Vector3(28, 0, 14), Vector3(0, 0, -30), Vector3(-10, 0, 30), Vector3(18, 0, -26), Vector3(-36, 0, 36), Vector3(36, 0, -38)]:
		_lamp(p)

	# --- металлолом (декор)
	var junk_mats := [Fx.solid_mat(Color(0.25, 0.22, 0.2), 0.7, 0.6), rust, Fx.solid_mat(Color(0.18, 0.2, 0.22), 0.8, 0.45)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for c in [Vector3(-38, 0, 0), Vector3(38, 0, 24), Vector3(10, 0, 40), Vector3(-38, 0, -38), Vector3(20, 0, -40)]:
		for i in 9:
			var size = Vector3(rng.randf_range(0.6, 2.4), rng.randf_range(0.3, 1.4), rng.randf_range(0.6, 2.2))
			var p: Vector3 = c + Vector3(rng.randf_range(-3, 3), size.y * 0.4 + rng.randf_range(0, 0.8), rng.randf_range(-3, 3))
			var b := _static_box(p, size, junk_mats[i % 3])
			b.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))

	# --- горизонт: трубы и краны
	var silhouette := Fx.solid_mat(Color(0.08, 0.08, 0.09), 0.3, 0.8)
	for i in 14:
		var a := i * TAU / 14.0 + 0.2
		var r = rng.randf_range(85, 130)
		var h = rng.randf_range(18, 55)
		var w = rng.randf_range(8, 20)
		_deco_box(Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(w, h, w * 0.7), silhouette, a)
		if i % 3 == 0:
			var st := _deco_cyl(Vector3(cos(a) * r + 6, h + 15, sin(a) * r), 1.6, 30, silhouette)
			var glow := MeshInstance3D.new()
			var gs := SphereMesh.new()
			gs.radius = 0.6
			gs.height = 1.2
			glow.mesh = gs
			glow.material_override = Fx.glow_mat(Color(1.0, 0.1, 0.05), 8.0)
			main.add_child(glow)
			glow.global_position = st.global_position + Vector3(0, 15.5, 0)
	_crane(Vector3(-60, 0, -55), 0.7)
	_crane(Vector3(70, 0, 40), 2.4)

	# --- точки высадки роботов
	for i in 12:
		var a := i * TAU / 12.0 + 0.13
		main.spawn_points.append(Vector3(cos(a) * 36.0, 0, sin(a) * 36.0))
	for p in [Vector3(-10, 0, -28), Vector3(20, 0, -14), Vector3(-30, 0, 12)]:
		main.spawn_points.append(p)


# ------------------------------------------------------------------ helpers

static func _static_box(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = G.L_WORLD
	b.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	_main.add_child(b)
	b.global_position = pos
	return b


static func _deco_box(pos: Vector3, size: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	_main.add_child(mi)
	mi.global_position = pos
	mi.rotation.y = rot_y
	return mi


static func _deco_cyl(pos: Vector3, r: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.8
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	_main.add_child(mi)
	mi.global_position = pos
	return mi


static func _deco_ring(center: Vector3, r: float, mat: Material) -> void:
	for i in 48:
		var a := i * TAU / 48.0
		if i % 2 == 0:
			_deco_box(center + Vector3(cos(a) * r, 0.005, sin(a) * r), Vector3(0.3, 0.01, 2.2), mat, -a)


static func _container(pos: Vector3, rot: float, c: Color) -> void:
	var size := Vector3(6.1, 2.6, 2.45)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.55
	m.roughness = 0.55
	m.normal_enabled = true
	m.normal_texture = _main.concrete_nrm
	m.normal_scale = 0.3
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.3, 0.3, 0.3)
	var b := _static_box(pos + Vector3(0, size.y * 0.5, 0), size, m)
	b.rotation.y = rot
	# рёбра жёсткости
	var dark := Fx.solid_mat(c.darkened(0.45), 0.6, 0.5)
	for i in 13:
		var x := -2.8 + i * 0.466
		for side in [-1.0, 1.0]:
			var r := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.12, size.y - 0.2, 0.06)
			r.mesh = rm
			r.material_override = dark
			b.add_child(r)
			r.position = Vector3(x, 0, side * (size.z * 0.5 + 0.02))
	for y in [-1.0, 1.0]:
		var f := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(size.x + 0.06, 0.16, size.z + 0.06)
		f.mesh = fm
		f.material_override = dark
		b.add_child(f)
		f.position = Vector3(0, y * (size.y * 0.5 - 0.08), 0)


static func _platform(pos: Vector3, rot: float) -> void:
	var metal := Fx.solid_mat(Color(0.22, 0.23, 0.25), 0.8, 0.45)
	var yellow := Fx.solid_mat(Color(0.85, 0.6, 0.05), 0.3, 0.5)
	var root := Node3D.new()
	_main.add_child(root)
	root.global_position = pos
	root.rotation.y = rot
	var parts := [
		[Vector3(0, 0, 0), Vector3(12, 0.4, 4), metal],
		[Vector3(0, 0.6, -1.95), Vector3(12, 0.08, 0.08), yellow],
		[Vector3(0, 1.05, -1.95), Vector3(12, 0.08, 0.08), yellow],
	]
	for p in parts:
		var b := StaticBody3D.new()
		b.collision_layer = G.L_WORLD
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.material_override = p[2]
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = p[1]
		cs.shape = bs
		b.add_child(cs)
		root.add_child(b)
		b.position = p[0]
	# опоры
	for x in [-5.5, 0.0, 5.5]:
		for z in [-1.7, 1.7]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.25, pos.y, 0.25)
			leg.mesh = lm
			leg.material_override = metal
			root.add_child(leg)
			leg.position = Vector3(x, -pos.y * 0.5, z)
	# пандус
	var length := 10.6
	var ang := atan2(pos.y, 10.0)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = G.L_WORLD
	var rmi := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(3.0, 0.3, length)
	rmi.mesh = rbm
	rmi.material_override = metal
	ramp.add_child(rmi)
	var rcs := CollisionShape3D.new()
	var rbs := BoxShape3D.new()
	rbs.size = rbm.size
	rcs.shape = rbs
	ramp.add_child(rcs)
	root.add_child(ramp)
	ramp.position = Vector3(4.5, -pos.y * 0.5, 2.0 + 5.0)
	ramp.rotation.x = ang


static func _wall(pos: Vector3, rot: float, w: int, h: int, c: Color) -> void:
	var wall := DestructibleWall.new().setup(w, h, c)
	_main.add_child(wall)
	wall.global_position = pos
	wall.rotation.y = rot


static func _crates(center: Vector3, n: int) -> void:
	for i in n:
		var size := 1.0 if i % 3 != 2 else 1.3
		var p := center + Vector3((i % 3) * 1.15 - 1.1, size * 0.5 + 0.01 + (i / 3) * 1.05, (i % 2) * 0.3)
		Prop.crate(p, size)


static func _lamp(pos: Vector3) -> void:
	var metal := Fx.solid_mat(Color(0.15, 0.15, 0.16), 0.8, 0.4)
	_static_box(pos + Vector3(0, 4.0, 0), Vector3(0.25, 8.0, 0.25), metal)
	_deco_box(pos + Vector3(0.7, 8.0, 0), Vector3(1.6, 0.15, 0.25), metal)
	var head := _deco_box(pos + Vector3(1.4, 7.85, 0), Vector3(0.6, 0.12, 0.4), Fx.glow_mat(Color(1.0, 0.75, 0.45), 6.0))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.42)
	l.light_energy = 6.0
	l.spot_range = 18.0
	l.spot_angle = 55.0
	l.spot_attenuation = 0.8
	l.shadow_enabled = true
	_main.add_child(l)
	l.global_position = pos + Vector3(1.4, 7.7, 0)
	l.rotation.x = -PI * 0.5
	_main.lamps.append(l)


static func _crane(pos: Vector3, rot: float) -> void:
	var m := Fx.solid_mat(Color(0.09, 0.09, 0.1), 0.4, 0.7)
	var root := Node3D.new()
	_main.add_child(root)
	root.global_position = pos
	root.rotation.y = rot
	var mast := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(2.5, 45, 2.5)
	mast.mesh = mm
	mast.material_override = m
	root.add_child(mast)
	mast.position = Vector3(0, 22.5, 0)
	var jib := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(40, 1.8, 1.8)
	jib.mesh = jm
	jib.material_override = m
	root.add_child(jib)
	jib.position = Vector3(12, 45, 0)
	var light := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.5
	lm.height = 1.0
	light.mesh = lm
	light.material_override = Fx.glow_mat(Color(1.0, 0.1, 0.05), 10.0)
	root.add_child(light)
	light.position = Vector3(31, 46.2, 0)

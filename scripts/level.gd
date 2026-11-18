class_name Level
extends RefCounted
## Арена: заброшенная промзона, заросшая травой. Модели и текстуры — Poly Haven (CC0).

const HALF := 48.0
const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D mask_tex : filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D road_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_r : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec4 m = texture(mask_tex, (p + 150.0) / 300.0);
	float n1 = texture(noise_tex, p * 0.031).r;
	float n2 = texture(noise_tex, p * 0.17 + 3.7).r;
	vec2 uv_road = p * 0.22;
	vec2 uv_grass = p * 0.33;
	vec2 uv_conc = p * 0.2;
	vec2 uv_dirt = p * 0.28;
	vec3 a_d = texture(dirt_a, uv_dirt).rgb;
	vec3 a_c = texture(conc_a, uv_conc).rgb;
	vec3 a_r = texture(road_a, uv_road).rgb;
	vec3 a_g = texture(grass_a, uv_grass).rgb;
	vec3 n_d = texture(dirt_n, uv_dirt).rgb;
	vec3 n_c = texture(conc_n, uv_conc).rgb;
	vec3 n_r = texture(road_n, uv_road).rgb;
	vec3 n_g = texture(grass_n, uv_grass).rgb;
	vec3 r_d = texture(dirt_r, uv_dirt).rgb;
	vec3 r_c = texture(conc_r, uv_conc).rgb;
	vec3 r_r = texture(road_r, uv_road).rgb;
	vec3 r_g = texture(grass_r, uv_grass).rgb;

	float wc0 = smoothstep(0.45, 0.6, n1 + (n2 - 0.5) * 0.3);
	vec3 alb = mix(a_d, a_c * 0.92, wc0);
	vec3 nrm = mix(n_d, n_c, wc0);
	vec3 arm = mix(r_d, r_c, wc0);
	float wc = smoothstep(0.35, 0.65, m.b + (n2 - 0.5) * 0.5);
	alb = mix(alb, a_c, wc); nrm = mix(nrm, n_c, wc); arm = mix(arm, r_c, wc);
	float wr = smoothstep(0.4, 0.6, m.r + (n2 - 0.5) * 0.35);
	alb = mix(alb, a_r, wr); nrm = mix(nrm, n_r, wr); arm = mix(arm, r_r, wr);
	float wg = smoothstep(0.3, 0.7, m.g + (n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.3);
	alb = mix(alb, a_g, wg); nrm = mix(nrm, n_g, wg); arm = mix(arm, r_g, wg);
	alb *= mix(0.82, 1.08, n1);

	ALBEDO = alb;
	NORMAL_MAP = nrm;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = arm.g;
	METALLIC = 0.0;
}
"""

static var _main: Node3D
static var mask: Image
static var rng := RandomNumberGenerator.new()
static var _pieces := {}


static func build(main: Node3D) -> void:
	_main = main
	rng.seed = 2026
	var mt: Texture2D = load("res://assets/ground_mask.png")
	mask = mt.get_image()
	if mask.is_compressed():
		mask.decompress()
	_ground()
	_facades()
	_cover()
	_props()
	_nature()
	_decals()
	for i in 12:
		var a := i * TAU / 12.0 + 0.13
		main.spawn_points.append(Vector3(cos(a) * 34.0, 0, sin(a) * 34.0))
	for p in [Vector3(-10, 0, -28), Vector3(20, 0, -14), Vector3(-30, 0, 12)]:
		main.spawn_points.append(p)


## Значения маски покрытия в точке мира: r — асфальт, g — трава, b — бетон.
static func mask_at(x: float, z: float) -> Color:
	var u = int(clamp((x + 150.0) / 300.0 * mask.get_width(), 0, mask.get_width() - 1))
	var v = int(clamp((z + 150.0) / 300.0 * mask.get_height(), 0, mask.get_height() - 1))
	return mask.get_pixel(u, v)


# ================================================================ земля

static func _ground() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = G.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(300, 8, 300)
	cs.shape = bs
	cs.position.y = -4.0
	sb.add_child(cs)
	_main.add_child(sb)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("mask_tex", load("res://assets/ground_mask.png"))
	m.set_shader_parameter("noise_tex", Mats.noise)
	for pair in [["road", "worn_asphalt"], ["grass", "sparse_grass"], ["conc", "cracked_concrete"], ["dirt", "brown_mud_leaves_01"]]:
		m.set_shader_parameter(pair[0] + "_a", Assets.tex(pair[1], "diff"))
		m.set_shader_parameter(pair[0] + "_n", Assets.tex(pair[1], "nor"))
		m.set_shader_parameter(pair[0] + "_r", Assets.tex(pair[1], "arm"))
	mi.material_override = m
	sb.add_child(mi)


# ================================================================ фасады

static func _piece(kit: String, prefix: String) -> Mesh:
	var key := kit + "/" + prefix
	if _pieces.has(key):
		return _pieces[key]
	var names: Array = Assets.nodes(kit).keys()
	names.sort()
	var found: Mesh = null
	for n in names:
		if n == prefix or (n.begins_with(prefix + "_") and n.substr(prefix.length() + 1).is_valid_int()):
			found = Assets.mesh(kit, n)
			if found:
				break
	if found == null:
		push_warning("нет детали " + key)
	_pieces[key] = found
	return found


static func _facades() -> void:
	var factory := {
		"kit": "modular_factory_facade", "floors": 3,
		"ground": [["wall_door_garage_door", "door_garage_door", 2], ["wall_standard_standard", "", 1],
			["wall_door_recessed_large", "door_recessed_large", 1], ["wall_window_tall_large", "window_tall_large", 1],
			["wall_standard_standard", "", 1], ["wall_window_tall_small", "window_tall_small", 1]],
		"upper": [["wall_window_tall_large", "window_tall_large"], ["wall_window_tall_small", "window_tall_small"],
			["wall_window_centered_large", "window_centered_large"], ["wall_standard_standard", ""]],
		"base": "base_standard_standard", "dado": "dado_standard_standard",
		"cornice": "cornice01_standard_standard", "crown": "crown_standard_standard",
	}
	var apart := {
		"kit": "modular_urban_apartments_facade", "floors": 4,
		"ground": [["wall_door_centered_large", "door_centered_large", 1], ["wall_standard_standard", "", 1],
			["wall_door_window_small", "door_window_small", 1], ["wall_door_offset_small", "door_offset_small", 1],
			["wall_window_centered_large", "window_centered_large", 1]],
		"upper": [["wall_window_centered_large", "window_centered_large"], ["wall_window_centered_double", "window_centered_double"],
			["wall_window_offset_small", "window_offset_small"], ["wall_window_centered_small", "window_centered_small"]],
		"base": "base_standard", "dado": "dado_standard_standard",
		"cornice": "cornice_standard_standard", "crown": "crown_standard_standard",
	}
	_facade_row(factory, Vector3(0, 0, -HALF), 0.0)
	_facade_row(apart, Vector3(0, 0, HALF), PI)
	_facade_row(factory, Vector3(HALF, 0, 0), -PI * 0.5)
	_facade_row(apart, Vector3(-HALF, 0, 0), PI * 0.5)


static func _facade_row(style: Dictionary, origin: Vector3, rot: float) -> void:
	var kit: String = style.kit
	var floors: int = style.floors
	var basis := Basis(Vector3.UP, rot)
	var row := Transform3D(basis, origin)
	var n_slots := 34
	var half := n_slots * 1.5
	var xf := {}
	var add := func(prefix: String, x: float, y: float) -> void:
		if prefix == "":
			return
		var m := _piece(kit, prefix)
		if m == null:
			return
		if not xf.has(m):
			xf[m] = []
		xf[m].append(row * Transform3D(Basis(), Vector3(x, y, 0)))
	var i := 0
	while i < n_slots:
		var opt: Array = style.ground[rng.randi() % style.ground.size()]
		var w: int = opt[2]
		if i + w > n_slots:
			opt = style.ground[1]
			w = 1
		var x := -half + 3.0 * (i + w)
		add.call(opt[0], x, 0.0)
		add.call(opt[1], x, 0.0)
		i += w
	var pattern: Array = []
	for k in n_slots:
		pattern.append(style.upper[rng.randi() % style.upper.size()])
	for f in range(1, floors):
		for k in n_slots:
			var x := -half + 3.0 * (k + 1)
			var opt: Array = pattern[k] if rng.randf() > 0.12 else style.upper[rng.randi() % style.upper.size()]
			add.call(opt[0], x, 3.0 * f)
			add.call(opt[1], x, 3.0 * f)
	for k in n_slots:
		var x := -half + 3.0 * (k + 1)
		add.call(style.base, x, 0.0)
		for f in range(1, floors):
			add.call(style.dado, x, 3.0 * f - 0.25)
		add.call(style.cornice, x, 3.0 * floors)
		add.call(style.crown, x, 3.0 * floors + 0.15)
	for m in xf:
		Assets.multimesh(_main, m, xf[m], true)
	var depth := 10.0
	var height := 3.0 * floors + 1.0
	var inner := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(n_slots * 3.0 + 2.0, height, depth)
	inner.mesh = bm
	inner.material_override = Fx.solid_mat(Color(0.035, 0.033, 0.03), 0.0, 1.0)
	_main.add_child(inner)
	inner.global_transform = row * Transform3D(Basis(), Vector3(0, height * 0.5, -0.35 - depth * 0.5))
	var sb := StaticBody3D.new()
	sb.collision_layer = G.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(n_slots * 3.0 + 2.0, height + 30.0, depth)
	cs.shape = bs
	sb.add_child(cs)
	_main.add_child(sb)
	sb.global_transform = row * Transform3D(Basis(), Vector3(0, (height + 30.0) * 0.5, -0.05 - depth * 0.5))
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(n_slots * 3.0 + 2.0, 0.4, depth + 0.4)
	roof.mesh = rm
	roof.material_override = Assets.pbr("concrete_wall_006", Color(0.6, 0.58, 0.55), 0.25)
	_main.add_child(roof)
	roof.global_transform = row * Transform3D(Basis(), Vector3(0, height - 0.6, -0.2 - depth * 0.5))
	for k in 4:
		var px = rng.randf_range(-half + 6.0, half - 6.0)
		var pipes := Assets.whole("modular_industrial_pipes_01")
		_main.add_child(pipes)
		pipes.global_transform = row * Transform3D(Basis().scaled(Vector3.ONE * 1.4), Vector3(px, 1.6, 0.15))


# ================================================================ укрытия

static func _cover() -> void:
	var cols := [Color(0.95, 0.42, 0.32), Color(0.45, 0.6, 0.85), Color(0.6, 0.8, 0.55), Color(1.0, 0.75, 0.45), Color(0.8, 0.8, 0.82)]
	var conts := [
		[Vector3(-30, 0, -28), 0.2, 0], [Vector3(-30.3, 2.6, -28.2), 0.28, 1], [Vector3(-34, 0, -21), 1.5, 4],
		[Vector3(33, 0, -20), 1.4, 2], [Vector3(-35, 0, 22), -0.3, 1], [Vector3(29, 0, 31), 0.1, 0],
		[Vector3(29.4, 2.6, 30.8), 0.05, 3], [Vector3(-3, 0, -39), 0.0, 3], [Vector3(3.5, 0, -38.6), 0.06, 4],
		[Vector3(38, 0, 6), 1.62, 1],
	]
	for c in conts:
		_container(c[0], c[1], Assets.pbr("rusty_corrugated_iron", cols[c[2]], 0.45, false))

	_platform(Vector3(-18, 3.4, -6), 0.0)
	_platform(Vector3(19, 3.4, 8), PI)

	var conc := Assets.pbr("concrete_wall_006", Color(0.85, 0.83, 0.8), 0.3)
	for p in [Vector3(8, 0, 9), Vector3(-9, 0, -15), Vector3(15, 0, -12), Vector3(-7, 0, 13), Vector3(-24, 0, 8), Vector3(25, 0, -6)]:
		_box(p + Vector3(0, 3.5, 0), Vector3(1.3, 7, 1.3), conc)
		_box(p + Vector3(0, 7.2, 0), Vector3(2.4, 0.5, 2.4), conc)

	_wall(Vector3(0, 0, 0), 0.0, 12, 8, "concrete_wall_006")
	_wall(Vector3(-12, 0, 8), 1.2, 9, 6, "red_brick")
	_wall(Vector3(12, 0, -4), -0.6, 10, 6, "concrete_wall_006")
	_wall(Vector3(-20, 0, -18), 0.4, 10, 9, "red_brick")
	_wall(Vector3(22, 0, 19), 2.0, 10, 7, "concrete_wall_006")
	_wall(Vector3(6, 0, -23), 0.0, 8, 5, "red_brick")
	_wall(Vector3(-25, 0, 31), 0.9, 8, 6, "concrete_wall_006")
	_wall(Vector3(31, 0, -4), 1.57, 8, 7, "red_brick")
	_wall(Vector3(-6, 0, 25), 0.0, 7, 5, "concrete_wall_006")

	var barriers := [
		[Vector3(-14, 0, -2), 0.1], [Vector3(-12.4, 0, -1.8), 0.05], [Vector3(14, 0, 3.5), 1.4], [Vector3(14.2, 0, 5.1), 1.5],
		[Vector3(4, 0, 15), 0.3], [Vector3(5.6, 0, 15.4), 0.2], [Vector3(-3, 0, -18), -0.2], [Vector3(-1.4, 0, -18.2), -0.1],
		[Vector3(24, 0, -16), 0.8], [Vector3(-30, 0, -6), 1.6], [Vector3(-30.2, 0, -4.4), 1.5], [Vector3(10, 0, 26), -0.4],
		[Vector3(-16, 0, 18), 2.4], [Vector3(36, 0, 18), 0.9], [Vector3(-38, 0, 8), 1.3], [Vector3(18, 0, -30), 0.0],
	]
	for i in barriers.size():
		var b: Array = barriers[i]
		var model := "concrete_road_barrier" if i % 3 != 2 else "concrete_road_barrier_02"
		Assets.place(_main, Assets.whole(model), b[0], b[1], 1.0, "box")

	for c in [[Vector3(-31, 0, 28), 0.3], [Vector3(-24, 0, 33), 0.25], [Vector3(-36, 0, 34), 0.35], [Vector3(26, 0, 12), 1.9]]:
		Assets.place(_main, Assets.whole("covered_car"), c[0], c[1], 1.0, "box")

	_fence(Vector3(-44, 0, 14), 0.0, 9)
	_fence(Vector3(42, 0, -34), PI * 0.5, 7)


static func _box(pos: Vector3, size: Vector3, m: Material) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = G.L_WORLD
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	_main.add_child(b)
	b.global_position = pos
	return b


static func _container(pos: Vector3, rot: float, m: Material) -> void:
	var size := Vector3(6.1, 2.6, 2.45)
	var b := _box(pos + Vector3(0, size.y * 0.5, 0), size, m)
	b.rotation.y = rot
	var frame := Assets.pbr("rusty_metal_02", Color(0.55, 0.5, 0.45), 0.5, false)
	for y in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(size.x + 0.08, 0.16, 0.16)
			f.mesh = fm
			f.material_override = frame
			b.add_child(f)
			f.position = Vector3(0, y * (size.y * 0.5 - 0.08), z * (size.z * 0.5 - 0.05))
	for x in [-1.0, 1.0]:
		var d := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(0.06, size.y - 0.1, size.z - 0.1)
		d.mesh = dm
		d.material_override = frame
		b.add_child(d)
		d.position = Vector3(x * (size.x * 0.5 + 0.01), 0, 0)


static func _platform(pos: Vector3, rot: float) -> void:
	var metal := Assets.pbr("metal_plate_02", Color(0.75, 0.75, 0.75), 0.4)
	var yellow := Fx.solid_mat(Color(0.85, 0.6, 0.05), 0.3, 0.5)
	var root := Node3D.new()
	_main.add_child(root)
	root.global_position = pos
	root.rotation.y = rot
	var parts := [
		[Vector3(0, 0, 0), Vector3(12, 0.3, 4), metal],
		[Vector3(0, 0.6, -1.95), Vector3(12, 0.06, 0.06), yellow],
		[Vector3(0, 1.05, -1.95), Vector3(12, 0.06, 0.06), yellow],
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
	for x in [-5.5, 0.0, 5.5]:
		for z in [-1.7, 1.7]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.22, pos.y, 0.22)
			leg.mesh = lm
			leg.material_override = metal
			root.add_child(leg)
			leg.position = Vector3(x, -pos.y * 0.5, z)
	var length := 10.6
	var ramp := StaticBody3D.new()
	ramp.collision_layer = G.L_WORLD
	var rmi := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(3.0, 0.25, length)
	rmi.mesh = rbm
	rmi.material_override = metal
	ramp.add_child(rmi)
	var rcs := CollisionShape3D.new()
	var rbs := BoxShape3D.new()
	rbs.size = rbm.size
	rcs.shape = rbs
	ramp.add_child(rcs)
	root.add_child(ramp)
	ramp.position = Vector3(4.5, -pos.y * 0.5, 7.0)
	ramp.rotation.x = atan2(pos.y, 10.0)


static func _wall(pos: Vector3, rot: float, w: int, h: int, tex: String) -> void:
	var wall := DestructibleWall.new().setup(w, h, Color.WHITE)
	wall.tex_name = tex
	_main.add_child(wall)
	wall.global_position = pos
	wall.rotation.y = rot


static func _fence(start: Vector3, rot: float, n: int) -> void:
	var kit := "modular_chainlink_fence"
	var basis := Basis(Vector3.UP, rot)
	var panel := _piece(kit, "modular_chainlink_fence_double")
	var post := _piece(kit, "modular_chainlink_fence_post")
	var px: Array = []
	var pp: Array = []
	for i in n + 1:
		pp.append(Transform3D(basis, start) * Transform3D(Basis(), Vector3(-2.0 * i, 0, 0)))
		if i > 0:
			px.append(Transform3D(basis, start) * Transform3D(Basis(), Vector3(-2.0 * (i - 1), 0, 0)))
	if panel:
		Assets.multimesh(_main, panel, px, true)
	if post:
		Assets.multimesh(_main, post, pp, true)
	var sb := StaticBody3D.new()
	sb.collision_layer = G.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0 * n, 2.5, 0.12)
	cs.shape = bs
	sb.add_child(cs)
	_main.add_child(sb)
	sb.global_transform = Transform3D(basis, start) * Transform3D(Basis(), Vector3(-n, 1.25, 0))


# ================================================================ мелкие предметы

static func _props() -> void:
	_crates(Vector3(-5, 0, -8), 4)
	_crates(Vector3(16, 0, 11), 5)
	_crates(Vector3(-27, 0, 3), 4)
	_crates(Vector3(24, 0, -31), 5)
	_crates(Vector3(-15, 0, 26), 3)
	_crates(Vector3(9, 0, 30), 3)
	for p in [Vector3(-3, 0, -6), Vector3(-2.2, 0, -6.6), Vector3(14, 0, 13), Vector3(-26, 0, 6),
			Vector3(3, 0, 2.2), Vector3(-10, 0, 10.5), Vector3(20, 0, -2), Vector3(-19, 0, -14),
			Vector3(26, 0, 25), Vector3(-30, 0, -24), Vector3(5, 0, -20), Vector3(-6.6, 0, 27)]:
		Prop.barrel(p + Vector3(0, 0.5, 0))
	var junk := ["old_tyre", "rusted_wheel_rim_01", "metal_jerrycan", "cardboard_box_01", "barrel_03"]
	for i in 45:
		var p = Vector3(rng.randf_range(-44, 44), 0, rng.randf_range(-44, 44))
		if p.length() < 6.0:
			continue
		var model: String = junk[i % junk.size()]
		var n := Assets.whole(model)
		Assets.place(_main, n, p, rng.randf() * TAU, 1.0, "none")
		if model == "old_tyre" and rng.randf() < 0.6:
			n.rotation.x = PI * 0.5
			n.position.y = 0.08
	for p in [Vector3(-6, 0.0, 2), Vector3(-6, 0.0, 22), Vector3(14, 0.0, 2), Vector3(-6, 0.0, -24), Vector3(-30, 0, 2)]:
		Assets.place(_main, Assets.whole("water_manhole_cover"), p + Vector3(0, 0.005, 0), rng.randf() * TAU, 1.0, "none")
	for p in [Vector3(2, 0, -5), Vector3(-14, 0, 9), Vector3(10, 0, 9), Vector3(-1, 0, -30), Vector3(-12, 0, 36)]:
		Assets.place(_main, Assets.whole("street_lamp_01"), p, rng.randf() * TAU, 1.3, "box")
	for p in [Vector3(-40, 0, -8), Vector3(40, 0, 12), Vector3(-12, 0, -42), Vector3(30, 0, 42)]:
		Assets.place(_main, Assets.copy("modular_electricity_poles", "preset_01_pole"), p, rng.randf() * PI, 1.2, "box")
	for i in 8:
		var side := i % 4
		var along = rng.randf_range(-40, 40)
		var p: Vector3 = [Vector3(along, 0, -HALF + 0.7), Vector3(along, 0, HALF - 0.7), Vector3(HALF - 0.7, 0, along), Vector3(-HALF + 0.7, 0, along)][side]
		var r: float = [0.0, PI, -PI * 0.5, PI * 0.5][side]
		Assets.place(_main, Assets.whole("utility_box_01"), p, r, 1.4, "box")


static func _crates(center: Vector3, n: int) -> void:
	for i in n:
		var p = center + Vector3((i % 2) * 0.95 - 0.45, 0.2 + (i / 2) * 0.36, rng.randf_range(-0.1, 0.1))
		Prop.crate(p, 1.0)


# ================================================================ растительность

static func _nature() -> void:
	var grass_meshes: Array = []
	for n in ["grass_medium_02_c", "grass_medium_02_d", "grass_medium_02_e", "grass_medium_01_large_a_LOD0", "grass_medium_01_tall_a_LOD0", "grass_medium_01_mid_a_LOD0"]:
		var model := "grass_medium_02" if n.begins_with("grass_medium_02") else "grass_medium_01"
		var m := Assets.mesh(model, n)
		if m:
			grass_meshes.append(m)
	var weeds: Array = []
	for n in ["weed_plant_02_a_LOD0", "weed_plant_02_b_LOD0", "nettle_plant_tall_a_LOD0", "nettle_plant_medium_a_LOD0"]:
		var model := "weed_plant_02" if n.begins_with("weed") else "nettle_plant"
		var m := Assets.mesh(model, n)
		if m:
			weeds.append(m)
	if grass_meshes.is_empty():
		push_warning("трава не найдена")
		return
	var chunk := 16.0
	var cx := -HALF
	while cx < HALF:
		var cz := -HALF
		while cz < HALF:
			var per: Array = []
			for k in grass_meshes.size() + weeds.size():
				per.append([])
			for k in 520:
				var x := cx + rng.randf() * chunk
				var z := cz + rng.randf() * chunk
				if absf(x) > HALF - 0.5 or absf(z) > HALF - 0.5:
					continue
				var g := mask_at(x, z).g
				if rng.randf() > g * 0.95 + 0.03:
					continue
				var s = rng.randf_range(1.6, 3.2) if g > 0.5 else rng.randf_range(1.0, 1.8)
				var t = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(x, 0, z))
				if rng.randf() < 0.12 and weeds.size() > 0:
					per[grass_meshes.size() + rng.randi() % weeds.size()].append(t)
				else:
					per[rng.randi() % grass_meshes.size()].append(t)
			for k in per.size():
				if per[k].size() > 0:
					var mesh: Mesh = grass_meshes[k] if k < grass_meshes.size() else weeds[k - grass_meshes.size()]
					Assets.multimesh(_main, mesh, per[k], false, 55.0)
			cz += chunk
		cx += chunk

	var shrubs := ["shrub_02_a", "shrub_02_b", "shrub_02_c", "shrub_02_d"]
	for i in 26:
		var p = _edge_point(rng.randf_range(2.0, 7.0))
		Assets.place(_main, Assets.copy("shrub_02", shrubs[i % shrubs.size()]), p, rng.randf() * TAU, rng.randf_range(0.8, 1.4), "none")
	var ferns := ["fern_02_a", "fern_02_b", "fern_02_c", "fern_02_d"]
	for i in 40:
		var p = Vector3(rng.randf_range(-44, 44), 0, rng.randf_range(-44, 44))
		if mask_at(p.x, p.z).g < 0.4:
			continue
		Assets.place(_main, Assets.copy("fern_02", ferns[i % 4]), p, rng.randf() * TAU, rng.randf_range(1.0, 1.8), "none")
	for t in [[Vector3(-38, 0.15, -14), 0.4], [Vector3(34, 0.15, -38), 1.2], [Vector3(16, 0.15, 38), 2.6]]:
		Assets.place(_main, Assets.whole("dead_tree_trunk"), t[0], t[1], 1.6, "box")
	for p in [Vector3(-40, 0, 40), Vector3(41, 0, -12), Vector3(-41, 0, -36)]:
		Assets.place(_main, Assets.whole("boulder_01"), p, rng.randf() * TAU, rng.randf_range(1.2, 1.8), "hull")
	var rocks := ["rock_moss_set_01_rock01", "rock_moss_set_01_rock02", "rock_moss_set_01_rock03", "rock_moss_set_01_rock04", "rock_moss_set_01_rock05", "rock_moss_set_01_rock06"]
	for i in 8:
		var p = _edge_point(rng.randf_range(2.0, 9.0))
		Assets.place(_main, Assets.copy("rock_moss_set_01", rocks[i % rocks.size()]), p - Vector3(0, 0.2, 0), rng.randf() * TAU, rng.randf_range(0.6, 1.0), "hull")


static func _edge_point(inset: float) -> Vector3:
	var side := rng.randi() % 4
	var along = rng.randf_range(-HALF + 4.0, HALF - 4.0)
	var d := HALF - inset
	return [Vector3(along, 0, -d), Vector3(along, 0, d), Vector3(d, 0, along), Vector3(-d, 0, along)][side]


static func _decals() -> void:
	var oil: Texture2D = load("res://assets/fx/oil.png")
	var scorch: Texture2D = load("res://assets/fx/scorch.png")
	for i in 36:
		var p = Vector3(rng.randf_range(-44, 44), 0, rng.randf_range(-44, 44))
		var road := mask_at(p.x, p.z).r
		var d := Decal.new()
		d.texture_albedo = oil if road > 0.4 or rng.randf() < 0.3 else scorch
		var s = rng.randf_range(1.5, 4.5)
		d.size = Vector3(s, 1.0, s)
		d.modulate = Color(1, 1, 1, rng.randf_range(0.5, 0.9))
		_main.add_child(d)
		d.global_position = p
		d.rotation.y = rng.randf() * TAU

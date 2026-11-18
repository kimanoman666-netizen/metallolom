class_name ViewModel
extends Node3D
## Руки и оружие от первого лица. Специальный шейдер «сжимает» модель к камере,
## поэтому оружие никогда не проваливается в стены.

const SHADER := """
shader_type spatial;
render_mode skip_vertex_transform, cull_back;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic = 0.5;
uniform float roughness = 0.5;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * 0.1;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb * emission_energy;
}
"""

static var _shader: Shader

var player: Node
var root: Node3D
var weapons: Array = []          # Node3D для каждого оружия
var muzzles: Array = []
var current := 0
var target := 0
var switch_t := 0.0
var kick := 0.0
var kick_rot := 0.0
var sway := Vector2.ZERO
var bob_phase := 0.0
var right_hand: Node3D
var left_hand: Node3D
var fist: Node3D
var fist_mat: ShaderMaterial
var coil_mats: Array = []
var laser_mat: ShaderMaterial
var rocket_tip: Node3D
var punch_state := 0.0           # 0 нет, 0..1 заряд, 2 удар
var _t := 0.0


static func mat(c: Color, metal: float = 0.5, rough: float = 0.5, emis: Color = Color.BLACK, energy: float = 0.0) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("emission", emis)
	m.set_shader_parameter("emission_energy", energy)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	parent.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, rot: Vector3 = Vector3(PI * 0.5, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	mi.mesh = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	parent.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi


func _ready() -> void:
	root = Node3D.new()
	add_child(root)
	var sleeve := mat(Color(0.12, 0.13, 0.15), 0.1, 0.8)
	var glove := mat(Color(0.08, 0.08, 0.09), 0.2, 0.6)
	var armor := mat(Color(0.22, 0.23, 0.25), 0.7, 0.35)
	var orange := mat(Color(0.85, 0.45, 0.06), 0.5, 0.4)
	var gun_dark := mat(Color(0.1, 0.1, 0.11), 0.85, 0.35)
	var gun_mid := mat(Color(0.5, 0.52, 0.55), 0.9, 0.28)

	# правая рука (держит оружие)
	right_hand = Node3D.new()
	root.add_child(right_hand)
	_box(right_hand, Vector3(0.1, 0.1, 0.34), Vector3(0.05, -0.12, 0.17), sleeve, Vector3(0.45, 0, 0))
	_box(right_hand, Vector3(0.11, 0.035, 0.16), Vector3(0.05, -0.065, 0.15), armor, Vector3(0.45, 0, 0))
	_box(right_hand, Vector3(0.112, 0.012, 0.03), Vector3(0.05, -0.05, 0.08), orange, Vector3(0.45, 0, 0))
	_box(right_hand, Vector3(0.09, 0.1, 0.1), Vector3(0.03, -0.06, 0.0), glove)

	# левая рука (поддерживает)
	left_hand = Node3D.new()
	root.add_child(left_hand)
	_box(left_hand, Vector3(0.09, 0.09, 0.32), Vector3(-0.15, -0.13, -0.05), sleeve, Vector3(0.45, -0.7, 0))
	_box(left_hand, Vector3(0.1, 0.03, 0.14), Vector3(-0.14, -0.085, -0.05), armor, Vector3(0.45, -0.7, 0))
	_box(left_hand, Vector3(0.09, 0.08, 0.11), Vector3(-0.06, -0.06, -0.2), glove)

	# ---------- бластер
	var w0 := Node3D.new()
	root.add_child(w0)
	_box(w0, Vector3(0.08, 0.12, 0.42), Vector3(0, 0, -0.12), gun_dark)
	_box(w0, Vector3(0.085, 0.04, 0.3), Vector3(0, 0.075, -0.1), gun_mid)
	_box(w0, Vector3(0.06, 0.13, 0.07), Vector3(0, -0.1, 0.02), gun_dark, Vector3(-0.3, 0, 0))
	_cyl(w0, 0.025, 0.24, Vector3(0, 0.01, -0.42), gun_mid)
	for i in 3:
		var cm := mat(Color(0.1, 0.6, 0.8), 0.2, 0.3, Color(0.2, 0.8, 1.0), 2.0)
		coil_mats.append(cm)
		_cyl(w0, 0.04, 0.025, Vector3(0, 0.01, -0.36 - i * 0.05), cm)
	_box(w0, Vector3(0.02, 0.03, 0.18), Vector3(0.045, 0.02, -0.1), mat(Color(0.1, 0.6, 0.8), 0.2, 0.3, Color(0.2, 0.8, 1.0), 3.0))
	_add_muzzle(w0, Vector3(0, 0.01, -0.56))

	# ---------- лазер
	var w1 := Node3D.new()
	root.add_child(w1)
	_box(w1, Vector3(0.11, 0.14, 0.38), Vector3(0, 0, -0.1), gun_mid)
	_box(w1, Vector3(0.115, 0.05, 0.4), Vector3(0, 0.09, -0.12), armor)
	_box(w1, Vector3(0.06, 0.13, 0.07), Vector3(0, -0.11, 0.03), gun_dark, Vector3(-0.3, 0, 0))
	for i in 4:
		_box(w1, Vector3(0.16, 0.012, 0.05), Vector3(0, -0.04 + i * 0.03, -0.3), gun_dark)
	laser_mat = mat(Color(1.0, 0.3, 0.2), 0.0, 0.2, Color(1.0, 0.25, 0.1), 3.0)
	var lens := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.045
	sp.height = 0.09
	lens.mesh = sp
	lens.material_override = laser_mat
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens.extra_cull_margin = 16384.0
	w1.add_child(lens)
	lens.position = Vector3(0, 0.01, -0.34)
	_cyl(w1, 0.06, 0.06, Vector3(0, 0.01, -0.33), gun_dark)
	_add_muzzle(w1, Vector3(0, 0.01, -0.4))

	# ---------- РПГ
	var w2 := Node3D.new()
	root.add_child(w2)
	var olive := mat(Color(0.25, 0.28, 0.18), 0.4, 0.6)
	_cyl(w2, 0.075, 0.85, Vector3(0, 0.06, -0.12), olive)
	_cyl(w2, 0.085, 0.08, Vector3(0, 0.06, -0.52), gun_dark)
	_cyl(w2, 0.09, 0.1, Vector3(0, 0.06, 0.28), gun_dark)
	_box(w2, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.06, 0.0), gun_dark, Vector3(-0.3, 0, 0))
	_box(w2, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.05, -0.22), gun_dark)
	_box(w2, Vector3(0.03, 0.06, 0.12), Vector3(-0.07, 0.15, -0.05), gun_mid)
	rocket_tip = Node3D.new()
	w2.add_child(rocket_tip)
	var tipm := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.0
	tc.bottom_radius = 0.06
	tc.height = 0.16
	tipm.mesh = tc
	tipm.material_override = mat(Color(0.8, 0.2, 0.1), 0.5, 0.4)
	tipm.rotation.x = -PI * 0.5
	tipm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tipm.extra_cull_margin = 16384.0
	rocket_tip.add_child(tipm)
	rocket_tip.position = Vector3(0, 0.06, -0.6)
	_add_muzzle(w2, Vector3(0, 0.06, -0.62))

	weapons = [w0, w1, w2]
	for i in weapons.size():
		weapons[i].visible = i == 0
	root.position = Vector3(0.2, -0.17, -0.5)
	root.scale = Vector3.ONE * 0.72

	# кулак для суперудара
	fist = Node3D.new()
	add_child(fist)
	fist_mat = mat(Color(0.75, 0.42, 0.08), 0.7, 0.3, Color(0.3, 0.7, 1.0), 0.0)
	_box(fist, Vector3(0.1, 0.1, 0.3), Vector3(0, -0.04, 0.16), sleeve)
	_box(fist, Vector3(0.12, 0.1, 0.12), Vector3(0, 0, 0), fist_mat)
	_box(fist, Vector3(0.125, 0.025, 0.1), Vector3(0, 0.04, -0.01), mat(Color(0.2, 0.2, 0.2), 0.8, 0.3))
	fist.visible = false


func _add_muzzle(w: Node3D, pos: Vector3) -> void:
	var m := Marker3D.new()
	w.add_child(m)
	m.position = pos
	muzzles.append(m)


func muzzle_world() -> Vector3:
	return muzzles[current].global_position


func switch_to(i: int) -> void:
	if i == target:
		return
	target = i
	switch_t = 0.32
	Sfx.play2d("reload", -10.0, 1.4)


func is_switching() -> bool:
	return switch_t > 0.0


func add_kick(k: float) -> void:
	kick = min(kick + k, 1.5)
	kick_rot = min(kick_rot + k, 1.5)


func add_sway(rel: Vector2) -> void:
	sway += rel * 0.0006
	sway = sway.limit_length(0.08)


func _process(delta: float) -> void:
	_t += delta
	if player == null:
		return
	# смена оружия: опускаем, меняем, поднимаем
	var dip := 0.0
	if switch_t > 0.0:
		switch_t -= delta
		var k := 1.0 - switch_t / 0.32
		if k >= 0.5 and current != target:
			weapons[current].visible = false
			current = target
			weapons[current].visible = true
		dip = sin(k * PI)

	kick = move_toward(kick, 0.0, delta * 6.0)
	kick_rot = lerp(kick_rot, 0.0, clamp(delta * 12.0, 0.0, 1.0))
	sway = sway.lerp(Vector2.ZERO, clamp(delta * 8.0, 0.0, 1.0))

	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	var on_floor: bool = player.is_on_floor()
	if on_floor:
		bob_phase += delta * hv * 1.25
	var bob: float = clamp(hv / 7.0, 0.0, 1.6) * (1.0 if on_floor else 0.2)
	var bx: float = sin(bob_phase) * 0.012 * bob
	var by: float = -abs(cos(bob_phase)) * 0.012 * bob
	var breathe := sin(_t * 1.6) * 0.003

	var pos := Vector3(0.2 + bx - sway.x * 0.3, -0.17 + by + breathe - dip * 0.3 + sway.y * 0.3, -0.5 + kick * 0.06)
	var rot := Vector3(kick_rot * 0.12 + sway.y * 1.5 - dip * 0.6, -sway.x * 1.5, -bx * 2.0 - sway.x * 0.8)
	if player.sprinting and on_floor and hv > 8.0:
		pos += Vector3(-0.04, -0.03, 0.02)
		rot += Vector3(-0.15, 0.35, 0.25)

	# суперудар: оружие уходит вниз, вылетает кулак
	if punch_state > 0.0:
		if punch_state <= 1.0:
			var c := punch_state
			pos.y -= 0.25 * c
			fist.visible = true
			fist.position = fist.position.lerp(Vector3(0.16, -0.17 - 0.02 * c, -0.36 + 0.08 * c) + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.006 * c, clamp(delta * 14.0, 0.0, 1.0))
			fist.rotation = Vector3(0.1, 0.25, -0.3)
			fist_mat.set_shader_parameter("emission_energy", c * 6.0)
		else:
			pos.y -= 0.4
			fist.visible = true
			fist.position = fist.position.lerp(Vector3(0.03, -0.1, -0.6), clamp(delta * 30.0, 0.0, 1.0))
			fist.rotation = Vector3(0.0, 0.0, -0.1)
			fist_mat.set_shader_parameter("emission_energy", 8.0)
	else:
		fist.position = fist.position.lerp(Vector3(0.25, -0.6, -0.35), clamp(delta * 10.0, 0.0, 1.0))
		if fist.position.y < -0.55:
			fist.visible = false

	root.position = root.position.lerp(pos, clamp(delta * 18.0, 0.0, 1.0))
	root.rotation = root.rotation.lerp(rot, clamp(delta * 14.0, 0.0, 1.0))

	# свечение оружия
	var heat: float = player.heat
	var hc = Color(0.2, 0.8, 1.0).lerp(Color(1.0, 0.3, 0.05), heat)
	for m in coil_mats:
		m.set_shader_parameter("emission", hc)
		m.set_shader_parameter("emission_energy", 2.0 + heat * 6.0 + (4.0 if player.overheated and fmod(_t, 0.2) < 0.1 else 0.0))
	laser_mat.set_shader_parameter("emission_energy", 3.0 + (10.0 if player.laser_on else 0.0) * (0.8 + 0.2 * sin(_t * 60.0)))
	rocket_tip.visible = player.rockets > 0 and player.fire_cd <= 0.0

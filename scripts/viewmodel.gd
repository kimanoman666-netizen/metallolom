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
var hands := {}
var grip_r: Array = []        # точка хвата правой руки для каждого оружия
var grip_l: Array = []        # [узел, "guard"/"grip"] для левой
var fist: Node3D
var fist_mat: ShaderMaterial
var coil_mats: Array = []
var laser_mat: ShaderMaterial
var rocket_tip: Node3D
var punch_state := 0.0           # 0 нет, 0..1 заряд, 2 удар
var _t := 0.0
var wcfg: Array = []             # настройки позы для каждого оружия
var levers: Array = []
var lever_t: Array = []
var drum: Node3D
var drum_angle := 0.0
var drum_target := 0.0
var barrels: Node3D
var reload_total := 0.0
var reload_left := 0.0

const GLB := {
	"rifle": {"scale": 0.8, "pos": Vector3(0.0, -0.01, 0.0), "lh": Vector3(0.08, 0.04, -0.3), "ads": Vector3(0.0, -0.052, -0.36)},
	"shotgun": {"scale": 0.8, "pos": Vector3(0.0, -0.01, 0.0), "lh": Vector3(0.08, 0.02, -0.26), "ads": Vector3(0.0, -0.062, -0.36)},
	"minigun": {"scale": 0.85, "pos": Vector3(0.0, 0.0, 0.0), "lh": Vector3(0.06, 0.05, -0.12), "ads": Vector3(0.1, -0.2, -0.5)},
	"launcher": {"scale": 0.85, "pos": Vector3(0.0, -0.01, 0.0), "lh": Vector3(0.08, -0.02, -0.22), "ads": Vector3(0.0, -0.13, -0.4)},
	"blaster": {"scale": 0.9, "pos": Vector3(0.0, -0.01, 0.0), "lh": Vector3.ZERO, "ads": Vector3(0.0, -0.085, -0.4)},
	"laser": {"scale": 0.9, "pos": Vector3(0.0, -0.01, 0.0), "lh": Vector3.ZERO, "ads": Vector3(0.0, -0.095, -0.4)},
	"rpg": {"scale": 0.85, "pos": Vector3(0.02, -0.02, 0.0), "lh": Vector3.ZERO, "ads": Vector3(0.045, -0.1, -0.38)},
}


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
	var sleeve := mat(Color(0.2, 0.21, 0.19), 0.05, 0.85)
	var glove := mat(Color(0.08, 0.08, 0.09), 0.2, 0.6)
	var armor := mat(Color(0.22, 0.23, 0.25), 0.7, 0.35)
	var orange := mat(Color(0.85, 0.45, 0.06), 0.5, 0.4)
	var gun_dark := mat(Color(0.1, 0.1, 0.11), 0.85, 0.35)
	var gun_mid := mat(Color(0.5, 0.52, 0.55), 0.9, 0.28)

	# руки — модели из Blender (tools/blender/hands.py)
	var hands_scene: PackedScene = load("res://models/hands.glb")
	var hs := hands_scene.instantiate()
	for nm in ["hand_r_grip", "hand_l_guard", "hand_l_grip"]:
		var h: Node3D = hs.get_node(nm)
		_clear_owner(h)
		hs.remove_child(h)
		Mats.apply(h, true)
		root.add_child(h)
		hands[nm] = h
	hs.free()
	right_hand = hands.hand_r_grip
	left_hand = hands.hand_l_guard

	# ---------- все стволы — модели из Blender (tools/blender/weapons.py)
	var order := ["rifle", "shotgun", "minigun", "blaster", "laser", "launcher", "rpg"]
	var glb_nodes := {}
	for id in order:
		var wrap := Node3D.new()
		root.add_child(wrap)
		var inst: Node3D = load("res://models/weapons/%s.glb" % id).instantiate()
		wrap.add_child(inst)
		Mats.apply(inst, true)
		var c: Dictionary = GLB[id]
		wrap.scale = Vector3.ONE * c.scale
		wrap.position = c.pos
		glb_nodes[id] = wrap
	weapons = []
	muzzles = []
	for i in order.size():
		var w: Node3D = glb_nodes[order[i]]
		weapons.append(w)
		muzzles.append(w.find_child("muzzle", true, false))
		levers.append(w.find_child("lever", true, false))
		lever_t.append(1.0)
		wcfg.append(GLB[order[i]])
		w.visible = i == 0
		var gr: Node3D = w.find_child("grip_r", true, false)
		var gl: Node3D = w.find_child("guard_l", true, false)
		var kind := "guard"
		if gl == null:
			gl = w.find_child("grip_l", true, false)
			kind = "grip"
		grip_r.append(gr)
		grip_l.append([gl, kind])
	coil_mats = [Mats.vm("glow_coil")]
	laser_mat = Mats.vm("glow_laser")
	rocket_tip = glb_nodes.rpg.find_child("rocket", true, false)
	root.position = Vector3(0.2, -0.17, -0.5)
	root.scale = Vector3.ONE * 0.72
	_attach_hands(0)

	# кулак для суперудара
	fist = Node3D.new()
	add_child(fist)
	fist_mat = mat(Color(0.75, 0.42, 0.08), 0.7, 0.3, Color(0.3, 0.7, 1.0), 0.0)
	var fh: Node3D = hands.hand_r_grip.duplicate()
	fist.add_child(fh)
	fh.transform = Transform3D(Basis(Vector3.RIGHT, -0.77), Vector3.ZERO)
	var knuck := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.022, 0.09, 0.03)
	knuck.mesh = km
	knuck.material_override = fist_mat
	knuck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	knuck.extra_cull_margin = 16384.0
	fh.add_child(knuck)
	knuck.position = Vector3(0.062, 0.0, 0.006)
	fist.visible = false
	drum = glb_nodes.launcher.find_child("drum", true, false)
	barrels = glb_nodes.minigun.find_child("barrels", true, false)
	root.position = Vector3(0.2, -0.17, -0.5)
	root.scale = Vector3.ONE * 0.72



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


func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)


func _attach_hands(i: int) -> void:
	var gr: Node3D = grip_r[i]
	var gl_info: Array = grip_l[i]
	var gl: Node3D = gl_info[0]
	var kind: String = gl_info[1]
	var lh: Node3D = hands.hand_l_guard if kind == "guard" else hands.hand_l_grip
	var other: Node3D = hands.hand_l_grip if kind == "guard" else hands.hand_l_guard
	other.visible = false
	other.reparent(root, false)
	for pair in [[hands.hand_r_grip, gr], [lh, gl]]:
		var h: Node3D = pair[0]
		var target: Node3D = pair[1]
		h.visible = target != null
		if target == null:
			continue
		h.reparent(target, false)
		# компенсация масштаба обёртки оружия — руки всегда одного размера
		var sc = target.global_transform.basis.get_scale().x / max(root.global_transform.basis.get_scale().x, 0.001)
		h.transform = Transform3D(Basis().scaled(Vector3.ONE / max(sc, 0.001)), Vector3.ZERO)
	left_hand = lh


func on_shot() -> void:
	lever_t[current] = 0.0
	if current == 5:
		drum_target += PI * 0.5


func start_reload(t: float) -> void:
	reload_total = t
	reload_left = t


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
			_attach_hands(current)
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
			fist.rotation = Vector3(0.15, 0.2, -0.25)
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
	right_hand.visible = punch_state <= 0.0 and grip_r.size() > current and grip_r[current] != null

	# прицеливание: оружие к центру, прицел на линию взгляда
	var aim: float = player.aim_t
	if aim > 0.0:
		var ads: Vector3 = wcfg[current].ads + Vector3(0, 0, kick * 0.04)
		pos = pos.lerp(ads, aim)
		rot = rot.lerp(Vector3(kick_rot * 0.05, 0, 0), aim)
	# перезарядка: наклон и опускание
	if reload_left > 0.0:
		reload_left -= delta
		var k: float = 1.0 - max(reload_left, 0.0) / max(reload_total, 0.01)
		var d := sin(k * PI)
		pos.y -= 0.1 * d
		pos.x -= 0.04 * d
		rot += Vector3(0.35 * d, 0.2 * d, 0.55 * d)
		if current == 5:
			drum_target += delta * 8.0
	# рычаг после выстрела
	for i in levers.size():
		if levers[i] and lever_t[i] < 1.0:
			lever_t[i] = min(lever_t[i] + delta * 2.4, 1.0)
			levers[i].rotation.x = sin(lever_t[i] * PI) * 0.9
	if drum:
		drum_angle = lerp(drum_angle, drum_target, clamp(delta * 14.0, 0.0, 1.0))
		drum.rotation.z = drum_angle
	if barrels:
		barrels.rotate_object_local(Vector3.BACK, player.spin * delta * 45.0)

	root.position = root.position.lerp(pos, clamp(delta * 18.0, 0.0, 1.0))
	root.rotation = root.rotation.lerp(rot, clamp(delta * 14.0, 0.0, 1.0))

	# свечение оружия
	var heat: float = player.heat
	var hc = Color(0.2, 0.8, 1.0).lerp(Color(1.0, 0.3, 0.05), heat)
	for m in coil_mats:
		m.set_shader_parameter("emission", hc)
		m.set_shader_parameter("emission_energy", 2.0 + heat * 6.0 + (4.0 if player.overheated and fmod(_t, 0.2) < 0.1 else 0.0))
	laser_mat.set_shader_parameter("emission_energy", 3.0 + (10.0 if player.laser_on else 0.0) * (0.8 + 0.2 * sin(_t * 60.0)))
	rocket_tip.visible = player.ammo[6] > 0 and player.fire_cd <= 0.0

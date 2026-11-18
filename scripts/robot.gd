class_name Robot
extends CharacterBody3D
## Робот, собранный из отдельных частей. Каждую часть можно отстрелить:
## она становится физическим обломком, а робот теряет соответствующую способность.

enum Kind { SCOUT, SOLDIER, BRUTE }

const KINDS := {
	Kind.SCOUT: {
		"name": "Скаут", "s": 0.82, "bulk": 0.85, "hp": 0.55, "speed": 7.0, "range": 13.0,
		"fire_cd": 0.16, "burst": 4, "burst_cd": 1.5, "dmg": 4.0, "melee_dmg": 10.0,
		"main": Color(0.78, 0.8, 0.82), "accent": Color(0.05, 0.7, 0.75), "dark": Color(0.12, 0.13, 0.15),
		"eye": Color(0.2, 1.0, 1.0), "score": 100, "gun": true,
	},
	Kind.SOLDIER: {
		"name": "Солдат", "s": 1.0, "bulk": 1.0, "hp": 1.0, "speed": 4.4, "range": 19.0,
		"fire_cd": 0.11, "burst": 6, "burst_cd": 2.1, "dmg": 5.0, "melee_dmg": 14.0,
		"main": Color(0.33, 0.34, 0.36), "accent": Color(0.95, 0.58, 0.06), "dark": Color(0.1, 0.1, 0.11),
		"eye": Color(1.0, 0.18, 0.05), "score": 200, "gun": true,
	},
	Kind.BRUTE: {
		"name": "Громила", "s": 1.45, "bulk": 1.35, "hp": 2.7, "speed": 3.5, "range": 2.9,
		"fire_cd": 0.0, "burst": 0, "burst_cd": 0.0, "dmg": 0.0, "melee_dmg": 30.0,
		"main": Color(0.42, 0.11, 0.08), "accent": Color(0.85, 0.75, 0.1), "dark": Color(0.08, 0.08, 0.08),
		"eye": Color(1.0, 0.5, 0.0), "score": 450, "gun": false,
	},
}

const PART_NAMES := {
	"head": "ГОЛОВА СНЕСЕНА", "arm_l": "РУКА ОТОРВАНА", "arm_r": "РУКА ОТОРВАНА",
	"fore_l": "КИСТЬ ОТСТРЕЛЕНА", "fore_r": "ОРУЖИЕ ОТСТРЕЛЕНО", "thigh_l": "НОГА ОТОРВАНА",
	"thigh_r": "НОГА ОТОРВАНА", "shin_l": "ГОЛЕНЬ ОТБИТА", "shin_r": "ГОЛЕНЬ ОТБИТА",
}

var kind: int = Kind.SOLDIER
var cfg: Dictionary
var s := 1.0
var bulk := 1.0

var rig: Node3D
var parts := {}            # имя -> словарь части
var shape: CollisionShape3D
var capsule: CapsuleShape3D
var muzzle: Marker3D
var eye_mat: StandardMaterial3D
var core_light: OmniLight3D
var thruster: Node3D

var state := "drop"        # drop, active, dead
var dead := false
var crippled := false
var blind := false
var has_gun := true
var self_destruct := -1.0

var knock := Vector3.ZERO
var walk_phase := 0.0
var strafe_dir := 1.0
var strafe_timer := 0.0
var fire_timer := 1.5
var burst_left := 0
var attack_cd := 1.0
var windup := -1.0
var recoil := 0.0
var land_timer := 0.0
var fx_cooldown := 0.0
var sound_cooldown := 0.0
var step_timer := 0.0
var think_offset := 0.0
var _lean := 0.0


static func create(k: int) -> Robot:
	var r := Robot.new()
	r.kind = k
	return r


func _ready() -> void:
	cfg = KINDS[kind]
	s = cfg.s
	bulk = cfg.bulk
	has_gun = cfg.gun
	collision_layer = G.L_ROBOT
	collision_mask = G.L_WORLD | G.L_PLAYER | G.L_ROBOT | G.L_PROPS
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	safe_margin = 0.02
	strafe_dir = 1.0 if randf() < 0.5 else -1.0
	fire_timer = randf_range(1.0, 2.5)
	think_offset = randf() * 10.0
	_build()
	velocity = Vector3(0, -22, 0)


# =================================================================== сборка

func _mats() -> Dictionary:
	var d := {}
	for key in ["main", "accent", "dark"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = cfg[key]
		m.metallic = 0.75 if key != "dark" else 0.6
		m.roughness = 0.38 if key == "main" else 0.5
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 0.0
		d[key] = m
	return d


func _v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * s * bulk, y * s, z * s * bulk)


func _add_part(pname: String, parent: Node3D, pivot: Vector3, hp: float, children_of: String = "") -> Dictionary:
	var node := Node3D.new()
	node.name = pname
	parent.add_child(node)
	node.position = pivot
	var p := {
		"name": pname, "node": node, "hp": hp * cfg.hp, "max": hp * cfg.hp, "alive": true,
		"areas": [], "mats": _mats(), "parent": children_of, "kids": [], "redirect": "",
	}
	parts[pname] = p
	if children_of != "":
		parts[children_of].kids.append(pname)
	return p


func _mesh(p: Dictionary, kind_mesh: String, size: Vector3, pos: Vector3, mat_key: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	match kind_mesh:
		"box":
			var b := BoxMesh.new()
			b.size = size
			mi.mesh = b
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = size.x
			c.bottom_radius = size.x
			c.height = size.y
			c.radial_segments = 12
			mi.mesh = c
		"sph":
			var sp := SphereMesh.new()
			sp.radius = size.x
			sp.height = size.x * 2.0
			sp.radial_segments = 16
			sp.rings = 8
			mi.mesh = sp
	if mat_key == "eye":
		mi.material_override = eye_mat
	else:
		mi.material_override = p.mats[mat_key]
	p.node.add_child(mi)
	mi.position = pos
	return mi


func _hitbox(p: Dictionary, size: Vector3, pos: Vector3, mult: float = 1.0, target: String = "") -> void:
	var a := Hitbox.new()
	a.robot = self
	a.part = target if target != "" else p.name
	a.mult = mult
	a.collision_layer = G.L_HITBOX
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	p.node.add_child(a)
	a.position = pos
	p.areas.append(a)


func _build() -> void:
	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = cfg.eye
	eye_mat.emission_enabled = true
	eye_mat.emission = cfg.eye
	eye_mat.emission_energy_multiplier = 6.0

	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)

	var big := kind == Kind.BRUTE

	# --- таз
	var hips := _add_part("hips", rig, Vector3(0, 1.0 * s, 0), 1.0)
	hips.redirect = "torso"
	_mesh(hips, "box", _v(0.5, 0.22, 0.32), Vector3.ZERO, "dark")
	_hitbox(hips, _v(0.52, 0.26, 0.36), Vector3.ZERO, 1.0, "torso")

	# --- торс
	var torso := _add_part("torso", hips.node, Vector3(0, 0.1 * s, 0), 220.0, "hips")
	_mesh(torso, "box", _v(0.72, 0.62, 0.44), _v(0, 0.42, 0), "main")
	_mesh(torso, "box", _v(0.5, 0.24, 0.36), _v(0, 0.08, 0), "dark")
	_mesh(torso, "box", _v(0.75, 0.08, 0.47), _v(0, 0.64, 0), "accent")
	_mesh(torso, "box", _v(0.5, 0.46, 0.22), _v(0, 0.45, 0.3), "dark")
	_mesh(torso, "box", _v(0.12, 0.3, 0.06), _v(-0.2, 0.32, 0.43), "accent")
	_mesh(torso, "box", _v(0.12, 0.3, 0.06), _v(0.2, 0.32, 0.43), "accent")
	_mesh(torso, "sph", Vector3(0.11 * s, 0, 0), _v(0, 0.42, -0.21), "eye")
	_hitbox(torso, _v(0.76, 0.82, 0.5), _v(0, 0.35, 0.02))
	_hitbox(torso, _v(0.24, 0.24, 0.12), _v(0, 0.42, -0.25), 2.5)
	core_light = OmniLight3D.new()
	core_light.light_color = cfg.eye
	core_light.light_energy = 0.35
	core_light.omni_range = 1.6 * s
	core_light.shadow_enabled = false
	torso.node.add_child(core_light)
	core_light.position = _v(0, 0.42, -0.7)

	# --- голова
	var head := _add_part("head", torso.node, _v(0, 0.75, 0), 60.0, "torso")
	_mesh(head, "cyl", Vector3(0.07 * s * bulk, 0.14 * s, 0), Vector3.ZERO, "dark")
	if big:
		_mesh(head, "box", _v(0.42, 0.26, 0.4), _v(0, 0.12, -0.04), "main")
		_mesh(head, "box", _v(0.34, 0.06, 0.04), _v(0, 0.14, -0.25), "eye")
	else:
		_mesh(head, "box", _v(0.38, 0.3, 0.38), _v(0, 0.15, 0), "main")
		_mesh(head, "box", _v(0.3, 0.08, 0.04), _v(0, 0.17, -0.19), "eye")
		_mesh(head, "cyl", Vector3(0.015 * s, 0.3 * s, 0), _v(0.12, 0.42, 0.05), "dark")
		_mesh(head, "box", _v(0.4, 0.05, 0.3), _v(0, 0.31, 0.02), "accent")
	_hitbox(head, _v(0.42, 0.36, 0.44), _v(0, 0.15, -0.02), 1.6)

	# --- руки
	for side in [-1.0, 1.0]:
		var sfx := "_l" if side < 0 else "_r"
		var arm := _add_part("arm" + sfx, torso.node, _v(0.48 * side, 0.6, 0), 70.0, "torso")
		_mesh(arm, "box", _v(0.28, 0.22, 0.32), _v(0, 0.03, 0), "accent")
		_mesh(arm, "box", _v(0.17, 0.42, 0.17), _v(0, -0.22, 0), "main")
		_hitbox(arm, _v(0.26, 0.52, 0.26), _v(0, -0.18, 0))
		var fore := _add_part("fore" + sfx, arm.node, _v(0, -0.44, 0), 55.0, "arm" + sfx)
		_mesh(fore, "box", _v(0.16, 0.38, 0.16), _v(0, -0.19, 0), "dark")
		if big:
			_mesh(fore, "box", _v(0.3, 0.28, 0.3), _v(0, -0.46, 0), "main")
			_mesh(fore, "box", _v(0.32, 0.06, 0.32), _v(0, -0.36, 0), "accent")
			_hitbox(fore, _v(0.32, 0.62, 0.32), _v(0, -0.3, 0))
		elif side > 0 and has_gun:
			_mesh(fore, "box", _v(0.14, 0.34, 0.2), _v(0, -0.34, -0.09), "dark")
			_mesh(fore, "cyl", Vector3(0.04 * s, 0.3 * s, 0), _v(0, -0.56, -0.09), "dark")
			_mesh(fore, "cyl", Vector3(0.05 * s, 0.04 * s, 0), _v(0, -0.68, -0.09), "eye")
			_mesh(fore, "box", _v(0.04, 0.2, 0.06), _v(0, -0.3, -0.21), "accent")
			muzzle = Marker3D.new()
			fore.node.add_child(muzzle)
			muzzle.position = _v(0, -0.76, -0.09)
			_hitbox(fore, _v(0.22, 0.75, 0.3), _v(0, -0.36, -0.05))
		else:
			_mesh(fore, "box", _v(0.14, 0.12, 0.12), _v(0, -0.42, 0), "main")
			_hitbox(fore, _v(0.2, 0.52, 0.2), _v(0, -0.24, 0))

	# --- ноги
	for side in [-1.0, 1.0]:
		var sfx := "_l" if side < 0 else "_r"
		var thigh := _add_part("thigh" + sfx, hips.node, _v(0.17 * side, -0.06, 0), 80.0, "hips")
		_mesh(thigh, "box", _v(0.2, 0.46, 0.24), _v(0, -0.23, 0), "main")
		_mesh(thigh, "box", _v(0.17, 0.13, 0.2), _v(0, -0.47, -0.05), "accent")
		_hitbox(thigh, _v(0.27, 0.54, 0.3), _v(0, -0.24, 0))
		var shin := _add_part("shin" + sfx, thigh.node, _v(0, -0.48, 0), 65.0, "thigh" + sfx)
		_mesh(shin, "box", _v(0.17, 0.42, 0.2), _v(0, -0.21, 0), "dark")
		_mesh(shin, "box", _v(0.23, 0.08, 0.38), _v(0, -0.44, -0.06), "main")
		_mesh(shin, "box", _v(0.06, 0.25, 0.04), _v(0, -0.2, -0.12), "accent")
		_hitbox(shin, _v(0.25, 0.5, 0.4), _v(0, -0.24, -0.03))

	# --- коллайдер тела
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.38 * s * bulk
	capsule.height = 2.15 * s
	shape = CollisionShape3D.new()
	shape.shape = capsule
	add_child(shape)
	shape.position = Vector3(0, 1.075 * s, 0)

	# --- реактивный ранец для высадки
	thruster = Node3D.new()
	torso.node.add_child(thruster)
	thruster.position = _v(0, 0.2, 0.42)
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.12 * s
	fm.bottom_radius = 0.02
	fm.height = 1.4 * s
	flame.mesh = fm
	flame.material_override = Fx.glow_mat(Color(0.4, 0.7, 1.0), 6.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	thruster.add_child(flame)
	flame.position = Vector3(0, -0.8 * s, 0)
	var tl := OmniLight3D.new()
	tl.light_color = Color(0.4, 0.7, 1.0)
	tl.light_energy = 4.0
	tl.omni_range = 6.0
	thruster.add_child(tl)
	tl.position = Vector3(0, -1.0, 0)

	_pose_idle()


func _pose_idle() -> void:
	if has_gun and parts.arm_r.alive:
		parts.arm_r.node.rotation.x = PI * 0.5


# =================================================================== ИИ

func _physics_process(delta: float) -> void:
	if dead:
		return
	if global_position.y < -25.0:
		die(Vector3.UP, 0.0, true)
		return
	fx_cooldown -= delta
	sound_cooldown -= delta
	if state == "drop":
		velocity.y = max(velocity.y - 30.0 * delta, -28.0)
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		if is_on_floor():
			_land()
		return
	if land_timer > 0.0:
		land_timer -= delta
		velocity.x = move_toward(velocity.x, 0, 20 * delta)
		velocity.z = move_toward(velocity.z, 0, 20 * delta)
		velocity.y -= 22.0 * delta
		move_and_slide()
		return

	var p = G.player
	if p == null or not is_instance_valid(p) or p.dead:
		velocity.x = move_toward(velocity.x, 0, 10 * delta)
		velocity.z = move_toward(velocity.z, 0, 10 * delta)
		velocity.y -= 22.0 * delta
		move_and_slide()
		return

	if self_destruct > 0.0:
		self_destruct -= delta
		eye_mat.emission_energy_multiplier = 12.0 if fmod(self_destruct, 0.2) < 0.1 else 0.5
		if self_destruct <= 0.0:
			die(Vector3.UP, 300.0)
			return

	var to: Vector3 = p.global_position - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var dir: Vector3 = flat / max(dist, 0.001)
	var speed: float = cfg.speed
	if crippled:
		speed *= 0.32
	var melee: bool = not has_gun
	if melee and kind != Kind.BRUTE:
		speed *= 1.25   # без оружия — бешеный рывок

	var desired := Vector3.ZERO
	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(1.2, 3.2)
		strafe_dir = -strafe_dir if randf() < 0.6 else strafe_dir

	if melee:
		var rng: float = cfg.range if kind == Kind.BRUTE else 2.2
		if windup < 0.0:
			if dist > rng * 0.8:
				desired = dir
			if dist < rng and attack_cd <= 0.0:
				windup = 0.6 if kind == Kind.BRUTE else 0.35
				Sfx.play3d("servo", global_position, 0.0, 0.7 if kind == Kind.BRUTE else 1.2)
		else:
			windup -= delta
			if windup <= 0.0:
				windup = -1.0
				_melee_hit(p, dist, dir)
	else:
		var rng: float = cfg.range
		var side := Vector3(-dir.z, 0, dir.x) * strafe_dir
		if dist > rng:
			desired = (dir + side * 0.3).normalized()
		elif dist < rng * 0.45:
			desired = (-dir + side * 0.5).normalized()
		else:
			desired = side
		_gun_logic(delta, p, dist)

	attack_cd -= delta

	# обход препятствий
	if desired.length() > 0.1:
		var eye := global_position + Vector3(0, 0.7 * s, 0)
		var hit := G.ray(eye, eye + desired * 1.6 * s, G.L_WORLD | G.L_PROPS, [get_rid()], false)
		if not hit.is_empty():
			desired = desired.rotated(Vector3.UP, 1.1 * strafe_dir)
			if is_on_wall():
				strafe_dir = -strafe_dir

	var target_v := desired * speed
	var accel := 9.0 if is_on_floor() else 2.0
	velocity.x = lerp(velocity.x, target_v.x, clamp(accel * delta, 0.0, 1.0))
	velocity.z = lerp(velocity.z, target_v.z, clamp(accel * delta, 0.0, 1.0))
	velocity.y -= 22.0 * delta
	velocity += knock
	knock = Vector3.ZERO
	move_and_slide()

	# поворот к игроку
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clamp(6.0 * delta, 0.0, 1.0))

	# шаги
	var hs := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hs > 0.6:
		step_timer -= delta * hs * (0.5 if kind == Kind.BRUTE else 0.8)
		if step_timer <= 0.0:
			step_timer = 1.0
			Sfx.play3d("step", global_position, -6.0 + 6.0 * (s - 1.0), randf_range(0.7, 0.9) / s)


func _gun_logic(delta: float, p: Node, dist: float) -> void:
	fire_timer -= delta
	if fire_timer > 0.0 or muzzle == null:
		return
	if dist > cfg.range * 1.6:
		fire_timer = 0.5
		return
	var mpos := muzzle.global_position
	var target: Vector3 = p.global_position + Vector3(0, 1.2, 0)
	var los := G.ray(mpos, target, G.L_WORLD | G.L_PROPS, [], false)
	if not los.is_empty():
		fire_timer = 0.4
		burst_left = 0
		return
	if burst_left <= 0:
		burst_left = cfg.burst
	burst_left -= 1
	fire_timer = cfg.fire_cd if burst_left > 0 else cfg.burst_cd * randf_range(0.8, 1.3)
	var lead: Vector3 = p.velocity * (mpos.distance_to(target) / 38.0) * 0.5
	var aim := (target + lead - mpos).normalized()
	var spread := 0.03
	if blind:
		spread = 0.16
	if crippled:
		spread *= 1.6
	aim = (aim + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	Projectile.robot_bolt(mpos, aim, cfg.dmg)
	recoil = 1.0
	Sfx.play3d("robot_shot", mpos, -3.0, randf_range(0.9, 1.1) / sqrt(s))
	Fx.flash(mpos, cfg.eye, 2.0, 3.0, 0.08)


func _melee_hit(p: Node, dist: float, dir: Vector3) -> void:
	attack_cd = 1.7 if kind == Kind.BRUTE else 1.1
	var reach: float = (cfg.range if kind == Kind.BRUTE else 2.2) + 0.6
	var hit_pos := global_position + dir * 1.4 * s
	Fx.dust(hit_pos, 0.8 * s)
	Sfx.play3d("impact" if kind == Kind.BRUTE else "clang", hit_pos, 0.0, 0.8)
	if dist <= reach and not crippled or dist <= reach * 0.6:
		p.take_damage(cfg.melee_dmg, global_position)
		p.knockback(dir * (16.0 if kind == Kind.BRUTE else 7.0) + Vector3.UP * (6.0 if kind == Kind.BRUTE else 2.0))
	if kind == Kind.BRUTE:
		# ударная волна по обломкам
		var q := PhysicsShapeQueryParameters3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 3.0
		q.shape = sp
		q.transform = Transform3D(Basis(), hit_pos)
		q.collision_mask = G.L_DEBRIS | G.L_PROPS
		for r in get_world_3d().direct_space_state.intersect_shape(q, 64):
			var c = r.collider
			if c is RigidBody3D and not c.freeze:
				c.apply_central_impulse((c.global_position - hit_pos).normalized() * c.mass * 4.0 + Vector3.UP * c.mass * 3.0)


func _land() -> void:
	state = "active"
	land_timer = 0.45
	thruster.queue_free()
	thruster = null
	Fx.dust(global_position, 1.2 * s)
	Sfx.play3d("step", global_position, 6.0, 0.5)
	if G.player and is_instance_valid(G.player):
		var d: float = G.player.global_position.distance_to(global_position)
		G.player.add_shake(clamp(0.5 - d / 40.0, 0.0, 0.5) * s)


func knockback(v: Vector3) -> void:
	if dead:
		return
	var resist := 1.0 / (s * bulk * (2.2 if kind == Kind.BRUTE else 1.0))
	knock += v * resist


# =================================================================== анимация

func _process(delta: float) -> void:
	if dead or rig == null:
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	var moving: float = clamp(hs / max(cfg.speed, 0.1), 0.0, 1.2)
	walk_phase += delta * hs * (2.2 / s)
	recoil = move_toward(recoil, 0.0, delta * 8.0)

	var hips: Dictionary = parts.hips
	if crippled:
		hips.node.position.y = lerp(hips.node.position.y, 0.35 * s, delta * 6.0)
		hips.node.rotation.x = lerp(hips.node.rotation.x, -0.55, delta * 5.0)
		hips.node.rotation.z = sin(walk_phase * 1.5) * 0.12
		for side in ["_l", "_r"]:
			if parts["thigh" + side].alive:
				parts["thigh" + side].node.rotation.x = lerp(parts["thigh" + side].node.rotation.x, 1.4, delta * 5.0)
			if parts["shin" + side].alive:
				parts["shin" + side].node.rotation.x = lerp(parts["shin" + side].node.rotation.x, -1.9, delta * 5.0)
	else:
		hips.node.position.y = 1.0 * s + abs(sin(walk_phase)) * 0.05 * s * moving
		hips.node.rotation.z = sin(walk_phase) * 0.04 * moving
		var sw := 0.55 * moving
		for i in 2:
			var side := "_l" if i == 0 else "_r"
			var ph := walk_phase + (0.0 if i == 0 else PI)
			if parts["thigh" + side].alive:
				parts["thigh" + side].node.rotation.x = sin(ph) * sw
			if parts["shin" + side].alive:
				parts["shin" + side].node.rotation.x = -max(0.0, sin(ph + PI * 0.5)) * 0.9 * moving

	# корпус дышит / качается
	if parts.torso.alive:
		_lean = lerp(_lean, -0.12 * moving, delta * 4.0)
		parts.torso.node.rotation.x = _lean + (sin(Time.get_ticks_msec() * 0.003 + think_offset) * 0.02)

	# цель
	var aim_pitch := 0.0
	var p = G.player
	if p and is_instance_valid(p) and parts.arm_r.alive:
		var sh: Vector3 = parts.arm_r.node.global_position
		var tgt: Vector3 = p.global_position + Vector3(0, 1.2, 0)
		var hd := Vector2(tgt.x - sh.x, tgt.z - sh.z).length()
		aim_pitch = atan2(tgt.y - sh.y, hd)

	# руки
	var swing := sin(walk_phase) * 0.45 * moving
	if parts.arm_l.alive:
		if windup > 0.0:
			parts.arm_l.node.rotation.x = lerp(parts.arm_l.node.rotation.x, PI * 0.95, delta * 10.0)
		elif kind == Kind.BRUTE and attack_cd > 1.2:
			parts.arm_l.node.rotation.x = lerp(parts.arm_l.node.rotation.x, PI * 0.35, delta * 14.0)
		else:
			parts.arm_l.node.rotation.x = lerp(parts.arm_l.node.rotation.x, swing + 0.1, delta * 8.0)
		parts.arm_l.node.rotation.z = -0.1
	if parts.arm_r.alive:
		if has_gun:
			var r := PI * 0.5 + aim_pitch + recoil * 0.25
			parts.arm_r.node.rotation.x = lerp(parts.arm_r.node.rotation.x, r, delta * 12.0)
		elif windup > 0.0:
			parts.arm_r.node.rotation.x = lerp(parts.arm_r.node.rotation.x, PI * 0.95, delta * 10.0)
		elif attack_cd > (1.2 if kind == Kind.BRUTE else 0.7):
			parts.arm_r.node.rotation.x = lerp(parts.arm_r.node.rotation.x, PI * 0.35, delta * 14.0)
		else:
			parts.arm_r.node.rotation.x = lerp(parts.arm_r.node.rotation.x, -swing + 0.1, delta * 8.0)
		parts.arm_r.node.rotation.z = 0.1
	if parts.fore_l.alive:
		parts.fore_l.node.rotation.x = 0.35 + (0.6 if windup > 0.0 else 0.0)
	if parts.fore_r.alive:
		parts.fore_r.node.rotation.x = 0.0 if has_gun else 0.35 + (0.6 if windup > 0.0 else 0.0)

	if parts.head.alive:
		parts.head.node.rotation.x = lerp(parts.head.node.rotation.x, aim_pitch * 0.5, delta * 6.0)

	# мигание повреждённых частей
	for pn in parts:
		var pp: Dictionary = parts[pn]
		var m: StandardMaterial3D = pp.mats.main
		if m.emission_energy_multiplier > 0.0:
			var e = move_toward(m.emission_energy_multiplier, 0.0, delta * 30.0)
			for k in pp.mats:
				pp.mats[k].emission_energy_multiplier = e


# =================================================================== урон

func damage_part(pname: String, dmg: float, pos: Vector3, dir: Vector3, force: float, crit: bool = false) -> void:
	if dead or state == "drop" and dmg < 1.0:
		return
	if not parts.has(pname):
		return
	var p: Dictionary = parts[pname]
	if not p.alive:
		return
	if p.redirect != "":
		pname = p.redirect
		p = parts[pname]
		if not p.alive:
			return
	var absorbed: float = min(dmg, max(p.hp, 0.0))
	p.hp -= dmg
	if pname != "torso":
		parts.torso.hp -= absorbed * 0.18
	# вспышка попадания
	for k in p.mats:
		p.mats[k].emission_energy_multiplier = 1.4 if crit else 0.8
	_tint(p)
	if fx_cooldown <= 0.0:
		fx_cooldown = 0.07
		Fx.sparks(pos, -dir + Vector3.UP * 0.3, 8 if dmg < 30 else 20, 6.0)
	if sound_cooldown <= 0.0:
		sound_cooldown = 0.09
		Sfx.play3d("clang" if dmg >= 25 or crit else "hit", pos, -4.0 if dmg < 25 else 0.0, randf_range(0.8, 1.25))
	if G.hud:
		G.hud.hitmarker(crit)
	knock += dir * min(force * 0.002, 2.0) / (s * bulk)

	if pname == "torso":
		if p.hp <= 0.0:
			die(dir, force)
		return
	if p.hp <= 0.0:
		_detach(pname, dir, force, true)
	if not dead and parts.torso.hp <= 0.0:
		die(dir, force)


func _tint(p: Dictionary) -> void:
	var r: float = clamp(p.hp / max(p.max, 1.0), 0.0, 1.0)
	var burnt := Color(0.07, 0.06, 0.05)
	for k in ["main", "accent"]:
		var base: Color = cfg[k]
		p.mats[k].albedo_color = base.lerp(burnt, (1.0 - r) * 0.65)
		p.mats[k].roughness = lerp(0.38, 0.85, 1.0 - r)


func _subtree(pname: String) -> Array:
	var out := [pname]
	for k in parts[pname].kids:
		out.append_array(_subtree(k))
	return out


func _detach(pname: String, dir: Vector3, force: float, scored: bool) -> RigidBody3D:
	var p: Dictionary = parts[pname]
	var names := _subtree(pname)
	for n in names:
		if not parts[n].alive and n != pname:
			continue
		parts[n].alive = false
		for a in parts[n].areas:
			if is_instance_valid(a):
				a.queue_free()
		parts[n].areas.clear()
	p.alive = false

	var pivot: Node3D = p.node
	var parent := pivot.get_parent() as Node3D
	var joint_world := pivot.global_position
	var rb := _make_debris(pivot)
	if rb == null:
		return null
	# пыхаем обрубок
	if not dead and parent and is_instance_valid(parent):
		Fx.spark_emitter(parent, pivot.position if pivot.get_parent() == parent else parent.to_local(joint_world), -1.0 if pname == "head" else 6.0)
	Fx.spark_emitter(rb, Vector3.ZERO, 4.0)
	if randf() < 0.5:
		Fx.smoke_emitter(rb, Vector3.ZERO, 6.0)
	var m := rb.mass
	var push := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	rb.apply_central_impulse(push * (m * 4.0 + force * 0.015) + Vector3.UP * m * 3.5)
	rb.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	Fx.sparks(joint_world, push, 26, 9.0)

	if scored:
		G.parts_ripped += 1
		G.add_score(25 * (2 if kind == Kind.BRUTE else 1), PART_NAMES.get(pname, "ОТОРВАНО"))
		Sfx.play3d("clang", joint_world, 3.0, randf_range(0.6, 0.8))
		_update_caps()
	return rb


func _make_debris(pivot: Node3D) -> RigidBody3D:
	var rb := WallChunk.new()       # тот же скрипт: обломок, который можно пинать и стрелять
	rb.broken = true
	rb.collision_layer = G.L_DEBRIS
	rb.collision_mask = G.L_WORLD | G.L_DEBRIS | G.L_PROPS | G.L_PLAYER | G.L_ROBOT
	G.world.add_child(rb)
	rb.global_transform = pivot.global_transform.orthonormalized()
	var meshes: Array = []
	_collect_meshes(pivot, meshes)
	pivot.reparent(rb, true)
	var vol := 0.0
	var inv := rb.global_transform.affine_inverse()
	for mi in meshes:
		if not is_instance_valid(mi):
			continue
		var aabb: AABB = mi.get_aabb()
		var size := aabb.size
		if size.x < 0.03 or size.y < 0.03 or size.z < 0.03:
			continue
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		rb.add_child(cs)
		cs.transform = (inv * mi.global_transform) * Transform3D(Basis(), aabb.get_center())
		vol += size.x * size.y * size.z
	if rb.get_child_count() == 0:
		rb.queue_free()
		return null
	rb.mass = clamp(vol * 700.0, 3.0, 160.0)
	rb.physics_material_override = WallChunk.debris_phys()
	rb.linear_velocity = velocity * 0.6
	G.add_debris(rb)
	return rb


func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		if c is Node3D and not (c is Hitbox):
			_collect_meshes(c, out)


func _update_caps() -> void:
	if not parts.head.alive and not blind:
		blind = true
	if has_gun and (not parts.fore_r.alive or not parts.arm_r.alive):
		has_gun = false
		muzzle = null
		attack_cd = 0.5
	var legs_ok: bool = parts.thigh_l.alive and parts.thigh_r.alive and parts.shin_l.alive and parts.shin_r.alive
	if not legs_ok and not crippled:
		crippled = true
		capsule.height = max(capsule.radius * 2.0, 1.2 * s)
		shape.position = Vector3(0, capsule.height * 0.5, 0)
		Fx.dust(global_position, s)
		Sfx.play3d("step", global_position, 4.0, 0.5)
	var arms_gone: bool = not parts.arm_l.alive and not parts.arm_r.alive
	if crippled and arms_gone and self_destruct < 0.0:
		self_destruct = 1.6
		Sfx.play3d("alarm", global_position, -4.0, 1.6)


func die(dir: Vector3, force: float, silent: bool = false) -> void:
	if dead:
		return
	dead = true
	state = "dead"
	var center: Vector3 = parts.torso.node.global_position + Vector3(0, 0.4 * s, 0)
	if G.main:
		G.main.on_robot_killed(self, center)
	if silent:
		queue_free()
		return
	G.kills += 1
	G.add_score(cfg.score, "%s УНИЧТОЖЕН" % cfg.name.to_upper())
	if core_light:
		core_light.queue_free()
	eye_mat.emission_energy_multiplier = 0.0
	var order := ["fore_l", "fore_r", "shin_l", "shin_r", "head", "arm_l", "arm_r", "thigh_l", "thigh_r", "torso", "hips"]
	for n in order:
		var p: Dictionary = parts[n]
		if not (p.alive or (n == "hips" and is_instance_valid(p.node) and p.node.get_parent() == rig)):
			continue
		var out: Vector3 = p.node.global_position - center
		out = out.normalized() if out.length() > 0.01 else Vector3.UP
		var push := (out * 1.3 + dir.normalized() * 0.8 + Vector3.UP * 0.6).normalized()
		_detach(n, push, force * 0.6 + 350.0, false)
	shape.disabled = true
	G.get_tree().create_timer(0.06, false).timeout.connect(
		G.explode.bind(center, 2.6 * s, 45.0, 700.0, 0.45, false))
	if thruster:
		thruster.queue_free()
	queue_free()

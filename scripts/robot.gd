class_name Robot
extends CharacterBody3D
## Робот ARC из модели Blender. Каждая часть — отдельный узел с хитбоксом.
## Слабые точки (колени, глаз, роторы ракетчика) ломаются с одного попадания.
## Шагающие роботы ставят ноги через IK; летающие держатся на роторах и падают без них.

enum Kind { LEAPER, CRAB, HORNET, ROCKETEER }

const KINDS := {
	Kind.LEAPER: {
		"name": "Прыгун", "model": "res://models/leaper.glb", "flyer": false,
		"body_hp": 950.0, "hp": {"thigh": 260.0, "shin": 210.0, "calf": 180.0},
		"weak": ["knee", "eye"], "crit": {}, "bone2": "shin",
		"speed": 5.2, "score": 700, "radius": 1.05, "step": 1.5, "step_time": 0.3, "step_h": 0.8,
	},
	Kind.CRAB: {
		"name": "Краб", "model": "res://models/crab.glb", "flyer": false,
		"body_hp": 650.0, "hp": {"thigh": 170.0, "calf": 150.0},
		"weak": ["knee"], "crit": {"eye": 3.0}, "bone2": "knee",
		"speed": 3.4, "score": 400, "radius": 1.25, "step": 0.75, "step_time": 0.2, "step_h": 0.35,
	},
	Kind.HORNET: {
		"name": "Шершень", "model": "res://models/hornet.glb", "flyer": true,
		"body_hp": 180.0, "hp": {"rotor": 80.0, "gun": 70.0},
		"weak": ["eye"], "crit": {}, "speed": 8.0, "score": 200, "radius": 0.75,
		"alt": 5.0, "dist": 13.0, "crash_at": 1,
	},
	Kind.ROCKETEER: {
		"name": "Ракетчик", "model": "res://models/rocketeer.glb", "flyer": true,
		"body_hp": 420.0, "hp": {"pod": 110.0},
		"weak": ["rotor"], "crit": {}, "speed": 4.5, "score": 500, "radius": 1.1,
		"alt": 8.5, "dist": 21.0, "crash_at": 2,
	},
}

const BREAK_TEXT := {
	"knee": "КОЛЕНО ВЫБИТО", "eye": "ГЛАЗ РАЗБИТ", "rotor": "РОТОР СБИТ", "gun": "ПУШКА СБИТА",
	"pod": "РАКЕТНИЦА СБИТА", "thigh": "НОГА ОТОРВАНА", "shin": "НОГА ПЕРЕБИТА", "calf": "ГОЛЕНЬ ОТБИТА",
}

static var _models := {}

var kind: int = Kind.HORNET
var cfg: Dictionary
var flyer := false
var model: Node3D
var body: MeshInstance3D
var parts := {}              # имя узла -> данные части
var mats := {}               # имя материала -> материал этого робота
var shape: CollisionShape3D
var legs: Array = []
var rotors: Array = []       # [{node, blades, name}]
var muzzles: Array = []

var state := "drop"
var dead := false
var blind := false
var t_state := 0.0
var knock := Vector3.ZERO
var fx_cd := 0.0
var snd_cd := 0.0
var step_snd_cd := 0.0
var flash := 0.0

# шагающие
var ride := 2.0
var ride_cur := 2.0
var ride_min := 0.5          # ниже нельзя: днище корпуса упрётся в землю
var crouch := 0.0
var tilt := Vector2.ZERO
var walk_phase := 0.0
var jump_cd := 3.0
var melee_cd := 1.0
var mortar_cd := 3.0
var charge_dir := Vector3.ZERO
var strafe := 1.0
var strafe_t := 0.0
var air_t := 0.0

# летающие
var orbit := 0.0
var fire_cd := 2.0
var burst := 0
var lock_t := -1.0
var lock_beam: MeshInstance3D
var spin := 0.0
var wobble := 0.0


static func create(k: int) -> Robot:
	var r := Robot.new()
	r.kind = k
	return r


static func _scene(path: String) -> PackedScene:
	if not _models.has(path):
		_models[path] = load(path)
	return _models[path]


func _ready() -> void:
	cfg = KINDS[kind]
	flyer = cfg.flyer
	collision_layer = G.L_ROBOT
	collision_mask = G.L_WORLD | G.L_PLAYER | G.L_ROBOT | G.L_PROPS
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.5
	safe_margin = 0.03
	if flyer:
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	strafe = 1.0 if randf() < 0.5 else -1.0
	orbit = randf() * TAU
	jump_cd = randf_range(2.5, 5.0)
	fire_cd = randf_range(1.5, 3.0)
	mortar_cd = randf_range(2.0, 4.0)

	model = _scene(cfg.model).instantiate()
	add_child(model)
	body = model.get_node("body")
	_scan(body)
	_setup_materials()

	shape = CollisionShape3D.new()
	if flyer:
		var sp := SphereShape3D.new()
		sp.radius = cfg.radius
		shape.shape = sp
		for n in parts:
			if parts[n].type == "rotor":
				rotors.append({"node": parts[n].node, "blades": parts[n].node.find_child("blades_*", false, false), "name": n})
		for m in ["muzzle", "muzzle_l", "muzzle_r"]:
			var mz := model.find_child(m, true, false)
			if mz:
				muzzles.append(mz)
	else:
		ride = body.position.y
		ride_cur = ride
		ride_min = -body.get_aabb().position.y + 0.08
		var cap := CapsuleShape3D.new()
		cap.radius = cfg.radius
		cap.height = ride + 0.9
		shape.shape = cap
		shape.position.y = cap.height * 0.5
		_setup_legs()
	add_child(shape)

	lock_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 1.0)
	lock_beam.mesh = bm
	lock_beam.material_override = Fx.glow_mat(Color(1.0, 0.1, 0.05), 6.0)
	lock_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lock_beam.top_level = true
	lock_beam.visible = false
	add_child(lock_beam)

	velocity = Vector3(0, -18, 0) if not flyer else Vector3(0, -8, 0)


# ================================================================== сборка

func _scan(n: Node) -> void:
	if n is MeshInstance3D:
		var t := String(n.name).get_slice("_", 0)
		if t == "body" or cfg.hp.has(t) or t in cfg.weak or cfg.crit.has(t):
			_register(n, t)
	for c in n.get_children():
		_scan(c)


func _register(n: MeshInstance3D, t: String) -> void:
	var weak: bool = t in cfg.weak
	var hp: float = cfg.body_hp if t == "body" else (1.0 if weak else float(cfg.hp.get(t, 100.0)))
	var p := {
		"name": String(n.name), "type": t, "node": n, "hp": hp, "max": hp, "weak": weak,
		"crit": float(cfg.crit.get(t, 0.0)), "alive": true, "areas": [],
	}
	parts[p.name] = p
	n.set_meta("pid", p.name)
	var aabb := n.get_aabb()
	var k := 1.35 if weak else (0.8 if t == "body" else 0.95)
	var a := Hitbox.new()
	a.robot = self
	a.part = p.name
	a.mult = 1.0
	a.collision_layer = G.L_HITBOX
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (aabb.size * k).max(Vector3(0.22, 0.22, 0.22))
	cs.shape = bs
	a.add_child(cs)
	n.add_child(a)
	a.position = aabb.get_center()
	p.areas.append(a)


func _setup_materials() -> void:
	var stack: Array = [model]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and n.mesh:
			for s in n.mesh.get_surface_count():
				var src: Material = n.mesh.surface_get_material(s)
				var nm := src.resource_name if src else "metal_dark"
				if not mats.has(nm):
					mats[nm] = Mats.robot(nm).duplicate()
				n.set_surface_override_material(s, mats[nm])


func _setup_legs() -> void:
	for i in 8:
		var th := body.get_node_or_null("thigh_%d" % i) as Node3D
		if th == null:
			break
		var b2 := th.get_node_or_null("%s_%d" % [cfg.bone2, i]) as Node3D
		var end := th.find_child("end_%d" % i, true, false) as Node3D
		if b2 == null or end == null:
			continue
		var rest := to_local(end.global_position)
		rest.y = 0.0
		var leg := {
			"i": i, "thigh": th, "b2": b2, "end": end,
			"a": b2.position.length(), "b": b2.global_position.distance_to(end.global_position),
			"rest": rest, "foot": end.global_position, "from": Vector3.ZERO, "to": Vector3.ZERO,
			"t": -1.0, "group": i % 2, "ok": true, "swing": randf() * TAU,
			"chain": _chain_names(th), "thigh_name": String(th.name),
		}
		legs.append(leg)


func _chain_names(th: Node) -> Array:
	var out: Array = []
	var stack: Array = [th]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.has_meta("pid"):
			out.append(n.get_meta("pid"))
		for c in n.get_children():
			stack.append(c)
	return out


# ================================================================== кадр

func _physics_process(delta: float) -> void:
	if dead:
		return
	fx_cd -= delta
	snd_cd -= delta
	step_snd_cd -= delta
	t_state -= delta
	if global_position.y < -25.0:
		die(Vector3.UP, 0.0, true)
		return
	if state == "show":
		velocity = Vector3(0, 0 if flyer else velocity.y - 24.0 * delta, 0)
		move_and_slide()
		return
	if flyer:
		_fly(delta)
	else:
		_walk_ai(delta)


func _process(delta: float) -> void:
	if dead:
		return
	if flash > 0.0:
		flash = max(flash - delta * 2.5, 0.0)
		for nm in ["metal_dark", "metal_mid", "metal_light"]:
			if mats.has(nm):
				mats[nm].emission_energy_multiplier = flash
	if flyer:
		_animate_flyer(delta)
	else:
		_animate_walker(delta)


func _player() -> Node:
	var p = G.player
	if p == null or not is_instance_valid(p) or p.dead:
		return null
	return p


# ================================================================== шагающие

func supports() -> int:
	var n := 0
	for l in legs:
		if l.ok:
			n += 1
	return n


func _walk_ai(delta: float) -> void:
	var p := _player()
	var sup := supports()
	var on_floor := is_on_floor()
	var g := 24.0

	if state == "drop":
		velocity.y = max(velocity.y - 30.0 * delta, -30.0)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if is_on_floor():
			_land(0.6)
		return

	if state == "air":
		air_t += delta
		velocity.y -= g * delta
		move_and_slide()
		if is_on_floor() and air_t > 0.25:
			_land(1.0)
			state = "move"
			jump_cd = randf_range(4.5, 7.5)
		return

	var desired := Vector3.ZERO
	var sfac: Array = [0.0, 0.12, 0.3, 0.7, 1.0]
	var spd: float = cfg.speed * sfac[min(sup, 4)]
	var dist := 999.0
	var dir := -global_basis.z
	if p:
		var to: Vector3 = p.global_position - global_position
		to.y = 0
		dist = to.length()
		if dist > 0.01:
			dir = to / dist

	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_t = randf_range(1.5, 3.5)
		if randf() < 0.5:
			strafe = -strafe
	var side := Vector3(-dir.z, 0, dir.x) * strafe

	match state:
		"move":
			if p:
				if blind:
					desired = (dir.rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.0007) * 1.6)).normalized()
				elif kind == Kind.LEAPER:
					desired = dir if dist > 7.0 else side
				else:
					desired = dir if dist > 5.0 else side * 0.5
				jump_cd -= delta
				melee_cd -= delta
				mortar_cd -= delta
				var los := _los(p)
				if kind == Kind.LEAPER:
					if sup >= 3 and jump_cd <= 0.0 and dist > 6.0 and dist < 26.0 and los and not blind:
						state = "crouch"
						t_state = 0.55
						Sfx.play3d("servo", global_position, 4.0, 0.5)
					elif dist < 4.8 and melee_cd <= 0.0:
						state = "stomp"
						t_state = 0.5
						Sfx.play3d("servo", global_position, 2.0, 0.7)
				else:
					if sup >= 3 and dist < 13.0 and dist > 4.0 and melee_cd <= 0.0 and los and not blind:
						state = "wind"
						t_state = 0.6
						Sfx.play3d("servo", global_position, 2.0, 0.6)
					elif dist < 3.2 and melee_cd <= 0.0:
						state = "stomp"
						t_state = 0.4
					elif dist > 7.0 and mortar_cd <= 0.0 and sup >= 2:
						_fire_mortar(p)
						mortar_cd = randf_range(3.5, 5.5)
		"crouch":
			crouch = move_toward(crouch, 1.0, delta * 4.0)
			if t_state <= 0.0 and p:
				_leap(p)
				return
		"stomp":
			crouch = move_toward(crouch, -0.6, delta * 5.0)
			if t_state <= 0.0:
				_stomp(p, dist)
				state = "move"
				melee_cd = 2.0
		"wind":
			crouch = move_toward(crouch, 0.5, delta * 4.0)
			if t_state <= 0.0:
				state = "charge"
				t_state = 1.3
				charge_dir = dir
				Sfx.play3d("whoosh", global_position, 4.0, 0.5)
		"charge":
			crouch = move_toward(crouch, 0.0, delta * 4.0)
			desired = charge_dir
			spd = 11.0 * sfac[min(sup, 4)]
			if p and dist < 2.6:
				p.take_damage(28.0, global_position)
				p.knockback(charge_dir * 16.0 + Vector3.UP * 6.0)
				Sfx.play3d("impact", global_position, 2.0, 0.7)
				p.add_shake(0.6)
				state = "move"
				melee_cd = 3.5
			elif is_on_wall() or t_state <= 0.0:
				if is_on_wall():
					Sfx.play3d("clang", global_position, 4.0, 0.5)
					Fx.dust(global_position + charge_dir * 1.5, 1.0)
				state = "move"
				melee_cd = 3.0

	if state == "move":
		crouch = move_toward(crouch, 0.0, delta * 3.0)

	# обход препятствий
	if desired.length() > 0.1 and state != "charge":
		var eye := global_position + Vector3(0, 0.8, 0)
		var hit := G.ray(eye, eye + desired * (cfg.radius + 1.6), G.L_WORLD | G.L_PROPS, [get_rid()], false)
		if not hit.is_empty():
			desired = desired.rotated(Vector3.UP, 1.2 * strafe)

	var tv := desired * spd
	var acc := 7.0 if on_floor else 1.0
	velocity.x = lerp(velocity.x, tv.x, clamp(acc * delta, 0.0, 1.0))
	velocity.z = lerp(velocity.z, tv.z, clamp(acc * delta, 0.0, 1.0))
	velocity.y -= g * delta
	velocity += knock
	knock = Vector3.ZERO
	move_and_slide()

	if p and sup > 0:
		var yaw := atan2(-dir.x, -dir.z)
		if state == "charge":
			yaw = atan2(-charge_dir.x, -charge_dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, clamp(2.5 * delta, 0.0, 1.0))


func _los(p: Node) -> bool:
	var from := global_position + Vector3(0, ride_cur, 0)
	return G.ray(from, p.global_position + Vector3(0, 1.2, 0), G.L_WORLD, [], false).is_empty()


func _leap(p: Node) -> void:
	var target: Vector3 = p.global_position + p.velocity * 0.4
	var d := target - global_position
	var flat := Vector2(d.x, d.z).length()
	var tt: float = clamp(flat / 16.0, 0.75, 1.3)
	var g := 24.0
	velocity = Vector3(d.x / tt, (d.y + 0.5 * g * tt * tt) / tt, d.z / tt)
	state = "air"
	air_t = 0.0
	crouch = -0.4
	Sfx.play3d("whoosh", global_position, 6.0, 0.45)
	Fx.dust(global_position, 1.5)


func _land(power: float) -> void:
	if state == "drop":
		state = "move"
	crouch = 0.6 * power
	Fx.dust(global_position, 1.6 * power + 0.4)
	Sfx.play3d("impact" if power > 0.8 else "step", global_position, 4.0, 0.5)
	for l in legs:
		l.foot = _foot_target(l)
		l.t = -1.0
	var p := _player()
	if p:
		var dist: float = p.global_position.distance_to(global_position)
		p.add_shake(clamp(0.8 - dist / 30.0, 0.0, 0.8) * power)
		if power > 0.8 and dist < 5.0:
			p.take_damage(32.0 * (1.0 - dist / 6.0), global_position)
			p.knockback((p.global_position - global_position).normalized() * 12.0 + Vector3.UP * 7.0)
	_push_debris(global_position, 5.0 * power, 6.0)


func _stomp(p: Node, dist: float) -> void:
	var pos := global_position + (-global_basis.z) * 2.0
	Fx.dust(pos, 1.2)
	Sfx.play3d("impact", pos, 2.0, 0.65)
	_push_debris(pos, 3.5, 5.0)
	if p and dist < (5.2 if kind == Kind.LEAPER else 3.6):
		p.take_damage(26.0, global_position)
		p.knockback((p.global_position - global_position).normalized() * 14.0 + Vector3.UP * 6.0)


func _push_debris(pos: Vector3, radius: float, k: float) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	q.shape = sp
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = G.L_DEBRIS | G.L_PROPS
	for r in get_world_3d().direct_space_state.intersect_shape(q, 64):
		var c = r.collider
		if c is RigidBody3D and not c.freeze:
			c.apply_central_impulse(((c.global_position - pos).normalized() + Vector3.UP) * c.mass * k * 0.5)


func _fire_mortar(p: Node) -> void:
	var from := body.global_position + Vector3(0, 1.4, 0)
	var target: Vector3 = p.global_position + p.velocity * 0.6
	var tt := 1.6
	var g := 20.0
	var d := target - from
	var v := Vector3(d.x / tt, (d.y + 0.5 * g * tt * tt) / tt, d.z / tt)
	Projectile.mortar(from, v, target)
	Sfx.play3d("rocket", from, 0.0, 0.6)
	Fx.smoke(from, 6, 0.6, 1.2, Color(0.5, 0.5, 0.5))
	crouch = 0.3


func _foot_target(l: Dictionary) -> Vector3:
	var lead := Vector3(velocity.x, 0, velocity.z) * 0.22
	var d: Vector3 = global_transform * l.rest + lead
	var hit := G.ray(d + Vector3.UP * 3.0, d + Vector3.DOWN * 4.0, G.L_WORLD | G.L_PROPS, [], false)
	if not hit.is_empty():
		d.y = hit.position.y
	else:
		d.y = global_position.y
	return d


func _animate_walker(delta: float) -> void:
	var sup := supports()
	var hv := Vector2(velocity.x, velocity.z).length()
	walk_phase += delta * hv * 2.0
	var kk: Array = [0.18, 0.28, 0.5, 0.85, 1.0]
	var k: float = kk[min(sup, 4)]
	var target_ride = ride * k - crouch * ride * 0.25 + sin(walk_phase) * 0.04 * min(hv, 1.0)
	if state == "air":
		target_ride = ride * 0.9
	target_ride = max(target_ride, ride_min + tilt.length() * 0.35)
	ride_cur = lerp(ride_cur, target_ride, clamp(delta * 6.0, 0.0, 1.0))
	ride_cur = max(ride_cur, ride_min)
	body.position.y = ride_cur
	var tilt_t := Vector2.ZERO
	for l in legs:
		if not l.ok:
			tilt_t += Vector2(l.rest.x, l.rest.z).normalized()
	if state == "stomp":
		tilt_t += Vector2(0, 1.2)
	tilt = tilt.lerp(tilt_t.limit_length(1.4), clamp(delta * 4.0, 0.0, 1.0))
	body.rotation = Vector3(-tilt.y * 0.22, 0.0, tilt.x * 0.22)
	var cap := shape.shape as CapsuleShape3D
	cap.height = max(ride_cur + 0.9, cfg.radius * 2.0 + 0.1)
	shape.position.y = cap.height * 0.5

	# шаги: ноги одной диагонали переставляются вместе
	var stepping_group := -1
	for l in legs:
		if l.ok and l.t >= 0.0:
			stepping_group = l.group
	for l in legs:
		if not l.ok:
			_dangle(l, delta)
			continue
		if state == "air":
			var tuck: Vector3 = global_transform * (l.rest * 0.6) + Vector3(0, ride_cur * 0.35, 0)
			l.foot = l.foot.lerp(tuck, clamp(delta * 10.0, 0.0, 1.0))
		elif l.t >= 0.0:
			l.t += delta / cfg.step_time
			var e: float = min(l.t, 1.0)
			l.foot = l.from.lerp(l.to, e * e * (3.0 - 2.0 * e)) + Vector3.UP * sin(PI * e) * cfg.step_h
			if l.t >= 1.0:
				l.t = -1.0
				l.foot = l.to
				if step_snd_cd <= 0.0:
					step_snd_cd = 0.12
					Sfx.play3d("step", l.foot, -2.0 if kind == Kind.LEAPER else -6.0, randf_range(0.5, 0.65))
		else:
			var tgt := _foot_target(l)
			var far: float = Vector2(tgt.x - l.foot.x, tgt.z - l.foot.z).length()
			if far > cfg.step and (stepping_group == -1 or stepping_group == l.group):
				l.from = l.foot
				l.to = tgt
				l.t = 0.0
				stepping_group = l.group
		_ik(l)


func _ik(l: Dictionary) -> void:
	var th: Node3D = l.thigh
	var b2: Node3D = l.b2
	var h := th.global_position
	var t: Vector3 = l.foot
	var out := h - body.global_position
	out.y = 0
	out = out.normalized() if out.length() > 0.01 else Vector3.RIGHT
	var pole := Vector3.UP * 1.6 + out * 0.5
	var k := _solve(h, t, l.a, l.b, pole)
	var n := (t - h).cross(pole)
	if n.length() < 0.001:
		n = global_basis.x
	n = n.normalized()
	th.global_basis = _bone_basis(k - h, n)
	b2.global_basis = _bone_basis(t - k, n)


func _dangle(l: Dictionary, delta: float) -> void:
	if not parts[l.thigh_name].alive or not is_instance_valid(l.thigh):
		return
	var th: Node3D = l.thigh
	l.swing += delta * 2.0
	var h := th.global_position
	var out := h - body.global_position
	out.y = 0
	out = out.normalized() if out.length() > 0.01 else Vector3.RIGHT
	var dir := (out * 0.9 + Vector3.DOWN * 0.45 + global_basis.z * sin(l.swing) * 0.15).normalized()
	# чем ниже бедро, тем горизонтальнее висит нога — чтобы не проваливалась в землю
	var ground_y := global_position.y + 0.15
	var reach: float = l.a + (l.b if is_instance_valid(l.b2) and parts.has(String(l.b2.name)) and parts[String(l.b2.name)].alive else 0.3)
	var max_drop: float = clamp((h.y - ground_y) / max(reach, 0.1), -0.2, 1.0)
	if -dir.y > max_drop:
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		var dy: float = max_drop
		dir = (flat * sqrt(max(1.0 - dy * dy, 0.0)) + Vector3.DOWN * dy).normalized()
	var n := dir.cross(Vector3.UP)
	if n.length() < 0.01:
		n = Vector3.RIGHT
	var target := _bone_basis(dir, n.normalized())
	th.global_basis = th.global_basis.slerp(target, clamp(delta * 4.0, 0.0, 1.0)).orthonormalized()
	if not is_instance_valid(l.b2):
		return
	var b2: Node3D = l.b2
	if b2.get_parent() == th:
		b2.basis = b2.basis.slerp(Basis(Vector3.RIGHT, 0.6), clamp(delta * 3.0, 0.0, 1.0)).orthonormalized()


static func _solve(h: Vector3, t: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var d := t - h
	var dist: float = clamp(d.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dn := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var ca: float = clamp((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0)
	var ang := acos(ca)
	var pp := pole - dn * pole.dot(dn)
	if pp.length() < 0.0001:
		pp = Vector3.UP
	pp = pp.normalized()
	return h + dn * cos(ang) * a + pp * sin(ang) * a


static func _bone_basis(dir: Vector3, n: Vector3) -> Basis:
	var y := -dir.normalized()
	var x := n - y * n.dot(y)
	if x.length() < 0.001:
		x = y.cross(Vector3.FORWARD) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# ================================================================== летающие

func rotors_alive() -> int:
	var n := 0
	for r in rotors:
		if parts[r.name].alive:
			n += 1
	return n


func _fly(delta: float) -> void:
	var p := _player()
	var lost := rotors.size() - rotors_alive()

	if state == "crash":
		velocity.y -= 16.0 * delta
		velocity.x *= 0.99
		velocity.z *= 0.99
		spin += delta * 7.0
		rotation.y += delta * spin * 0.5
		move_and_slide()
		if get_slide_collision_count() > 0 or is_on_floor():
			die(Vector3.UP, 600.0)
		return

	if state == "drop":
		velocity = velocity.lerp(Vector3.ZERO, delta * 1.5)
		move_and_slide()
		if velocity.length() < 1.5:
			state = "fly"
		return

	if state == "dive":
		if p == null:
			state = "fly"
			return
		var to: Vector3 = p.global_position + Vector3(0, 1.0, 0) - global_position
		velocity = velocity.lerp(to.normalized() * 17.0, clamp(delta * 3.0, 0.0, 1.0))
		move_and_slide()
		if to.length() < 2.0 or get_slide_collision_count() > 0:
			die(velocity.normalized(), 500.0)
		return

	var target := global_position
	if p:
		orbit += delta * (0.25 if kind == Kind.ROCKETEER else 0.45) * strafe
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = randf_range(2.0, 5.0)
			if randf() < 0.4:
				strafe = -strafe
		var alt: float = cfg.alt * (1.0 - 0.3 * lost) + sin(Time.get_ticks_msec() * 0.001 + orbit) * 1.2
		var dist: float = cfg.dist
		if blind:
			dist *= 0.6
			orbit += delta * 1.5
		target = p.global_position + Vector3(cos(orbit), 0, sin(orbit)) * dist + Vector3.UP * alt
	var gh := G.ray(global_position, global_position + Vector3.DOWN * 3.0, G.L_WORLD | G.L_PROPS, [], false)
	if not gh.is_empty():
		target.y = max(target.y, gh.position.y + 2.8)
	var desired := (target - global_position)
	var speed: float = cfg.speed * (1.0 - 0.25 * lost)
	var want := desired.limit_length(speed)
	if velocity.length() > 0.5:
		var ob := G.ray(global_position, global_position + velocity.normalized() * 4.0, G.L_WORLD | G.L_PROPS, [get_rid()], false)
		if not ob.is_empty():
			want += ob.normal * speed + Vector3.UP * speed * 0.6
	velocity = velocity.lerp(want, clamp(delta * 1.6, 0.0, 1.0))
	if lost > 0:
		wobble += delta * 6.0
		velocity += Vector3(sin(wobble * 1.3), sin(wobble) * 0.6, cos(wobble * 0.9)) * 2.0 * lost * delta
	velocity += knock
	knock = Vector3.ZERO
	move_and_slide()

	if p:
		var to: Vector3 = p.global_position - global_position
		var yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, yaw, clamp(delta * 2.5, 0.0, 1.0))
		if kind == Kind.HORNET:
			_hornet_gun(delta, p)
		else:
			_rocket_logic(delta, p)


func _hornet_gun(delta: float, p: Node) -> void:
	if not parts.has("gun") or not parts.gun.alive or muzzles.is_empty() or not is_instance_valid(muzzles[0]):
		if global_position.distance_to(p.global_position) < 30.0 and state == "fly":
			state = "dive"
			Sfx.play3d("alarm", global_position, -4.0, 1.8)
		return
	fire_cd -= delta
	if fire_cd > 0.0:
		return
	var m: Vector3 = muzzles[0].global_position
	var tgt: Vector3 = p.global_position + Vector3(0, 1.2, 0)
	if not G.ray(m, tgt, G.L_WORLD | G.L_PROPS, [], false).is_empty():
		fire_cd = 0.5
		return
	if burst <= 0:
		burst = 4
	burst -= 1
	fire_cd = 0.12 if burst > 0 else randf_range(1.6, 2.4)
	var lead: Vector3 = p.velocity * (m.distance_to(tgt) / 38.0) * 0.5
	var aim := (tgt + lead - m).normalized()
	var spread := 0.18 if blind else 0.03
	aim = (aim + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	Projectile.robot_bolt(m, aim, 6.0)
	Sfx.play3d("robot_shot", m, -2.0, randf_range(0.9, 1.1))
	Fx.flash(m, Color(1.0, 0.25, 0.1), 2.0, 3.0, 0.08)


func _rocket_logic(delta: float, p: Node) -> void:
	var pods: Array = []
	for m in muzzles:
		if is_instance_valid(m) and m.get_parent() and m.get_parent().has_meta("pid") and parts[m.get_parent().get_meta("pid")].alive:
			pods.append(m)
	if pods.is_empty():
		if state == "fly" and global_position.distance_to(p.global_position) < 40.0:
			state = "dive"
			Sfx.play3d("alarm", global_position, -2.0, 1.4)
		lock_beam.visible = false
		return
	var tgt: Vector3 = p.global_position + Vector3(0, 1.0, 0)
	if lock_t >= 0.0:
		lock_t += delta
		_show_beam(pods[0].global_position, tgt)
		if lock_t >= 1.3:
			lock_t = -1.0
			lock_beam.visible = false
			for i in pods.size():
				var mz: Node3D = pods[i]
				for k in 2:
					var spread = Vector3(randf_range(-1, 1), randf_range(-0.2, 0.6), randf_range(-1, 1)) * (3.0 if blind else 1.4)
					get_tree().create_timer(0.12 * (i * 2 + k), false).timeout.connect(
						_launch_rocket.bind(mz, tgt + spread))
			fire_cd = randf_range(4.5, 6.5)
		return
	fire_cd -= delta
	if fire_cd <= 0.0 and G.ray(pods[0].global_position, tgt, G.L_WORLD, [], false).is_empty():
		lock_t = 0.0
		Sfx.play3d("alarm", global_position, -6.0, 2.2)


func _launch_rocket(mz: Node3D, tgt: Vector3) -> void:
	if dead or not is_instance_valid(mz) or not is_inside_tree():
		return
	var m := mz.global_position
	Projectile.robot_rocket(m, (tgt - m).normalized())
	Sfx.play3d("rocket", m, -2.0, 1.2)
	Fx.flash(m, Color(1.0, 0.5, 0.2), 3.0, 4.0, 0.1)


func _show_beam(a: Vector3, b: Vector3) -> void:
	lock_beam.visible = true
	var ln := a.distance_to(b)
	if ln < 0.1:
		return
	lock_beam.global_transform = Transform3D(Basis(), (a + b) * 0.5)
	lock_beam.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT)
	lock_beam.scale = Vector3(1, 1, ln)


func _animate_flyer(delta: float) -> void:
	for r in rotors:
		if parts[r.name].alive and r.blades and is_instance_valid(r.blades):
			r.blades.rotate_y(delta * 40.0)
	var lv := global_basis.inverse() * velocity
	var lost := rotors.size() - rotors_alive()
	var roll := -lv.x * 0.04
	var pitch := lv.z * 0.04
	if lost > 0:
		roll += sin(wobble) * 0.25 * lost
	model.rotation.x = lerp(model.rotation.x, clamp(pitch, -0.5, 0.5), clamp(delta * 4.0, 0.0, 1.0))
	model.rotation.z = lerp(model.rotation.z, clamp(roll, -0.6, 0.6), clamp(delta * 4.0, 0.0, 1.0))
	model.position.y = sin(Time.get_ticks_msec() * 0.003 + orbit) * 0.08


func knockback(v: Vector3) -> void:
	if dead:
		return
	var mass := 3.0 if kind == Kind.LEAPER else (2.5 if kind == Kind.CRAB else 1.0)
	knock += v / mass


# ================================================================== урон

func damage_part(pname: String, dmg: float, pos: Vector3, dir: Vector3, force: float, crit: bool = false) -> void:
	if dead or not parts.has(pname):
		return
	var p: Dictionary = parts[pname]
	if not p.alive:
		return
	var is_crit: bool = crit or p.weak or p.crit > 0.0
	flash = 0.3 if is_crit else 0.15
	if fx_cd <= 0.0:
		fx_cd = 0.06
		Fx.sparks(pos, -dir + Vector3.UP * 0.3, 8 if dmg < 30 else 18, 6.0)
	if snd_cd <= 0.0:
		snd_cd = 0.08
		Sfx.play3d("clang" if dmg >= 25 or is_crit else "hit", pos, -4.0 if dmg < 25 else 0.0, randf_range(0.8, 1.25))
	if G.hud:
		G.hud.hitmarker(is_crit)
	if state != "drop":
		knock += dir * min(force * 0.0015, 1.5)

	if p.crit > 0.0:
		_damage_body(dmg * p.crit, dir, force)
		return
	if p.type == "body":
		_damage_body(dmg, dir, force)
		return
	var absorbed: float = min(dmg, max(p.hp, 0.0))
	p.hp -= dmg
	parts.body.hp -= absorbed * 0.2
	if p.hp <= 0.0:
		_break(pname, dir, force)
	if not dead and parts.body.hp <= 0.0:
		die(dir, force)


func _damage_body(dmg: float, dir: Vector3, force: float) -> void:
	parts.body.hp -= dmg
	if parts.body.hp <= 0.0:
		die(dir, force)


func _break(pname: String, dir: Vector3, force: float) -> void:
	var p: Dictionary = parts[pname]
	var pos: Vector3 = p.node.global_position
	_detach(pname, dir, force)
	G.parts_ripped += 1
	G.add_score(60 if p.weak else 35, BREAK_TEXT.get(p.type, "ДЕТАЛЬ ОТОРВАНА"))
	Sfx.play3d("clang", pos, 4.0, randf_range(0.55, 0.75))
	if p.weak:
		Fx.flash(pos, Color(1.0, 0.7, 0.3), 5.0, 5.0, 0.25)
		parts.body.hp -= parts.body.max * 0.08
		G.hitstop(0.035)
	match p.type:
		"eye":
			blind = true
			Fx.sparks(pos, -dir, 30, 8.0, Color(0.4, 0.8, 1.0))
		"rotor":
			var lost := rotors.size() - rotors_alive()
			if lost >= cfg.crash_at and state != "crash":
				state = "crash"
				spin = 2.0
				Fx.smoke_emitter(body, Vector3.ZERO, -1.0)
				Sfx.play3d("alarm", global_position, 0.0, 0.9)
	if not flyer:
		for l in legs:
			l.ok = true
			for n in l.chain:
				if not parts[n].alive:
					l.ok = false
		if supports() <= 1 and state == "air":
			state = "move"
	if not dead and parts.body.hp <= 0.0:
		die(dir, force)


func _detach(pname: String, dir: Vector3, force: float) -> RigidBody3D:
	var p: Dictionary = parts[pname]
	var node: Node3D = p.node
	var stack: Array = [node]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.has_meta("pid") and parts.has(n.get_meta("pid")):
			var pp: Dictionary = parts[n.get_meta("pid")]
			pp.alive = false
			for a in pp.areas:
				if is_instance_valid(a):
					a.queue_free()
			pp.areas.clear()
		for c in n.get_children():
			stack.append(c)
	var parent := node.get_parent() as Node3D
	var joint := node.global_position
	var rb := _make_debris(node)
	if not dead and parent and is_instance_valid(parent):
		Fx.spark_emitter(parent, parent.to_local(joint), 6.0)
	if rb:
		Fx.spark_emitter(rb, Vector3.ZERO, 3.0)
		if randf() < 0.5:
			Fx.smoke_emitter(rb, Vector3.ZERO, 5.0)
		var push := dir.normalized() if dir.length() > 0.01 else Vector3.UP
		rb.apply_central_impulse(push * (rb.mass * 3.5 + force * 0.015) + Vector3.UP * rb.mass * 3.0)
		rb.angular_velocity = Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7))
	Fx.sparks(joint, dir, 22, 9.0)
	return rb


func _make_debris(node: Node3D) -> RigidBody3D:
	var rb := WallChunk.new()
	rb.broken = true
	rb.collision_layer = G.L_DEBRIS
	rb.collision_mask = G.L_WORLD | G.L_DEBRIS | G.L_PROPS | G.L_PLAYER | G.L_ROBOT
	G.world.add_child(rb)
	rb.global_transform = node.global_transform.orthonormalized()
	var meshes: Array = []
	_collect_meshes(node, meshes)
	node.reparent(rb, true)
	var vol := 0.0
	var inv := rb.global_transform.affine_inverse()
	for mi in meshes:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var aabb: AABB = mi.get_aabb()
		var size = aabb.size.max(Vector3(0.06, 0.06, 0.06))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		rb.add_child(cs)
		cs.transform = (inv * mi.global_transform) * Transform3D(Basis(), aabb.get_center())
		vol += size.x * size.y * size.z
	rb.mass = clamp(vol * 500.0, 3.0, 250.0)
	rb.physics_material_override = WallChunk.debris_phys()
	rb.linear_velocity = velocity * 0.7
	rb.continuous_cd = true
	G.lift_above_ground(rb)
	G.add_debris(rb)
	return rb


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		if not (c is Hitbox):
			_collect_meshes(c, out)


func die(dir: Vector3, force: float, silent: bool = false) -> void:
	if dead:
		return
	dead = true
	state = "dead"
	lock_beam.visible = false
	var center := body.global_position
	if G.main:
		G.main.on_robot_killed(self, center)
	if silent:
		queue_free()
		return
	G.kills += 1
	G.add_score(cfg.score, "%s УНИЧТОЖЕН" % String(cfg.name).to_upper())
	for nm in ["glow_blue", "glow_red"]:
		if mats.has(nm):
			mats[nm].emission_energy_multiplier = 0.0
	var order: Array = []
	var depth := {}
	for n in parts:
		if parts[n].alive and is_instance_valid(parts[n].node):
			order.append(n)
			depth[n] = _depth(parts[n].node)
	order.sort_custom(func(a, b): return depth[a] > depth[b])
	for n in order:
		if n == "body" or not parts[n].alive:
			continue
		var out: Vector3 = parts[n].node.global_position - center
		out = out.normalized() if out.length() > 0.01 else Vector3.UP
		_detach(n, (out * 1.2 + dir.normalized() * 0.7 + Vector3.UP * 0.6).normalized(), force * 0.5 + 300.0)
	parts.body.alive = false
	_detach("body", (dir + Vector3.UP).normalized(), force * 0.3 + 200.0)
	var r := 3.2 if kind in [Kind.LEAPER, Kind.ROCKETEER] else 2.4
	G.get_tree().create_timer(0.05, false).timeout.connect(G.explode.bind(center, r, 60.0, 900.0, 0.5, true))
	queue_free()


func _depth(n: Node) -> int:
	var d := 0
	while n and n != self:
		n = n.get_parent()
		d += 1
	return d

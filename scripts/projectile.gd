class_name Projectile
extends Node3D
## Снаряды: плазменные заряды игрока, красные заряды роботов, ракеты.

const PLAYER_MASK := 1 | 8 | 16 | 32   # мир, хитбоксы, обломки, пропы
const ROBOT_MASK := 1 | 2 | 32        # мир, игрок, пропы

static var _bolt_mesh: CapsuleMesh
static var _rbolt_mesh: CapsuleMesh

var vel := Vector3.ZERO
var life := 2.5
var dmg := 10.0
var force := 30.0
var from_player := true
var rocket := false
var mask := PLAYER_MASK
var trail: CPUParticles3D
var gravity := 0.0
var homing := 0.0
var radius := 4.5
var player_hurt := 0.6
var warn: Node3D


static func _mk_bolt(c: Color, r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 2
	m.material = Fx.glow_mat(c, 8.0)
	return m


static func player_bolt(pos: Vector3, dir: Vector3, damage: float) -> Projectile:
	if _bolt_mesh == null:
		_bolt_mesh = _mk_bolt(Color(0.3, 0.85, 1.0), 0.035, 0.7)
	var p := Projectile.new()
	p.vel = dir * 150.0
	p.dmg = damage
	p.force = 40.0
	p.from_player = true
	p.mask = PLAYER_MASK
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	mi.rotation.x = PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	G.world.add_child(p)
	p.global_position = pos
	p._orient()
	return p


static func robot_bolt(pos: Vector3, dir: Vector3, damage: float) -> Projectile:
	if _rbolt_mesh == null:
		_rbolt_mesh = _mk_bolt(Color(1.0, 0.18, 0.08), 0.06, 0.9)
	var p := Projectile.new()
	p.vel = dir * 38.0
	p.dmg = damage
	p.force = 10.0
	p.from_player = false
	p.mask = ROBOT_MASK
	p.life = 3.0
	var mi := MeshInstance3D.new()
	mi.mesh = _rbolt_mesh
	mi.rotation.x = PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.25, 0.1)
	l.light_energy = 1.5
	l.omni_range = 2.5
	p.add_child(l)
	G.world.add_child(p)
	p.global_position = pos
	p._orient()
	return p


static func rocket_shot(pos: Vector3, dir: Vector3) -> Projectile:
	var p := Projectile.new()
	p.vel = dir * 52.0
	p.dmg = 180.0
	p.force = 1500.0
	p.rocket = true
	p.life = 4.0
	p.mask = PLAYER_MASK
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 0.5
	body.mesh = cm
	body.material_override = Fx.solid_mat(Color(0.3, 0.32, 0.25), 0.6, 0.4)
	body.rotation.x = PI * 0.5
	p.add_child(body)
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.06
	tm.height = 0.16
	tip.mesh = tm
	tip.material_override = Fx.solid_mat(Color(0.8, 0.2, 0.1), 0.5, 0.4)
	tip.rotation.x = -PI * 0.5
	tip.position = Vector3(0, 0, -0.33)
	p.add_child(tip)
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.11
	fm.height = 0.35
	flame.mesh = fm
	flame.material_override = Fx.glow_mat(Color(1.0, 0.6, 0.2), 10.0)
	flame.position = Vector3(0, 0, 0.32)
	p.add_child(flame)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 4.0
	l.omni_range = 7.0
	l.position = Vector3(0, 0, 0.5)
	p.add_child(l)
	G.world.add_child(p)
	p.global_position = pos
	p._orient()
	# дымный след
	var t := CPUParticles3D.new()
	t.amount = 70
	t.lifetime = 1.4
	t.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.7, 0.7, 0.7, 0.5)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	t.mesh = sm
	t.direction = Vector3(0, 1, 0)
	t.spread = 180.0
	t.initial_velocity_min = 0.1
	t.initial_velocity_max = 0.6
	t.gravity = Vector3(0, 0.5, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.2))
	t.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.8, 0.75, 0.55))
	grad.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	t.color_ramp = grad
	p.add_child(t)
	t.position = Vector3(0, 0, 0.4)
	t.emitting = true
	p.trail = t
	return p


static func _smoke_trail(p: Projectile, color: Color, amount: int = 60) -> void:
	var t := CPUParticles3D.new()
	t.amount = amount
	t.lifetime = 1.2
	t.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1, 1, 1, 0.5)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	t.mesh = sm
	t.spread = 180.0
	t.initial_velocity_min = 0.1
	t.initial_velocity_max = 0.5
	t.gravity = Vector3(0, 0.5, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.0))
	t.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.55))
	grad.set_color(1, Color(0.35, 0.35, 0.35, 0.0))
	t.color_ramp = grad
	p.add_child(t)
	t.position = Vector3(0, 0, 0.3)
	t.emitting = true
	p.trail = t


static func _glow_ball(p: Projectile, c: Color, r: float, light: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = Fx.glow_mat(c, 8.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	if light > 0.0:
		var l := OmniLight3D.new()
		l.light_color = c
		l.light_energy = light
		l.omni_range = 4.0
		p.add_child(l)


## Граната барабанного гранатомёта (летит по дуге, взрыв при касании).
static func grenade(pos: Vector3, v: Vector3) -> Projectile:
	var p := Projectile.new()
	p.vel = v
	p.gravity = 16.0
	p.dmg = 150.0
	p.force = 1300.0
	p.rocket = true
	p.radius = 4.0
	p.player_hurt = 0.5
	p.life = 5.0
	p.mask = PLAYER_MASK
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.045
	cm.height = 0.14
	body.mesh = cm
	body.material_override = Mats.robot("brass")
	body.rotation.x = PI * 0.5
	p.add_child(body)
	_glow_ball(p, Color(1.0, 0.6, 0.2), 0.03, 1.5)
	G.world.add_child(p)
	p.global_position = pos
	p._orient()
	_smoke_trail(p, Color(0.8, 0.8, 0.8), 30)
	return p


## Миномётный снаряд краба: дуга + предупреждающий круг на земле.
static func mortar(pos: Vector3, v: Vector3, target: Vector3) -> Projectile:
	var p := Projectile.new()
	p.vel = v
	p.gravity = 20.0
	p.dmg = 90.0
	p.force = 1100.0
	p.rocket = true
	p.radius = 3.6
	p.player_hurt = 1.0
	p.life = 6.0
	p.from_player = false
	p.mask = ROBOT_MASK
	_glow_ball(p, Color(1.0, 0.25, 0.08), 0.16, 3.0)
	G.world.add_child(p)
	p.global_position = pos
	_smoke_trail(p, Color(0.5, 0.45, 0.4), 40)
	p.warn = Fx.warning_ring(target, 3.6, 1.7)
	return p


## Ракета ракетчика: медленная, слегка доворачивает на игрока.
static func robot_rocket(pos: Vector3, dir: Vector3) -> Projectile:
	var p := Projectile.new()
	p.vel = dir * 24.0
	p.homing = 1.1
	p.dmg = 80.0
	p.force = 900.0
	p.rocket = true
	p.radius = 3.2
	p.player_hurt = 1.0
	p.life = 6.0
	p.from_player = false
	p.mask = ROBOT_MASK
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 0.4
	body.mesh = cm
	body.material_override = Mats.robot("metal_mid")
	body.rotation.x = PI * 0.5
	p.add_child(body)
	_glow_ball(p, Color(1.0, 0.35, 0.1), 0.08, 3.0)
	G.world.add_child(p)
	p.global_position = pos
	p._orient()
	_smoke_trail(p, Color(0.7, 0.65, 0.6), 50)
	return p


func _orient() -> void:
	if vel.length() > 0.01:
		var up = Vector3.UP if abs(vel.normalized().y) < 0.98 else Vector3.RIGHT
		look_at(global_position + vel, up)


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + vel * delta
	var ex: Array = []
	if not from_player and G.player:
		ex = []
	elif from_player and G.player:
		ex = [G.player.get_rid()]
	var hit := G.ray(from, to, mask, ex, from_player)
	if not hit.is_empty():
		_impact(hit)
		return
	global_position = to
	if rocket:
		vel += Vector3(0, -1.5 - gravity, 0) * delta
		if homing > 0.0 and G.player and is_instance_valid(G.player) and not G.player.dead:
			var want: Vector3 = (G.player.global_position + Vector3(0, 1.0, 0) - global_position).normalized() * vel.length()
			vel = vel.lerp(want, clamp(homing * delta, 0.0, 1.0))
		_orient()
	life -= delta
	if life <= 0.0:
		if rocket:
			_boom(global_position)
		_finish()


func _boom(pos: Vector3) -> void:
	G.explode(pos, radius, dmg, force, player_hurt, radius > 3.0)


func _impact(hit: Dictionary) -> void:
	var pos: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var c = hit.collider
	var d := vel.normalized()
	if rocket:
		_boom(pos + n * 0.2)
		_finish()
		return
	if from_player:
		G.apply_hit(c, dmg, pos, d, force)
		if not (c is Hitbox):
			Fx.sparks(pos, n, 6, 5.0, Color(0.4, 0.85, 1.0))
	else:
		if c == G.player:
			G.player.take_damage(dmg, pos - d * 5.0)
		else:
			Fx.sparks(pos, n, 5, 4.0, Color(1.0, 0.3, 0.1))
			if c and c.has_method("take_hit"):
				c.take_hit(dmg * 0.5, pos, d, force)
	_finish()


func _finish() -> void:
	if warn and is_instance_valid(warn):
		warn.queue_free()
	if trail and is_instance_valid(trail):
		var gp := trail.global_position
		trail.emitting = false
		trail.reparent(G.world, false)
		trail.global_position = gp
		var tw := trail.create_tween()
		tw.tween_interval(1.6)
		tw.tween_callback(trail.queue_free)
	queue_free()

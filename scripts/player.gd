class_name Player
extends CharacterBody3D
## Игрок: движение, три оружия, суперудар (как у Супермена), удар об землю, двойной прыжок.

const WALK := 7.5
const SPRINT := 12.0
const JUMP := 8.0
const GRAVITY := 24.0
const WEAPON_NAMES := ["ПЛАЗМЕННЫЙ БЛАСТЕР", "ЛАЗЕРНЫЙ РЕЗАК", "РАКЕТОМЁТ"]

var max_hp := 100.0
var hp := 100.0
var dead := false
var god := false

var head: Node3D
var cam: Camera3D
var vm: ViewModel
var yaw := 0.0
var pitch := 0.0
var sens := 1.0
var base_fov := 90.0

var weapon := 0
var fire_cd := 0.0
var heat := 0.0
var overheated := false
var energy := 1.0
var energy_idle := 0.0
var laser_on := false
var rockets := 8
var max_rockets := 16

var sprinting := false
var jumps_left := 1
var knock := Vector3.ZERO
var shake := 0.0
var since_damage := 99.0
var step_t := 0.0
var _was_floor := true
var _fall_speed := 0.0

# суперудар
var punch_charge := -1.0
var punch_cd := 0.0
var punch_time := 0.0
var punch_dir := Vector3.ZERO
var punch_power := 0.0
var punch_hit := false
# удар об землю
var slam_cd := 0.0
var slamming := false

var laser_beam: MeshInstance3D
var laser_beam_mat: StandardMaterial3D
var laser_light: OmniLight3D
var laser_sparks: CPUParticles3D
var laser_snd: AudioStreamPlayer
var charge_snd: AudioStreamPlayer
var _noise := FastNoiseLite.new()
var _nt := 0.0

# для автотеста: программные нажатия
var bot_fire := false
var bot_punch := false
var bot_move := Vector2.ZERO


func _ready() -> void:
	G.player = self
	collision_layer = G.L_PLAYER
	collision_mask = G.L_WORLD | G.L_ROBOT | G.L_PROPS
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	head = Node3D.new()
	add_child(head)
	head.position.y = 1.62
	cam = Camera3D.new()
	cam.near = 0.02
	cam.keep_aspect = Camera3D.KEEP_WIDTH   # FOV по горизонтали, как в обычных шутерах
	cam.far = 600.0
	head.add_child(cam)
	cam.current = true
	vm = ViewModel.new()
	vm.player = self
	cam.add_child(vm)

	_noise.frequency = 2.0
	laser_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.03
	bm.bottom_radius = 0.03
	bm.height = 1.0
	bm.radial_segments = 8
	laser_beam.mesh = bm
	laser_beam_mat = StandardMaterial3D.new()
	laser_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	laser_beam_mat.albedo_color = Color(3.0, 0.6, 0.3, 1.0)
	laser_beam.material_override = laser_beam_mat
	laser_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser_beam.top_level = true
	laser_beam.visible = false
	add_child(laser_beam)
	laser_light = OmniLight3D.new()
	laser_light.light_color = Color(1.0, 0.35, 0.15)
	laser_light.light_energy = 0.0
	laser_light.omni_range = 4.0
	laser_light.top_level = true
	add_child(laser_light)
	laser_sparks = CPUParticles3D.new()
	laser_sparks.amount = 30
	laser_sparks.lifetime = 0.4
	laser_sparks.local_coords = false
	var spm := BoxMesh.new()
	spm.size = Vector3(0.02, 0.02, 0.1)
	spm.material = Fx.glow_mat(Color(1.0, 0.6, 0.2), 9.0)
	laser_sparks.mesh = spm
	laser_sparks.spread = 70.0
	laser_sparks.initial_velocity_min = 2.0
	laser_sparks.initial_velocity_max = 6.0
	laser_sparks.gravity = Vector3(0, -12, 0)
	laser_sparks.emitting = false
	laser_sparks.top_level = true
	add_child(laser_sparks)
	laser_snd = AudioStreamPlayer.new()
	laser_snd.stream = Sfx.streams["laser_loop"]
	laser_snd.volume_db = -8.0
	add_child(laser_snd)
	charge_snd = AudioStreamPlayer.new()
	charge_snd.stream = Sfx.streams["charge"]
	charge_snd.volume_db = -6.0
	add_child(charge_snd)
	apply_settings()


func apply_settings() -> void:
	sens = G.settings.sensitivity
	base_fov = G.settings.fov
	if cam:
		cam.fov = base_fov


# ================================================================ ввод

func _unhandled_input(e: InputEvent) -> void:
	if dead or not G.playing:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = e.relative
		yaw -= rel.x * 0.0022 * sens
		pitch = clamp(pitch - rel.y * 0.0022 * sens, deg_to_rad(-88), deg_to_rad(88))
		vm.add_sway(rel)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select((weapon + 2) % 3)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select((weapon + 1) % 3)
	if e.is_action_pressed("weapon_1"):
		_select(0)
	elif e.is_action_pressed("weapon_2"):
		_select(1)
	elif e.is_action_pressed("weapon_3"):
		_select(2)
	elif e.is_action_pressed("slam"):
		_start_slam()


func _select(i: int) -> void:
	if i == weapon:
		return
	weapon = i
	vm.switch_to(i)
	_laser_off()
	if G.hud:
		G.hud.weapon_changed(WEAPON_NAMES[i])


# ================================================================ физика

func _physics_process(delta: float) -> void:
	if dead:
		velocity.y -= GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0, 10 * delta)
		velocity.z = move_toward(velocity.z, 0, 10 * delta)
		move_and_slide()
		return

	rotation.y = yaw
	head.rotation.x = pitch
	since_damage += delta
	fire_cd -= delta
	punch_cd -= delta
	slam_cd -= delta

	if since_damage > 4.0 and hp < max_hp:
		hp = min(hp + 9.0 * delta, max_hp)

	if global_position.y < -30.0:
		global_position = Vector3(0, 3, 0)
		velocity = Vector3.ZERO

	var active: bool = G.playing
	var input := Vector2.ZERO
	if active:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if bot_move != Vector2.ZERO:
			input = bot_move
	var wish := (transform.basis * Vector3(input.x, 0, input.y))
	wish.y = 0
	wish = wish.normalized() * min(input.length(), 1.0)
	sprinting = active and Input.is_action_pressed("sprint") and input.y < 0.0

	if punch_time > 0.0:
		_punch_move(delta)
	elif slamming:
		_slam_move(delta)
	else:
		var on_floor := is_on_floor()
		var spd := SPRINT if sprinting else WALK
		if punch_charge >= 0.0:
			spd *= 0.45
		var accel := 14.0 if on_floor else 3.5
		var target := wish * spd
		velocity.x = lerp(velocity.x, target.x, clamp(accel * delta, 0.0, 1.0))
		velocity.z = lerp(velocity.z, target.z, clamp(accel * delta, 0.0, 1.0))
		if not on_floor:
			velocity.y -= GRAVITY * delta
			_fall_speed = min(_fall_speed, velocity.y)
		else:
			jumps_left = 1
		if active and Input.is_action_just_pressed("jump"):
			if on_floor:
				velocity.y = JUMP
			elif jumps_left > 0:
				jumps_left -= 1
				velocity.y = JUMP * 0.95
				Fx.sparks(global_position, Vector3.DOWN, 16, 6.0, Color(0.4, 0.8, 1.0))
				Sfx.play2d("whoosh", -6.0, 1.4)
		velocity += knock
		knock = Vector3.ZERO
		move_and_slide()
		_push_props()
		# приземление
		var now_floor := is_on_floor()
		if now_floor and not _was_floor and _fall_speed < -9.0:
			add_shake(clamp(-_fall_speed / 40.0, 0.0, 0.5))
			Sfx.play2d("step", -2.0, 0.8)
		if now_floor:
			_fall_speed = 0.0
		_was_floor = now_floor
		# шаги
		var hv := Vector2(velocity.x, velocity.z).length()
		if now_floor and hv > 1.0:
			step_t -= delta * hv
			if step_t <= 0.0:
				step_t = 2.6
				Sfx.play2d("step", -14.0, randf_range(1.2, 1.5))

	if active:
		_weapons(delta)
		_punch_input(delta)
	_camera(delta)


func _push_props() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o = c.get_collider()
		if o is RigidBody3D and not o.freeze:
			var push := -c.get_normal()
			push.y = 0
			o.apply_impulse(push * 2.5 * clamp(o.mass / 20.0, 0.2, 2.0), c.get_position() - o.global_position)


# ================================================================ оружие

func _aim_point(dist: float = 300.0) -> Vector3:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var hit := G.ray(from, from + dir * dist, Projectile.PLAYER_MASK, [get_rid()], true)
	return hit.position if not hit.is_empty() else from + dir * dist


func _muzzle() -> Vector3:
	var m := vm.muzzle_world()
	# если ствол «в стене» — стреляем из камеры
	var blocked := G.ray(cam.global_position, m, G.L_WORLD | G.L_PROPS, [get_rid()], false)
	return cam.global_position if not blocked.is_empty() else m


func _weapons(delta: float) -> void:
	var trigger := Input.is_action_pressed("fire") or bot_fire
	var busy := vm.is_switching() or punch_charge >= 0.0 or punch_time > 0.0

	# перегрев бластера
	heat = max(heat - delta * (0.55 if not overheated else 0.4), 0.0)
	if overheated and heat < 0.25:
		overheated = false

	# энергия лазера
	if not laser_on:
		energy_idle += delta
		if energy_idle > 0.35:
			energy = min(energy + delta * 0.3, 1.0)

	if busy or not trigger:
		_laser_off()
		return

	match weapon:
		0:
			if fire_cd <= 0.0 and not overheated:
				fire_cd = 0.105
				heat += 0.06
				if heat >= 1.0:
					heat = 1.0
					overheated = true
					Sfx.play2d("overheat", -4.0)
				var aim := _aim_point()
				var m := _muzzle()
				var moving := Vector2(velocity.x, velocity.z).length() / WALK
				var spread := 0.006 + moving * 0.006 + heat * 0.01
				var dir := (aim - m).normalized()
				dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
				Projectile.player_bolt(m, dir, 15.0)
				vm.add_kick(0.35)
				add_shake(0.05)
				Sfx.play2d("blaster", -9.0, randf_range(0.92, 1.1))
				Fx.flash(m, Color(0.3, 0.8, 1.0), 2.5, 4.0, 0.06)
		1:
			if energy > 0.02:
				_laser(delta)
			else:
				_laser_off()
		2:
			if fire_cd <= 0.0 and rockets > 0:
				fire_cd = 0.9
				rockets -= 1
				var aim := _aim_point()
				var m := _muzzle()
				Projectile.rocket_shot(m, (aim - m).normalized())
				vm.add_kick(1.4)
				add_shake(0.35)
				knockback(cam.global_basis.z * 3.0)
				Sfx.play2d("rocket", -2.0, randf_range(0.95, 1.05))
				Fx.flash(m, Color(1.0, 0.6, 0.2), 5.0, 6.0, 0.15)
				Fx.smoke(m + cam.global_basis.z * 0.8, 5, 0.5, 1.2, Color(0.6, 0.6, 0.6))
				get_tree().create_timer(0.45, false).timeout.connect(func(): Sfx.play2d("reload", -8.0))
			elif fire_cd <= 0.0 and rockets <= 0:
				fire_cd = 0.4
				Sfx.play2d("hit", -10.0, 0.5)
				if G.hud:
					G.hud.popup("НЕТ РАКЕТ", 0)


func _laser(delta: float) -> void:
	if not laser_on:
		laser_on = true
		laser_snd.play()
		laser_beam.visible = true
		laser_sparks.emitting = true
	energy = max(energy - delta * 0.24, 0.0)
	energy_idle = 0.0
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var to := from + dir * 120.0
	var hit := G.ray(from, to, Projectile.PLAYER_MASK, [get_rid()], true)
	var end := to
	if not hit.is_empty():
		end = hit.position
		G.apply_hit(hit.collider, 120.0 * delta, end, dir, 6.0)
		laser_sparks.global_position = end
		laser_sparks.direction = hit.normal
		laser_light.global_position = end + hit.normal * 0.3
		laser_light.light_energy = 4.0
		laser_sparks.emitting = true
	else:
		laser_sparks.emitting = false
		laser_light.light_energy = 0.0
	var m := vm.muzzle_world()
	var length := m.distance_to(end)
	laser_beam.global_position = (m + end) * 0.5
	var b := Basis()
	var y := (end - m).normalized()
	var x = y.cross(Vector3.UP if abs(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var w := 1.0 + sin(Time.get_ticks_msec() * 0.08) * 0.25
	b = Basis(x * w, y * length, z * w)
	laser_beam.global_basis = b
	vm.add_kick(0.02)
	add_shake(0.015)


func _laser_off() -> void:
	if not laser_on:
		return
	laser_on = false
	laser_beam.visible = false
	laser_light.light_energy = 0.0
	laser_sparks.emitting = false
	laser_snd.stop()


# ================================================================ суперудар

func _punch_input(delta: float) -> void:
	var held := Input.is_action_pressed("punch") or bot_punch
	if punch_time > 0.0 or slamming:
		return
	if punch_charge < 0.0:
		if held and punch_cd <= 0.0:
			punch_charge = 0.0
			charge_snd.play()
			_laser_off()
	else:
		punch_charge = min(punch_charge + delta * 1.4, 1.0)
		vm.punch_state = max(punch_charge, 0.05)
		add_shake(0.01 * punch_charge)
		if not held:
			_launch_punch()


func _launch_punch() -> void:
	punch_power = clamp(punch_charge, 0.25, 1.0)
	punch_charge = -1.0
	charge_snd.stop()
	punch_time = 0.18 + 0.22 * punch_power
	punch_dir = -cam.global_basis.z
	if is_on_floor() and punch_dir.y < 0.0:
		punch_dir.y *= 0.3
		punch_dir = punch_dir.normalized()
	punch_hit = false
	punch_cd = 1.6
	vm.punch_state = 2.0
	Sfx.play2d("whoosh", 0.0, 0.8)
	add_shake(0.2)


func _punch_move(delta: float) -> void:
	punch_time -= delta
	var spd := 22.0 + 26.0 * punch_power
	velocity = punch_dir * spd
	# ищем цель перед кулаком
	var center := global_position + Vector3(0, 1.2, 0) + punch_dir * 1.1
	var q := PhysicsShapeQueryParameters3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.9
	q.shape = sp
	q.transform = Transform3D(Basis(), center)
	q.collide_with_areas = true
	q.collision_mask = G.L_HITBOX | G.L_PROPS
	q.exclude = [get_rid()]
	var res := get_world_3d().direct_space_state.intersect_shape(q, 8)
	if res.size() > 0:
		_punch_impact(center)
		return
	move_and_slide()
	if get_slide_collision_count() > 0:
		var c := get_slide_collision(0)
		if c.get_normal().dot(punch_dir) < -0.5:
			_punch_impact(c.get_position())
			return
	if punch_time <= 0.0:
		vm.punch_state = 0.0
		velocity *= 0.35


func _punch_impact(point: Vector3) -> void:
	punch_time = 0.0
	vm.punch_state = 0.0
	velocity = -punch_dir * 5.0 + Vector3.UP * 2.0
	var p := punch_power
	_shockwave(point, 2.6 + 1.8 * p, 120.0 + 280.0 * p, 900.0 + 1700.0 * p, punch_dir)
	Fx.flash(point, Color(0.5, 0.8, 1.0), 10.0, 10.0, 0.3)
	Fx.sparks(point, -punch_dir, 40, 14.0, Color(0.6, 0.9, 1.0))
	Fx.dust(point, 0.9)
	Sfx.play2d("impact", 2.0, randf_range(0.9, 1.1))
	add_shake(0.6 + 0.4 * p)
	G.hitstop(0.05 + 0.07 * p)


# ================================================================ удар об землю

func _start_slam() -> void:
	if is_on_floor() or slamming or slam_cd > 0.0 or punch_time > 0.0:
		return
	slamming = true
	velocity = Vector3(velocity.x * 0.2, -46.0, velocity.z * 0.2)
	Sfx.play2d("whoosh", 0.0, 0.6)


func _slam_move(_delta: float) -> void:
	velocity.y = -46.0
	move_and_slide()
	if is_on_floor():
		slamming = false
		slam_cd = 3.0
		var pos := global_position
		_shockwave(pos + Vector3.UP * 0.3, 6.5, 140.0, 1600.0, Vector3.ZERO)
		Fx.explosion(pos, 3.0, false)
		Fx.dust(pos, 2.0)
		Sfx.play2d("impact", 4.0, 0.7)
		add_shake(1.0)
		G.hitstop(0.08)


func _shockwave(center: Vector3, radius: float, dmg: float, force: float, bias: Vector3) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	q.shape = sp
	q.transform = Transform3D(Basis(), center)
	q.collide_with_areas = true
	q.collision_mask = G.L_HITBOX | G.L_PROPS | G.L_DEBRIS
	var res := get_world_3d().direct_space_state.intersect_shape(q, 256)
	var robots := {}
	for r in res:
		var c = r.collider
		if c == null or not is_instance_valid(c):
			continue
		var cp: Vector3 = c.global_position
		var dist := cp.distance_to(center)
		var fall: float = clamp(1.0 - dist / radius, 0.25, 1.0)
		var out := (cp - center)
		out = out.normalized() if out.length() > 0.01 else Vector3.UP
		var dir := (out + bias * 1.5 + Vector3.UP * 0.5).normalized()
		if c is Hitbox:
			c.take_hit(dmg * fall, cp, dir, force * fall)
			if not robots.has(c.robot) and is_instance_valid(c.robot):
				robots[c.robot] = true
				c.robot.knockback(dir * (10.0 + force * 0.01) * fall)
		elif c.has_method("take_hit"):
			c.take_hit(dmg * fall * 1.5, cp, dir, force * fall)
		elif c is RigidBody3D and not c.freeze:
			c.apply_central_impulse(dir * c.mass * (6.0 + force * 0.004) * fall)


# ================================================================ урон

func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead or god:
		return
	hp -= amount
	since_damage = 0.0
	add_shake(clamp(amount / 30.0, 0.15, 0.6))
	Sfx.play2d("hurt", -4.0, randf_range(0.9, 1.1))
	if G.hud:
		var to := from_pos - global_position
		var local := transform.basis.inverse() * to
		G.hud.damage(atan2(local.x, -local.z), amount)
	if hp <= 0.0:
		hp = 0.0
		_die()


func heal(a: float) -> void:
	hp = min(hp + a, max_hp)


func knockback(v: Vector3) -> void:
	knock += v


func _die() -> void:
	dead = true
	_laser_off()
	charge_snd.stop()
	vm.visible = false
	var t := create_tween()
	t.tween_property(head, "position:y", 0.3, 0.6).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(head, "rotation:z", 0.9, 0.6)
	if G.main:
		G.main.game_over()


# ================================================================ камера

func add_shake(a: float) -> void:
	shake = min(shake + a, 1.2)


func _camera(delta: float) -> void:
	shake = max(shake - delta * 1.8, 0.0)
	_nt += delta * 30.0
	var s2 := shake * shake
	cam.rotation = Vector3(
		_noise.get_noise_2d(_nt, 0) * 0.08 * s2,
		_noise.get_noise_2d(0, _nt) * 0.08 * s2,
		_noise.get_noise_2d(_nt, _nt) * 0.12 * s2)
	var fov := base_fov
	var hv := Vector2(velocity.x, velocity.z).length()
	if sprinting and hv > 8.0:
		fov += 8.0
	if punch_charge >= 0.0:
		fov -= 10.0 * punch_charge
	if punch_time > 0.0:
		fov += 22.0
	if slamming:
		fov += 12.0
	cam.fov = lerp(cam.fov, fov, clamp(delta * 10.0, 0.0, 1.0))

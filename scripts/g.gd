extends Node
## Глобальное состояние игры: слои физики, ссылки на игрока/мир, очки, взрывы, обломки.

const L_WORLD := 1
const L_PLAYER := 2
const L_ROBOT := 4
const L_HITBOX := 8
const L_DEBRIS := 16
const L_PROPS := 32

const MAX_DEBRIS := 260

var player: Node = null
var world: Node3D = null
var hud: Node = null
var main: Node = null

var autostart := false
var autotest := false
var playing := false

var score := 0
var combo := 1.0
var combo_timer := 0.0
var kills := 0
var parts_ripped := 0
var best_score := 0

var settings := {
	"sensitivity": 1.0,
	"quality": 2,        # 0 низкое, 1 среднее, 2 высокое
	"fullscreen": true,
	"volume": 0.8,
	"fov": 90.0,
}

var _debris: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	autotest = "--autotest" in args or "--shots" in args or "--showcase" in args or "--vmshots" in args
	_setup_input()
	_load_settings()
	_apply_window()


## Управление задаётся кодом по физическим клавишам — работает на любой раскладке.
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "punch": [KEY_F, KEY_E],
		"slam": [KEY_Q, KEY_CTRL, KEY_C], "reload": [KEY_R], "pause": [KEY_ESCAPE, KEY_P],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "weapon_4": [KEY_4],
		"weapon_5": [KEY_5], "weapon_6": [KEY_6], "weapon_7": [KEY_7],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		for k in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
	var mb := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for a in mb:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		var e := InputEventMouseButton.new()
		e.button_index = mb[a]
		InputMap.action_add_event(a, e)


func _process(delta: float) -> void:
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 1.0
	# страховка: обломок, провалившийся под землю, возвращаем наверх
	for i in range(_debris.size() - 1, -1, -1):
		var d = _debris[i]
		if not is_instance_valid(d):
			_debris.remove_at(i)
		elif d.global_position.y < -0.6 and d is RigidBody3D and not d.freeze:
			d.global_position.y = 0.6
			d.linear_velocity = Vector3(d.linear_velocity.x, 0.0, d.linear_velocity.z) * 0.5
			lift_above_ground(d)


## Поднимает тело так, чтобы ни одна его форма не была ниже земли (y = 0).
func lift_above_ground(rb: Node3D) -> void:
	var lowest := 1e9
	for c in rb.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var t: Transform3D = rb.global_transform * c.transform
			var h: Vector3 = (c.shape as BoxShape3D).size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						lowest = min(lowest, (t * Vector3(h.x * sx, h.y * sy, h.z * sz)).y)
	if lowest < 0.02 and lowest > -50.0:
		rb.global_position.y += 0.02 - lowest


func reset_run() -> void:
	score = 0
	combo = 1.0
	combo_timer = 0.0
	kills = 0
	parts_ripped = 0
	_debris.clear()


func add_score(points: int, label: String = "") -> void:
	var gained := int(points * combo)
	score += gained
	combo = min(combo + 0.15, 5.0)
	combo_timer = 3.0
	if hud and label != "":
		hud.popup(label, gained)


# ---------------------------------------------------------------- обломки

func add_debris(body: RigidBody3D) -> void:
	_debris.append(body)
	while _debris.size() > MAX_DEBRIS:
		var old = _debris.pop_front()
		if is_instance_valid(old):
			_fade_out(old)


func _fade_out(node: Node3D) -> void:
	if node is RigidBody3D:
		node.collision_layer = 0
		node.collision_mask = 0
		node.freeze = true
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector3.ONE * 0.01, 0.4)
	t.tween_callback(node.queue_free)


# ---------------------------------------------------------------- урон

## Наносит удар по любому коллайдеру: роботу, стене, ящику или обломку.
func apply_hit(collider: Object, dmg: float, pos: Vector3, dir: Vector3, force: float) -> void:
	if collider == null or not is_instance_valid(collider):
		return
	if collider.has_method("take_hit"):
		collider.take_hit(dmg, pos, dir, force)
	elif collider is RigidBody3D and not collider.freeze:
		collider.apply_impulse(dir.normalized() * force, pos - collider.global_position)


## Взрыв: урон, отрывание конечностей, разрушение стен, импульс по физике.
func explode(pos: Vector3, radius: float, damage: float, force: float, hurts_player: float = 0.35, big: bool = true) -> void:
	if world == null:
		return
	Fx.explosion(pos, radius, big)
	Sfx.play3d("explosion" if big else "boom_small", pos, 4.0 if big else 0.0, randf_range(0.85, 1.1))
	if player and is_instance_valid(player):
		var d: float = player.global_position.distance_to(pos)
		player.add_shake(clamp(1.4 - d / (radius * 4.0), 0.0, 1.0) * (1.0 if big else 0.5))

	var space := world.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	q.shape = sphere
	q.transform = Transform3D(Basis(), pos)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.collision_mask = L_PLAYER | L_HITBOX | L_DEBRIS | L_PROPS
	var results := space.intersect_shape(q, 256)
	var knocked := {}
	for r in results:
		var c = r.collider
		if c == null or not is_instance_valid(c):
			continue
		var cpos: Vector3 = c.global_position
		var dist := cpos.distance_to(pos)
		var fall: float = clamp(1.0 - dist / radius, 0.15, 1.0)
		var dir := (cpos - pos)
		if dir.length() < 0.01:
			dir = Vector3.UP
		dir = dir.normalized()
		var push := (dir + Vector3.UP * 0.6).normalized()
		if c == player:
			if hurts_player > 0.0:
				player.take_damage(damage * fall * hurts_player * 0.35, pos)
			player.knockback(push * force * fall * 0.06)
		elif c is Hitbox:
			c.take_hit(damage * fall, cpos, push, force * fall)
			if not knocked.has(c.robot):
				knocked[c.robot] = true
				if is_instance_valid(c.robot):
					c.robot.knockback(push * force * fall * 0.05)
		elif c.has_method("take_hit"):
			c.take_hit(damage * fall * (1.6 if dist < radius * 0.6 else 1.0), cpos, push, force * fall)
		elif c is RigidBody3D and not c.freeze:
			c.apply_impulse(push * force * fall * 0.6, Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)))


# ---------------------------------------------------------------- лучи

func ray(from: Vector3, to: Vector3, mask: int, exclude: Array = [], areas: bool = true) -> Dictionary:
	if world == null:
		return {}
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.collide_with_areas = areas
	q.hit_from_inside = false
	return space.intersect_ray(q)


# ---------------------------------------------------------------- время

func hitstop(duration: float, scale: float = 0.05) -> void:
	if autotest:
		return
	Engine.time_scale = scale
	get_tree().create_timer(duration, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func slowmo(duration: float, scale: float = 0.3) -> void:
	if autotest:
		return
	Engine.time_scale = scale
	get_tree().create_timer(duration, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


# ---------------------------------------------------------------- настройки

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		for k in settings.keys():
			settings[k] = cf.get_value("s", k, settings[k])
		best_score = cf.get_value("s", "best", 0)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("s", k, settings[k])
	cf.set_value("s", "best", best_score)
	cf.save("user://settings.cfg")


func _apply_window() -> void:
	if autotest or DisplayServer.get_name() == "headless":
		return
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	AudioServer.set_bus_volume_db(0, linear_to_db(max(settings.volume, 0.001)))


func apply_settings() -> void:
	_apply_window()
	if main and main.has_method("apply_quality"):
		main.apply_quality()
	if player and is_instance_valid(player):
		player.apply_settings()
	save_settings()

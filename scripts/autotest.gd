extends Node
## Автотест: запускается с аргументом `-- --autotest` (или `--shots` для скриншотов).
## Бот сам целится в роботов, стреляет всеми оружиями, бьёт, взрывает, потом выходит.

var t := 0.0
var shots := false
var shot_i := 0
var next_shot := 2.5
var max_robots := 0
var started_fps: Array = []
var _did := {}


func _ready() -> void:
	shots = "--shots" in OS.get_cmdline_user_args()
	G.main.start_game()
	G.player.god = true
	print("[autotest] старт, shots=", shots)


func _once(key: String) -> bool:
	if _did.has(key):
		return false
	_did[key] = true
	return true


func _nearest_robot() -> Robot:
	var best: Robot = null
	var bd := 1e9
	for n in G.main.get_children():
		if n is Robot and not n.dead and n.state == "active":
			var d: float = n.global_position.distance_to(G.player.global_position)
			if d < bd:
				bd = d
				best = n
	return best


## Целимся по очереди в слабые точки, потом в корпус.
func _target_point(r: Robot) -> Vector3:
	for n in r.parts:
		var pp: Dictionary = r.parts[n]
		if pp.alive and (pp.weak or pp.type in ["thigh", "rotor", "gun", "pod"]) and int(t * 2.0) % 3 != 0:
			return pp.node.global_position
	return r.body.global_position


func _aim_at(pos: Vector3) -> void:
	var p: Player = G.player
	var d := pos - p.cam.global_position
	p.yaw = atan2(-d.x, -d.z)
	var hd := Vector2(d.x, d.z).length()
	p.pitch = atan2(d.y, hd)


func _physics_process(delta: float) -> void:
	t += delta
	var p: Player = G.player
	var robots := 0
	for n in G.main.get_children():
		if n is Robot:
			robots += 1
	max_robots = max(max_robots, robots)

	var r := _nearest_robot()
	if r and is_instance_valid(r) and r.parts.body.alive:
		_aim_at(_target_point(r))
	p.bot_fire = false
	p.bot_punch = false
	p.bot_move = Vector2.ZERO

	if t > 3.0 and t < 17.0:
		# каждые 2 секунды — следующее оружие, через одно — с прицелом
		var wi := int((t - 3.0) / 2.0) % 7
		p.select(wi)
		p.bot_aim = wi % 2 == 0
		p.bot_fire = fmod(t, 0.2) < 0.1 or Player.WEAPONS[wi].auto
		if p.ammo[wi] == 0 and Player.WEAPONS[wi].has("mag"):
			p.reserve[wi] = 50
	elif t > 19.0 and t < 20.0:
		p.select(0)
		if r:
			# подходим к роботу и заряжаем суперудар
			p.global_position = r.global_position + (p.global_position - r.global_position).normalized() * 5.0
			p.global_position.y = max(p.global_position.y, 0.1)
		p.bot_punch = true
	elif t > 20.0 and t < 20.5:
		p.bot_punch = false
	elif t > 21.0 and t < 21.1:
		if _once("jump"):
			p.velocity.y = 12.0
	elif t > 21.5 and t < 21.6:
		if _once("slam"):
			p._start_slam()
	elif t > 22.0 and t < 22.1:
		if _once("bigboom"):
			# взрываем все стены и роботов
			for n in G.main.get_children():
				if n is DestructibleWall:
					G.explode(n.global_position + Vector3(0, 1.5, 0), 4.0, 200.0, 1800.0, 0.0, true)
	elif t > 23.0 and t < 23.1:
		if _once("wave2"):
			G.main._start_wave()
			G.main._start_wave()
	elif t > 26.0 and t < 32.0:
		p.select(6)
		p.ammo[6] = 1
		p.reserve[6] = 10
		p.bot_fire = fmod(t, 0.4) < 0.2
		p.bot_fire = true
	elif t > 32.0 and t < 32.1:
		if _once("killall"):
			for n in G.main.get_children():
				if n is Robot and not n.dead:
					G.explode(n.global_position + Vector3(0, 1.0, 0), 3.0, 900.0, 1500.0, 0.0, true)
	elif t > 34.0 and t < 34.1:
		if _once("die"):
			p.god = false
			p.take_damage(1000.0, p.global_position + Vector3(1, 0, 0))
	elif t > 37.0:
		if _once("end"):
			_report()

	if shots and t >= next_shot:
		next_shot += 2.0
		_shot()


func _shot() -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	var path := "user://shots/shot_%02d.png" % shot_i
	img.save_png(path)
	print("[autotest] скриншот ", ProjectSettings.globalize_path(path))
	shot_i += 1


func _report() -> void:
	var debris := 0
	for n in G.main.get_children():
		if n is RigidBody3D and not n.freeze:
			debris += 1
	print("[autotest] ===== ИТОГ =====")
	print("[autotest] волна: ", G.main.wave)
	print("[autotest] максимум роботов одновременно: ", max_robots)
	print("[autotest] убито: ", G.kills, "  деталей оторвано: ", G.parts_ripped, "  очки: ", G.score)
	print("[autotest] обломков на сцене: ", debris)
	print("[autotest] игрок мёртв: ", G.player.dead, "  game over: ", G.main.over)
	print("[autotest] FPS: ", Engine.get_frames_per_second())
	print("[autotest] OK")
	get_tree().quit(0)

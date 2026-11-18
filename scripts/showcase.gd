extends Node
## Витрина для проверки внешнего вида: `-- --showcase`.
## Ставит роботов перед камерой, ломает слабые точки и делает скриншоты.

var t := 0.0
var robots: Array = []
var step := 0


func _ready() -> void:
	Engine.max_physics_steps_per_frame = 24
	G.main.start_game()
	G.main.break_timer = 9999.0
	var p: Player = G.player
	p.god = true
	p.global_position = Vector3(0, 0.1, 22)
	p.yaw = 0.0
	p.pitch = 0.08
	var setup := [
		[Robot.Kind.CRAB, Vector3(-5.5, 0.0, 12.0)],
		[Robot.Kind.LEAPER, Vector3(1.0, 0.0, 9.0)],
		[Robot.Kind.HORNET, Vector3(-3.0, 5.0, 13.0)],
		[Robot.Kind.ROCKETEER, Vector3(5.0, 6.5, 12.0)],
	]
	for s in setup:
		var r := Robot.create(s[0])
		G.main.add_child(r)
		r.global_position = s[1]
		r.state = "show"
		r.rotation.y = 0.15
		r.velocity = Vector3.ZERO
		robots.append(r)


func _physics_process(delta: float) -> void:
	t += delta
	var p: Player = G.player
	if t > 1.5 and step == 0:
		step = 1
		_shot("a_intact")
	elif t > 1.8 and step == 1:
		step = 2
		p.select(0)
	elif t > 2.6 and step == 2:
		step = 3
		_shot("b_rifle")
		var crab: Robot = robots[0]
		var leaper: Robot = robots[1]
		var hornet: Robot = robots[2]
		var rock: Robot = robots[3]
		for n in ["knee_0", "knee_1"]:
			leaper.damage_part(n, 50, leaper.parts[n].node.global_position, Vector3(1, 0.3, 0), 300)
		crab.damage_part("knee_0", 50, crab.parts.knee_0.node.global_position, Vector3(1, 0.3, 0), 300)
		hornet.damage_part("eye", 50, hornet.parts.eye.node.global_position, Vector3(-1, 0.3, 0), 300)
		rock.damage_part("rotor_0", 50, rock.parts.rotor_0.node.global_position, Vector3(1, 0.3, 0), 300)
	elif t > 3.4 and step == 3:
		step = 4
		_shot("c_broken")
	elif t > 4.6 and step == 4:
		step = 5
		_shot("d_settled")
		for r in robots:
			if is_instance_valid(r) and not r.dead:
				r.state = "move" if not r.flyer else "fly"
		p.select(2)
		p.bot_aim = true
	elif t > 6.5 and step == 5:
		step = 6
		_shot("e_ads_minigun")
		p.bot_aim = false
		p.select(5)
	elif t > 7.5 and step == 6:
		step = 7
		_shot("f_launcher")
		var leaper: Robot = robots[1]
		if is_instance_valid(leaper) and not leaper.dead:
			leaper.die(Vector3(0, 0.3, -1), 900)
	elif t > 7.75 and step == 7:
		step = 8
		_shot("g_death")
	elif t > 9.0 and step == 8:
		step = 9
		_shot("h_after")
		p.select(3)
		p.yaw = PI
		p.pitch = 0.05
		p.global_position = Vector3(-6, 0.1, -10)
	elif t > 10.0 and step == 9:
		step = 10
		_shot("i_south_blaster")
		p.select(1)
		p.yaw = PI * 0.5
		p.pitch = 0.12
		p.global_position = Vector3(20, 0.1, 30)
	elif t > 11.0 and step == 10:
		step = 11
		_shot("j_west_shotgun")
		p.yaw = -2.4
		p.pitch = 0.35
		p.global_position = Vector3(-18, 3.6, -6)
		p.select(6)
	elif t > 12.0 and step == 11:
		step = 12
		_shot("k_sky_rpg")
		get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/show_%s.png" % name)
	print("[showcase] ", name)

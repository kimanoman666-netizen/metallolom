extends Node
## Режим витрины для проверки внешнего вида: `-- --showcase`.
## Ставит трёх роботов перед камерой, отстреливает им части и делает скриншоты.

var t := 0.0
var robots: Array = []
var step := 0


func _ready() -> void:
	G.main.start_game()
	G.main.break_timer = 9999.0
	var p: Player = G.player
	p.god = true
	p.global_position = Vector3(0, 0.1, 18)
	p.yaw = 0.0
	p.pitch = -0.05
	var kinds := [Robot.Kind.SCOUT, Robot.Kind.SOLDIER, Robot.Kind.BRUTE]
	for i in 3:
		var r := Robot.create(kinds[i])
		G.main.add_child(r)
		r.global_position = Vector3(-3.2 + i * 3.2, 0.0, 11.0)
		r.state = "active"
		r.land_timer = 9999.0
		r.thruster.queue_free()
		r.thruster = null
		r.rotation.y = PI
		robots.append(r)


func _physics_process(delta: float) -> void:
	t += delta
	for r in robots:
		if is_instance_valid(r) and not r.dead:
			r.rotation.y = PI
	if t > 2.0 and step == 0:
		step = 1
		_shot("a_intact")
	elif t > 2.5 and step == 1:
		step = 2
		var s: Robot = robots[0]
		s.damage_part("arm_l", 200, s.parts.arm_l.node.global_position, Vector3(-1, 0.3, 0), 300)
		var so: Robot = robots[1]
		so.damage_part("head", 200, so.parts.head.node.global_position, Vector3(0.3, 0.5, 1), 300)
		so.damage_part("fore_r", 200, so.parts.fore_r.node.global_position, Vector3(1, 0.2, 0.5), 300)
		var b: Robot = robots[2]
		b.damage_part("thigh_r", 400, b.parts.thigh_r.node.global_position, Vector3(1, 0.2, 0), 400)
	elif t > 3.3 and step == 2:
		step = 3
		_shot("b_ripped")
	elif t > 4.5 and step == 3:
		step = 4
		_shot("c_settled")
		var so: Robot = robots[1]
		so.die(Vector3(0, 0.3, -1), 800)
	elif t > 4.75 and step == 4:
		step = 5
		_shot("d_death")
	elif t > 6.0 and step == 5:
		step = 6
		_shot("e_after")
		get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/show_%s.png" % name)
	print("[showcase] ", name)

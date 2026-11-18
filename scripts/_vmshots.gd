extends Node
## Крупные кадры рук и оружия: `-- --vmshots`.
var t := 0.0
var idx := 0
var phase := 0
func _ready():
	Engine.max_physics_steps_per_frame = 24
	G.main.start_game()
	G.main.break_timer = 9999.0
	var p: Player = G.player
	p.god = true
	p.global_position = Vector3(-8, 0.1, 20)
	p.yaw = 0.6
	p.pitch = -0.05
func _physics_process(delta):
	t += delta
	var p: Player = G.player
	if phase == 0 and t > 0.3:
		p.select(idx)
		p.bot_aim = false
		phase = 1
		t = 0.0
	elif phase == 1 and t > 1.0:
		phase = 2
		_shot("vm_%d" % idx)
	elif phase == 2 and t > 1.3:
		if idx == 0 or idx == 5:
			p.bot_aim = true
			phase = 3
			t = 0.0
		else:
			_next()
	elif phase == 3 and t > 1.0:
		phase = 4
		_shot("vm_%d_ads" % idx)
	elif phase == 4 and t > 1.3:
		_next()
func _next():
	idx += 1
	phase = 0
	t = 0.0
	if idx >= 7:
		get_tree().quit()
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s.png" % name)
	print("[vm] ", name)

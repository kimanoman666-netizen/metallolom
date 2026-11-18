extends Node3D
## Корневой узел: окружение, арена, волны роботов, состояния игры.

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var player: Player
var hud: HUD
var menu_cam: Camera3D
var menu_t := 0.0

var concrete_tex: Texture2D
var wood_tex: Texture2D
var rust_tex: Texture2D
var concrete_nrm: Texture2D

var spawn_points: Array = []
var wave := 0
var to_spawn: Array = []
var spawn_timer := 0.0
var alive := 0
var break_timer := -1.0
var paused := false
var over := false
var lamps: Array = []


func _ready() -> void:
	G.main = self
	G.world = self
	G.reset_run()
	_make_textures()
	_make_environment()
	Level.build(self)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.2, 18)
	player.yaw = 0.0
	menu_cam = Camera3D.new()
	menu_cam.fov = 70
	menu_cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(menu_cam)
	hud = HUD.new()
	add_child(hud)
	apply_quality()
	if G.autotest:
		var script_path := "res://scripts/showcase.gd" if "--showcase" in OS.get_cmdline_user_args() else "res://scripts/autotest.gd"
		add_child(load(script_path).new())
		return
	if G.autostart:
		G.autostart = false
		start_game()
	else:
		to_menu_state()


func _make_textures() -> void:
	concrete_tex = _noise_tex(0.06, [Color(0.36, 0.35, 0.33), Color(0.52, 0.5, 0.47), Color(0.44, 0.43, 0.41)], 3)
	concrete_nrm = _noise_tex(0.12, [], 4, true)
	rust_tex = _noise_tex(0.035, [Color(0.18, 0.09, 0.05), Color(0.42, 0.2, 0.08), Color(0.3, 0.3, 0.3)], 5)
	wood_tex = _noise_tex(0.02, [Color(0.45, 0.31, 0.17), Color(0.58, 0.42, 0.24)], 6)


func _noise_tex(freq: float, colors: Array, seed_v: int, normal: bool = false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 5
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	elif colors.size() > 0:
		var g := Gradient.new()
		var offs := PackedFloat32Array()
		var cols := PackedColorArray()
		for i in colors.size():
			offs.append(float(i) / max(colors.size() - 1, 1))
			cols.append(colors[i])
		g.offsets = offs
		g.colors = cols
		t.color_ramp = g
	t.generate_mipmaps = true
	return t


func _make_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.09, 0.12, 0.2)
	sm.sky_horizon_color = Color(0.78, 0.5, 0.32)
	sm.ground_bottom_color = Color(0.05, 0.04, 0.04)
	sm.ground_horizon_color = Color(0.5, 0.28, 0.16)
	sm.sun_angle_max = 20.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.45, 0.4)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_blur = 1.5
	sun.rotation_degrees = Vector3(-28, -40, 0)
	add_child(sun)


func apply_quality() -> void:
	if env == null:
		return
	var q: int = G.settings.quality
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 2.2
	env.ssao_radius = 1.2
	env.ssil_enabled = q >= 2
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 48
	env.volumetric_fog_enabled = q >= 2
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color(0.9, 0.75, 0.6)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0 if q >= 2 else 80.0
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_4X if q >= 2 else (Viewport.MSAA_2X if q == 1 else Viewport.MSAA_DISABLED)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_debanding = q >= 1
	RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 2 else 2048, true)
	for l in lamps:
		if is_instance_valid(l):
			l.shadow_enabled = q >= 2


# ================================================================ состояния

func to_menu_state() -> void:
	G.playing = false
	over = false
	menu_cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu()


func start_game() -> void:
	G.reset_run()
	G.playing = true
	over = false
	player.cam.current = true
	player.yaw = 0.0
	player.pitch = 0.0
	if not G.autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_game()
	wave = 0
	break_timer = 2.0
	hud.announce_text("ПРИГОТОВЬСЯ", Color.WHITE, 1.2)


func restart() -> void:
	G.autostart = true
	_unpause()
	get_tree().reload_current_scene()


func to_menu() -> void:
	G.autostart = false
	_unpause()
	get_tree().reload_current_scene()


func _unpause() -> void:
	paused = false
	get_tree().paused = false
	Engine.time_scale = 1.0


func set_paused(v: bool) -> void:
	if over or not G.playing and v:
		return
	paused = v
	get_tree().paused = v
	hud.show_pause(v)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if v else Input.MOUSE_MODE_CAPTURED


func game_over() -> void:
	if over:
		return
	over = true
	G.playing = false
	if G.score > G.best_score:
		G.best_score = G.score
	G.save_settings()
	G.slowmo(1.2, 0.25)
	get_tree().create_timer(1.2, true, false, true).timeout.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.show_game_over(wave))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and G.playing and not paused and not G.autotest:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and G.playing and not over and not G.autotest:
		set_paused(true)


# ================================================================ волны

func _process(delta: float) -> void:
	if not G.playing:
		menu_t += delta * 0.08
		var r := 34.0
		menu_cam.global_position = Vector3(sin(menu_t) * r, 9.0 + sin(menu_t * 0.7) * 2.0, cos(menu_t) * r)
		menu_cam.look_at(Vector3(0, 2, 0))
		return
	if break_timer > 0.0:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
	if to_spawn.size() > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and alive < 10:
			spawn_timer = 0.7
			_spawn(to_spawn.pop_front())
	hud.set_wave(max(wave, 1), alive + to_spawn.size())


func _start_wave() -> void:
	wave += 1
	var list: Array = []
	var hornets := 2 + wave
	var crabs := 1 + int(wave / 2)
	var leapers := 0 if wave < 2 else 1 + int((wave - 2) / 3)
	var rocketeers := 0 if wave < 3 else 1 + int((wave - 3) / 2)
	for i in hornets:
		list.append(Robot.Kind.HORNET)
	for i in crabs:
		list.append(Robot.Kind.CRAB)
	for i in leapers:
		list.append(Robot.Kind.LEAPER)
	for i in rocketeers:
		list.append(Robot.Kind.ROCKETEER)
	list.shuffle()
	to_spawn = list
	spawn_timer = 0.5
	player.add_ammo(0.5)
	hud.announce_text("ВОЛНА %d" % wave, Color(1.0, 0.55, 0.1), 1.6)
	Sfx.play2d("alarm", -6.0)


func _spawn(k: int) -> void:
	var pts := spawn_points.duplicate()
	pts.shuffle()
	var pos: Vector3 = pts[0]
	for p in pts:
		if p.distance_to(player.global_position) > 18.0:
			pos = p
			break
	pos += Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	var r := Robot.create(k)
	add_child(r)
	var flyer: bool = Robot.KINDS[k].flyer
	r.global_position = pos + Vector3(0, 18.0 if flyer else 26.0, 0)
	r.rotation.y = randf() * TAU
	alive += 1


func on_robot_killed(_r: Node, pos: Vector3) -> void:
	alive -= 1
	if randf() < 0.22:
		drop_pickup(pos, 0 if randf() < 0.6 else 1)
	if alive <= 0 and to_spawn.is_empty() and G.playing and break_timer <= 0.0:
		G.slowmo(0.9, 0.3)
		var bonus := 250 * wave
		G.score += bonus
		hud.announce_text("ВОЛНА ЗАЧИЩЕНА", Color(0.4, 1.0, 0.5), 1.6)
		hud.popup("БОНУС ЗА ВОЛНУ", bonus)
		break_timer = 5.0
		drop_pickup(player.global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), 0)


func drop_pickup(pos: Vector3, kind: int) -> void:
	call_deferred("_drop", pos, kind)


func _drop(pos: Vector3, kind: int) -> void:
	Pickup.spawn(pos, kind)

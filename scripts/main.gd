extends Node3D
## Корневой узел: окружение, арена, волны роботов, состояния игры.

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var player: Player
var hud: HUD
var menu_cam: Camera3D
var menu_t := 0.0


var spawn_points: Array = []
var wave := 0
var to_spawn: Array = []
var spawn_timer := 0.0
var alive := 0
var break_timer := -1.0
var paused := false
var over := false


func _ready() -> void:
	G.main = self
	G.world = self
	G.reset_run()
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
		if "--vmshots" in OS.get_cmdline_user_args():
			script_path = "res://scripts/_vmshots.gd"
		add_child(load(script_path).new())
		return
	if G.autostart:
		G.autostart = false
		start_game()
	else:
		to_menu_state()


func _make_textures() -> void:
	pass


## Направление на солнце на HDRI-небе (найдено по самому яркому пикселю панорамы).
const SUN_YAW := 34.23
const SUN_ELEV := 47.86


func _make_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/sky/kloofendal_48d_partly_cloudy_puresky.hdr")
	pm.energy_multiplier = 0.55
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.62, 0.7, 0.8)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.75
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.92
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 2.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.0
	sun.light_angular_distance = 0.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)
	var yaw := deg_to_rad(SUN_YAW)
	var el := deg_to_rad(SUN_ELEV)
	var to_sun := Vector3(sin(yaw) * cos(el), sin(el), -cos(yaw) * cos(el))
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP)

	# пост-обработка «под камеру»: зерно, виньетка, хроматическая аберрация
	var post := CanvasLayer.new()
	post.layer = 5
	add_child(post)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float grain = 0.035;
uniform float vignette = 0.32;
uniform float aberration = 0.0016;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec3 col;
	col.r = texture(screen, uv + d * aberration * r2 * 4.0).r;
	col.g = texture(screen, uv).g;
	col.b = texture(screen, uv - d * aberration * r2 * 4.0).b;
	col *= 1.0 - vignette * smoothstep(0.1, 0.55, r2 * 1.6);
	float g = hash(uv * 1000.0 + fract(TIME * 7.13)) - 0.5;
	col += g * grain;
	COLOR = vec4(col, 1.0);
}
"""
	var pmat := ShaderMaterial.new()
	pmat.shader = sh
	rect.material = pmat
	post.add_child(rect)

	# реверберация на общем звуке: эхо от стен промзоны
	if AudioServer.get_bus_effect_count(0) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.55
		rev.damping = 0.6
		rev.wet = 0.12
		rev.dry = 1.0
		rev.spread = 0.8
		AudioServer.add_bus_effect(0, rev)
		var lim := AudioEffectHardLimiter.new()
		AudioServer.add_bus_effect(0, lim)


func apply_quality() -> void:
	if env == null:
		return
	var q: int = G.settings.quality
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 1.6
	env.ssao_radius = 1.0
	env.ssao_detail = 0.6
	env.ssil_enabled = q >= 2
	env.ssil_intensity = 0.7
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 48
	env.sdfgi_enabled = q >= 2
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_energy = 0.8
	env.volumetric_fog_enabled = q >= 1
	env.volumetric_fog_density = 0.0045
	env.volumetric_fog_albedo = Color(0.85, 0.9, 1.0)
	env.volumetric_fog_anisotropy = 0.75
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.15
	sun.directional_shadow_max_distance = 140.0 if q >= 2 else 80.0
	sun.light_volumetric_fog_energy = 1.4
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_4X if q >= 2 else (Viewport.MSAA_2X if q == 1 else Viewport.MSAA_DISABLED)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_debanding = q >= 1
		vp.mesh_lod_threshold = 1.0 if q >= 2 else 3.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 2 else 2048, true)


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

class_name HUD
extends CanvasLayer
## Интерфейс: прицел, здоровье, оружие, очки, всплывающие надписи, меню.

const ACCENT := Color(1.0, 0.55, 0.1)
const CYAN := Color(0.3, 0.85, 1.0)

var font: SystemFont
var font_title: SystemFont
var root: Control
var game_ui: Control
var crosshair: Control
var hp_bar: ProgressBar
var hp_label: Label
var weapon_label: Label
var ammo_label: Label
var ammo_bar: ProgressBar
var punch_bar: ProgressBar
var slam_bar: ProgressBar
var wave_label: Label
var left_label: Label
var score_label: Label
var combo_label: Label
var announce: Label
var popups: VBoxContainer
var vignette: ColorRect
var vig_mat: ShaderMaterial
var dmg_dirs: Control

var menu: Control
var pause_menu: Control
var settings_menu: Control
var over_menu: Control
var over_label: Label
var best_label: Label

var hit_t := 0.0
var hit_crit := false
var dmg_flash := 0.0
var dmg_marks: Array = []   # [угол, время]
var _settings_from := ""


func _ready() -> void:
	G.hud = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "DejaVu Sans", "Noto Sans"])
	font.font_weight = 600
	font_title = SystemFont.new()
	font_title.font_names = PackedStringArray(["Impact", "Bahnschrift", "Arial Black", "Arial", "DejaVu Sans"])
	font_title.font_weight = 900

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 22
	root.theme = th

	_build_vignette()
	_build_game_ui()
	_build_menus()


# ------------------------------------------------------------------ helpers

func _label(text: String, size: int, color: Color = Color.WHITE, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", max(4, size / 7))
	if title:
		l.add_theme_font_override("font", font_title)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	b.step = 0.001
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = Color(1, 1, 1, 0.15)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(2)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 58)
	b.add_theme_font_size_override("font_size", 26)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.08, 0.08, 0.09, 0.85)
	n.border_color = Color(1, 1, 1, 0.12)
	n.set_border_width_all(2)
	n.set_corner_radius_all(3)
	var h := n.duplicate()
	h.bg_color = Color(0.9, 0.45, 0.05, 0.95)
	h.border_color = Color(1, 0.8, 0.5, 0.8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_hover_color", Color.BLACK)
	b.pressed.connect(func():
		Sfx.play2d("hit", -8.0, 0.8)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play2d("hit", -16.0, 1.6))
	return b


func _panel_bg() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.02, 0.03, 0.72)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


# ------------------------------------------------------------------ сборка

func _build_vignette() -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float hurt = 0.0;
uniform float low = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.6, 1.0));
	float v = smoothstep(0.35, 0.95, d);
	float pulse = 0.6 + 0.4 * sin(TIME * 6.0);
	float a = v * (hurt * 0.85 + low * 0.55 * pulse) + v * v * 0.35;
	vec3 col = mix(vec3(0.0), vec3(0.6, 0.0, 0.0), clamp(hurt + low, 0.0, 1.0));
	COLOR = vec4(col, a);
}
"""
	vig_mat = ShaderMaterial.new()
	vig_mat.shader = sh
	vignette.material = vig_mat
	root.add_child(vignette)


func _build_game_ui() -> void:
	game_ui = Control.new()
	game_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(game_ui)

	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	game_ui.add_child(crosshair)

	dmg_dirs = Control.new()
	dmg_dirs.set_anchors_preset(Control.PRESET_CENTER)
	dmg_dirs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg_dirs.draw.connect(_draw_dmg_dirs)
	game_ui.add_child(dmg_dirs)

	# здоровье — слева снизу
	var hb := VBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hb.position = Vector2(40, -150)
	hb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	game_ui.add_child(hb)
	hp_label = _label("100", 54, Color.WHITE, true)
	hb.add_child(hp_label)
	hp_bar = _bar(Color(0.3, 0.95, 0.4), 320, 14)
	hb.add_child(hp_bar)
	var ab := HBoxContainer.new()
	ab.add_theme_constant_override("separation", 14)
	hb.add_child(ab)
	var pv := VBoxContainer.new()
	pv.add_child(_label("[F / ПКМ] СУПЕРУДАР", 14, Color(0.7, 0.85, 1.0)))
	punch_bar = _bar(CYAN, 150, 6)
	pv.add_child(punch_bar)
	ab.add_child(pv)
	var sv := VBoxContainer.new()
	sv.add_child(_label("[Q в воздухе] УДАР О ЗЕМЛЮ", 14, Color(1.0, 0.8, 0.6)))
	slam_bar = _bar(ACCENT, 150, 6)
	sv.add_child(slam_bar)
	ab.add_child(sv)

	# оружие — справа снизу
	var wb := VBoxContainer.new()
	wb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wb.position = Vector2(-420, -130)
	wb.custom_minimum_size = Vector2(380, 0)
	wb.alignment = BoxContainer.ALIGNMENT_END
	game_ui.add_child(wb)
	weapon_label = _label("ПЛАЗМЕННЫЙ БЛАСТЕР", 22, CYAN)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wb.add_child(weapon_label)
	ammo_label = _label("∞", 48, Color.WHITE, true)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wb.add_child(ammo_label)
	ammo_bar = _bar(CYAN, 380, 8)
	wb.add_child(ammo_bar)
	var keys := _label("1 БЛАСТЕР   2 ЛАЗЕР   3 РАКЕТЫ", 14, Color(1, 1, 1, 0.55))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wb.add_child(keys)

	# волна — сверху по центру
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-200, 20)
	top.custom_minimum_size = Vector2(400, 0)
	game_ui.add_child(top)
	wave_label = _label("ВОЛНА 1", 30, ACCENT, true)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(wave_label)
	left_label = _label("", 18, Color(1, 1, 1, 0.8))
	left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(left_label)

	# очки — справа сверху
	var sc := VBoxContainer.new()
	sc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sc.position = Vector2(-340, 20)
	sc.custom_minimum_size = Vector2(310, 0)
	game_ui.add_child(sc)
	score_label = _label("0", 44, Color.WHITE, true)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.add_child(score_label)
	combo_label = _label("", 24, ACCENT, true)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.add_child(combo_label)

	# всплывающие надписи
	popups = VBoxContainer.new()
	popups.set_anchors_preset(Control.PRESET_CENTER)
	popups.position = Vector2(-300, 60)
	popups.custom_minimum_size = Vector2(600, 0)
	popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(popups)

	announce = _label("", 84, ACCENT, true)
	announce.set_anchors_preset(Control.PRESET_CENTER)
	announce.position = Vector2(-600, -230)
	announce.custom_minimum_size = Vector2(1200, 100)
	announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce.modulate.a = 0.0
	game_ui.add_child(announce)
	game_ui.visible = false


func _build_menus() -> void:
	# ---------- главное меню
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	var grad := ColorRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	var gsh := Shader.new()
	gsh.code = """
shader_type canvas_item;
void fragment() {
	float x = UV.x;
	COLOR = vec4(0.0, 0.0, 0.0, mix(0.85, 0.0, smoothstep(0.0, 0.65, x)));
}
"""
	var gm := ShaderMaterial.new()
	gm.shader = gsh
	grad.material = gm
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(grad)
	var mv := VBoxContainer.new()
	mv.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	mv.position = Vector2(90, 0)
	mv.custom_minimum_size = Vector2(700, 0)
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 14)
	menu.add_child(mv)
	var t := _label("МЕТАЛЛОЛОМ", 120, ACCENT, true)
	mv.add_child(t)
	mv.add_child(_label("Разбери их на запчасти.", 26, Color(1, 1, 1, 0.75)))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	mv.add_child(sp)
	mv.add_child(_button("ИГРАТЬ", func(): G.main.start_game()))
	mv.add_child(_button("НАСТРОЙКИ", func(): _open_settings("menu")))
	mv.add_child(_button("ВЫХОД", func(): get_tree().quit()))
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 20)
	mv.add_child(sp2)
	best_label = _label("", 20, Color(1, 1, 1, 0.6))
	mv.add_child(best_label)
	mv.add_child(_label("WASD — движение   SHIFT — бег   ПРОБЕЛ — прыжок (двойной)\nЛКМ — огонь   1/2/3, колесо — оружие\nF или ПКМ (держать) — суперудар   Q в воздухе — удар о землю\nESC — пауза", 17, Color(1, 1, 1, 0.55)))

	# ---------- пауза
	pause_menu = Control.new()
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	root.add_child(pause_menu)
	pause_menu.add_child(_panel_bg())
	var pv := VBoxContainer.new()
	pv.set_anchors_preset(Control.PRESET_CENTER)
	pv.position = Vector2(-180, -200)
	pv.add_theme_constant_override("separation", 14)
	pause_menu.add_child(pv)
	var pt := _label("ПАУЗА", 72, ACCENT, true)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pt)
	pv.add_child(_button("ПРОДОЛЖИТЬ", func(): G.main.set_paused(false)))
	pv.add_child(_button("НАСТРОЙКИ", func(): _open_settings("pause")))
	pv.add_child(_button("ЗАНОВО", func(): G.main.restart()))
	pv.add_child(_button("В МЕНЮ", func(): G.main.to_menu()))

	# ---------- конец игры
	over_menu = Control.new()
	over_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_menu.visible = false
	root.add_child(over_menu)
	over_menu.add_child(_panel_bg())
	var ov := VBoxContainer.new()
	ov.set_anchors_preset(Control.PRESET_CENTER)
	ov.position = Vector2(-300, -260)
	ov.custom_minimum_size = Vector2(600, 0)
	ov.add_theme_constant_override("separation", 14)
	over_menu.add_child(ov)
	var ot := _label("ТЕБЯ РАЗОБРАЛИ", 72, Color(1, 0.2, 0.1), true)
	ot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov.add_child(ot)
	over_label = _label("", 26)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov.add_child(over_label)
	var bc := CenterContainer.new()
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 14)
	bc.add_child(bv)
	ov.add_child(bc)
	bv.add_child(_button("ЕЩЁ РАЗ", func(): G.main.restart()))
	bv.add_child(_button("В МЕНЮ", func(): G.main.to_menu()))

	# ---------- настройки
	settings_menu = Control.new()
	settings_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_menu.visible = false
	root.add_child(settings_menu)
	settings_menu.add_child(_panel_bg())
	var sv := VBoxContainer.new()
	sv.set_anchors_preset(Control.PRESET_CENTER)
	sv.position = Vector2(-260, -300)
	sv.custom_minimum_size = Vector2(520, 0)
	sv.add_theme_constant_override("separation", 12)
	settings_menu.add_child(sv)
	var st := _label("НАСТРОЙКИ", 60, ACCENT, true)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(st)
	sv.add_child(_slider("Чувствительность мыши", "sensitivity", 0.2, 3.0, 0.05))
	sv.add_child(_slider("Поле зрения (FOV)", "fov", 70.0, 110.0, 1.0))
	sv.add_child(_slider("Громкость", "volume", 0.0, 1.0, 0.05))
	var q := OptionButton.new()
	q.add_theme_font_size_override("font_size", 22)
	q.add_item("Графика: низкая")
	q.add_item("Графика: средняя")
	q.add_item("Графика: высокая")
	q.selected = G.settings.quality
	q.item_selected.connect(func(i):
		G.settings.quality = i
		G.apply_settings())
	sv.add_child(q)
	var fs := CheckBox.new()
	fs.text = "Полный экран"
	fs.button_pressed = G.settings.fullscreen
	fs.add_theme_font_size_override("font_size", 22)
	fs.toggled.connect(func(v):
		G.settings.fullscreen = v
		G.apply_settings())
	sv.add_child(fs)
	var bc2 := CenterContainer.new()
	bc2.add_child(_button("НАЗАД", _close_settings))
	sv.add_child(bc2)
	_refresh_best()


func _slider(title: String, key: String, mn: float, mx: float, step: float) -> Control:
	var v := VBoxContainer.new()
	var l := _label("%s: %s" % [title, _fmt(G.settings[key])], 20)
	v.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = G.settings[key]
	s.custom_minimum_size = Vector2(500, 24)
	s.value_changed.connect(func(val):
		G.settings[key] = val
		l.text = "%s: %s" % [title, _fmt(val)]
		G.apply_settings())
	v.add_child(s)
	return v


func _fmt(v) -> String:
	if v is float and v != floor(v):
		return "%.2f" % v
	return str(int(v))


func _open_settings(from: String) -> void:
	_settings_from = from
	menu.visible = false
	pause_menu.visible = false
	settings_menu.visible = true


func _close_settings() -> void:
	settings_menu.visible = false
	if _settings_from == "menu":
		menu.visible = true
	else:
		pause_menu.visible = true


func _refresh_best() -> void:
	if best_label:
		best_label.text = "Рекорд: %d" % G.best_score if G.best_score > 0 else ""


# ------------------------------------------------------------------ состояния

func show_menu() -> void:
	_refresh_best()
	menu.visible = true
	game_ui.visible = false
	pause_menu.visible = false
	over_menu.visible = false
	settings_menu.visible = false


func show_game() -> void:
	menu.visible = false
	pause_menu.visible = false
	over_menu.visible = false
	settings_menu.visible = false
	game_ui.visible = true


func show_pause(v: bool) -> void:
	pause_menu.visible = v
	settings_menu.visible = false


func show_game_over(wave: int) -> void:
	over_label.text = "Волна: %d     Очки: %d\nРоботов уничтожено: %d     Деталей оторвано: %d%s" % [
		wave, G.score, G.kills, G.parts_ripped, "\nНОВЫЙ РЕКОРД!" if G.score >= G.best_score and G.score > 0 else ""]
	over_menu.visible = true
	over_menu.modulate.a = 0.0
	create_tween().tween_property(over_menu, "modulate:a", 1.0, 0.8)


# ------------------------------------------------------------------ события

func popup(text: String, points: int) -> void:
	var l := _label(text + ("   +%d" % points if points > 0 else ""), 26, ACCENT if points > 0 else Color(0.5, 1.0, 0.6), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popups.add_child(l)
	if popups.get_child_count() > 5:
		popups.get_child(0).queue_free()
	l.scale = Vector2(1.3, 1.3)
	l.pivot_offset = Vector2(300, 16)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.12)
	t.tween_interval(1.1)
	t.tween_property(l, "modulate:a", 0.0, 0.4)
	t.tween_callback(l.queue_free)


func announce_text(text: String, color: Color = ACCENT, dur: float = 2.0) -> void:
	announce.text = text
	announce.add_theme_color_override("font_color", color)
	announce.modulate.a = 1.0
	announce.scale = Vector2(1.4, 1.4)
	announce.pivot_offset = Vector2(600, 50)
	var t := announce.create_tween()
	t.tween_property(announce, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(dur)
	t.tween_property(announce, "modulate:a", 0.0, 0.5)


func hitmarker(crit: bool) -> void:
	hit_t = 0.12
	hit_crit = crit


func damage(angle: float, amount: float) -> void:
	dmg_flash = min(dmg_flash + amount / 25.0, 1.0)
	dmg_marks.append([angle, 1.0])


func weapon_changed(_name: String) -> void:
	pass


func set_wave(w: int, left: int) -> void:
	wave_label.text = "ВОЛНА %d" % w
	left_label.text = "Роботов осталось: %d" % left if left > 0 else ""


# ------------------------------------------------------------------ кадр

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and G.main:
		if settings_menu.visible and G.main.paused:
			_close_settings()
		elif G.playing and not G.main.over:
			G.main.set_paused(not G.main.paused)


func _process(delta: float) -> void:
	hit_t = max(hit_t - delta, 0.0)
	dmg_flash = max(dmg_flash - delta * 1.5, 0.0)
	for m in dmg_marks:
		m[1] -= delta * 0.8
	dmg_marks = dmg_marks.filter(func(m): return m[1] > 0.0)
	crosshair.queue_redraw()
	dmg_dirs.queue_redraw()

	var p = G.player
	if p == null or not is_instance_valid(p):
		return
	vig_mat.set_shader_parameter("hurt", dmg_flash)
	vig_mat.set_shader_parameter("low", clamp(1.0 - p.hp / 35.0, 0.0, 1.0) if game_ui.visible else 0.0)
	if not game_ui.visible:
		return
	hp_label.text = str(int(ceil(p.hp)))
	hp_bar.value = p.hp / p.max_hp
	var hcol := Color(0.3, 0.95, 0.4) if p.hp > 35 else Color(1.0, 0.25, 0.15)
	(hp_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = hcol
	punch_bar.value = 1.0 - clamp(p.punch_cd / 1.6, 0.0, 1.0)
	slam_bar.value = 1.0 - clamp(p.slam_cd / 3.0, 0.0, 1.0)

	weapon_label.text = Player.WEAPON_NAMES[p.weapon]
	var fill := ammo_bar.get_theme_stylebox("fill") as StyleBoxFlat
	match p.weapon:
		0:
			ammo_label.text = "ПЕРЕГРЕВ!" if p.overheated else "∞"
			ammo_bar.value = p.heat
			fill.bg_color = CYAN.lerp(Color(1, 0.2, 0.05), p.heat)
			weapon_label.add_theme_color_override("font_color", CYAN)
		1:
			ammo_label.text = "%d%%" % int(p.energy * 100.0)
			ammo_bar.value = p.energy
			fill.bg_color = Color(1.0, 0.35, 0.2)
			weapon_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
		2:
			ammo_label.text = "%d / %d" % [p.rockets, p.max_rockets]
			ammo_bar.value = float(p.rockets) / p.max_rockets
			fill.bg_color = ACCENT
			weapon_label.add_theme_color_override("font_color", ACCENT)

	score_label.text = str(G.score)
	combo_label.text = "КОМБО x%.1f" % G.combo if G.combo > 1.01 else ""


func _draw_crosshair() -> void:
	var c := Color(1, 1, 1, 0.9)
	var p = G.player
	var gap := 6.0
	if p and is_instance_valid(p):
		gap += Vector2(p.velocity.x, p.velocity.z).length() * 0.6 + p.heat * 6.0
		if p.punch_charge >= 0.0:
			var r: float = 22.0 + 10.0 * (1.0 - p.punch_charge)
			crosshair.draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * p.punch_charge, 48, CYAN, 3.0, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		crosshair.draw_line(d * gap, d * (gap + 9.0), Color(0, 0, 0, 0.6), 4.0)
		crosshair.draw_line(d * gap, d * (gap + 9.0), c, 2.0)
	crosshair.draw_circle(Vector2.ZERO, 1.5, c)
	if hit_t > 0.0:
		var hc := Color(1.0, 0.3, 0.1) if hit_crit else Color.WHITE
		var k := 8.0 + (0.12 - hit_t) * 40.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			crosshair.draw_line(d.normalized() * k, d.normalized() * (k + 9.0), hc, 2.5)


func _draw_dmg_dirs() -> void:
	for m in dmg_marks:
		var a: float = m[0]
		var alpha: float = m[1]
		var dir := Vector2(sin(a), -cos(a))
		var center := dir * 140.0
		var perp := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([center + dir * 26.0, center + perp * 22.0, center - perp * 22.0])
		dmg_dirs.draw_colored_polygon(pts, Color(1.0, 0.15, 0.05, alpha * 0.8))

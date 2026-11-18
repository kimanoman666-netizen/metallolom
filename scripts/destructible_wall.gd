class_name DestructibleWall
extends Node3D
## Стена из блоков. Выбитые блоки падают; всё, что потеряло опору, обрушивается.

var nx := 8
var ny := 6
var cell := Vector3(0.62, 0.46, 0.38)
var mats: Array = []
var grid: Array = []          # grid[x][y] -> WallChunk или null
var _dirty := false
var _fx_cd := 0.0
var _snd_cd := 0.0
var color_a := Color(0.55, 0.53, 0.5)


func setup(w_cells: int, h_cells: int, c: Color, thick: float = 0.38) -> DestructibleWall:
	nx = w_cells
	ny = h_cells
	cell.z = thick
	color_a = c
	return self


func _ready() -> void:
	for i in 3:
		var m := StandardMaterial3D.new()
		var v := 1.0 - i * 0.08
		m.albedo_color = Color(color_a.r * v, color_a.g * v, color_a.b * v)
		m.roughness = 0.92
		if G.main and G.main.concrete_tex:
			m.albedo_texture = G.main.concrete_tex
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.6, 0.6, 0.6)
		mats.append(m)
	var mesh := BoxMesh.new()
	mesh.size = cell - Vector3(0.015, 0.015, 0.0)
	var shape := BoxShape3D.new()
	shape.size = cell - Vector3(0.004, 0.004, 0.0)
	grid.resize(nx)
	var x0 := -(nx - 1) * cell.x * 0.5
	for x in nx:
		grid[x] = []
		grid[x].resize(ny)
		for y in ny:
			var ch := WallChunk.new()
			ch.wall = self
			ch.ix = x
			ch.iy = y
			ch.hp = 30.0
			ch.freeze = true
			ch.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			ch.collision_layer = G.L_PROPS
			ch.collision_mask = G.L_WORLD | G.L_PROPS | G.L_DEBRIS | G.L_PLAYER | G.L_ROBOT
			ch.mass = 10.0
			ch.physics_material_override = WallChunk.debris_phys()
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mats[(x * 7 + y * 3) % mats.size()]
			ch.add_child(mi)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			ch.add_child(cs)
			# кладка со смещением рядов
			var off := (cell.x * 0.25) if y % 2 == 1 else 0.0
			ch.position = Vector3(x0 + x * cell.x + off, cell.y * 0.5 + y * cell.y, 0)
			add_child(ch)
			grid[x][y] = ch


func _physics_process(delta: float) -> void:
	_fx_cd -= delta
	_snd_cd -= delta
	if _dirty:
		_dirty = false
		_check_support()


func hit_chunk(ch: WallChunk, dmg: float, pos: Vector3, dir: Vector3, force: float) -> void:
	if ch.broken:
		return
	ch.hp -= dmg
	if _fx_cd <= 0.0:
		_fx_cd = 0.05
		Fx.chips(pos, -dir, 5, mats[0].albedo_color)
	if ch.hp <= 0.0:
		_break(ch, dir * (force * 0.06 + 4.0))
	# сильный удар выбивает соседей
	if force > 250.0:
		var r: float = clamp(force / 900.0, 0.35, 1.9)
		for x in nx:
			for y in ny:
				var c = grid[x][y]
				if c and c.global_position.distance_to(pos) < r:
					_break(c, (c.global_position - pos + dir).normalized() * force * 0.05)


func _break(ch: WallChunk, impulse: Vector3) -> void:
	if ch.broken:
		return
	ch.broken = true
	grid[ch.ix][ch.iy] = null
	ch.collision_layer = G.L_DEBRIS
	ch.collision_mask = G.L_WORLD | G.L_DEBRIS | G.L_PROPS | G.L_PLAYER | G.L_ROBOT
	ch.freeze = false
	ch.apply_central_impulse(impulse)
	ch.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	G.add_debris(ch)
	if _fx_cd <= 0.0:
		_fx_cd = 0.04
		Fx.dust(ch.global_position, 0.5)
	if _snd_cd <= 0.0:
		_snd_cd = 0.08
		Sfx.play3d("crumble", ch.global_position, -2.0, randf_range(0.8, 1.2))
	_dirty = true


## Всё, что не связано с землёй через целые блоки, падает.
func _check_support() -> void:
	var seen := {}
	var stack: Array = []
	for x in nx:
		if grid[x][0] != null:
			stack.append(Vector2i(x, 0))
			seen[Vector2i(x, 0)] = true
	while stack.size() > 0:
		var c: Vector2i = stack.pop_back()
		# кирпичная кладка: соседи по горизонтали и вертикали (+ диагональ из-за смещения рядов)
		var nbrs := [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]
		var shift := 1 if c.y % 2 == 1 else -1
		nbrs.append(Vector2i(c.x + shift, c.y + 1))
		nbrs.append(Vector2i(c.x + shift, c.y - 1))
		for n in nbrs:
			if n.x < 0 or n.x >= nx or n.y < 0 or n.y >= ny:
				continue
			if seen.has(n) or grid[n.x][n.y] == null:
				continue
			seen[n] = true
			stack.append(n)
	var falling := 0
	for x in nx:
		for y in ny:
			var ch = grid[x][y]
			if ch != null and not seen.has(Vector2i(x, y)):
				falling += 1
				_break(ch, Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)))
	if falling > 4 and _snd_cd <= 0.3:
		Sfx.play3d("crumble", global_position + Vector3(0, ny * cell.y * 0.5, 0), 4.0, 0.6)

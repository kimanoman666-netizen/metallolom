extends Node
## Загрузка CC0-ассетов Poly Haven (assets/): модели, PBR-текстуры, пропы с коллизией.

const MODEL := "res://assets/models/%s/%s.gltf"
const TEX := "res://assets/textures/%s/%s_%s.jpg"

var _scenes := {}
var _nodes := {}      # модель -> {имя узла: Node3D-шаблон}
var _mats := {}


func scene(model: String) -> PackedScene:
	if not _scenes.has(model):
		_scenes[model] = load(MODEL % [model, model])
	return _scenes[model]


## Шаблоны всех узлов модели (по имени). Используются для копирования отдельных деталей.
func nodes(model: String) -> Dictionary:
	if _nodes.has(model):
		return _nodes[model]
	var root := scene(model).instantiate()
	var d := {}
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		d[String(n.name)] = n
		for c in n.get_children():
			stack.append(c)
	_nodes[model] = d
	add_child(root)
	root.visible = false
	root.process_mode = Node.PROCESS_MODE_DISABLED
	if root is Node3D:
		(root as Node3D).position = Vector3(0, -1000, 0)
	return d


func mesh(model: String, node: String) -> Mesh:
	var n = nodes(model).get(node)
	if n is MeshInstance3D:
		return n.mesh
	return null


## Копия узла (с детьми) со сброшенным положением.
func copy(model: String, node: String) -> Node3D:
	var n = nodes(model).get(node)
	if n == null:
		push_warning("нет узла %s в %s" % [node, model])
		return Node3D.new()
	var c: Node3D = n.duplicate()
	c.transform = Transform3D(n.basis, Vector3.ZERO)
	c.visible = true
	return c


## Вся модель целиком.
func whole(model: String) -> Node3D:
	return scene(model).instantiate()


func tex(name: String, kind: String) -> Texture2D:
	var p := TEX % [name, name, kind]
	if ResourceLoader.exists(p):
		return load(p)
	return null


## PBR-материал из текстуры Poly Haven (цвет + нормаль + AO/шероховатость/металл).
func pbr(name: String, tint: Color = Color.WHITE, scale: float = 0.25, world: bool = true, metal: float = -1.0) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s_%s" % [name, tint.to_html(), scale, world, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name, "diff")
	m.albedo_color = tint
	var n := tex(name, "nor")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = 1.0
	var arm := tex(name, "arm")
	if arm:
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.6
		m.roughness = 1.0
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if metal >= 0.0:
			m.metallic = metal
		else:
			m.metallic = 1.0
			m.metallic_texture = arm
			m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## Ставит декорацию/укрытие со статической коллизией.
## shape: "box" — коробка по габаритам, "hull" — выпуклая оболочка каждого меша, "none".
func place(parent: Node3D, n: Node3D, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0, shape: String = "box", layer: int = 1) -> Node3D:
	var holder: Node3D
	if shape == "none":
		holder = Node3D.new()
	else:
		var sb := StaticBody3D.new()
		sb.collision_layer = layer
		sb.collision_mask = 0
		holder = sb
	parent.add_child(holder)
	holder.global_position = pos
	holder.rotation.y = rot_y
	holder.add_child(n)
	n.scale *= scl
	if shape == "box":
		var aabb := local_aabb(n, holder)
		if aabb.size.length() > 0.01:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = aabb.size
			cs.shape = bs
			cs.position = aabb.get_center()
			holder.add_child(cs)
	elif shape == "hull":
		for mi in meshes_in(n):
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_convex_shape(true, true)
			cs.transform = holder.global_transform.affine_inverse() * mi.global_transform
			holder.add_child(cs)
	return holder


func meshes_in(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and c.mesh:
			out.append(c)
		for k in c.get_children():
			stack.append(k)
	return out


## Габариты всех мешей узла в системе координат ref.
func local_aabb(n: Node3D, ref: Node3D) -> AABB:
	var inv := ref.global_transform.affine_inverse()
	var first := true
	var box := AABB()
	for mi in meshes_in(n):
		var a: AABB = mi.get_aabb()
		var t: Transform3D = inv * mi.global_transform
		var b := t * a
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


## Много копий одного меша одним вызовом отрисовки.
func multimesh(parent: Node3D, m: Mesh, xforms: Array, shadows: bool = false, vis_end: float = 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi

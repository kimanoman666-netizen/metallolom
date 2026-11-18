class_name Prop
extends RigidBody3D
## Физический объект: ящик (разлетается на доски) или взрывная бочка.

enum Type { CRATE, BARREL }

var type: int = Type.CRATE
var hp := 45.0
var _armed := false
var _mat: StandardMaterial3D


static func crate(pos: Vector3, size: float = 1.0) -> Prop:
	var p := Prop.new()
	p.type = Type.CRATE
	p.hp = 45.0 * size
	p.mass = 25.0 * size * size * size
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	mi.mesh = bm
	p._mat = StandardMaterial3D.new()
	p._mat.albedo_color = Color(0.52, 0.38, 0.22)
	p._mat.roughness = 0.85
	if G.main and G.main.wood_tex:
		p._mat.albedo_texture = G.main.wood_tex
	mi.material_override = p._mat
	p.add_child(mi)
	# рёбра ящика
	for i in 4:
		var e := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(size * 1.02, size * 0.12, size * 0.12)
		e.mesh = em
		e.material_override = Fx.solid_mat(Color(0.3, 0.2, 0.1), 0.0, 0.9)
		e.position = Vector3(0, (0.45 if i < 2 else -0.45) * size, (0.45 if i % 2 == 0 else -0.45) * size)
		p.add_child(e)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3.ONE * size
	cs.shape = bs
	p.add_child(cs)
	p._common()
	G.world.add_child(p)
	p.global_position = pos
	p.rotation.y = randf_range(-0.3, 0.3)
	return p


static func barrel(pos: Vector3) -> Prop:
	var p := Prop.new()
	p.type = Type.BARREL
	p.hp = 22.0
	p.mass = 30.0
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.38
	cm.bottom_radius = 0.38
	cm.height = 1.15
	cm.radial_segments = 20
	mi.mesh = cm
	p._mat = StandardMaterial3D.new()
	p._mat.albedo_color = Color(0.75, 0.1, 0.05)
	p._mat.metallic = 0.6
	p._mat.roughness = 0.45
	p._mat.emission_enabled = true
	p._mat.emission = Color(1.0, 0.4, 0.1)
	p._mat.emission_energy_multiplier = 0.0
	mi.material_override = p._mat
	p.add_child(mi)
	for y in [-0.35, 0.35]:
		var r := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.4
		rm.bottom_radius = 0.4
		rm.height = 0.06
		rm.radial_segments = 20
		r.mesh = rm
		r.material_override = Fx.solid_mat(Color(0.15, 0.15, 0.15), 0.8, 0.4)
		r.position.y = y
		p.add_child(r)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.385
	bm.bottom_radius = 0.385
	bm.height = 0.18
	bm.radial_segments = 20
	band.mesh = bm
	band.material_override = Fx.glow_mat(Color(1.0, 0.75, 0.1), 1.5)
	p.add_child(band)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.38
	cy.height = 1.15
	cs.shape = cy
	p.add_child(cs)
	p._common()
	G.world.add_child(p)
	p.global_position = pos
	return p


func _common() -> void:
	collision_layer = G.L_PROPS
	collision_mask = G.L_WORLD | G.L_PROPS | G.L_DEBRIS | G.L_PLAYER | G.L_ROBOT
	physics_material_override = WallChunk.debris_phys()
	can_sleep = true


func take_hit(dmg: float, pos: Vector3, dir: Vector3, force: float) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	apply_impulse(d * (force * 0.05 + dmg * 0.08), pos - global_position)
	if _armed:
		return
	hp -= dmg
	if hp <= 0.0:
		if type == Type.BARREL:
			_arm()
		else:
			_shatter(d, force)


func _arm() -> void:
	_armed = true
	_mat.emission_energy_multiplier = 6.0
	Fx.spark_emitter(self, Vector3(0, 0.6, 0), 0.5)
	Sfx.play3d("overheat", global_position, 0.0, 1.4)
	get_tree().create_timer(0.18, false).timeout.connect(_blow)


func _blow() -> void:
	if not is_instance_valid(self):
		return
	var pos := global_position
	collision_layer = 0
	queue_free()
	G.explode(pos, 5.5, 160.0, 1800.0, 0.7, true)


func _shatter(dir: Vector3, force: float) -> void:
	var pos := global_position
	var size: float = (get_child(0) as MeshInstance3D).mesh.size.x
	Sfx.play3d("crumble", pos, 0.0, 1.4)
	Fx.chips(pos, Vector3.UP, 12, Color(0.5, 0.36, 0.2))
	Fx.dust(pos, 0.6 * size)
	var pm := BoxMesh.new()
	pm.size = Vector3(size, 0.1 * size, 0.24 * size)
	var ps := BoxShape3D.new()
	ps.size = pm.size
	for i in 7:
		var rb := WallChunk.new()
		rb.broken = true
		rb.collision_layer = G.L_DEBRIS
		rb.collision_mask = G.L_WORLD | G.L_DEBRIS | G.L_PROPS | G.L_PLAYER | G.L_ROBOT
		rb.mass = 2.0
		rb.physics_material_override = WallChunk.debris_phys()
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = _mat
		rb.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = ps
		rb.add_child(cs)
		G.world.add_child(rb)
		rb.global_position = pos + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)) * size
		rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		rb.apply_central_impulse((dir * (2.0 + force * 0.004) + Vector3(randf_range(-1, 1), randf_range(0.5, 2.0), randf_range(-1, 1)) * 2.0) * rb.mass)
		rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		G.add_debris(rb)
	if randf() < 0.35 and G.main:
		G.main.drop_pickup(pos, randi() % 2)
	queue_free()

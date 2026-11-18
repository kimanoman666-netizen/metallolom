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
	p.mass = 22.0 * size
	var vis := Assets.whole("wooden_crate_01")
	p.add_child(vis)
	vis.scale = Vector3.ONE * size
	p._mat = Assets.pbr("rusty_metal_02", Color(0.55, 0.4, 0.25), 0.8, false, 0.0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.83, 0.34, 0.41) * size
	cs.shape = bs
	cs.position.y = 0.17 * size
	p.add_child(cs)
	p._common()
	G.world.add_child(p)
	p.global_position = pos - Vector3(0, 0.17 * size, 0)
	p.rotation.y = randf_range(-0.3, 0.3)
	return p


static func barrel(pos: Vector3) -> Prop:
	var p := Prop.new()
	p.type = Type.BARREL
	p.hp = 22.0
	p.mass = 30.0
	var vis := Assets.whole("barrel_03")
	p.add_child(vis)
	p._mat = StandardMaterial3D.new()
	p._mat.emission_enabled = true
	p._mat.emission = Color(1.0, 0.4, 0.1)
	p._mat.emission_energy_multiplier = 0.0
	# красная окраска «опасно»: перекрашиваем материал модели
	for mi in Assets.meshes_in(vis):
		for s in mi.mesh.get_surface_count():
			var src = mi.mesh.surface_get_material(s)
			if src is StandardMaterial3D:
				var m: StandardMaterial3D = src.duplicate()
				m.albedo_color = Color(1.0, 0.32, 0.25)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.4, 0.1)
				m.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(s, m)
				p._mat = m
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.322
	bm.bottom_radius = 0.322
	bm.height = 0.12
	bm.radial_segments = 24
	band.mesh = bm
	band.material_override = Fx.glow_mat(Color(1.0, 0.75, 0.1), 1.2)
	p.add_child(band)
	band.position.y = 0.6
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.31
	cy.height = 0.93
	cs.shape = cy
	cs.position.y = 0.465
	p.add_child(cs)
	p._common()
	G.world.add_child(p)
	p.global_position = pos - Vector3(0, 0.5, 0)
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
	Fx.spark_emitter(self, Vector3(0, 1.0, 0), 0.5)
	Sfx.play3d("overheat", global_position, 0.0, 1.4)
	get_tree().create_timer(0.18, false).timeout.connect(_blow)


func _blow() -> void:
	if not is_instance_valid(self):
		return
	var pos := global_position + Vector3(0, 0.5, 0)
	collision_layer = 0
	queue_free()
	G.explode(pos, 5.5, 160.0, 1800.0, 0.7, true)


func _shatter(dir: Vector3, force: float) -> void:
	var pos := global_position + Vector3(0, 0.2, 0)
	var size := 0.6
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

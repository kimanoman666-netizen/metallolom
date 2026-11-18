class_name Pickup
extends Area3D
## Подбираемый предмет: аптечка (0) или патроны (1).

var type := 0
var t := 0.0
var life := 30.0
var vis: Node3D
var base_y := 0.0


static func spawn(pos: Vector3, kind: int) -> Pickup:
	var p := Pickup.new()
	p.type = kind
	p.collision_layer = 0
	p.collision_mask = G.L_PLAYER
	p.monitoring = true
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.0
	cs.shape = sp
	p.add_child(cs)
	p.vis = Node3D.new()
	p.add_child(p.vis)
	var c := Color(0.2, 1.0, 0.35) if kind == 0 else Color(1.0, 0.55, 0.1)
	var model := Assets.whole("medical_box" if kind == 0 else "ammo_box")
	p.vis.add_child(model)
	model.scale = Vector3.ONE * (0.9 if kind == 0 else 2.2)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.46
	ring.mesh = tm
	ring.material_override = Fx.glow_mat(c, 3.0)
	p.add_child(ring)
	ring.position.y = -0.7
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 2.0
	l.omni_range = 3.5
	p.add_child(l)
	G.world.add_child(p)
	# ставим на землю
	var hit := G.ray(pos + Vector3.UP * 2.0, pos + Vector3.DOWN * 30.0, G.L_WORLD, [], false)
	p.global_position = (hit.position if not hit.is_empty() else pos) + Vector3(0, 0.8, 0)
	p.base_y = p.global_position.y
	p.body_entered.connect(p._on_body)
	return p


func _process(delta: float) -> void:
	t += delta
	life -= delta
	vis.rotation.y += delta * 2.5
	vis.position.y = sin(t * 3.0) * 0.08 - 0.45
	if life < 5.0:
		vis.visible = fmod(life, 0.3) > 0.12
	if life <= 0.0:
		queue_free()


func _on_body(b: Node) -> void:
	if b != G.player or G.player.dead:
		return
	if type == 0:
		if G.player.hp >= G.player.max_hp:
			return
		G.player.heal(40.0)
		if G.hud:
			G.hud.popup("+40 ЗДОРОВЬЯ", 0)
	else:
		G.player.add_ammo(0.6)
		if G.hud:
			G.hud.popup("+ПАТРОНЫ", 0)
	Sfx.play2d("pickup", -2.0)
	queue_free()

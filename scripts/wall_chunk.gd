class_name WallChunk
extends RigidBody3D
## Блок разрушаемой стены. Пока цел, он заморожен и держит соседей.
## Отколотый блок (и любой обломок робота) становится обычным физическим телом.

static var _phys: PhysicsMaterial

var wall: Node = null
var ix := 0
var iy := 0
var hp := 30.0
var broken := false


static func debris_phys() -> PhysicsMaterial:
	if _phys == null:
		_phys = PhysicsMaterial.new()
		_phys.friction = 0.85
		_phys.bounce = 0.12
	return _phys


func take_hit(dmg: float, pos: Vector3, dir: Vector3, force: float) -> void:
	if broken or wall == null:
		if not freeze:
			var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
			apply_impulse(d * (force * 0.03 + dmg * 0.04) * clamp(mass / 10.0, 0.3, 3.0), pos - global_position)
		return
	wall.hit_chunk(self, dmg, pos, dir, force)

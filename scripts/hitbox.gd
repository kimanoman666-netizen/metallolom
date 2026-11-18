class_name Hitbox
extends Area3D
## Зона попадания по части робота. Передаёт урон роботу.

var robot: Node = null
var part: String = ""
var mult: float = 1.0


func take_hit(dmg: float, pos: Vector3, dir: Vector3, force: float) -> void:
	if robot and is_instance_valid(robot):
		robot.damage_part(part, dmg * mult, pos, dir, force, mult > 1.5)

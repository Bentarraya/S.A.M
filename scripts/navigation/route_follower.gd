extends RefCounted

var position: Vector3 = Vector3.ZERO
var heading: float = 0.0

func step_toward(target: Vector3, speed: float, turn_rate: float, dt: float, tolerance: float) -> Dictionary:
	var desired := atan2(target.z - position.z, target.x - position.x)
	var delta := wrapf(desired - heading, -PI, PI)
	heading = wrapf(heading + clampf(delta, -turn_rate * dt, turn_rate * dt), -PI, PI)
	var aligned := absf(delta) <= deg_to_rad(10.0)
	if aligned:
		var distance := position.distance_to(target)
		position += Vector3(cos(heading), 0.0, sin(heading)) * minf(speed * dt, distance)
	var arrived := position.distance_to(target) <= tolerance
	if arrived:
		position = target
		heading = desired
	return {"arrived": arrived, "aligned": aligned}

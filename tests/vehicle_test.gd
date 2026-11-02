extends RefCounted

const RouteFollower = preload("res://scripts/navigation/route_follower.gd")
const Vehicle = preload("res://scripts/entities/vehicle.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var f := RouteFollower.new()
	f.position = Vector3(0, 0, 0)
	f.heading = 0.0
	var r := f.step_toward(Vector3(10, 0, 0), 2.0, 1.5, 1.0, 0.15)
	_check(r["aligned"] and not r["arrived"], "aligned and moving")
	_check(is_equal_approx(f.position.x, 2.0), "moved 2m east, got %s" % f.position)

	f.position = Vector3(10, 0, 0)
	f.heading = 0.0
	r = f.step_toward(Vector3(10.1, 0, 0), 2.0, 1.5, 1.0, 0.15)
	_check(r["arrived"], "snapped within tolerance")
	_check(f.position == Vector3(10.1, 0, 0), "snap exact")

	f.position = Vector3(0, 0, 0)
	f.heading = PI
	r = f.step_toward(Vector3(0, 0, 10), 2.0, 1.5, 0.1, 0.15)
	_check(not r["aligned"], "must turn first (180 deg)")
	_check(f.position.length() < 0.01, "no movement while misaligned")

	var v := Vehicle.new()
	v.id = "PE-01"
	v.vehicle_class = "PE"
	v.state = Vehicle.State.IDLE
	_check(v.transition(Vehicle.State.TO_DOCK), "idle->to_dock")
	_check(v.transition(Vehicle.State.ALIGN_PICKUP), "to_dock->align_pickup")
	_check(not v.transition(Vehicle.State.LOADED_TO_RACK), "PE cannot enter RD state")
	_check(v.invalid_transitions == 1, "invalid transition counted")

	var rd := Vehicle.new()
	rd.id = "RD-01"
	rd.vehicle_class = "RD"
	rd.state = Vehicle.State.IDLE
	_check(rd.transition(Vehicle.State.TO_XFER), "RD idle->to_xfer")
	_check(not rd.transition(Vehicle.State.TO_DOCK), "RD cannot enter PE state")
	return failures

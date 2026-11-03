extends RefCounted

const RouteFollower = preload("res://scripts/navigation/route_follower.gd")

enum State {IDLE, TO_DOCK, ALIGN_PICKUP, PICKING, LOADED_TO_XFER, ALIGN_DROPOFF, DROPPING, RETURNING, TO_XFER, LOADED_TO_RACK, ALIGN_RACK, PLACING}

const _PE_NEXT := {
	State.IDLE: [State.TO_DOCK],
	State.TO_DOCK: [State.ALIGN_PICKUP],
	State.ALIGN_PICKUP: [State.PICKING],
	State.PICKING: [State.LOADED_TO_XFER],
	State.LOADED_TO_XFER: [State.ALIGN_DROPOFF],
	State.ALIGN_DROPOFF: [State.DROPPING],
	State.DROPPING: [State.RETURNING],
	State.RETURNING: [State.IDLE],
}

const _RD_NEXT := {
	State.IDLE: [State.TO_XFER],
	State.TO_XFER: [State.ALIGN_PICKUP],
	State.ALIGN_PICKUP: [State.PICKING],
	State.PICKING: [State.LOADED_TO_RACK],
	State.LOADED_TO_RACK: [State.ALIGN_RACK],
	State.ALIGN_RACK: [State.PLACING],
	State.PLACING: [State.RETURNING],
	# A returning RD chains straight onto the next handoff instead of parking first.
	State.RETURNING: [State.IDLE, State.TO_XFER],
}

var id: String = ""
var vehicle_class: String = ""
var state: int = State.IDLE
var task_id: String = ""
var pallet_id: String = ""
var blocked_reason: String = ""
var invalid_transitions: int = 0
var follower = RouteFollower.new()

func can_transition(from: int, to: int, cls: String) -> bool:
	var table: Dictionary
	if cls == "PE":
		table = _PE_NEXT
	elif cls == "RD":
		table = _RD_NEXT
	else:
		return false
	return to in table.get(from, [])

func transition(to: int) -> bool:
	if not can_transition(state, to, vehicle_class):
		invalid_transitions += 1
		return false
	state = to
	return true

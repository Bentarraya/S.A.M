extends RefCounted
class_name Dispatcher

const Vehicle = preload("res://scripts/entities/vehicle.gd")
const Pallet = preload("res://scripts/entities/pallet.gd")

var pickup_seconds := {"PE": 1.5, "RD": 2.0}
var dropoff_seconds := {"PE": 1.5, "RD": 2.0}

var _wait_timers: Dictionary = {}
var _seq: int = 0

func step(engine) -> void:
	_assign_pe_tasks(engine)
	_assign_rd_tasks(engine)
	_advance_vehicles(engine, engine.last_dt)
	for vid in engine.vehicles:
		var v: Vehicle = engine.vehicles[vid]["ref"]
		engine.vehicles[vid]["pallet_id"] = v.pallet_id
		engine.vehicles[vid]["heading"] = v.follower.heading

func _next_seq() -> int:
	_seq += 1
	return _seq

func _try_request(engine, res_id: String, vid: String) -> bool:
	if engine.resources.is_held_by(res_id, vid):
		return true
	return engine.resources.request(res_id, vid, _next_seq())

func _release_station_res(engine, vid: String, vdata: Dictionary, res_id: String) -> void:
	if vdata["station_res"].has(res_id):
		vdata["station_res"].erase(res_id)
		if vdata.get("current_leg_resource", "") != res_id:
			engine.resources.release(res_id, vid)

func _release_leg_res(engine, vid: String, vdata: Dictionary, res_id: String) -> void:
	if not vdata.get("station_res", {}).has(res_id):
		engine.resources.release(res_id, vid)

func _set_blocked(engine, v: Vehicle, vid: String, reason: String, event_name: String, msg: String) -> void:
	if v.blocked_reason != reason:
		v.blocked_reason = reason
		engine.blocked_reasons[vid] = reason
		engine.events.log_event(engine.time, event_name, msg)

func _clear_blocked(engine, v: Vehicle, vid: String) -> void:
	if v.blocked_reason != "":
		v.blocked_reason = ""
	if engine.blocked_reasons.has(vid):
		engine.blocked_reasons.erase(vid)

func _clear_blocked_if_waiting(engine, v: Vehicle, vid: String) -> void:
	if v.blocked_reason.begins_with("waiting:"):
		v.blocked_reason = ""
	if engine.blocked_reasons.get(vid, "").begins_with("waiting:"):
		engine.blocked_reasons.erase(vid)

func _transition_task(engine, task_id: String, to_status: int) -> bool:
	var ok: bool = engine.tasks.transition(task_id, to_status)
	if not ok:
		engine.events.log_event(engine.time, "task_transition_error",
			"Failed to transition task %s to status %d" % [task_id, to_status])
	return ok

func _transition_vehicle(engine, v: Vehicle, vid: String, to_state: int) -> bool:
	var ok: bool = v.transition(to_state)
	if not ok:
		engine.events.log_event(engine.time, "vehicle_transition_error",
			"Failed to transition vehicle %s to state %d" % [vid, to_state])
	return ok

func _assign_pe_tasks(engine) -> void:
	for p in engine.inventory.pallets_with_status(Pallet.Status.AT_DOCK):
		if p.task_id != "":
			continue
		var task: Dictionary = engine.tasks.find_task_by_pallet(p.id)
		if task.is_empty():
			continue
		for vid in engine.vehicles:
			var vdata: Dictionary = engine.vehicles[vid]
			var v: Vehicle = vdata["ref"]
			if v.vehicle_class != "PE" or v.state != Vehicle.State.IDLE or v.pallet_id != "":
				continue

			var xfer_id: String = _free_xfer(engine)
			if xfer_id == "":
				_set_blocked(engine, v, vid, "waiting:xfer", "pe_blocked", "%s waiting for handoff station" % vid)
				break
			var dock_id: String = p.location_id
			if not _try_request(engine, dock_id, vid):
				_set_blocked(engine, v, vid, "waiting:" + dock_id, "pe_blocked", "%s failed to reserve %s" % [vid, dock_id])
				continue
			if not _try_request(engine, xfer_id, vid):
				_set_blocked(engine, v, vid, "waiting:" + xfer_id, "pe_blocked", "%s failed to reserve %s" % [vid, xfer_id])
				_release_station_res(engine, vid, vdata, dock_id)
				continue

			engine.xfer_state[xfer_id] = "RESERVED"
			vdata["station_res"][dock_id] = true
			vdata["station_res"][xfer_id] = true

			var pickup_wp: String = dock_id.replace("DOCK-", "DOCK_PICKUP_")
			var drop_wp: String = xfer_id.replace("XFER-", "XFER_DROP_")
			var home: String = _home_wp(engine, vdata, v)
			var path: Array = _join(engine.graph.find_path(home, pickup_wp, "PE"),
				engine.graph.find_path(pickup_wp, drop_wp, "PE"))
			if path.is_empty():
				_release_station_res(engine, vid, vdata, dock_id)
				_release_station_res(engine, vid, vdata, xfer_id)
				engine.xfer_state[xfer_id] = "FREE"
				_set_blocked(engine, v, vid, "empty_path", "pe_blocked", "%s empty path to %s" % [vid, drop_wp])
				continue

			if not _transition_task(engine, task["id"], engine.TaskStatus.ASSIGNED_PE):
				_release_station_res(engine, vid, vdata, dock_id)
				_release_station_res(engine, vid, vdata, xfer_id)
				engine.xfer_state[xfer_id] = "FREE"
				continue

			task["pe_id"] = vid
			p.set_status(Pallet.Status.ASSIGNED_TO_PE)
			p.task_id = task["id"]
			engine.events.log_event(engine.time, "task_assigned_pe",
				"%s assigned to %s for %s" % [task["id"], vid, p.id])

			v.task_id = task["id"]
			vdata["target_pallet"] = p.id
			vdata["path"] = path
			vdata["path_index"] = 0
			vdata["dropoff_wp"] = drop_wp
			vdata["target_xfer"] = xfer_id
			_clear_blocked(engine, v, vid)
			_transition_vehicle(engine, v, vid, Vehicle.State.TO_DOCK)
			break

func _assign_rd_tasks(engine) -> void:
	for p in engine.inventory.pallets_with_status(Pallet.Status.AT_XFER):
		var task: Dictionary = engine.tasks.get_task(p.task_id)
		if task.is_empty() or task.get("rd_id", "") != "":
			continue
		for vid in engine.vehicles:
			var vdata: Dictionary = engine.vehicles[vid]
			var v: Vehicle = vdata["ref"]
			if v.vehicle_class != "RD" or v.state != Vehicle.State.IDLE or v.pallet_id != "":
				continue

			var rack_id: String = _free_rack(engine)
			if rack_id == "":
				_set_blocked(engine, v, vid, "waiting:rack", "rd_blocked", "%s waiting for free rack slot" % vid)
				return
			var xfer_id: String = p.location_id
			if not _try_request(engine, rack_id, vid):
				_set_blocked(engine, v, vid, "waiting:" + rack_id, "rd_blocked", "%s failed to reserve %s" % [vid, rack_id])
				continue
			if not _try_request(engine, xfer_id, vid):
				_set_blocked(engine, v, vid, "waiting:" + xfer_id, "rd_blocked", "%s failed to reserve %s" % [vid, xfer_id])
				_release_station_res(engine, vid, vdata, rack_id)
				continue

			vdata["station_res"][rack_id] = true
			vdata["station_res"][xfer_id] = true

			var drop_wp: String = xfer_id.replace("XFER-", "XFER_DROP_")
			var place_wp: String = "RACK_PLACE_" + _rack_code(rack_id)
			var home: String = _home_wp(engine, vdata, v)
			var path: Array = _join(engine.graph.find_path(home, drop_wp, "RD"),
				engine.graph.find_path(drop_wp, place_wp, "RD"))
			if path.is_empty():
				_release_station_res(engine, vid, vdata, rack_id)
				_release_station_res(engine, vid, vdata, xfer_id)
				_set_blocked(engine, v, vid, "empty_path", "rd_blocked", "%s empty path to %s" % [vid, place_wp])
				continue

			if not _transition_task(engine, p.task_id, engine.TaskStatus.ASSIGNED_RD):
				_release_station_res(engine, vid, vdata, rack_id)
				_release_station_res(engine, vid, vdata, xfer_id)
				continue

			task["rd_id"] = vid
			p.set_status(Pallet.Status.ASSIGNED_TO_RD)
			engine.rack_slots[rack_id]["state"] = "RESERVED"
			engine.events.log_event(engine.time, "task_assigned_rd",
				"%s assigned to %s for %s -> %s" % [p.task_id, vid, p.id, rack_id])

			v.task_id = p.task_id
			vdata["target_pallet"] = p.id
			vdata["path"] = path
			vdata["path_index"] = 0
			vdata["pickup_wp"] = drop_wp
			vdata["place_wp"] = place_wp
			vdata["target_rack"] = rack_id
			vdata["target_xfer"] = xfer_id
			_clear_blocked(engine, v, vid)
			_transition_vehicle(engine, v, vid, Vehicle.State.TO_XFER)
			break

func _advance_vehicles(engine, dt: float) -> void:
	for vid in engine.vehicles:
		var vdata: Dictionary = engine.vehicles[vid]
		var v: Vehicle = vdata["ref"]

		if vdata.get("waiting", false):
			vdata["target_waypoint"] = ""
			_wait_tick(engine, vid, vdata, v, dt)
			continue

		var path: Array = vdata.get("path", [])
		var idx: int = vdata.get("path_index", 0)
		if path.is_empty() or idx >= path.size() or v.state == Vehicle.State.IDLE:
			vdata["target_waypoint"] = ""
			if v.state == Vehicle.State.RETURNING:
				if _transition_vehicle(engine, v, vid, Vehicle.State.IDLE):
					v.task_id = ""
					vdata["path"] = []
			continue

		var cur_wp: String = path[idx]
		vdata["target_waypoint"] = cur_wp

		var target_res: String = engine.graph.get_waypoint(cur_wp).get("resource", "")
		var cur_res: String = vdata.get("current_leg_resource", "")
		if target_res != "" and target_res != cur_res:
			if not _try_request(engine, target_res, vid):
				_set_blocked(engine, v, vid, "waiting:" + target_res, "vehicle_blocked", "%s waiting for %s" % [vid, target_res])
				continue
			_clear_blocked_if_waiting(engine, v, vid)
			vdata["current_leg_resource"] = target_res
			if cur_res != "":
				_release_leg_res(engine, vid, vdata, cur_res)
		else:
			_clear_blocked_if_waiting(engine, v, vid)

		var result: Dictionary = v.follower.step_toward(
			engine.graph.waypoint_pos(cur_wp), vdata["speed"], vdata["turn_rate"], dt, vdata["tolerance"])
		vdata["pos"] = v.follower.position
		vdata["heading"] = v.follower.heading
		if not result["arrived"]:
			continue

		vdata["path_index"] = idx + 1
		var at_end: bool = idx + 1 >= path.size()

		# Station resource is kept past dropoff/pickup until the body leaves the pad.
		_release_xfer_if_vacated(engine, vdata, vid, cur_wp)

		if v.vehicle_class == "PE":
			if v.state == Vehicle.State.TO_DOCK and cur_wp.begins_with("DOCK_PICKUP"):
				_begin_wait(engine, vdata, vid, "PE_PICKUP", pickup_seconds["PE"])
			elif v.state == Vehicle.State.LOADED_TO_XFER and at_end and cur_wp == vdata.get("dropoff_wp", ""):
				_begin_wait(engine, vdata, vid, "PE_DROPOFF", dropoff_seconds["PE"])
		else:
			if v.state == Vehicle.State.TO_XFER and cur_wp == vdata.get("pickup_wp", ""):
				_begin_wait(engine, vdata, vid, "RD_PICKUP", pickup_seconds["RD"])
			elif v.state == Vehicle.State.LOADED_TO_RACK and at_end and cur_wp == vdata.get("place_wp", ""):
				_begin_wait(engine, vdata, vid, "RD_DROPOFF", dropoff_seconds["RD"])

# Called when a vehicle ARRIVES at a waypoint while returning/leaving a handoff:
# if it was keeping the XFER station resource past its pickup/dropoff and has now
# physically stepped off the pad, the resource is finally released.
func _release_xfer_if_vacated(engine, vdata: Dictionary, vid: String, arrived_wp: String) -> void:
	var xfer_id: String = vdata.get("xfer_vacate", "")
	if xfer_id == "":
		return
	var drop_wp: String = xfer_id.replace("XFER-", "XFER_DROP_")
	if arrived_wp == drop_wp:
		return  # still on the pad
	_release_station_res(engine, vid, vdata, xfer_id)
	vdata["xfer_vacate"] = ""

func _begin_wait(engine, vdata: Dictionary, vid: String, kind: String, seconds: float) -> void:
	var v: Vehicle = vdata["ref"]
	if kind == "PE_PICKUP":
		_transition_vehicle(engine, v, vid, Vehicle.State.ALIGN_PICKUP)
		_transition_vehicle(engine, v, vid, Vehicle.State.PICKING)
	elif kind == "PE_DROPOFF":
		_transition_vehicle(engine, v, vid, Vehicle.State.ALIGN_DROPOFF)
		_transition_vehicle(engine, v, vid, Vehicle.State.DROPPING)
	elif kind == "RD_PICKUP":
		_transition_vehicle(engine, v, vid, Vehicle.State.ALIGN_PICKUP)
		_transition_vehicle(engine, v, vid, Vehicle.State.PICKING)
	else:
		_transition_vehicle(engine, v, vid, Vehicle.State.ALIGN_RACK)
		_transition_vehicle(engine, v, vid, Vehicle.State.PLACING)
	vdata["waiting"] = true
	vdata["wait_kind"] = kind
	vdata["wait_seconds"] = seconds
	_wait_timers[vid] = 0.0

func _wait_tick(engine, vid: String, vdata: Dictionary, v: Vehicle, dt: float) -> void:
	var t: float = _wait_timers.get(vid, 0.0) + dt
	_wait_timers[vid] = t
	if t < vdata.get("wait_seconds", 0.0):
		return

	vdata["waiting"] = false
	var kind: String = vdata.get("wait_kind", "")

	if kind == "PE_PICKUP":
		var p = engine.inventory.get_pallet(vdata["target_pallet"])
		v.pallet_id = vdata["target_pallet"]
		if p != null:
			p.set_status(Pallet.Status.IN_TRANSIT_PE)
		_transition_task(engine, v.task_id, engine.TaskStatus.PE_PICKED)
		engine.events.log_event(engine.time, "pe_picked", "%s picked %s" % [vid, v.pallet_id])
		_transition_vehicle(engine, v, vid, Vehicle.State.LOADED_TO_XFER)

	elif kind == "PE_DROPOFF":
		var p = engine.inventory.get_pallet(v.pallet_id)
		var dock_id: String = ""
		if p != null:
			dock_id = p.location_id
			p.set_status(Pallet.Status.AT_XFER)
			p.location_id = vdata["target_xfer"]
		_transition_task(engine, v.task_id, engine.TaskStatus.AT_XFER)
		engine.xfer_state[vdata["target_xfer"]] = "OCCUPIED"
		if dock_id != "":
			engine.dock_free[dock_id] = true
			_release_station_res(engine, vid, vdata, dock_id)
		# Keep the XFER resource held until the PE's body has left the pad —
		# the departing PE and an incoming RD would otherwise overlap here
		# (their leg resources differ, so nothing else arbitrates this).
		# _release_xfer_if_vacated finishes the release once the PE arrives at
		# its next waypoint.
		engine.events.log_event(engine.time, "xfer_drop", "%s dropped %s at %s" % [vid, v.pallet_id, vdata["target_xfer"]])
		v.pallet_id = ""
		vdata["xfer_vacate"] = vdata["target_xfer"]
		vdata["path"] = engine.graph.find_path(vdata.get("dropoff_wp", ""), vdata.get("home_wp", ""), "PE")
		vdata["path_index"] = 0
		vdata["dropoff_wp"] = ""
		vdata["target_xfer"] = ""
		_transition_vehicle(engine, v, vid, Vehicle.State.RETURNING)

	elif kind == "RD_PICKUP":
		var p = engine.inventory.get_pallet(vdata["target_pallet"])
		v.pallet_id = vdata["target_pallet"]
		if p != null:
			p.set_status(Pallet.Status.IN_TRANSIT_RD)
		_transition_task(engine, v.task_id, engine.TaskStatus.RD_PICKED)
		engine.events.log_event(engine.time, "rd_picked", "%s picked %s" % [vid, v.pallet_id])
		_transition_vehicle(engine, v, vid, Vehicle.State.LOADED_TO_RACK)
		if vdata.get("target_xfer", "") != "":
			engine.xfer_state[vdata["target_xfer"]] = "FREE"
			# Keep the resource held until the RD's body leaves the pad —
			# same vacate rule as the PE dropoff. _release_xfer_if_vacated
			# completes it once the RD reaches its next waypoint.
			vdata["xfer_vacate"] = vdata["target_xfer"]
			vdata["target_xfer"] = ""

	else:  # RD_DROPOFF
		var p = engine.inventory.get_pallet(v.pallet_id)
		var rack_id: String = vdata["target_rack"]
		if p != null:
			p.set_status(Pallet.Status.STORED)
			p.location_id = rack_id
		_transition_task(engine, v.task_id, engine.TaskStatus.STORED)
		_transition_task(engine, v.task_id, engine.TaskStatus.COMPLETED)
		engine.rack_slots[rack_id]["state"] = "OCCUPIED"
		engine.rack_slots[rack_id]["pallet"] = v.pallet_id
		_release_station_res(engine, vid, vdata, rack_id)
		engine.events.log_event(engine.time, "pallet_stored", "%s stored %s at %s" % [vid, v.pallet_id, rack_id])
		v.pallet_id = ""
		vdata["path"] = engine.graph.find_path(vdata.get("place_wp", ""), vdata.get("home_wp", ""), "RD")
		vdata["path_index"] = 0
		vdata["target_rack"] = ""
		_transition_vehicle(engine, v, vid, Vehicle.State.RETURNING)

func _home_wp(engine, vdata: Dictionary, v: Vehicle) -> String:
	if vdata.get("home_wp", "") != "":
		return vdata["home_wp"]
	for wp_id in engine.graph.waypoints:
		var w: Dictionary = engine.graph.waypoints[wp_id]
		if w.get("type", "") == "parking" and w.get("class", "") == v.vehicle_class and w["pos"] == vdata["pos"]:
			vdata["home_wp"] = wp_id
			return wp_id
	return ""

func _free_xfer(engine) -> String:
	for xfer_id in engine.xfer_state:
		if engine.xfer_state[xfer_id] == "FREE":
			return xfer_id
	return ""

func _free_rack(engine) -> String:
	for slot_id in engine.rack_slots:
		if engine.rack_slots[slot_id]["state"] == "FREE":
			return slot_id
	return ""

func _rack_code(rack_id: String) -> String:
	var parts := rack_id.split("-")
	return parts[1] + "_" + parts[2]

func _join(a: Array, b: Array) -> Array:
	if a.is_empty() or b.is_empty():
		return []
	var out: Array = Array(a)
	for i in range(1, b.size()):
		out.append(b[i])
	return out

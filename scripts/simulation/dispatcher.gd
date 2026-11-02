extends RefCounted
class_name Dispatcher

const Vehicle = preload("res://scripts/entities/vehicle.gd")
const Pallet = preload("res://scripts/entities/pallet.gd")

# Seconds a vehicle spends stopped at a pickup / dropoff / placement waypoint
var pickup_seconds := {"PE": 1.5, "RD": 2.0}
var dropoff_seconds := {"PE": 1.5, "RD": 2.0}

var _wait_timers: Dictionary = {}
var _seq: int = 0

func step(engine) -> void:
	_release_finished_legs(engine)
	_assign_pe_tasks(engine)
	_assign_rd_tasks(engine)
	_advance_vehicles(engine, engine.last_dt)
	# Mirror carrier state onto the engine vehicle dict (tests read it there)
	for vid in engine.vehicles:
		engine.vehicles[vid]["pallet_id"] = engine.vehicles[vid]["ref"].pallet_id

func _next_seq() -> int:
	_seq += 1
	return _seq

# Never re-request a resource this owner already holds: a second request for a
# resource that is already held would append a duplicate holder (Task 4 path).
func _try_request(engine, res_id: String, vid: String) -> bool:
	if engine.resources.is_held_by(res_id, vid):
		return true
	return engine.resources.request(res_id, vid, _next_seq())

func _release_finished_legs(engine) -> void:
	for vid in engine.vehicles:
		var v: Vehicle = engine.vehicles[vid]["ref"]
		if v.pallet_id != "" or v.state != Vehicle.State.IDLE:
			continue
		for res_id in engine.resources._holders.keys():
			if engine.resources.is_held_by(res_id, vid):
				engine.resources.release(res_id, vid)

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
				break
			var dock_id: String = p.location_id
			if not _try_request(engine, dock_id, vid):
				continue
			if not _try_request(engine, xfer_id, vid):
				engine.resources.release(dock_id, vid)
				continue

			var pickup_wp: String = dock_id.replace("DOCK-", "DOCK_PICKUP_")
			var drop_wp: String = xfer_id.replace("XFER-", "XFER_DROP_")
			var home: String = _home_wp(engine, vdata, v)
			var path: Array = _join(engine.graph.find_path(home, pickup_wp, "PE"),
				engine.graph.find_path(pickup_wp, drop_wp, "PE"))
			if path.is_empty():
				engine.resources.release(dock_id, vid)
				engine.resources.release(xfer_id, vid)
				continue

			task["pe_id"] = vid
			p.set_status(Pallet.Status.ASSIGNED_TO_PE)
			p.task_id = task["id"]
			engine.tasks.transition(task["id"], engine.TaskStatus.ASSIGNED_PE)
			engine.events.log_event(engine.time, "task_assigned_pe",
				"%s assigned to %s for %s" % [task["id"], vid, p.id])

			v.task_id = task["id"]
			vdata["target_pallet"] = p.id
			vdata["path"] = path
			vdata["path_index"] = 0
			vdata["dropoff_wp"] = drop_wp
			vdata["target_xfer"] = xfer_id
			v.transition(Vehicle.State.TO_DOCK)
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
				return
			var xfer_id: String = p.location_id
			if not _try_request(engine, rack_id, vid):
				continue
			if not _try_request(engine, xfer_id, vid):
				engine.resources.release(rack_id, vid)
				continue

			var drop_wp: String = xfer_id.replace("XFER-", "XFER_DROP_")
			var place_wp: String = "RACK_PLACE_" + _rack_code(rack_id)
			var home: String = _home_wp(engine, vdata, v)
			var path: Array = _join(engine.graph.find_path(home, drop_wp, "RD"),
				engine.graph.find_path(drop_wp, place_wp, "RD"))
			if path.is_empty():
				engine.resources.release(rack_id, vid)
				engine.resources.release(xfer_id, vid)
				continue

			task["rd_id"] = vid
			p.set_status(Pallet.Status.ASSIGNED_TO_RD)
			engine.tasks.transition(p.task_id, engine.TaskStatus.ASSIGNED_RD)
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
			v.transition(Vehicle.State.TO_XFER)
			break

func _advance_vehicles(engine, dt: float) -> void:
	for vid in engine.vehicles:
		var vdata: Dictionary = engine.vehicles[vid]
		var v: Vehicle = vdata["ref"]

		if vdata.get("waiting", false):
			_wait_tick(engine, vid, vdata, v, dt)
			continue

		var path: Array = vdata.get("path", [])
		var idx: int = vdata.get("path_index", 0)
		if path.is_empty() or idx >= path.size():
			if v.state == Vehicle.State.RETURNING:
				v.transition(Vehicle.State.IDLE)
				v.task_id = ""
				vdata["path"] = []
			continue

		var cur_wp: String = path[idx]
		var result: Dictionary = v.follower.step_toward(
			engine.graph.waypoint_pos(cur_wp), vdata["speed"], vdata["turn_rate"], dt, vdata["tolerance"])
		vdata["pos"] = v.follower.position
		if not result["arrived"]:
			continue

		vdata["path_index"] = idx + 1
		var at_end: bool = idx + 1 >= path.size()

		if v.vehicle_class == "PE":
			if v.state == Vehicle.State.TO_DOCK and cur_wp.begins_with("DOCK_PICKUP"):
				_begin_wait(vdata, vid, "PE_PICKUP", pickup_seconds["PE"])
			elif v.state == Vehicle.State.LOADED_TO_XFER and at_end and cur_wp == vdata.get("dropoff_wp", ""):
				_begin_wait(vdata, vid, "PE_DROPOFF", dropoff_seconds["PE"])
		else:
			if v.state == Vehicle.State.TO_XFER and cur_wp == vdata.get("pickup_wp", ""):
				_begin_wait(vdata, vid, "RD_PICKUP", pickup_seconds["RD"])
			elif v.state == Vehicle.State.LOADED_TO_RACK and at_end and cur_wp == vdata.get("place_wp", ""):
				_begin_wait(vdata, vid, "RD_DROPOFF", dropoff_seconds["RD"])

func _begin_wait(vdata: Dictionary, vid: String, kind: String, seconds: float) -> void:
	var v: Vehicle = vdata["ref"]
	if kind == "PE_PICKUP":
		v.transition(Vehicle.State.ALIGN_PICKUP)
		v.transition(Vehicle.State.PICKING)
	elif kind == "PE_DROPOFF":
		v.transition(Vehicle.State.ALIGN_DROPOFF)
		v.transition(Vehicle.State.DROPPING)
	elif kind == "RD_PICKUP":
		v.transition(Vehicle.State.ALIGN_PICKUP)
		v.transition(Vehicle.State.PICKING)
	else:
		v.transition(Vehicle.State.ALIGN_RACK)
		v.transition(Vehicle.State.PLACING)
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
		engine.tasks.transition(v.task_id, engine.TaskStatus.PE_PICKED)
		engine.events.log_event(engine.time, "pe_picked", "%s picked %s" % [vid, v.pallet_id])
		v.transition(Vehicle.State.LOADED_TO_XFER)

	elif kind == "PE_DROPOFF":
		var p = engine.inventory.get_pallet(v.pallet_id)
		if p != null:
			var dock_id: String = p.location_id
			engine.resources.release(dock_id, vid)
			engine.dock_free[dock_id] = true
			p.set_status(Pallet.Status.AT_XFER)
			p.location_id = vdata["target_xfer"]
		engine.tasks.transition(v.task_id, engine.TaskStatus.AT_XFER)
		engine.xfer_state[vdata["target_xfer"]] = "OCCUPIED"
		engine.resources.release(vdata["target_xfer"], vid)
		engine.events.log_event(engine.time, "xfer_drop", "%s dropped %s at %s" % [vid, v.pallet_id, vdata["target_xfer"]])
		v.pallet_id = ""
		vdata["path"] = engine.graph.find_path(vdata.get("dropoff_wp", ""), vdata.get("home_wp", ""), "PE")
		vdata["path_index"] = 0
		vdata["dropoff_wp"] = ""
		vdata["target_xfer"] = ""
		v.transition(Vehicle.State.RETURNING)

	elif kind == "RD_PICKUP":
		var p = engine.inventory.get_pallet(vdata["target_pallet"])
		v.pallet_id = vdata["target_pallet"]
		if p != null:
			p.set_status(Pallet.Status.IN_TRANSIT_RD)
		engine.tasks.transition(v.task_id, engine.TaskStatus.RD_PICKED)
		engine.events.log_event(engine.time, "rd_picked", "%s picked %s" % [vid, v.pallet_id])
		v.transition(Vehicle.State.LOADED_TO_RACK)

	else:  # RD_DROPOFF
		var p = engine.inventory.get_pallet(v.pallet_id)
		var rack_id: String = vdata["target_rack"]
		if p != null:
			p.set_status(Pallet.Status.STORED)
			p.location_id = rack_id
		engine.tasks.transition(v.task_id, engine.TaskStatus.STORED)
		engine.tasks.transition(v.task_id, engine.TaskStatus.COMPLETED)
		engine.rack_slots[rack_id]["state"] = "OCCUPIED"
		engine.rack_slots[rack_id]["pallet"] = v.pallet_id
		engine.xfer_state[vdata["target_xfer"]] = "FREE"
		engine.resources.release(vdata["target_xfer"], vid)
		engine.resources.release(rack_id, vid)
		engine.events.log_event(engine.time, "pallet_stored", "%s stored %s at %s" % [vid, v.pallet_id, rack_id])
		v.pallet_id = ""
		vdata["path"] = engine.graph.find_path(vdata.get("place_wp", ""), vdata.get("home_wp", ""), "RD")
		vdata["path_index"] = 0
		vdata["target_rack"] = ""
		vdata["target_xfer"] = ""
		v.transition(Vehicle.State.RETURNING)

# The home waypoint is the parking waypoint the vehicle started on; found once by
# matching the vehicle's spawn position (setup places it on its start_waypoint).
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

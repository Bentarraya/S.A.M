extends RefCounted

const SimulationEngine = preload("res://scripts/simulation/simulation_engine.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func test_full_workflow() -> int:
	var before := failures
	var e := SimulationEngine.new()
	e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
	var pid := e.add_pallet("SKU-A")
	var task_id := ""
	var limit := 40000
	var steps := 0
	var pe01_carried := false
	while steps < limit:
		e.step(1.0 / 60.0)
		steps += 1
		var p = e.inventory.get_pallet(pid)
		if p == null:
			_check(false, "pallet vanished")
			break
		if p.status == e.PalletStatus.STORED:
			break
		if p.task_id != "":
			task_id = p.task_id
		if e.vehicles["PE-01"]["pallet_id"] == pid:
			pe01_carried = true
		if e.vehicles["RD-01"]["pallet_id"] != "":
			var carried = e.inventory.get_pallet(e.vehicles["RD-01"]["pallet_id"])
			_check(carried != null and carried.status == e.PalletStatus.IN_TRANSIT_RD, "RD only carries IN_TRANSIT_RD pallets")
	_check(e.inventory.get_pallet(pid).status == e.PalletStatus.STORED, "pallet stored after %d steps" % steps)
	_check(e.tasks.get_task(task_id)["status"] == e.TaskStatus.COMPLETED, "task completed")
	var placed := false
	for slot_id in e.rack_slots:
		if e.rack_slots[slot_id]["pallet"] == pid:
			placed = true
	_check(placed, "pallet occupies a rack slot")
	_check(pe01_carried, "PE-01 carried the pallet")
	_check(e.vehicles["PE-02"]["ref"].state == e.Vehicle.State.IDLE, "PE-02 stayed idle")
	_check(e.vehicles["PE-02"]["pallet_id"] == "", "PE-02 never acquired a pallet")
	_check(e.vehicles["PE-01"]["pallet_id"] == "", "PE-01 released pallet")
	_check(e.vehicles["RD-01"]["pallet_id"] == "", "RD released pallet")
	_check(e.vehicles["PE-01"]["ref"].invalid_transitions == 0, "PE-01 no invalid transitions")
	_check(e.vehicles["PE-02"]["ref"].invalid_transitions == 0, "PE-02 no invalid transitions")
	_check(e.vehicles["RD-01"]["ref"].invalid_transitions == 0, "RD-01 no invalid transitions")
	_check(e.events.entries.size() > 5, "events logged")
	return failures - before

# Regression: PE departing a handoff and RD entering it must never occupy the
# pad area simultaneously. The XFER station resource must stay held until the
# previous occupant's BODY has left the pad (arrived at its next waypoint).
func test_handoff_exclusive_use() -> int:
	var before := failures
	var e: SimulationEngine = SimulationEngine.new()
	e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
	var pid1: String = e.add_pallet("SKU-A")
	var pid2: String = e.add_pallet("SKU-B")
	var xfer_pads := {"XFER-01": e.graph.waypoint_pos("XFER_DROP_01"), "XFER-02": e.graph.waypoint_pos("XFER_DROP_02")}
	var pad_radius := 1.0  # pad is 2x2, so 1.0 from center covers the whole pad
	var limit: int = 80000
	var steps: int = 0
	while steps < limit:
		e.step(1.0 / 60.0)
		steps += 1
		var both_stored: bool = true
		for pid in [pid1, pid2]:
			var pal: Object = e.inventory.get_pallet(pid)
			if pal == null or pal.status != e.PalletStatus.STORED:
				both_stored = false
		if both_stored:
			break
		# While any vehicle still holds an XFER resource, no OTHER vehicle body may be inside that pad.
		for xfer_id in xfer_pads:
			for vid in e.vehicles:
				if not e.resources.is_held_by(xfer_id, vid):
					continue
				for other_vid in e.vehicles:
					if other_vid == vid:
						continue
					var op: Vector3 = e.vehicles[other_vid]["pos"]
					var inside: bool = Vector2(op.x, op.z).distance_to(Vector2(xfer_pads[xfer_id].x, xfer_pads[xfer_id].z)) < pad_radius
					_check(not inside, "%s body inside %s pad while held by %s (step %d)" % [other_vid, xfer_id, vid, steps])
	var p1: Object = e.inventory.get_pallet(pid1)
	var p2: Object = e.inventory.get_pallet(pid2)
	_check(p1 != null and p1.status == e.PalletStatus.STORED, "pallet 1 stored (handoff test)")
	_check(p2 != null and p2.status == e.PalletStatus.STORED, "pallet 2 stored (handoff test)")
	return failures - before

# Regression: after storing, the RD must take the next pallet waiting at a
# handoff instead of driving home and parking first.
func test_rd_chains_to_next_pallet() -> int:
	var before := failures
	var e: SimulationEngine = SimulationEngine.new()
	e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
	var pid1: String = e.add_pallet("SKU-A")
	e.add_pallet("SKU-B")
	var steps: int = 0
	while steps < 40000 and e.inventory.get_pallet(pid1).status != e.PalletStatus.STORED:
		e.step(1.0 / 60.0)
		steps += 1
	_check(e.inventory.get_pallet(pid1).status == e.PalletStatus.STORED, "first pallet stored (chain test)")
	var chained := false
	var parked := false
	for i in range(4000):
		e.step(1.0 / 60.0)
		var vdata: Dictionary = e.vehicles["RD-01"]
		var state: int = vdata["ref"].state
		if state == e.Vehicle.State.IDLE:
			parked = true
		if state == e.Vehicle.State.TO_XFER and vdata["path"].size() > 0:
			chained = vdata["path"][0] != "RD_PARK"
			break
	_check(chained, "RD chains from return to the next handoff")
	_check(not parked, "RD never idles at the park between pallets")
	return failures - before

# Regression: failed reservations must not leave phantom waiters behind.
# Six pallets through two handoff stations used to deadlock with both XFER
# resources stuck on an idle PE.
func test_many_pallets_no_stall() -> int:
	var before := failures
	var e: SimulationEngine = SimulationEngine.new()
	e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
	var pids: Array = []
	var steps: int = 0
	while steps < 120000:
		e.step(1.0 / 60.0)
		steps += 1
		# Only three docks: feed a new pallet whenever one is free.
		if pids.size() < 6 and steps % 120 == 0:
			var pid: String = e.add_pallet("SKU-%d" % pids.size())
			if pid != "":
				pids.append(pid)
		if pids.size() < 6:
			continue
		var done := true
		for pid in pids:
			if e.inventory.get_pallet(pid).status != e.PalletStatus.STORED:
				done = false
				break
		for vid in e.vehicles:
			if e.vehicles[vid]["ref"].state != e.Vehicle.State.IDLE:
				done = false
		if done:
			break
	_check(pids.size() == 6, "six pallets spawned (stall test)")
	for pid in pids:
		_check(e.inventory.get_pallet(pid).status == e.PalletStatus.STORED, "pallet %s stored (stall test)" % pid)
	for res_id in e.resources._capacity.keys():
		if res_id.begins_with("DOCK-") or res_id.begins_with("XFER-") or res_id.begins_with("RACK-"):
			_check(e.resources.holders(res_id).is_empty(), "no holder for " + res_id + " (stall test)")
	return failures - before

func test_two_pallets() -> int:
	var before := failures
	var e: SimulationEngine = SimulationEngine.new()
	e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
	var pid1: String = e.add_pallet("SKU-A")
	var pid2: String = e.add_pallet("SKU-B")
	var limit: int = 80000
	var steps: int = 0
	while steps < limit:
		e.step(1.0 / 60.0)
		steps += 1
		var p1: Object = e.inventory.get_pallet(pid1)
		var p2: Object = e.inventory.get_pallet(pid2)
		if p1 != null and p1.status == e.PalletStatus.STORED and p2 != null and p2.status == e.PalletStatus.STORED:
			var all_idle := true
			for vid in e.vehicles:
				if e.vehicles[vid]["ref"].state != e.Vehicle.State.IDLE:
					all_idle = false
					break
			if all_idle:
				break
	_check(e.inventory.get_pallet(pid1).status == e.PalletStatus.STORED, "pallet 1 stored")
	_check(e.inventory.get_pallet(pid2).status == e.PalletStatus.STORED, "pallet 2 stored")
	var p1: Object = e.inventory.get_pallet(pid1)
	var p2: Object = e.inventory.get_pallet(pid2)
	var t1: Dictionary = e.tasks.get_task(p1.task_id)
	var t2: Dictionary = e.tasks.get_task(p2.task_id)
	_check(not t1.is_empty() and t1["status"] == e.TaskStatus.COMPLETED, "task 1 completed")
	_check(not t2.is_empty() and t2["status"] == e.TaskStatus.COMPLETED, "task 2 completed")
	var occupied := 0
	var pallet_in_slot := {}
	for slot_id in e.rack_slots:
		if e.rack_slots[slot_id]["pallet"] != "":
			occupied += 1
			var pid: String = e.rack_slots[slot_id]["pallet"]
			_check(not pallet_in_slot.has(pid), "pallet %s in multiple slots" % pid)
			pallet_in_slot[pid] = true
	_check(occupied == 2, "two rack slots occupied")
	for res_id in e.resources._capacity.keys():
		if res_id.begins_with("DOCK-") or res_id.begins_with("XFER-") or res_id.begins_with("RACK-"):
			_check(e.resources.holders(res_id).is_empty(), "no holder for " + res_id)
	_check(e.resources.is_held_by("PE_PARK_01", "PE-01"), "PE-01 holds park")
	_check(e.resources.is_held_by("PE_PARK_02", "PE-02"), "PE-02 holds park")
	_check(e.resources.is_held_by("RD_PARK", "RD-01"), "RD-01 holds park")
	for vid in e.vehicles:
		_check(e.vehicles[vid]["ref"].invalid_transitions == 0, "%s has 0 invalid transitions" % vid)
	return failures - before

func test_reset() -> int:
	var before := failures
	var e := SimulationEngine.new()
	e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
	var pid := e.add_pallet("SKU-A")
	for i in range(100):
		e.step(1.0 / 60.0)
	e.reset()
	_check(e.time == 0.0, "reset restores time")
	_check(e.step_count == 0, "reset restores step_count")
	_check(e.blocked_reasons.is_empty(), "reset clears blocked reasons")
	_check(e.vehicles["PE-01"]["pos"] == Vector3(8, 0, 2.5), "reset restores vehicle pos")
	_check(e.vehicles["PE-01"]["heading"] == 0.0, "reset restores vehicle heading")
	_check(e.vehicles["PE-01"]["target_waypoint"] == "", "reset clears target waypoint")
	_check(e.resources.is_held_by("PE_PARK_01", "PE-01"), "reset restores park holder")
	return failures - before

func test_determinism() -> int:
	var before := failures
	var out: Array = []
	for run_index in [0, 1]:
		var e := SimulationEngine.new()
		e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
		e.run_demo()
		for i in range(20000):
			e.step(1.0 / 60.0)
		var snap := []
		for vid in ["PE-01", "PE-02", "RD-01"]:
			snap.append([vid, e.vehicles[vid]["pos"], e.vehicles[vid]["ref"].state])
		var pids: Array = e.inventory._pallets.keys()
		pids.sort()
		for pid in pids:
			snap.append([pid, e.inventory.get_pallet(pid).status])
		out.append(snap)
	_check(str(out[0]) == str(out[1]), "identical replay after 20000 steps")
	return failures - before

func run() -> int:
	var e := SimulationEngine.new()
	_check(e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json"), "engine setup")
	_check(e.vehicles.size() == 3, "3 vehicles")
	_check(e.vehicles.has("PE-01") and e.vehicles.has("PE-02") and e.vehicles.has("RD-01"), "vehicle ids")
	_check(e.vehicles["PE-01"]["pos"] == Vector3(8, 0, 2.5), "PE-01 parked")
	_check(e.rack_slots.size() == 8, "8 rack slots tracked")

	var id := e.add_pallet("SKU-A")
	_check(id == "PLT-0001", "pallet id sequence")
	_check(e.inventory.get_pallet(id).status == e.PalletStatus.AT_DOCK, "pallet at dock")
	_check(e.add_pallet("SKU-B") == "PLT-0002", "second pallet")

	var start := e.time
	e.step(1.0 / 60.0)
	_check(is_equal_approx(e.time, start + 1.0 / 60.0), "time advances")

	var bad := SimulationEngine.new()
	_check(not bad.setup("res://data/warehouse_layout.json", "res://data/missing.json", "res://data/vehicle_config.json"), "setup fails loudly on missing routes")

	# Full workflow tests
	test_full_workflow()
	test_rd_chains_to_next_pallet()
	test_many_pallets_no_stall()
	test_two_pallets()
	test_handoff_exclusive_use()
	test_reset()
	test_determinism()

	return failures
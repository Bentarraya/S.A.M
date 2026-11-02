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
	_check(e.vehicles["PE-01"]["pallet_id"] == "" and e.vehicles["PE-02"]["pallet_id"] == "", "PEs released pallet")
	_check(e.vehicles["RD-01"]["pallet_id"] == "", "RD released pallet")
	_check(e.events.entries.size() > 5, "events logged")
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
			break
	_check(e.inventory.get_pallet(pid1).status == e.PalletStatus.STORED, "pallet 1 stored")
	_check(e.inventory.get_pallet(pid2).status == e.PalletStatus.STORED, "pallet 2 stored")
	var occupied := 0
	var pallet_in_slot := {}
	for slot_id in e.rack_slots:
		if e.rack_slots[slot_id]["pallet"] != "":
			occupied += 1
			var pid: String = e.rack_slots[slot_id]["pallet"]
			_check(not pallet_in_slot.has(pid), "pallet %s in multiple slots" % pid)
			pallet_in_slot[pid] = true
	_check(occupied == 2, "two rack slots occupied")
	return failures - before

func run() -> int:
	var e := SimulationEngine.new()
	_check(e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json"), "engine setup")
	_check(e.vehicles.size() == 3, "3 vehicles")
	_check(e.vehicles.has("PE-01") and e.vehicles.has("PE-02") and e.vehicles.has("RD-01"), "vehicle ids")
	_check(e.vehicles["PE-01"]["pos"] == Vector3(8, 0, 1), "PE-01 parked")
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
	test_two_pallets()

	return failures
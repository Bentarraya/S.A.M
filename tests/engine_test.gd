extends RefCounted

const SimulationEngine = preload("res://scripts/simulation/simulation_engine.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

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
	return failures
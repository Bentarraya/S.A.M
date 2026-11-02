extends RefCounted

const WarehouseLayout = preload("res://scripts/simulation/warehouse_layout.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var l := WarehouseLayout.new()
	_check(l.load_from_file("res://data/warehouse_layout.json"), "layout loads")
	_check(l.dock_positions.size() == 3, "3 dock positions")
	_check(l.dock_positions["DOCK-01"] == Vector3(2, 0, 2), "DOCK-01 position")
	_check(l.handoff_stations.size() == 2, "2 handoff stations")
	_check(l.rack_slots.size() == 8, "8 rack slots")
	_check(l.rack_slots["RACK-D-02"] == Vector3(30, 0, 6), "RACK-D-02 position")
	_check(l.obstacles.size() == 12, "12 obstacles")
	_check(l.floor_size == Vector2(36, 8), "floor size")
	return failures

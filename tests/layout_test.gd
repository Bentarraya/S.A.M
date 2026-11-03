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

	# Fix round 1: AABB position/size correctness
	var rack_a_s := -1
	for i in range(l.obstacles.size()):
		if l.obstacles[i]["id"] == "RACK-A-S":
			rack_a_s = i
			break
	_check(rack_a_s != -1, "RACK-A-S obstacle found")
	if rack_a_s != -1:
		var aabb = l.obstacles[rack_a_s]["aabb"]
		_check(aabb.position == Vector3(17.5, 0, 1.4), "RACK-A-S AABB position")
		_check(aabb.size == Vector3(1, 2, 1.2), "RACK-A-S AABB size")

	# Fix round 1: areas stored as Rect2
	_check(l.areas["DOCK_ROOM"] == Rect2(Vector2(0, 0), Vector2(12, 8)), "DOCK_ROOM Rect2")
	_check(l.areas["STORAGE_ROOM"] == Rect2(Vector2(16, 0), Vector2(20, 8)), "STORAGE_ROOM Rect2")

	# Fix round 1: malformed/non-JSON input fails safely.
	# Plain-text fixture (not .godot config) so Godot's parser doesn't log
	# an ERROR line that reads like a test failure.
	var l2 := WarehouseLayout.new()
	_check(l2.load_from_file("res://tests/fixtures/invalid_json.txt") == false, "non-JSON file returns false")

	return failures
extends RefCounted

const WarehouseLayout = preload("res://scripts/simulation/warehouse_layout.gd")
const RouteGraph = preload("res://scripts/navigation/route_graph.gd")
const RouteValidator = preload("res://scripts/navigation/route_validator.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var layout := WarehouseLayout.new()
	layout.load_from_file("res://data/warehouse_layout.json")
	var g := RouteGraph.new()
	_check(g.load_from_file("res://data/routes.json"), "routes load")
	_check(g.get_waypoint("DOCK_PICKUP_01")["type"] == "pickup", "pickup type")
	_check(g.waypoint_pos("RACK_PLACE_D_02") == Vector3(30, 0, 6), "place position")

	var pe_path := g.find_path("PE_PARK_01", "XFER_DROP_01", "PE")
	_check(pe_path.size() > 0, "PE path to handoff exists")
	_check(pe_path[0] == "PE_PARK_01" and pe_path[-1] == "XFER_DROP_01", "PE path endpoints")
	_check(pe_path.has("XFER_EXIT"), "PE path uses return lane")

	var rd_path := g.find_path("XFER_DROP_01", "RACK_PLACE_B_02", "RD")
	_check(rd_path.size() > 0, "RD path to rack exists")
	_check(rd_path.has("XFER_DROP_01"), "RD path starts at handoff")

	var wrong_class := g.find_path("XFER_DROP_01", "RACK_PLACE_A_01", "PE")
	_check(wrong_class.size() == 0, "PE cannot enter storage rack path")

	var errors := RouteValidator.new().validate(g, layout)
	_check(errors.is_empty(), "route graph validates: " + str(errors))

	var empty_errors := RouteValidator.new().validate(RouteGraph.new(), layout)
	_check(not empty_errors.is_empty(), "validator rejects empty/invalid graph")
	return failures

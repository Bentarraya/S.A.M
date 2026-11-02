extends RefCounted
class_name SimulationEngine

const WarehouseLayout = preload("res://scripts/simulation/warehouse_layout.gd")
const RouteGraph = preload("res://scripts/navigation/route_graph.gd")
const RouteValidator = preload("res://scripts/navigation/route_validator.gd")
const Vehicle = preload("res://scripts/entities/vehicle.gd")
const Pallet = preload("res://scripts/entities/pallet.gd")
const InventoryManager = preload("res://scripts/simulation/inventory_manager.gd")
const TaskManager = preload("res://scripts/simulation/task_manager.gd")
const ResourceManager = preload("res://scripts/simulation/resource_manager.gd")
const EventLog = preload("res://scripts/simulation/event_log.gd")

const PalletStatus = Pallet.Status
const TaskStatus = TaskManager.Status

var time: float = 0.0
var step_count: int = 0
var layout: WarehouseLayout
var graph: RouteGraph
var inventory: InventoryManager
var tasks: TaskManager
var resources: ResourceManager
var events: EventLog
var vehicles: Dictionary = {}
var dock_free: Dictionary = {}
var xfer_state: Dictionary = {}
var rack_slots: Dictionary = {}
var blocked_reasons: Dictionary = {}

var _pallet_counter: int = 1
var _initial_snapshot: Dictionary = {}

func setup(layout_path: String, routes_path: String, config_path: String) -> bool:
	layout = WarehouseLayout.new()
	if not layout.load_from_file(layout_path):
		return false

	graph = RouteGraph.new()
	if not graph.load_from_file(routes_path):
		return false

	var validator = RouteValidator.new()
	var errors = validator.validate(graph, layout)
	if errors.size() > 0:
		for err in errors:
			printerr("Route validation: " + err)
		return false

	inventory = InventoryManager.new()
	tasks = TaskManager.new()
	resources = ResourceManager.new()
	events = EventLog.new()

	vehicles.clear()
	dock_free.clear()
	xfer_state.clear()
	rack_slots.clear()
	blocked_reasons.clear()

	# Create resources from non-empty waypoint resources + vehicle parks
	var resource_set: Array = []
	for w in graph.waypoints.values():
		var res: String = w.get("resource", "")
		if res != "" and not resource_set.has(res):
			resource_set.append(res)

	for res in resource_set:
		resources.add_resource(res, 1)

	# Vehicle parks have capacity 2 for PE_PARK
	resources.add_resource("PE_PARK_01", 2)
	resources.add_resource("PE_PARK_02", 2)
	resources.add_resource("RD_PARK", 2)

	# Initialize dock availability
	for dock_id in layout.dock_positions.keys():
		dock_free[dock_id] = true

	# Initialize transfer station state
	for xfer_id in layout.handoff_stations.keys():
		xfer_state[xfer_id] = "FREE"

	# Initialize rack slots
	for rack_id in layout.rack_slots.keys():
		rack_slots[rack_id] = {"state": "FREE", "pallet": ""}

	# Create vehicles
	var config_file = FileAccess.open(config_path, FileAccess.READ)
	if not config_file:
		printerr("Failed to open vehicle config: " + config_path)
		return false

	var config_data = JSON.parse_string(config_file.get_as_text())
	config_file.close()
	if typeof(config_data) != TYPE_DICTIONARY or not config_data.has("vehicles"):
		printerr("Invalid vehicle config")
		return false

	for vdata in config_data["vehicles"]:
		var v = Vehicle.new()
		v.id = vdata["id"]
		v.vehicle_class = vdata["class"]
		var start_wp = vdata.get("start_waypoint", vdata["id"])
		v.follower.position = graph.waypoint_pos(start_wp)
		v.follower.heading = 0.0
		v.task_id = ""
		v.pallet_id = ""
		v.blocked_reason = ""
		v.invalid_transitions = 0
		vehicles[v.id] = {
			"ref": v,
			"pos": v.follower.position,
			"speed": vdata.get("speed", 2.0),
			"turn_rate": vdata.get("turn_rate", 3.0),
			"tolerance": vdata.get("tolerance", 0.1),
			"target_waypoint": "",
		}

	# Request parking resources for initial vehicle positions
	if vehicles.has("PE-01"):
		resources.request("PE_PARK_01", "PE-01", 0)
	if vehicles.has("PE-02"):
		resources.request("PE_PARK_02", "PE-02", 0)
	if vehicles.has("RD-01"):
		resources.request("RD_PARK", "RD-01", 0)

	# Take initial snapshot for reset
	_pallet_counter = 1
	_take_snapshot()
	return true

func _take_snapshot() -> void:
	_initial_snapshot = {
		"time": 0.0,
		"step_count": 0,
		"vehicles": {},
		"dock_free": dock_free.duplicate(true),
		"xfer_state": xfer_state.duplicate(true),
		"rack_slots": rack_slots.duplicate(true),
		"blocked_reasons": blocked_reasons.duplicate(true),
	}
	for vid in vehicles:
		var vdata = vehicles[vid]
		_initial_snapshot["vehicles"][vid] = {
			"pos": vdata["pos"],
			"state": vdata["ref"].state,
			"task_id": vdata["ref"].task_id,
			"pallet_id": vdata["ref"].pallet_id,
		}

func step(dt: float) -> void:
	time += dt
	step_count += 1

func add_pallet(sku: String) -> String:
	var pallet_id := "PLT-%04d" % _pallet_counter

	# Find first free dock position (FIFO)
	var dock_id: String = ""
	for d in layout.dock_positions.keys():
		if dock_free.get(d, false):
			dock_id = d
			break

	if dock_id == "":
		return ""

	_pallet_counter += 1
	dock_free[dock_id] = false

	if not inventory.add_pallet(pallet_id, sku, dock_id):
		dock_free[dock_id] = true
		return ""

	var pallet = inventory.get_pallet(pallet_id)
	pallet.status = PalletStatus.AT_DOCK

	tasks.create_task(pallet_id)
	events.log_event(time, "pallet_spawned", "Pallet " + pallet_id + " (" + sku + ") at " + dock_id)

	return pallet_id

func run_demo() -> void:
	add_pallet("SKU-A")
	add_pallet("SKU-B")
	add_pallet("SKU-C")
	add_pallet("SKU-D")

func reset() -> void:
	time = _initial_snapshot["time"]
	step_count = _initial_snapshot["step_count"]

	inventory = InventoryManager.new()
	tasks = TaskManager.new()
	events = EventLog.new()

	dock_free = _initial_snapshot["dock_free"].duplicate(true)
	xfer_state = _initial_snapshot["xfer_state"].duplicate(true)
	rack_slots = _initial_snapshot["rack_slots"].duplicate(true)
	blocked_reasons = _initial_snapshot["blocked_reasons"].duplicate(true)

	_pallet_counter = 1

	for vid in _initial_snapshot["vehicles"]:
		var vdata = _initial_snapshot["vehicles"][vid]
		if vehicles.has(vid):
			var v = vehicles[vid]["ref"]
			v.follower.position = vdata["pos"]
			v.state = vdata["state"]
			v.task_id = vdata["task_id"]
			v.pallet_id = vdata["pallet_id"]
			v.blocked_reason = ""
			v.invalid_transitions = 0
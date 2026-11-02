extends Node3D

const SimulationEngine = preload("res://scripts/simulation/simulation_engine.gd")
const WarehouseBuilder = preload("res://scripts/app/warehouse_builder.gd")
const Pallet = preload("res://scripts/entities/pallet.gd")

const LAYOUT_PATH := "res://data/warehouse_layout.json"
const ROUTES_PATH := "res://data/routes.json"
const CONFIG_PATH := "res://data/vehicle_config.json"
const FIXED_DT := 1.0 / 60.0
# Cap catch-up steps so a slow frame cannot spiral into a long stall.
const MAX_CATCHUP_STEPS := 8

@onready var hud: CanvasLayer = $HUD

var sim: SimulationEngine
var world: Dictionary = {}
var accumulator := 0.0
var paused := false
var speed_multiplier := 1.0
var selected_vehicle := "PE-01"
# Assigned by the route overlay task.
var route_overlay: Node3D = null
var waypoint_labels: Node3D = null

var _pallet_nodes: Dictionary = {}

func _ready() -> void:
	sim = SimulationEngine.new()
	if not sim.setup(LAYOUT_PATH, ROUTES_PATH, CONFIG_PATH):
		push_error("Failed to set up simulation")
		return
	world = WarehouseBuilder.build_world(self, sim.layout, sim.graph)
	_wire_hud()
	hud.set_selected_vehicle(selected_vehicle)

func _wire_hud() -> void:
	hud.start_pressed.connect(_on_start_pressed)
	hud.pause_toggled.connect(_on_pause_toggled)
	hud.reset_pressed.connect(_on_reset_pressed)
	hud.speed_changed.connect(_on_speed_changed)
	hud.add_pallet_pressed.connect(_on_add_pallet_pressed)
	hud.demo_pressed.connect(_on_demo_pressed)
	hud.route_overlay_toggled.connect(_on_route_overlay_toggled)
	hud.waypoint_labels_toggled.connect(_on_waypoint_labels_toggled)
	hud.camera_preset_changed.connect(_on_camera_preset_changed)
	hud.vehicle_selected.connect(_on_vehicle_selected)

func _on_start_pressed() -> void:
	paused = false

func _on_pause_toggled(is_paused: bool) -> void:
	paused = is_paused

func _on_reset_pressed() -> void:
	sim.reset()
	accumulator = 0.0

func _on_speed_changed(mult: float) -> void:
	speed_multiplier = mult

func _on_add_pallet_pressed() -> void:
	sim.add_pallet("SKU-X")

func _on_demo_pressed() -> void:
	sim.run_demo()

func _on_route_overlay_toggled(v: bool) -> void:
	if route_overlay != null:
		route_overlay.visible = v

func _on_waypoint_labels_toggled(v: bool) -> void:
	if waypoint_labels != null:
		waypoint_labels.visible = v

func _on_camera_preset_changed(preset: String) -> void:
	_set_camera_preset(preset)

func _on_vehicle_selected(veh_id: String) -> void:
	selected_vehicle = veh_id
	hud.set_selected_vehicle(veh_id)

func _set_camera_preset(_preset: String) -> void:
	pass  # camera presets arrive with the route overlay task

func _physics_process(delta: float) -> void:
	if sim == null or paused:
		return
	accumulator += delta * speed_multiplier
	var steps := 0
	while accumulator >= FIXED_DT and steps < MAX_CATCHUP_STEPS:
		sim.step(FIXED_DT)
		accumulator -= FIXED_DT
		steps += 1
	if steps == MAX_CATCHUP_STEPS:
		accumulator = 0.0

func _process(_delta: float) -> void:
	if sim == null:
		return
	_sync_vehicles()
	_sync_racks()
	_sync_pallets()
	hud.update_state(sim, paused, Engine.get_frames_per_second())

func _sync_vehicles() -> void:
	for vid in world["vehicles"]:
		var v: Dictionary = sim.vehicles.get(vid, {})
		if v.is_empty():
			continue
		var node: MeshInstance3D = world["vehicles"][vid]
		var pos: Vector3 = v["pos"]
		node.position.x = pos.x
		node.position.z = pos.z
		node.rotation.y = -float(v["heading"])

func _sync_racks() -> void:
	for slot_id in world["rack_nodes"]:
		var state: String = sim.rack_slots.get(slot_id, {}).get("state", "FREE")
		var mat: StandardMaterial3D = world["rack_nodes"][slot_id].material_override
		var color: Color = WarehouseBuilder.RACK_STATE_COLORS.get(state, Color.WHITE)
		if mat.albedo_color != color:
			mat.albedo_color = color

func _sync_pallets() -> void:
	var seen := {}
	for status in Pallet.Status.values():
		for p in sim.inventory.pallets_with_status(status):
			seen[p.id] = true
			var node: MeshInstance3D = _pallet_nodes.get(p.id)
			if node == null:
				node = WarehouseBuilder.build_pallet_mesh()
				node.name = p.id
				world["pallets_root"].add_child(node)
				_pallet_nodes[p.id] = node
			_place_pallet(node, p)

	for pid in _pallet_nodes.keys():
		if not seen.has(pid):
			_pallet_nodes[pid].queue_free()
			_pallet_nodes.erase(pid)

func _place_pallet(node: MeshInstance3D, p) -> void:
	for vid in sim.vehicles:
		if sim.vehicles[vid]["pallet_id"] != p.id:
			continue
		var vpos: Vector3 = sim.vehicles[vid]["pos"]
		var heading: float = sim.vehicles[vid]["heading"]
		node.rotation.y = -heading
		if sim.vehicles[vid]["ref"].vehicle_class == "RD":
			var front := Vector3(cos(heading), 0.0, sin(heading)) * 0.95
			node.position = vpos + front + Vector3(0.0, 0.2, 0.0)
		else:
			node.position = vpos + Vector3(0.0, 0.375, 0.0)
		node.visible = true
		return

	node.rotation.y = 0.0
	var pos := Vector3.ZERO
	var y := 0.075
	if sim.layout.dock_positions.has(p.location_id):
		pos = sim.layout.dock_positions[p.location_id]
	elif sim.layout.handoff_stations.has(p.location_id):
		pos = sim.layout.handoff_stations[p.location_id]
	elif sim.layout.rack_slots.has(p.location_id):
		pos = sim.layout.rack_slots[p.location_id]
		y = 2.11
	else:
		node.visible = false
		return
	node.visible = true
	node.position = pos + Vector3(0.0, y, 0.0)

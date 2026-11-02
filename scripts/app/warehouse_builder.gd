extends RefCounted
class_name WarehouseBuilder

const FLOOR_COLOR := Color(0.16, 0.17, 0.19)
const WALL_COLOR := Color(0.55, 0.57, 0.6)
const RACK_COLOR := Color(0.18, 0.22, 0.3)
const DOCK_COLOR := Color(0.28, 0.42, 0.55)
const XFER_COLOR := Color(0.95, 0.8, 0.2)
const PALLET_COLOR := Color(0.72, 0.55, 0.32)
const RD_COLOR := Color(0.6, 0.62, 0.65)
const RACK_HEIGHT := 2.0

const PE_COLORS := {
	"PE-01": Color(0.2, 0.4, 0.9),
	"PE-02": Color(0.95, 0.55, 0.1),
}
const RACK_STATE_COLORS := {
	"FREE": Color(0.25, 0.85, 0.35),
	"RESERVED": Color(1.0, 0.8, 0.1),
	"OCCUPIED": Color(0.9, 0.2, 0.2),
}

# Builds every static prop plus vehicle visuals. Returns the nodes main.gd syncs each frame.
static func build_world(parent: Node3D, layout, _graph) -> Dictionary:
	var world := {
		"vehicles": {},
		"pallets_root": Node3D.new(),
		"rack_nodes": {},
		"xfer_nodes": {},
		"dock_nodes": {},
	}
	world["pallets_root"].name = "Pallets"
	parent.add_child(world["pallets_root"])

	_build_floor(parent, layout)
	_build_obstacles(parent, layout)
	_build_stations(parent, layout, world)
	_build_rack_indicators(parent, layout, world)
	_build_vehicles(parent, world)
	_build_area_labels(parent, layout)

	return world

static func build_pallet_mesh() -> MeshInstance3D:
	return _instance(_box(Vector3(1.2, 0.15, 1.0)), _material(PALLET_COLOR, false))

static func build_pe_mesh(color: Color) -> MeshInstance3D:
	var node := _instance(_box(Vector3(1.2, 0.3, 0.8)), _material(color, false))
	node.position.y = 0.15
	return node

static func build_rd_mesh() -> MeshInstance3D:
	var body := _instance(_box(Vector3(1.5, 1.0, 0.9)), _material(RD_COLOR, false))
	body.position.y = 0.5
	var mast := _instance(_box(Vector3(0.2, 1.6, 0.2)), _material(RD_COLOR.darkened(0.25), false))
	mast.position = Vector3(0.55, 0.3, 0)
	body.add_child(mast)
	var fork := _instance(_box(Vector3(0.9, 0.08, 0.15)), _material(RD_COLOR.darkened(0.4), false))
	fork.position = Vector3(0.95, -0.42, 0)
	body.add_child(fork)
	return body

static func _build_floor(parent: Node3D, layout) -> void:
	var plane := PlaneMesh.new()
	plane.size = layout.floor_size
	var floor_node := _instance(plane, _material(FLOOR_COLOR, true))
	floor_node.name = "Floor"
	floor_node.position = Vector3(layout.floor_size.x * 0.5, 0.0, layout.floor_size.y * 0.5)
	parent.add_child(floor_node)

static func _build_obstacles(parent: Node3D, layout) -> void:
	for o in layout.obstacles:
		var id: String = o["id"]
		if id.begins_with("WALL"):
			var wall := _instance(_box(o["aabb"].size), _material(WALL_COLOR, false))
			wall.name = id
			wall.position = o["aabb"].get_center()
			parent.add_child(wall)
		elif id.begins_with("RACK"):
			var rack := _instance(_box(o["aabb"].size), _material(RACK_COLOR, false))
			rack.name = id
			rack.position = o["aabb"].get_center()
			parent.add_child(rack)

static func _build_stations(parent: Node3D, layout, world: Dictionary) -> void:
	for dock_id in layout.dock_positions:
		var dock := _instance(_box(Vector3(2.0, 0.02, 2.0)), _material(DOCK_COLOR, true))
		dock.name = dock_id
		dock.position = layout.dock_positions[dock_id] + Vector3(0.0, 0.01, 0.0)
		parent.add_child(dock)
		_label(dock, dock_id, Vector3(0.0, 0.04, 0.0))
		world["dock_nodes"][dock_id] = dock

	for xfer_id in layout.handoff_stations:
		var xfer := _instance(_box(Vector3(2.0, 0.02, 2.0)), _material(XFER_COLOR, true))
		xfer.name = xfer_id
		xfer.position = layout.handoff_stations[xfer_id] + Vector3(0.0, 0.01, 0.0)
		parent.add_child(xfer)
		_label(xfer, xfer_id, Vector3(0.0, 0.04, 0.0))
		world["xfer_nodes"][xfer_id] = xfer

static func _build_rack_indicators(parent: Node3D, layout, world: Dictionary) -> void:
	for slot_id in layout.rack_slots:
		var quad := _instance(_box(Vector3(1.0, 0.01, 1.0)), _material(RACK_STATE_COLORS["FREE"], true))
		quad.name = slot_id
		# On top of the 2 m rack so the state stays visible with the solid blockout.
		quad.position = layout.rack_slots[slot_id] + Vector3(0.0, RACK_HEIGHT + 0.02, 0.0)
		parent.add_child(quad)
		world["rack_nodes"][slot_id] = quad

static func _build_vehicles(parent: Node3D, world: Dictionary) -> void:
	for vid in PE_COLORS:
		var pe := build_pe_mesh(PE_COLORS[vid])
		pe.name = vid
		_label(pe, vid, Vector3(0.0, 1.25, 0.0))
		parent.add_child(pe)
		world["vehicles"][vid] = pe

	var rd := build_rd_mesh()
	rd.name = "RD-01"
	_label(rd, "RD-01", Vector3(0.0, 1.5, 0.0))
	parent.add_child(rd)
	world["vehicles"]["RD-01"] = rd

static func _build_area_labels(parent: Node3D, layout) -> void:
	for area_id in layout.areas:
		var rect: Rect2 = layout.areas[area_id]
		var center := Vector3(rect.position.x + rect.size.x * 0.5, 2.5, rect.position.y + rect.size.y * 0.5)
		var label := _label(parent, area_id.replace("_", " "), center)
		label.name = area_id

static func _label(parent: Node3D, text: String, pos: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.01
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos
	parent.add_child(label)
	return label

static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

static func _instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	return node

static func _material(color: Color, unlit: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unlit:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

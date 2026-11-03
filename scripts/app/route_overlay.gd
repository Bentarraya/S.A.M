extends Node3D

const EDGE_COLOR := Color(0.1, 0.9, 1.0)
const EDGE_Y := 0.05
const MARKER_COLOR := Color(1.0, 0.8, 0.2)
const TARGET_COLOR := Color(0.2, 1.0, 0.35)
const MARKER_TYPES := ["turn", "wait", "pickup", "handoff"]
const TARGET_RADIUS := 0.12

var _waypoint_positions: Dictionary = {}
var _labels_root: Node3D
var _target_markers: Dictionary = {}

func build(graph, _layout) -> void:
	for id in graph.waypoints:
		_waypoint_positions[id] = graph.waypoint_pos(id)
	_build_edges(graph)
	_build_waypoint_markers(graph)
	_build_labels(graph)
	_build_target_markers()

func set_labels_visible(v: bool) -> void:
	if _labels_root != null:
		_labels_root.visible = v

func update_vehicle_markers(vehicles: Dictionary) -> void:
	for vid in _target_markers:
		var marker: MeshInstance3D = _target_markers[vid]
		var target: String = vehicles.get(vid, {}).get("target_waypoint", "")
		if not _waypoint_positions.has(target):
			marker.visible = false
			continue
		marker.visible = true
		marker.position = _waypoint_positions[target] + Vector3(0.0, TARGET_RADIUS, 0.0)

func _build_edges(graph) -> void:
	var material := _material(EDGE_COLOR)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge in graph.edges():
		mesh.surface_add_vertex(_lift(graph.waypoint_pos(edge["from"])))
		mesh.surface_add_vertex(_lift(graph.waypoint_pos(edge["to"])))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.name = "Edges"
	node.mesh = mesh
	add_child(node)

func _build_waypoint_markers(graph) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.35, 0.35)
	var material := _material(MARKER_COLOR)
	for id in graph.waypoints:
		var wp: Dictionary = graph.waypoints[id]
		if not wp["type"] in MARKER_TYPES:
			continue
		var node := MeshInstance3D.new()
		node.name = "WP_" + id
		node.mesh = box
		node.material_override = material
		node.position = _lift(wp["pos"]) + Vector3(0.0, 0.2, 0.0)
		add_child(node)

func _build_labels(graph) -> void:
	_labels_root = Node3D.new()
	_labels_root.name = "WaypointLabels"
	_labels_root.visible = false
	add_child(_labels_root)
	for id in graph.waypoints:
		var label := Label3D.new()
		label.name = "Label_" + id
		label.text = id
		label.font_size = 32
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = EDGE_COLOR
		label.position = _lift(graph.waypoints[id]["pos"]) + Vector3(0.0, 0.9, 0.0)
		_labels_root.add_child(label)

func _build_target_markers() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = TARGET_RADIUS
	sphere.height = TARGET_RADIUS * 2.0
	var material := _material(TARGET_COLOR)
	for vid in ["PE-01", "PE-02", "RD-01"]:
		var node := MeshInstance3D.new()
		node.name = "Target_" + vid
		node.mesh = sphere
		node.material_override = material
		node.visible = false
		add_child(node)
		_target_markers[vid] = node

func _lift(pos: Vector3) -> Vector3:
	return Vector3(pos.x, pos.y + EDGE_Y, pos.z)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

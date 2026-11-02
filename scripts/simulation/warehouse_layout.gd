extends RefCounted

var areas: Dictionary = {}
var dock_positions: Dictionary = {}
var handoff_stations: Dictionary = {}
var rack_slots: Dictionary = {}
var obstacles: Array = []
var floor_size: Vector2 = Vector2.ZERO

func load_from_file(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		printerr("Failed to open layout file: " + path)
		return false

	var json_string = file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_string)
	if not _validate(data):
		return false

	floor_size = Vector2(data["floor_size"][0], data["floor_size"][1])

	for a in data["areas"]:
		areas[a["id"]] = a["bounds"]

	for d in data["dock_positions"]:
		dock_positions[d["id"]] = Vector3(d["pos"][0], d["pos"][1], d["pos"][2])

	for h in data["handoff_stations"]:
		handoff_stations[h["id"]] = Vector3(h["pos"][0], h["pos"][1], h["pos"][2])

	for r in data["rack_slots"]:
		rack_slots[r["id"]] = Vector3(r["pos"][0], r["pos"][1], r["pos"][2])

	for o in data["obstacles"]:
		var aabb = AABB(
			Vector3(o["aabb"][0], o["aabb"][1], o["aabb"][2]),
			Vector3(o["aabb"][3], o["aabb"][4], o["aabb"][5])
		)
		obstacles.append({"id": o["id"], "aabb": aabb})

	return true

func _validate(data: Dictionary) -> bool:
	var required = ["floor_size", "areas", "dock_positions", "handoff_stations", "rack_slots", "obstacles"]
	for key in required:
		if not data.has(key):
			printerr("Missing required key: " + key)
			return false
	return true
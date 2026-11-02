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
	if typeof(data) != TYPE_DICTIONARY:
		printerr("JSON parse error or invalid root type")
		return false

	if not _validate(data):
		return false

	areas.clear()
	dock_positions.clear()
	handoff_stations.clear()
	rack_slots.clear()
	obstacles.clear()

	floor_size = Vector2(data["floor_size"][0], data["floor_size"][1])

	for a in data["areas"]:
		var b = a["bounds"]
		areas[a["id"]] = Rect2(Vector2(b[0], b[1]), Vector2(b[2] - b[0], b[3] - b[1]))

	for d in data["dock_positions"]:
		dock_positions[d["id"]] = Vector3(d["pos"][0], d["pos"][1], d["pos"][2])

	for h in data["handoff_stations"]:
		handoff_stations[h["id"]] = Vector3(h["pos"][0], h["pos"][1], h["pos"][2])

	for r in data["rack_slots"]:
		rack_slots[r["id"]] = Vector3(r["pos"][0], r["pos"][1], r["pos"][2])

	for o in data["obstacles"]:
		var a = o["aabb"]
		var pos = Vector3(a[0], a[1], a[2])
		var size = Vector3(a[3] - a[0], a[4] - a[1], a[5] - a[2])
		obstacles.append({"id": o["id"], "aabb": AABB(pos, size)})

	return true

func _validate(data: Dictionary) -> bool:
	var required = ["floor_size", "areas", "dock_positions", "handoff_stations", "rack_slots", "obstacles"]
	for key in required:
		if not data.has(key):
			printerr("Missing required key: " + key)
			return false
	if not (data["floor_size"] is Array and data["floor_size"].size() == 2):
		printerr("floor_size must be array of 2")
		return false
	for a in data["areas"]:
		if not (a.has("id") and a.has("bounds") and a["bounds"] is Array and a["bounds"].size() == 4):
			printerr("area entry missing id/bounds or bounds not 4")
			return false
	for d in data["dock_positions"]:
		if not (d.has("id") and d.has("pos") and d["pos"] is Array and d["pos"].size() == 3):
			printerr("dock entry missing id/pos or pos not 3")
			return false
	for h in data["handoff_stations"]:
		if not (h.has("id") and h.has("pos") and h["pos"] is Array and h["pos"].size() == 3):
			printerr("handoff entry missing id/pos or pos not 3")
			return false
	for r in data["rack_slots"]:
		if not (r.has("id") and r.has("pos") and r["pos"] is Array and r["pos"].size() == 3):
			printerr("rack entry missing id/pos or pos not 3")
			return false
	for o in data["obstacles"]:
		if not (o.has("id") and o.has("aabb") and o["aabb"] is Array and o["aabb"].size() == 6):
			printerr("obstacle entry missing id/aabb or aabb not 6")
			return false
	return true
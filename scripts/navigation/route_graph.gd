extends RefCounted

var waypoints: Dictionary = {}
var adj: Dictionary = {}
var edge_list: Array = []

func load_from_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		printerr("Failed to open routes file: " + path)
		return false

	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY or not (data.get("waypoints") is Array) or not (data.get("edges") is Array):
		printerr("Invalid routes JSON: " + path)
		return false

	waypoints.clear()
	adj.clear()
	edge_list.clear()

	for w in data["waypoints"]:
		if not (w is Dictionary and w.has("id") and w.get("pos") is Array and w["pos"].size() == 3):
			printerr("Invalid waypoint entry: " + str(w))
			return false
		var p: Array = w["pos"]
		waypoints[w["id"]] = {
			"id": w["id"],
			"pos": Vector3(p[0], p[1], p[2]),
			"type": w.get("type", ""),
			"class": w.get("class", "both"),
			"resource": w.get("resource", ""),
		}
		adj[w["id"]] = []

	for e in data["edges"]:
		if not (e is Dictionary and e.has("from") and e.has("to")):
			printerr("Invalid edge entry: " + str(e))
			return false
		if not waypoints.has(e["from"]) or not waypoints.has(e["to"]):
			printerr("Edge references unknown waypoint: " + str(e))
			return false
		# Resource arbitration is waypoint-based: the dispatcher reserves the
		# target waypoint's resource before stepping (see Dispatcher). Edges
		# carry only topology.
		var rec := {
			"from": e["from"],
			"to": e["to"],
			"class": e.get("class", "both"),
			"bidir": e.get("bidir", true),
		}
		edge_list.append(rec)
		adj[rec["from"]].append({"to": rec["to"], "class": rec["class"]})
		if rec["bidir"]:
			adj[rec["to"]].append({"to": rec["from"], "class": rec["class"]})

	return true

func get_waypoint(id: String) -> Dictionary:
	return waypoints.get(id, {})

func waypoint_pos(id: String) -> Vector3:
	return get_waypoint(id).get("pos", Vector3.ZERO)

func neighbors(id: String, vehicle_class: String) -> Array[String]:
	var out: Array[String] = []
	for e in adj.get(id, []):
		if e["class"] == "both" or e["class"] == vehicle_class:
			out.append(e["to"])
	return out

func find_path(from_id: String, to_id: String, vehicle_class: String) -> Array[String]:
	if not waypoints.has(from_id) or not waypoints.has(to_id):
		return []
	var prev := {from_id: ""}
	var queue: Array[String] = [from_id]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to_id:
			var path: Array[String] = []
			while cur != "":
				path.push_front(cur)
				cur = prev[cur]
			return path
		for n in neighbors(cur, vehicle_class):
			if not prev.has(n):
				prev[n] = cur
				queue.append(n)
	return []

func all_waypoint_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in waypoints:
		ids.append(id)
	return ids

func edges() -> Array:
	return edge_list

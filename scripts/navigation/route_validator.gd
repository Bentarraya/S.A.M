extends RefCounted

const REQUIRED := [
	["PE_PARK_01", "DOCK_PICKUP_01", "PE"],
	["DOCK_PICKUP_01", "XFER_DROP_01", "PE"],
	["XFER_DROP_01", "PE_PARK_01", "PE"],
	["PE_PARK_02", "DOCK_PICKUP_03", "PE"],
	["DOCK_PICKUP_03", "XFER_DROP_02", "PE"],
	["XFER_DROP_02", "PE_PARK_02", "PE"],
	["RD_PARK", "XFER_DROP_01", "RD"],
	["XFER_DROP_01", "RACK_PLACE_A_01", "RD"],
	["RACK_PLACE_A_01", "RD_PARK", "RD"],
	["RD_PARK", "RACK_PLACE_D_02", "RD"],
]

func validate(graph, layout) -> Array:
	var errors: Array = []

	for req in REQUIRED:
		if graph.find_path(req[0], req[1], req[2]).is_empty():
			errors.append("missing %s path %s -> %s" % [req[2], req[0], req[1]])

	for e in graph.edges():
		var target: Dictionary = graph.get_waypoint(e["to"])
		if target.get("type", "") in ["rack_place", "parking"]:
			continue
		var a: Vector3 = graph.waypoint_pos(e["from"])
		var b: Vector3 = graph.waypoint_pos(e["to"])
		for obs in layout.obstacles:
			var box: AABB = obs["aabb"].grow(0.4)
			var steps := int(max(a.distance_to(b) * 4.0, 1.0))
			for i in range(steps + 1):
				if box.has_point(a.lerp(b, float(i) / steps)):
					errors.append("edge %s -> %s crosses %s" % [e["from"], e["to"], obs["id"]])
					break

	return errors

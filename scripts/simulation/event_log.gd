extends RefCounted
class_name EventLog

var entries: Array = []

func log_event(time: float, type: String, message: String) -> void:
	entries.append({"time": time, "type": type, "message": message})

func recent(n: int) -> Array:
	if n <= 0:
		return []
	var start = max(0, entries.size() - n)
	return entries.slice(start, entries.size())
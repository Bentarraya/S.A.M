extends RefCounted

enum Status {CREATED, ASSIGNED_PE, PE_PICKED, AT_XFER, ASSIGNED_RD, RD_PICKED, STORED, COMPLETED}

const _NEXT := {
	Status.CREATED: [Status.ASSIGNED_PE],
	Status.ASSIGNED_PE: [Status.PE_PICKED],
	Status.PE_PICKED: [Status.AT_XFER],
	Status.AT_XFER: [Status.ASSIGNED_RD],
	Status.ASSIGNED_RD: [Status.RD_PICKED],
	Status.RD_PICKED: [Status.STORED],
	Status.STORED: [Status.COMPLETED],
	Status.COMPLETED: [],
}

var _tasks: Dictionary = {}
var _next_id: int = 1

func create_task(pallet_id: String) -> String:
	if pallet_id == "" or not find_task_by_pallet(pallet_id).is_empty():
		return ""
	var id := "TASK-%04d" % _next_id
	_next_id += 1
	_tasks[id] = {"id": id, "pallet_id": pallet_id, "status": Status.CREATED, "pe_id": "", "rd_id": ""}
	return id

func transition(task_id: String, s: int) -> bool:
	var t: Dictionary = _tasks.get(task_id, {})
	if t.is_empty() or not _NEXT.has(t["status"]) or not _NEXT[t["status"]].has(s):
		return false
	_tasks[task_id]["status"] = s
	return true

func get_task(id: String) -> Dictionary:
	return _tasks.get(id, {})

func find_task_by_pallet(pallet_id: String) -> Dictionary:
	for t in _tasks.values():
		if t["pallet_id"] == pallet_id and t["status"] != Status.COMPLETED:
			return t
	return {}

func active_tasks() -> Array:
	var out: Array = []
	for t in _tasks.values():
		if t["status"] != Status.COMPLETED:
			out.append(t)
	return out

extends RefCounted

var _capacity: Dictionary = {}
var _holders: Dictionary = {}
var _waiters: Dictionary = {}

func add_resource(id: String, capacity: int = 1) -> void:
	_capacity[id] = capacity
	_holders[id] = []
	_waiters[id] = []

func has_resource(id: String) -> bool:
	return _capacity.has(id)

func request(id: String, owner: String, seq: int) -> bool:
	if not _capacity.has(id):
		return false
	var queue: Array = _waiters[id]
	var free: int = _capacity[id] - _holders[id].size()
	if free > 0 and (queue.is_empty() or queue[0]["owner"] == owner):
		_holders[id].append(owner)
		if not queue.is_empty():
			queue.remove_at(0)
		return true
	for w in queue:
		if w["owner"] == owner:
			return false
	var pos := queue.size()
	for i in queue.size():
		if queue[i]["seq"] > seq:
			pos = i
			break
	queue.insert(pos, {"owner": owner, "seq": seq})
	return false

# Give up a pending request: a failed assignment attempt must not stay in the
# queue, or the next release hands the resource to a vehicle that moved on.
func cancel(id: String, owner: String) -> void:
	var queue: Array = _waiters.get(id, [])
	for i in range(queue.size() - 1, -1, -1):
		if queue[i]["owner"] == owner:
			queue.remove_at(i)

func release(id: String, owner: String) -> bool:
	if not _holders.has(id) or not _holders[id].has(owner):
		return false
	_holders[id].erase(owner)
	var queue: Array = _waiters[id]
	while not queue.is_empty() and _holders[id].size() < _capacity[id]:
		_holders[id].append(queue.pop_front()["owner"])
	return true

func is_held_by(id: String, owner: String) -> bool:
	return _holders.has(id) and _holders[id].has(owner)

func holders(id: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(_holders.get(id, []))
	return out

func waiter_count(id: String) -> int:
	return _waiters.get(id, []).size()

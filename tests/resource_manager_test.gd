extends RefCounted

const ResourceManager = preload("res://scripts/simulation/resource_manager.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var rm := ResourceManager.new()
	rm.add_resource("AISLE", 1)
	_check(rm.request("AISLE", "PE-01", 10), "PE-01 granted")
	_check(not rm.request("AISLE", "PE-02", 11), "PE-02 waits while held")
	_check(rm.waiter_count("AISLE") == 1, "PE-02 queued")
	_check(not rm.release("AISLE", "PE-02"), "non-holder cannot release")
	_check(rm.is_held_by("AISLE", "PE-01"), "PE-01 holds")
	_check(rm.release("AISLE", "PE-01"), "PE-01 releases")
	_check(rm.is_held_by("AISLE", "PE-02"), "PE-02 promoted on release")
	_check(rm.release("AISLE", "PE-02"), "PE-02 releases")
	rm.add_resource("WIDE", 2)
	_check(rm.request("WIDE", "PE-01", 1) and rm.request("WIDE", "PE-02", 2), "capacity 2 grants both")
	_check(rm.request("WIDE", "RD-01", 3) == false, "capacity 2 rejects third")
	return failures

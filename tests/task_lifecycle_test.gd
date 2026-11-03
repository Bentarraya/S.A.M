extends RefCounted

const Pallet = preload("res://scripts/entities/pallet.gd")
const InventoryManager = preload("res://scripts/simulation/inventory_manager.gd")
const TaskManager = preload("res://scripts/simulation/task_manager.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var p := Pallet.new()
	p.id = "PLT-0001"
	_check(p.status == Pallet.Status.AT_DOCK, "starts AT_DOCK")
	_check(p.set_status(Pallet.Status.ASSIGNED_TO_PE), "dock->assigned_pe")
	_check(not p.set_status(Pallet.Status.STORED), "illegal jump rejected")
	_check(p.set_status(Pallet.Status.IN_TRANSIT_PE), "assigned->transit")
	_check(p.set_status(Pallet.Status.AT_XFER), "transit->xfer")
	_check(p.set_status(Pallet.Status.ASSIGNED_TO_RD), "xfer->assigned_rd")
	_check(p.set_status(Pallet.Status.IN_TRANSIT_RD), "assigned_rd->transit_rd")
	_check(p.set_status(Pallet.Status.STORED), "transit_rd->stored")
	_check(not p.set_status(-1), "invalid status rejected from STORED")
	_check(p.status == Pallet.Status.STORED, "status unchanged after invalid")

	var inv := InventoryManager.new()
	_check(inv.add_pallet("PLT-0001", "SKU-A", "DOCK-01"), "add pallet")
	_check(not inv.add_pallet("PLT-0001", "SKU-A", "DOCK-01"), "duplicate pallet rejected")
	_check(inv.count_by_status()["AT_DOCK"] == 1, "count AT_DOCK")

	var tm := TaskManager.new()
	var t1 := tm.create_task("PLT-0001")
	_check(t1 != "", "task created")
	_check(tm.get_task(t1)["pe_id"] == "" and tm.get_task(t1)["rd_id"] == "", "task has empty pe_id/rd_id")
	_check(tm.create_task("PLT-0001") == "", "duplicate task for pallet rejected")
	_check(tm.transition(t1, TaskManager.Status.ASSIGNED_PE), "created->assigned_pe")
	_check(not tm.transition(t1, TaskManager.Status.AT_XFER), "illegal task jump rejected")
	for s in [TaskManager.Status.PE_PICKED, TaskManager.Status.AT_XFER, TaskManager.Status.ASSIGNED_RD, TaskManager.Status.RD_PICKED, TaskManager.Status.STORED, TaskManager.Status.COMPLETED]:
		_check(tm.transition(t1, s), "task chain step " + str(s))
	_check(tm.active_tasks().is_empty(), "completed task inactive")
	_check(not tm.transition(t1, -1), "invalid status rejected from COMPLETED")
	_check(not tm.transition(t1, TaskManager.Status.size()), "out-of-range status rejected")
	_check(tm.get_task(t1)["status"] == TaskManager.Status.COMPLETED, "completed status unchanged")
	return failures

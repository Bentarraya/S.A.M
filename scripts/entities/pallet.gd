extends RefCounted

enum Status {AT_DOCK, ASSIGNED_TO_PE, IN_TRANSIT_PE, AT_XFER, ASSIGNED_TO_RD, IN_TRANSIT_RD, STORED}

const _NEXT := {
	Status.AT_DOCK: [Status.ASSIGNED_TO_PE],
	Status.ASSIGNED_TO_PE: [Status.IN_TRANSIT_PE],
	Status.IN_TRANSIT_PE: [Status.AT_XFER],
	Status.AT_XFER: [Status.ASSIGNED_TO_RD],
	Status.ASSIGNED_TO_RD: [Status.IN_TRANSIT_RD],
	Status.IN_TRANSIT_RD: [Status.STORED],
	Status.STORED: [],
}

var id: String = ""
var sku: String = ""
var status: int = Status.AT_DOCK
var location_id: String = ""
var destination_rack_id: String = ""
var task_id: String = ""

func set_status(s: int) -> bool:
	if not _NEXT.has(status) or not _NEXT[status].has(s):
		return false
	status = s
	return true

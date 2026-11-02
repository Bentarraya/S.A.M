extends RefCounted

const Pallet = preload("res://scripts/entities/pallet.gd")

var _pallets: Dictionary = {}

func add_pallet(id: String, sku: String, location_id: String) -> bool:
	if id == "" or _pallets.has(id):
		return false
	var p := Pallet.new()
	p.id = id
	p.sku = sku
	p.location_id = location_id
	_pallets[id] = p
	return true

func get_pallet(id: String) -> Object:
	return _pallets.get(id)

func pallets_with_status(s: int) -> Array:
	var out: Array = []
	for p in _pallets.values():
		if p.status == s:
			out.append(p)
	return out

func count_by_status() -> Dictionary:
	var out := {}
	for name in Pallet.Status.keys():
		out[name] = 0
	for p in _pallets.values():
		out[Pallet.Status.keys()[p.status]] += 1
	return out

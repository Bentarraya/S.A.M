extends RefCounted

const Hud = preload("res://scripts/ui/hud.gd")
const SimulationEngine = preload("res://scripts/simulation/simulation_engine.gd")

var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var before := failures
	# HUD builds Control nodes, so it needs a SceneTree to enter.
	var root: Window = Engine.get_main_loop().root
	var hud = Hud.new()
	root.add_child(hud)
	_check(hud.get_child_count() > 0, "HUD builds its UI")

	var sim := SimulationEngine.new()
	_check(
		sim.setup(
			"res://data/warehouse_layout.json",
			"res://data/routes.json",
			"res://data/vehicle_config.json"
		),
		"engine setup"
	)
	sim.step(1.0 / 60.0)

	hud.update_state(sim, false, 60.0)
	_check(hud._clock_label.text.contains("0.0"), "clock shows elapsed sim time")
	_check(hud._vehicle_labels["PE-01"]["State"].text.begins_with("State: "), "vehicle state shown")
	_check(hud._rack_label.text.begins_with("Occupied 0/"), "rack occupancy shown")
	_check(hud._task_rows[0].text != "", "task queue row rendered")

	hud.set_selected_vehicle("RD-01")
	hud.update_state(sim, true, 30.0)
	_check(hud._pause_button.text == "Resume", "pause label reflects paused state")

	hud.queue_free()
	return failures - before

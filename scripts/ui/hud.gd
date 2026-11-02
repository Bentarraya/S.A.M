extends CanvasLayer

signal start_pressed
signal pause_toggled(is_paused: bool)
signal reset_pressed
signal speed_changed(mult: float)
signal add_pallet_pressed
signal demo_pressed
signal route_overlay_toggled(v: bool)
signal waypoint_labels_toggled(v: bool)
signal camera_preset_changed(preset: String)
signal vehicle_selected(veh_id: String)

const Vehicle = preload("res://scripts/entities/vehicle.gd")
const TaskManager = preload("res://scripts/simulation/task_manager.gd")

const VEHICLE_IDS := ["PE-01", "PE-02", "RD-01"]
const SPEEDS := [0.5, 1.0, 2.0, 4.0]
const SPEED_LABELS := ["0.5x", "1x", "2x", "4x"]
const CAMERA_LABELS := ["Overview", "Top-down", "Follow"]
const CAMERA_PRESETS := ["overview", "top_down", "follow"]
const TASK_ROWS := 8
const EVENT_ROWS := 10
const COUNT_KEYS := ["Dock", "PE", "Xfer", "RD", "Stored", "Completed"]

var _paused := false
var _selected := "PE-01"
var _pause_button: Button
var _clock_label: Label
var _rack_label: Label
var _event_log: RichTextLabel
var _fps_label: Label
var _task_rows: Array = []
var _vehicle_labels: Dictionary = {}
var _vehicle_cards: Dictionary = {}
var _count_labels: Dictionary = {}

func _init() -> void:
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_left(root)
	_build_right(root)
	_build_bottom(root)

func _build_left(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(8, 8)
	root.add_child(panel)

	var margin := _margin(8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	box.add_child(_label("S.A.M. WAREHOUSE", 16))

	var start := _button("Start")
	start.pressed.connect(func() -> void: start_pressed.emit())
	box.add_child(start)

	_pause_button = _button("Pause")
	_pause_button.pressed.connect(_on_pause_pressed)
	box.add_child(_pause_button)

	var reset := _button("Reset")
	reset.pressed.connect(func() -> void: reset_pressed.emit())
	box.add_child(reset)

	box.add_child(_label("Speed", 11))
	var speed := OptionButton.new()
	speed.add_theme_font_size_override("font_size", 12)
	for speed_label in SPEED_LABELS:
		speed.add_item(speed_label)
	speed.selected = 1
	speed.item_selected.connect(func(index: int) -> void: speed_changed.emit(SPEEDS[index]))
	box.add_child(speed)

	var add_pallet := _button("Add Pallet")
	add_pallet.pressed.connect(func() -> void: add_pallet_pressed.emit())
	box.add_child(add_pallet)

	var demo := _button("Run Demo")
	demo.pressed.connect(func() -> void: demo_pressed.emit())
	box.add_child(demo)

	var routes := CheckButton.new()
	routes.text = "Routes"
	routes.add_theme_font_size_override("font_size", 12)
	routes.toggled.connect(func(on: bool) -> void: route_overlay_toggled.emit(on))
	box.add_child(routes)

	var waypoint_ids := CheckButton.new()
	waypoint_ids.text = "Waypoint IDs"
	waypoint_ids.add_theme_font_size_override("font_size", 12)
	waypoint_ids.toggled.connect(func(on: bool) -> void: waypoint_labels_toggled.emit(on))
	box.add_child(waypoint_ids)

	box.add_child(_label("Camera", 11))
	var camera := OptionButton.new()
	camera.add_theme_font_size_override("font_size", 12)
	for camera_label in CAMERA_LABELS:
		camera.add_item(camera_label)
	camera.item_selected.connect(
		func(index: int) -> void: camera_preset_changed.emit(CAMERA_PRESETS[index])
	)
	box.add_child(camera)

	_clock_label = _label("Clock: 0.0 s", 12)
	box.add_child(_clock_label)

func _build_right(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -8
	panel.offset_top = 8
	root.add_child(panel)

	var margin := _margin(8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	box.add_child(_label("Vehicles", 14))

	for vid in VEHICLE_IDS:
		box.add_child(_build_vehicle_card(vid))

func _build_vehicle_card(vid: String) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(240, 104)
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(func() -> void: vehicle_selected.emit(vid))
	_vehicle_cards[vid] = card

	var margin := _margin(6)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	margin.add_child(box)

	var header := _label(vid, 13)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)

	var rows := {}
	for key in ["State", "Task", "Load", "Next WP", "Blocked"]:
		var row := _label("%s: -" % key, 11)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.clip_text = true
		box.add_child(row)
		rows[key] = row
	_vehicle_labels[vid] = rows
	return card

func _build_bottom(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 8
	panel.offset_top = -196
	panel.offset_right = -8
	panel.offset_bottom = -8
	root.add_child(panel)

	var margin := _margin(6)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	box.add_child(columns)

	var queue := VBoxContainer.new()
	queue.custom_minimum_size = Vector2(320, 0)
	columns.add_child(queue)
	queue.add_child(_label("Task Queue", 12))
	for i in range(TASK_ROWS):
		var row := _label("-", 11)
		queue.add_child(row)
		_task_rows.append(row)

	var events := VBoxContainer.new()
	events.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(events)
	events.add_child(_label("Event Log", 12))
	_event_log = RichTextLabel.new()
	_event_log.add_theme_font_size_override("normal_font_size", 11)
	_event_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_log.scroll_following = true
	events.add_child(_event_log)

	var stats := VBoxContainer.new()
	stats.custom_minimum_size = Vector2(170, 0)
	columns.add_child(stats)
	stats.add_child(_label("Racks", 12))
	_rack_label = _label("Occupied 0/0", 11)
	stats.add_child(_rack_label)
	for key in COUNT_KEYS:
		var row := _label("%s: 0" % key, 11)
		stats.add_child(row)
		_count_labels[key] = row

	_fps_label = _label("FPS 0 | tick 0.00 ms", 11)
	box.add_child(_fps_label)

func _on_pause_pressed() -> void:
	_paused = not _paused
	pause_toggled.emit(_paused)

func update_state(sim, paused: bool, fps: float) -> void:
	if sim == null or _clock_label == null:
		return
	_paused = paused
	_pause_button.text = "Resume" if paused else "Pause"
	_clock_label.text = "Clock: %.1f s" % sim.time
	_fps_label.text = "FPS %d | tick %.2f ms" % [int(fps), sim.last_dt * 1000.0]
	_update_vehicles(sim)
	_update_tasks(sim)
	_update_racks(sim)
	_update_counts(sim)
	_update_events(sim)

func set_selected_vehicle(veh_id: String) -> void:
	_selected = veh_id
	for vid in _vehicle_cards:
		var card: Button = _vehicle_cards[vid]
		card.modulate = Color(1, 1, 0.65) if vid == veh_id else Color(1, 1, 1)

func _update_vehicles(sim) -> void:
	for vid in VEHICLE_IDS:
		var rows: Dictionary = _vehicle_labels[vid]
		var vdata: Dictionary = sim.vehicles.get(vid, {})
		if vdata.is_empty():
			for key in rows:
				rows[key].text = "%s: -" % key
			continue
		var v = vdata["ref"]
		rows["State"].text = "State: " + Vehicle.State.keys()[v.state]
		rows["Task"].text = "Task: " + (v.task_id if v.task_id != "" else "-")
		rows["Load"].text = "Load: " + (vdata["pallet_id"] if vdata["pallet_id"] != "" else "-")
		rows["Next WP"].text = (
			"Next WP: " + (vdata["target_waypoint"] if vdata["target_waypoint"] != "" else "-")
		)
		rows["Blocked"].text = "Blocked: " + (v.blocked_reason if v.blocked_reason != "" else "-")

func _update_tasks(sim) -> void:
	var active: Array = sim.tasks.active_tasks()
	for i in range(TASK_ROWS):
		if i < active.size():
			var task: Dictionary = active[i]
			var status: String = TaskManager.Status.keys()[task["status"]]
			_task_rows[i].text = "%s %s %s" % [task["id"], task["pallet_id"], status]
		else:
			_task_rows[i].text = "-"

func _update_racks(sim) -> void:
	var occupied := 0
	for slot in sim.rack_slots.values():
		if slot["state"] == "OCCUPIED":
			occupied += 1
	_rack_label.text = "Occupied %d/%d" % [occupied, sim.rack_slots.size()]

func _update_counts(sim) -> void:
	var counts: Dictionary = sim.inventory.count_by_status()
	var values := {
		"Dock": counts.get("AT_DOCK", 0),
		"PE": counts.get("ASSIGNED_TO_PE", 0) + counts.get("IN_TRANSIT_PE", 0),
		"Xfer": counts.get("AT_XFER", 0),
		"RD": counts.get("ASSIGNED_TO_RD", 0) + counts.get("IN_TRANSIT_RD", 0),
		"Stored": counts.get("STORED", 0),
		"Completed": 0,
	}
	for entry in sim.events.entries:
		if entry["type"] == "pallet_stored":
			values["Completed"] += 1
	for key in COUNT_KEYS:
		_count_labels[key].text = "%s: %d" % [key, values[key]]

func _update_events(sim) -> void:
	var lines: Array = []
	for entry in sim.events.recent(EVENT_ROWS):
		lines.append("[%.1f] %s" % [entry["time"], entry["message"]])
	_event_log.text = "\n".join(lines)

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 12)
	return button

func _margin(px: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, px)
	return margin

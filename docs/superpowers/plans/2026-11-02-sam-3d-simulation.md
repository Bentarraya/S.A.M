# S.A.M. 3D Warehouse Simulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic local 3D warehouse simulation in Godot 4 (Compatibility renderer) where PE-01, PE-02 carry pallets from the Dock Room to handoff stations and RD-01 forklift stores them in rack slots, with authored waypoint routes, resource reservations, HUD, and headless tests.

**Architecture:** Pure-GDScript simulation classes (`RefCounted`, no Node dependencies) own authoritative state and are unit-tested headless. A single 3D scene reads engine state each frame: it steps the engine in `_physics_process` at a fixed 60 Hz and interpolates visuals in `_process`. All warehouse geometry, routes, and vehicle parameters come from JSON files.

**Tech Stack:** Godot 4.3+ (GL Compatibility renderer), GDScript, JSON data files, headless GDScript test runner. No external dependencies.

**Spec:** `docs/superpowers/specs/2026-11-02-sam-3d-simulation-design.md`

## Global Constraints

- Godot **4.3+**, `renderer/rendering_method="gl_compatibility"`; target hardware Intel HD Graphics 3000, OpenGL 3.3 (confirmed, Mesa 25.2.8).
- 1 world unit = 1 meter, Y-up. Simulation fixed timestep **1/60 s**.
- GDScript only; no Node.js, Python, ROS, Vim, or addons. Assets are primitive meshes.
- No real-time shadows, no SSAO/volumetrics/reflections; low-poly meshes only.
- All simulation classes are `RefCounted` and must run under `--headless` with no scene.
- Tests run with `godot --headless --path . --script tests/test_runner.gd` and exit non-zero on failure.
- Every completed task leaves the project runnable and committed.
- Engine-generated `*.uid` sidecar files are permitted and tracked (Godot 4.4+ emits them); `.superpowers/` is git-ignored workspace scratch.
- Exactly three vehicles exist: `PE-01`, `PE-02` (class `PE`), `RD-01` (class `RD`).
- Invalid state transitions must be rejected and logged, never silently applied.

## Review Focus

- **Concurrent dock/handoff use:** two PEs requesting the same dock position or handoff station at once must serialize through `ResourceManager`, never overlap.
- **RD early pickup:** RD must never pick a pallet that is not `AT_XFER`; a missing/duplicate task must block it with a reason.
- **Double assignment:** one pallet must never have two active tasks or be assigned to two vehicles.
- **Blocked vehicles:** a vehicle waiting on a resource must hold position and report `blocked_reason`, never pass through.
- **Invalid route data:** a disconnected or wall-crossing `routes.json` must fail validation loudly at load time.
- **Determinism:** resetting and replaying the demo with the same pallet inputs must produce the same final state.

---

## Data Design (authoritative values used by all tasks)

### `data/warehouse_layout.json`

Areas: Dock Room x∈[0,12], Transfer x∈[12,16], Storage x∈[16,36]; z∈[0,8] for all.

Dock positions (pallet pickup): `DOCK-01` (2,0,2), `DOCK-02` (2,0,4), `DOCK-03` (2,0,6).
Handoff stations: `XFER-01` (14,0,2), `XFER-02` (14,0,6).
Rack slots: `RACK-A-01` (18,0,2), `RACK-A-02` (18,0,6), `RACK-B-01` (22,0,2), `RACK-B-02` (22,0,6), `RACK-C-01` (26,0,2), `RACK-C-02` (26,0,6), `RACK-D-01` (30,0,2), `RACK-D-02` (30,0,6).

Rack obstacle AABBs (for route clearance): each rack row spans x±0.5 around its x center, and two cells z∈[1.4,2.6] and z∈[5.4,6.6], y∈[0,2].
Perimeter walls: z<0.2, z>7.8, x<0.2, x>35.8 (AABB strips) — routes must stay clear.

### `data/routes.json` waypoints

`type` ∈ `lane | wait | turn | parking | pickup | handoff | rack_approach | rack_place`.
`vehicle_class` ∈ `PE | RD | both`.

| id | pos | type | class | resource |
|---|---|---|---|---|
| PE_PARK_01 | (8,0,1) | parking | PE | PE_PARK_01 |
| PE_PARK_02 | (10,0,1) | parking | PE | PE_PARK_02 |
| RET_15 | (15,0,1) | lane | PE | RET_LANE |
| RET_11 | (11,0,1) | lane | PE | RET_LANE |
| RET_8 | (8,0,1) | lane | PE | RET_LANE |
| RET_5 | (5,0,1) | lane | PE | RET_LANE |
| RET_2 | (2,0,1) | lane | PE | RET_LANE |
| CORNER_W | (1,0,1) | turn | PE | RET_LANE |
| CORNER_NW | (1,0,4) | turn | PE | DOCK_LANE |
| DOCK_QUEUE | (4,0,4) | wait | PE | DOCK_LANE |
| DOCK_PICKUP_01 | (2,0,2) | pickup | PE | DOCK-01 |
| DOCK_PICKUP_02 | (2,0,4) | pickup | PE | DOCK-02 |
| DOCK_PICKUP_03 | (2,0,6) | pickup | PE | DOCK-03 |
| DOCK_EXIT | (7,0,4) | lane | PE | DOCK_LANE |
| MAIN_W | (8,0,4) | lane | both | MAIN_AISLE |
| MAIN_E | (13,0,4) | lane | both | MAIN_AISLE |
| XFER_JUNCTION | (14,0,4) | turn | PE | XFER_JUNCTION |
| XFER_DROP_01 | (14,0,2) | handoff | both | XFER-01 |
| XFER_DROP_02 | (14,0,6) | handoff | both | XFER-02 |
| XFER_EXIT | (15,0,1) | turn | PE | XFER_EXIT |
| RD_PARK | (17,0,1) | parking | RD | RD_PARK |
| RD_XFER_QUEUE | (16.5,0,4) | wait | RD | RD_XFER_QUEUE |
| RD_XFER_APPROACH_01 | (16,0,2) | turn | RD | RD_XFER_QUEUE |
| RD_XFER_APPROACH_02 | (16,0,6) | turn | RD | RD_XFER_QUEUE |
| SD_ENTRY | (17.5,0,4) | lane | RD | SD_ENTRY |
| SD_18 | (18,0,4) | lane | RD | SEG_18 |
| SD_22 | (22,0,4) | lane | RD | SEG_22 |
| SD_26 | (26,0,4) | lane | RD | SEG_26 |
| SD_30 | (30,0,4) | lane | RD | SEG_30 |
| SD_END | (32,0,4) | turn | RD | SEG_30 |
| RACK_APP_A_01 | (18,0,3.2) | rack_approach | RD | RACK-A-01 |
| RACK_APP_A_02 | (18,0,4.8) | rack_approach | RD | RACK-A-02 |
| RACK_PLACE_A_01 | (18,0,2) | rack_place | RD | RACK-A-01 |
| RACK_PLACE_A_02 | (18,0,6) | rack_place | RD | RACK-A-02 |
| RACK_APP_B_01 | (22,0,3.2) | rack_approach | RD | RACK-B-01 |
| RACK_APP_B_02 | (22,0,4.8) | rack_approach | RD | RACK-B-02 |
| RACK_PLACE_B_01 | (22,0,2) | rack_place | RD | RACK-B-01 |
| RACK_PLACE_B_02 | (22,0,6) | rack_place | RD | RACK-B-02 |
| RACK_APP_C_01 | (26,0,3.2) | rack_approach | RD | RACK-C-01 |
| RACK_APP_C_02 | (26,0,4.8) | rack_approach | RD | RACK-C-02 |
| RACK_PLACE_C_01 | (26,0,2) | rack_place | RD | RACK-C-01 |
| RACK_PLACE_C_02 | (26,0,6) | rack_place | RD | RACK-C-02 |
| RACK_APP_D_01 | (30,0,3.2) | rack_approach | RD | RACK-D-01 |
| RACK_APP_D_02 | (30,0,4.8) | rack_approach | RD | RACK-D-02 |
| RACK_PLACE_D_01 | (30,0,2) | rack_place | RD | RACK-D-01 |
| RACK_PLACE_D_02 | (30,0,6) | rack_place | RD | RACK-D-02 |

`RACK_APP_*_02` resource values are `RACK-<row>-02` (e.g. `RACK_APP_B_02` → `RACK-B-02`).

Edges (all listed are bidirectional unless `dir: one_way`; `class` filters vehicle classes):

- `PE_PARK_01—RET_8`, `PE_PARK_02—RET_11`.
- `RET_15—RET_11—RET_8—RET_5—RET_2—CORNER_W—CORNER_NW` (class PE).
- `CORNER_NW—DOCK_QUEUE—DOCK_EXIT` (class PE).
- `DOCK_QUEUE—DOCK_PICKUP_01`, `DOCK_QUEUE—DOCK_PICKUP_02`, `DOCK_QUEUE—DOCK_PICKUP_03` (class PE).
- `DOCK_PICKUP_01—DOCK_EXIT`, `DOCK_PICKUP_02—DOCK_EXIT`, `DOCK_PICKUP_03—DOCK_EXIT` (class PE).
- `DOCK_EXIT—MAIN_W—MAIN_E` (class both).
- `MAIN_E—XFER_JUNCTION` (class PE).
- `XFER_JUNCTION—XFER_DROP_01`, `XFER_JUNCTION—XFER_DROP_02` (class PE).
- `XFER_DROP_01—XFER_EXIT`, `XFER_DROP_02—XFER_EXIT` (class PE).
- `XFER_EXIT—RET_15` (class PE).
- `RD_PARK—RD_XFER_QUEUE` (class RD).
- `RD_XFER_QUEUE—RD_XFER_APPROACH_01—XFER_DROP_01` (class RD).
- `RD_XFER_QUEUE—RD_XFER_APPROACH_02—XFER_DROP_02` (class RD).
- `RD_XFER_APPROACH_01—SD_ENTRY`, `RD_XFER_APPROACH_02—SD_ENTRY` (class RD).
- `SD_ENTRY—SD_18—SD_22—SD_26—SD_30—SD_END` (class RD).
- `SD_18—RACK_APP_A_01—RACK_PLACE_A_01`, `SD_18—RACK_APP_A_02—RACK_PLACE_A_02` (class RD).
- Same pattern for x=22 (B), 26 (C), 30 (D); `SD_26—RACK_APP_C_*`, `SD_30—RACK_APP_D_*`.

Resource capacities all 1. `RET_LANE` is the single westbound return lane; `DOCK_LANE` is the dock approach/exits; `MAIN_AISLE` is the shared PE/RD main lane.

### `data/vehicle_config.json`

```json
{
  "PE": {"speed": 1.5, "accel": 0.8, "turn_rate": 1.6, "arrival_tolerance": 0.15, "length": 1.2, "width": 0.8, "height": 0.3, "pickup_seconds": 1.5, "dropoff_seconds": 1.5},
  "RD": {"speed": 1.2, "accel": 0.8, "turn_rate": 1.2, "arrival_tolerance": 0.15, "length": 1.5, "width": 0.9, "height": 1.0, "pickup_seconds": 2.0, "dropoff_seconds": 2.0},
  "safety_gap": 1.5,
  "deadlock_seconds": 30.0
}
```

---

## File Map

| File | Responsibility |
|---|---|
| `project.godot` | Godot 4 project; Compatibility renderer; main scene |
| `scenes/main.tscn` | Root scene: camera, light, HUD layer, world root |
| `scripts/app/main.gd` | Owns engine, fixed-step loop, visual sync, HUD wiring |
| `scripts/app/warehouse_builder.gd` | Builds floor, walls, racks, dock/xfer markings, vehicles, pallets from JSON |
| `scripts/app/route_overlay.gd` | Debug line mesh of route edges + waypoint markers |
| `scripts/ui/hud.gd` | Control panel, vehicle cards, task/rack/event panels, camera presets |
| `scripts/simulation/event_log.gd` | Timestamped event entries |
| `scripts/simulation/resource_manager.gd` | Exclusive resource reservations + FIFO waiters |
| `scripts/simulation/inventory_manager.gd` | Pallet registry + status counts |
| `scripts/simulation/task_manager.gd` | Task lifecycle with guarded transitions |
| `scripts/simulation/dispatcher.gd` | FIFO PE/RD assignment, rack reservation |
| `scripts/simulation/simulation_engine.gd` | Authoritative state, fixed step, pick/drop effects |
| `scripts/entities/pallet.gd` | Pallet data + status transitions |
| `scripts/entities/vehicle.gd` | Vehicle state machine + guarded transitions |
| `scripts/navigation/route_graph.gd` | JSON load, class-filtered BFS paths |
| `scripts/navigation/route_validator.gd` | Connectivity + clearance validation |
| `scripts/navigation/route_follower.gd` | Kinematic heading-align + move + snap |
| `data/warehouse_layout.json` | Areas, dock/xfer/rack positions, obstacle AABBs |
| `data/routes.json` | Waypoints + edges + resources |
| `data/vehicle_config.json` | Vehicle motion + timing parameters |
| `tests/test_runner.gd` | Runs all suites headless, non-zero on failure |
| `tests/*_test.gd` | Per-subsystem suites (see tasks) |
| `README.md` | Engine version, renderer, run/test instructions, results |

---

## Task 1: Project Scaffold + Headless Smoke Test

**Files:**
- Create: `project.godot`, `scenes/main.tscn`, `scripts/app/main.gd`, `tests/test_runner.gd`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/test_runner.gd` — a `SceneTree` script that runs suites registered in its `SUITES` array and calls `quit(0)` on success / `quit(1)` on failure. Every later test file extends `RefCounted` and exposes `func run() -> int` (failure count).

- [ ] **Step 1: Initialize git and directory tree**

```bash
cd /home/bentar-raya/Documents/S.A.M
git init
mkdir -p scenes scripts/app scripts/simulation scripts/entities scripts/navigation scripts/ui data tests assets
printf '.godot/\n*.import\n' > .gitignore
```

- [ ] **Step 2: Write `project.godot`**

```ini
config_version=5

[application]
config/name="S.A.M."
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.3", "GL Compatibility")

[display]
window/size/viewport_width=1366
window/size/viewport_height=768

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=0
textures/default_filters/use_nearest_mipmap_filter=false
```

- [ ] **Step 3: Write `scripts/app/main.gd` (minimal)**

```gdscript
extends Node3D

func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-60, -30, 0)
	add_child(light)
	var cam := Camera3D.new()
	cam.position = Vector3(18, 24, 20)
	add_child(cam)
	cam.look_at(Vector3(18, 0, 4))
```

- [ ] **Step 4: Write `scenes/main.tscn`**

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/app/main.gd" id="1"]

[node name="Main" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 5: Write `tests/test_runner.gd`**

```gdscript
extends SceneTree

const SUITES: Array = []

func _initialize() -> void:
	var failures := 0
	for suite in SUITES:
		failures += suite.new().run()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(0 if failures == 0 else 1)
```

- [ ] **Step 6: Import and run headless smoke test**

Run:
```bash
godot --headless --path . --import
godot --headless --path . --quit-after 120 2>&1 | tee /tmp/sam_smoke.log
grep -cE "SCRIPT ERROR|ERROR:" /tmp/sam_smoke.log
```
Expected: import completes; smoke run exits 0; grep count is `0`.

- [ ] **Step 7: Run test runner**

Run: `godot --headless --path . --script tests/test_runner.gd`
Expected: prints `ALL TESTS PASSED`, exit 0.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: scaffold Godot 4 compatibility project with headless test runner"
```

---

## Task 2: Warehouse Layout Data + Loader

**Files:**
- Create: `data/warehouse_layout.json`, `scripts/simulation/warehouse_layout.gd`
- Create: `tests/layout_test.gd`
- Modify: `tests/test_runner.gd` (add suite)

**Interfaces:**
- Consumes: test runner from Task 1.
- Produces:
  - `WarehouseLayout` (`RefCounted`): `func load_from_file(path: String) -> bool`; fields `areas: Dictionary`, `dock_positions: Dictionary` (id → `Vector3`), `handoff_stations: Dictionary`, `rack_slots: Dictionary`, `obstacles: Array` (`Array[Dictionary]` with `id`, `aabb: AABB`), `floor_size: Vector2`.
  - Layout JSON keys: `areas` (id, bounds), `dock_positions`, `handoff_stations`, `rack_slots`, `obstacles`.

- [ ] **Step 1: Write `data/warehouse_layout.json`**

Use the exact values from **Data Design** above. Shape:

```json
{
  "floor_size": [36, 8],
  "areas": [
    {"id": "DOCK_ROOM", "bounds": [0, 0, 12, 8]},
    {"id": "TRANSFER_AREA", "bounds": [12, 0, 16, 8]},
    {"id": "STORAGE_ROOM", "bounds": [16, 0, 36, 8]}
  ],
  "dock_positions": [
    {"id": "DOCK-01", "pos": [2, 0, 2]},
    {"id": "DOCK-02", "pos": [2, 0, 4]},
    {"id": "DOCK-03", "pos": [2, 0, 6]}
  ],
  "handoff_stations": [
    {"id": "XFER-01", "pos": [14, 0, 2]},
    {"id": "XFER-02", "pos": [14, 0, 6]}
  ],
  "rack_slots": [
    {"id": "RACK-A-01", "pos": [18, 0, 2]},
    {"id": "RACK-A-02", "pos": [18, 0, 6]},
    {"id": "RACK-B-01", "pos": [22, 0, 2]},
    {"id": "RACK-B-02", "pos": [22, 0, 6]},
    {"id": "RACK-C-01", "pos": [26, 0, 2]},
    {"id": "RACK-C-02", "pos": [26, 0, 6]},
    {"id": "RACK-D-01", "pos": [30, 0, 2]},
    {"id": "RACK-D-02", "pos": [30, 0, 6]}
  ],
  "obstacles": [
    {"id": "WALL_S", "aabb": [-0.2, 0, -0.2, 36.2, 3, 0.2]},
    {"id": "WALL_N", "aabb": [-0.2, 0, 7.8, 36.2, 3, 8.2]},
    {"id": "WALL_W", "aabb": [-0.2, 0, -0.2, 0.2, 3, 8.2]},
    {"id": "WALL_E", "aabb": [35.8, 0, -0.2, 36.2, 3, 8.2]},
    {"id": "RACK-A-S", "aabb": [17.5, 0, 1.4, 18.5, 2, 2.6]},
    {"id": "RACK-A-N", "aabb": [17.5, 0, 5.4, 18.5, 2, 6.6]},
    {"id": "RACK-B-S", "aabb": [21.5, 0, 1.4, 22.5, 2, 2.6]},
    {"id": "RACK-B-N", "aabb": [21.5, 0, 5.4, 22.5, 2, 6.6]},
    {"id": "RACK-C-S", "aabb": [25.5, 0, 1.4, 26.5, 2, 2.6]},
    {"id": "RACK-C-N", "aabb": [25.5, 0, 5.4, 26.5, 2, 6.6]},
    {"id": "RACK-D-S", "aabb": [29.5, 0, 1.4, 30.5, 2, 2.6]},
    {"id": "RACK-D-N", "aabb": [29.5, 0, 5.4, 30.5, 2, 6.6]}
  ]
}
```

- [ ] **Step 2: Write failing test `tests/layout_test.gd`**

```gdscript
extends RefCounted

const WarehouseLayout = preload("res://scripts/simulation/warehouse_layout.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var l := WarehouseLayout.new()
	_check(l.load_from_file("res://data/warehouse_layout.json"), "layout loads")
	_check(l.dock_positions.size() == 3, "3 dock positions")
	_check(l.dock_positions["DOCK-01"] == Vector3(2, 0, 2), "DOCK-01 position")
	_check(l.handoff_stations.size() == 2, "2 handoff stations")
	_check(l.rack_slots.size() == 8, "8 rack slots")
	_check(l.rack_slots["RACK-D-02"] == Vector3(30, 0, 6), "RACK-D-02 position")
	_check(l.obstacles.size() == 12, "12 obstacles")
	_check(l.floor_size == Vector2(36, 8), "floor size")
	return failures
```

Add `preload("res://tests/layout_test.gd")` to `SUITES` in `tests/test_runner.gd`.

- [ ] **Step 3: Run to verify failure**

Run: `godot --headless --path . --script tests/test_runner.gd`
Expected: FAIL — `warehouse_layout.gd` does not exist.

- [ ] **Step 4: Implement `scripts/simulation/warehouse_layout.gd`**

```gdscript
extends RefCounted

var floor_size := Vector2.ZERO
var areas := {}            # id -> Rect2 (x,z bounds)
var dock_positions := {}   # id -> Vector3
var handoff_stations := {} # id -> Vector3
var rack_slots := {}       # id -> Vector3
var obstacles := []        # Array of {id, aabb: AABB}

func load_from_file(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	floor_size = Vector2(data["floor_size"][0], data["floor_size"][1])
	areas.clear()
	for a in data["areas"]:
		var b: Array = a["bounds"]
		areas[a["id"]] = Rect2(Vector2(b[0], b[1]), Vector2(b[2] - b[0], b[3] - b[1]))
	for key in ["dock_positions", "handoff_stations", "rack_slots"]:
		var target: Dictionary = get(key)
		target.clear()
		for p in data[key]:
			target[p["id"]] = Vector3(p["pos"][0], p["pos"][1], p["pos"][2])
	obstacles.clear()
	for o in data["obstacles"]:
		var a: Array = o["aabb"]
		obstacles.append({"id": o["id"], "aabb": AABB(Vector3(a[0], a[1], a[2]), Vector3(a[3] - a[0], a[4] - a[1], a[5] - a[2]))})
	return true
```

- [ ] **Step 5: Run tests to verify pass**

Run: `godot --headless --path . --script tests/test_runner.gd`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add data/warehouse_layout.json scripts/simulation/warehouse_layout.gd tests/layout_test.gd tests/test_runner.gd
git commit -m "feat: warehouse layout data and loader"
```

---

## Task 3: Route Graph + Validator

**Files:**
- Create: `data/routes.json`, `scripts/navigation/route_graph.gd`, `scripts/navigation/route_validator.gd`
- Create: `tests/route_test.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Consumes: `WarehouseLayout` from Task 2.
- Produces:
  - `RouteGraph`: `func load_from_file(path: String) -> bool`; `func get_waypoint(id: String) -> Dictionary` (empty if absent); `func waypoint_pos(id: String) -> Vector3`; `func neighbors(id: String, vehicle_class: String) -> Array[String]`; `func find_path(from_id: String, to_id: String, vehicle_class: String) -> Array[String]` (BFS, endpoints included, `[]` if none); `func all_waypoint_ids() -> Array[String]`; `func edges() -> Array` (each `{from, to, class, resource, bidir}`).
  - `RouteValidator`: `func validate(graph: RouteGraph, layout: WarehouseLayout) -> Array[String]` — empty array means valid. Skips clearance for edges whose target waypoint type is `rack_place` or `parking`.

- [ ] **Step 1: Write `data/routes.json`**

Exactly the waypoints and edges from **Data Design**. Edge entries use:

```json
{"from": "MAIN_W", "to": "MAIN_E", "class": "both", "bidir": true}
```

Each waypoint entry:

```json
{"id": "MAIN_W", "pos": [8, 0, 4], "type": "lane", "class": "both", "resource": "MAIN_AISLE"}
```

Required resource list (referenced by name): `PE_PARK_01`, `PE_PARK_02`, `RET_LANE`, `DOCK_LANE`, `DOCK-01`, `DOCK-02`, `DOCK-03`, `MAIN_AISLE`, `XFER_JUNCTION`, `XFER-01`, `XFER-02`, `XFER_EXIT`, `RD_PARK`, `RD_XFER_QUEUE`, `SD_ENTRY`, `SEG_18`, `SEG_22`, `SEG_26`, `SEG_30`, `RACK-A-01`, `RACK-A-02`, `RACK-B-01`, `RACK-B-02`, `RACK-C-01`, `RACK-C-02`, `RACK-D-01`, `RACK-D-02`.

- [ ] **Step 2: Write failing test `tests/route_test.gd`**

```gdscript
extends RefCounted

const WarehouseLayout = preload("res://scripts/simulation/warehouse_layout.gd")
const RouteGraph = preload("res://scripts/navigation/route_graph.gd")
const RouteValidator = preload("res://scripts/navigation/route_validator.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var layout := WarehouseLayout.new()
	layout.load_from_file("res://data/warehouse_layout.json")
	var g := RouteGraph.new()
	_check(g.load_from_file("res://data/routes.json"), "routes load")
	_check(g.get_waypoint("DOCK_PICKUP_01")["type"] == "pickup", "pickup type")
	_check(g.waypoint_pos("RACK_PLACE_D_02") == Vector3(30, 0, 6), "place position")

	var pe_path := g.find_path("PE_PARK_01", "XFER_DROP_01", "PE")
	_check(pe_path.size() > 0, "PE path to handoff exists")
	_check(pe_path[0] == "PE_PARK_01" and pe_path[-1] == "XFER_DROP_01", "PE path endpoints")
	_check(pe_path.has("DOCK_PICKUP_01"), "PE path may route via dock")

	var rd_path := g.find_path("XFER_DROP_01", "RACK_PLACE_B_02", "RD")
	_check(rd_path.size() > 0, "RD path to rack exists")
	_check(rd_path.has("XFER_DROP_01"), "RD path starts at handoff")

	var wrong_class := g.find_path("XFER_DROP_01", "RACK_PLACE_A_01", "PE")
	_check(wrong_class.size() == 0, "PE cannot enter storage rack path")

	var errors := RouteValidator.new().validate(g, layout)
	_check(errors.is_empty(), "route graph validates: " + str(errors))

	var empty_errors := RouteValidator.new().validate(RouteGraph.new(), layout)
	_check(not empty_errors.is_empty(), "validator rejects empty/invalid graph")
	return failures
```

Add the suite to `SUITES`.

- [ ] **Step 3: Run to verify failure**

Run: `godot --headless --path . --script tests/test_runner.gd`
Expected: FAIL (missing `route_graph.gd`).

- [ ] **Step 4: Implement `route_graph.gd` (BFS, class-filtered, deterministic neighbor order)**

- Store `waypoints: Dictionary` (id → `{id, pos: Vector3, type, class, resource}`).
- Store adjacency `adj: Dictionary` (id → `Array[Dictionary]` of `{to, class, resource}`), adding reverse entries when `bidir`.
- `neighbors()` filters by class (`edge.class == "both" or edge.class == vehicle_class`) and preserves JSON order.
- `find_path()` uses BFS with a `visited` dictionary; deterministic because adjacency order is insertion order.

- [ ] **Step 5: Implement `route_validator.gd`**

```gdscript
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
		var target := graph.get_waypoint(e["to"])
		if target.get("type", "") in ["rack_place", "parking"]:
			continue
		var a: Vector3 = graph.waypoint_pos(e["from"])
		var b: Vector3 = graph.waypoint_pos(e["to"])
		for o in layout.obstacles:
			if _segment_hits_aabb(a, b, o["aabb"], 0.4):
				errors.append("edge %s->%s hits %s" % [e["from"], e["to"], o["id"]])
	return errors

func _segment_hits_aabb(a: Vector3, b: Vector3, box: AABB, margin: float) -> bool:
	var grown := box.grow(margin)
	var steps := int(max(a.distance_to(b) * 4.0, 1.0))
	for i in range(steps + 1):
		if grown.has_point(a.lerp(b, float(i) / float(steps))):
			return true
	return false
```

- [ ] **Step 6: Run tests to verify pass**

Run: `godot --headless --path . --script tests/test_runner.gd`
Expected: `ALL TESTS PASSED`. If an edge trips clearance, adjust that edge's intermediate waypoint coordinates (keep waypoints on open floor, z∈[0.6,7.4]) rather than loosening the margin.

- [ ] **Step 7: Commit**

```bash
git add data/routes.json scripts/navigation/route_graph.gd scripts/navigation/route_validator.gd tests/route_test.gd tests/test_runner.gd
git commit -m "feat: authored route graph with BFS paths and clearance validator"
```

---

## Task 4: Resource Manager

**Files:**
- Create: `scripts/simulation/resource_manager.gd`, `tests/resource_manager_test.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Produces:
  - `ResourceManager`: `func add_resource(id: String, capacity: int = 1) -> void`; `func has_resource(id: String) -> bool`; `func request(id: String, owner: String, seq: int) -> bool` (grants only if capacity available AND `owner` is first in FIFO order among waiters for that resource); `func release(id: String, owner: String) -> bool` (false if not held by owner); `func is_held_by(id: String, owner: String) -> bool`; `func holders(id: String) -> Array[String]`; `func waiter_count(id: String) -> int`.

- [ ] **Step 1: Write failing test `tests/resource_manager_test.gd`**

```gdscript
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
```

Implement exactly:

```
request(id, owner, seq):
  if free capacity and (no waiters or first waiter is owner):
      holders.append(owner); remove owner from waiters; return true
  add owner to waiters once (ordered by seq); return false
release(id, owner):
  if owner not holder: return false
  remove owner
  promote FIFO waiters while capacity free
  return true
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL (missing module).

- [ ] **Step 3: Implement `resource_manager.gd`** with `holders: Dictionary`, `waiters: Dictionary` (id → `Array[Dictionary]{owner, seq}`), `capacity: Dictionary`. Waiter order = insertion order by `seq` (stable sort on insert).

- [ ] **Step 4: Run tests to verify pass**

Run: `godot --headless --path . --script tests/test_runner.gd` → `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/simulation/resource_manager.gd tests/resource_manager_test.gd tests/test_runner.gd
git commit -m "feat: FIFO exclusive resource manager"
```

---

## Task 5: Pallet, Inventory, and Task Lifecycle

**Files:**
- Create: `scripts/entities/pallet.gd`, `scripts/simulation/inventory_manager.gd`, `scripts/simulation/task_manager.gd`, `tests/task_lifecycle_test.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Produces:
  - `Pallet`: enum `Status {AT_DOCK, ASSIGNED_TO_PE, IN_TRANSIT_PE, AT_XFER, ASSIGNED_TO_RD, IN_TRANSIT_RD, STORED}`; fields `id, sku, status, location_id, destination_rack_id, task_id`; `func set_status(s: int) -> bool` (false on invalid transition).
  - `InventoryManager`: `func add_pallet(id: String, sku: String, location_id: String) -> bool`; `func get_pallet(id: String) -> Object`; `func pallets_with_status(s: int) -> Array`; `func count_by_status() -> Dictionary` (string names → counts).
  - `TaskManager`: enum `Status {CREATED, ASSIGNED_PE, PE_PICKED, AT_XFER, ASSIGNED_RD, RD_PICKED, STORED, COMPLETED}`; `func create_task(pallet_id: String) -> String`; `func transition(task_id: String, s: int) -> bool`; `func get_task(id: String) -> Dictionary`; `func find_task_by_pallet(pallet_id: String) -> Dictionary`; `func active_tasks() -> Array`.

- [ ] **Step 1: Write failing test `tests/task_lifecycle_test.gd`**

```gdscript
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

	var inv := InventoryManager.new()
	_check(inv.add_pallet("PLT-0001", "SKU-A", "DOCK-01"), "add pallet")
	_check(not inv.add_pallet("PLT-0001", "SKU-A", "DOCK-01"), "duplicate pallet rejected")
	_check(inv.count_by_status()["AT_DOCK"] == 1, "count AT_DOCK")

	var tm := TaskManager.new()
	var t1 := tm.create_task("PLT-0001")
	_check(t1 != "", "task created")
	_check(tm.create_task("PLT-0001") == "", "duplicate task for pallet rejected")
	_check(tm.transition(t1, TaskManager.Status.ASSIGNED_PE), "created->assigned_pe")
	_check(not tm.transition(t1, TaskManager.Status.AT_XFER), "illegal task jump rejected")
	for s in [TaskManager.Status.PE_PICKED, TaskManager.Status.AT_XFER, TaskManager.Status.ASSIGNED_RD, TaskManager.Status.RD_PICKED, TaskManager.Status.STORED, TaskManager.Status.COMPLETED]:
		_check(tm.transition(t1, s), "task chain step " + str(s))
	_check(tm.active_tasks().is_empty(), "completed task inactive")
	return failures
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement `pallet.gd`** with an explicit transition dictionary:

```gdscript
const ALLOWED := {
	Status.AT_DOCK: [Status.ASSIGNED_TO_PE],
	Status.ASSIGNED_TO_PE: [Status.IN_TRANSIT_PE],
	Status.IN_TRANSIT_PE: [Status.AT_XFER],
	Status.AT_XFER: [Status.ASSIGNED_TO_RD],
	Status.ASSIGNED_TO_RD: [Status.IN_TRANSIT_RD],
	Status.IN_TRANSIT_RD: [Status.STORED],
	Status.STORED: [],
}
```

`set_status` returns false when `s` not in `ALLOWED[status]`; on success also updates `status` and appends to an `invalid_transitions` counter? No — keep it: return false only, engine logs.

- [ ] **Step 4: Implement `inventory_manager.gd` and `task_manager.gd`** per interfaces. `TaskManager` stores `tasks: Dictionary` id → `{id, pallet_id, status, pe_id, rd_id}`; ids `TASK-0001` incrementing; `find_task_by_pallet` returns the task whose status is not `COMPLETED` (there can be at most one active per pallet).

- [ ] **Step 5: Run tests** → `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/pallet.gd scripts/simulation/inventory_manager.gd scripts/simulation/task_manager.gd tests/task_lifecycle_test.gd tests/test_runner.gd
git commit -m "feat: pallet inventory and guarded task lifecycle"
```

---

## Task 6: Vehicle State Machine + Kinematic Route Follower

**Files:**
- Create: `scripts/entities/vehicle.gd`, `scripts/navigation/route_follower.gd`, `tests/vehicle_test.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Produces:
  - `RouteFollower`: fields `position: Vector3`, `heading: float` (radians, 0 = +X); `func step_toward(target: Vector3, speed: float, turn_rate: float, dt: float, tolerance: float) -> Dictionary` returning `{"arrived": bool, "aligned": bool}`. Behavior: rotate heading toward target at ≤ `turn_rate * dt`; move forward at `speed * dt` only when heading error ≤ 10°; snap to target when within `tolerance` and set `arrived`.
  - `Vehicle`: enum `State {IDLE, TO_DOCK, ALIGN_PICKUP, PICKING, LOADED_TO_XFER, ALIGN_DROPOFF, DROPPING, RETURNING, TO_XFER, LOADED_TO_RACK, ALIGN_RACK, PLACING}`; fields `id, vehicle_class, state, task_id, pallet_id, blocked_reason, follower`; `func can_transition(from: int, to: int, cls: String) -> bool`; `func transition(to: int) -> bool` (false + appends to `invalid_transitions` on illegal move).

- [ ] **Step 1: Write failing test `tests/vehicle_test.gd`**

```gdscript
extends RefCounted

const RouteFollower = preload("res://scripts/navigation/route_follower.gd")
const Vehicle = preload("res://scripts/entities/vehicle.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var f := RouteFollower.new()
	f.position = Vector3(0, 0, 0)
	f.heading = 0.0
	var r := f.step_toward(Vector3(10, 0, 0), 2.0, 1.5, 1.0, 0.15)
	_check(r["aligned"] and not r["arrived"], "aligned and moving")
	_check(is_equal_approx(f.position.x, 2.0), "moved 2m east, got %s" % f.position)

	f.position = Vector3(10, 0, 0)
	f.heading = 0.0
	r = f.step_toward(Vector3(10.1, 0, 0), 2.0, 1.5, 1.0, 0.15)
	_check(r["arrived"], "snapped within tolerance")
	_check(f.position == Vector3(10.1, 0, 0), "snap exact")

	f.position = Vector3(0, 0, 0)
	f.heading = PI
	r = f.step_toward(Vector3(0, 0, 10), 2.0, 1.5, 0.1, 0.15)
	_check(not r["aligned"], "must turn first (180 deg)")
	_check(f.position.length() < 0.01, "no movement while misaligned")

	var v := Vehicle.new()
	v.id = "PE-01"
	v.vehicle_class = "PE"
	v.state = Vehicle.State.IDLE
	_check(v.transition(Vehicle.State.TO_DOCK), "idle->to_dock")
	_check(v.transition(Vehicle.State.ALIGN_PICKUP), "to_dock->align_pickup")
	_check(not v.transition(Vehicle.State.LOADED_TO_RACK), "PE cannot enter RD state")
	_check(v.invalid_transitions == 1, "invalid transition counted")

	var rd := Vehicle.new()
	rd.id = "RD-01"
	rd.vehicle_class = "RD"
	rd.state = Vehicle.State.IDLE
	_check(rd.transition(Vehicle.State.TO_XFER), "RD idle->to_xfer")
	_check(not rd.transition(Vehicle.State.TO_DOCK), "RD cannot enter PE state")
	return failures
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `route_follower.gd`**

Key math: `desired = atan2(target.z - position.z, target.x - position.x)`; `delta = wrapf(desired - heading, -PI, PI)`; clamp by `turn_rate*dt`; move only if `abs(delta) <= deg_to_rad(10)`; snap if `position.distance_to(target) <= tolerance` (also update heading to desired).

- [ ] **Step 4: Implement `vehicle.gd`**

PE transition table: `IDLE→TO_DOCK`, `TO_DOCK→ALIGN_PICKUP`, `ALIGN_PICKUP→PICKING`, `PICKING→LOADED_TO_XFER`, `LOADED_TO_XFER→ALIGN_DROPOFF`, `ALIGN_DROPOFF→DROPPING`, `DROPPING→RETURNING`, `RETURNING→IDLE`.
RD table: `IDLE→TO_XFER`, `TO_XFER→ALIGN_PICKUP`, `ALIGN_PICKUP→PICKING`, `PICKING→LOADED_TO_RACK`, `LOADED_TO_RACK→ALIGN_RACK`, `ALIGN_RACK→PLACING`, `PLACING→RETURNING`, `RETURNING→IDLE`.
`can_transition` picks the table by class; `transition` returns false and increments `invalid_transitions` on failure.

- [ ] **Step 5: Run tests** → `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/vehicle.gd scripts/navigation/route_follower.gd tests/vehicle_test.gd tests/test_runner.gd
git commit -m "feat: vehicle state machines and kinematic route follower"
```

---

## Task 7: Event Log + Simulation Engine Core (vehicles, movement, pick/drop)

**Files:**
- Create: `scripts/simulation/event_log.gd`, `scripts/simulation/simulation_engine.gd`, `tests/engine_test.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Consumes: `WarehouseLayout`, `RouteGraph`, `RouteValidator`, `RouteFollower`, `Vehicle`, `Pallet`, `InventoryManager`, `TaskManager`, `ResourceManager`.
- Produces:
  - `EventLog`: `var entries: Array` (`{time, type, message}`); `func log_event(time: float, type: String, message: String) -> void`; `func recent(n: int) -> Array`.
  - `SimulationEngine`:
    - `func setup(layout_path: String, routes_path: String, config_path: String) -> bool` — loads all data, validates routes, creates resources from every non-empty waypoint resource plus vehicle parks, creates 3 vehicles: `PE-01` at `PE_PARK_01`, `PE-02` at `PE_PARK_02`, `RD-01` at `RD_PARK`; initializes dock/xfer/rack availability.
    - `func step(dt: float) -> void` — advances time and `step_count`.
    - `func add_pallet(sku: String) -> String` — places a new pallet at the first free dock position (FIFO), returns pallet id or `""`.
    - `func run_demo() -> void` — adds 4 pallets (`SKU-A`..`SKU-D`).
    - `func reset() -> void` — restores initial snapshot (same seed content, time 0, empty inventory).
    - Fields: `time`, `step_count`, `layout`, `graph`, `inventory`, `tasks`, `resources`, `events`, `vehicles: Dictionary`, `dock_free: Dictionary`, `xfer_state: Dictionary` (id → `"FREE" | "LOADED"`), `rack_slots: Dictionary` (id → `{"state": "FREE"|"RESERVED"|"OCCUPIED", "pallet": ""}`), `blocked_reasons: Dictionary`.

- [ ] **Step 1: Write failing test `tests/engine_test.gd`**

```gdscript
extends RefCounted

const SimulationEngine = preload("res://scripts/simulation/simulation_engine.gd")
var failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func run() -> int:
	var e := SimulationEngine.new()
	_check(e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json"), "engine setup")
	_check(e.vehicles.size() == 3, "3 vehicles")
	_check(e.vehicles.has("PE-01") and e.vehicles.has("PE-02") and e.vehicles.has("RD-01"), "vehicle ids")
	_check(e.vehicles["PE-01"]["pos"] == Vector3(8, 0, 1), "PE-01 parked")
	_check(e.rack_slots.size() == 8, "8 rack slots tracked")

	var id := e.add_pallet("SKU-A")
	_check(id == "PLT-0001", "pallet id sequence")
	_check(e.inventory.get_pallet(id).status == e.PalletStatus.AT_DOCK, "pallet at dock")
	_check(e.add_pallet("SKU-B") == "PLT-0002", "second pallet")

	var start := e.time
	e.step(1.0 / 60.0)
	_check(is_equal_approx(e.time, start + 1.0 / 60.0), "time advances")

	var bad := SimulationEngine.new()
	_check(not bad.setup("res://data/warehouse_layout.json", "res://data/missing.json", "res://data/vehicle_config.json"), "setup fails loudly on missing routes")
	return failures
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `event_log.gd`** (trivial: append dict, `recent(n)` returns last `n`).

- [ ] **Step 4: Implement `simulation_engine.gd` setup + step skeleton**

`setup`: load layout/routes/config; run `RouteValidator.validate` and return false on errors (print them); create `ResourceManager` and `add_resource()` for every distinct non-empty waypoint `resource`, plus `PE_PARK_01`, `PE_PARK_02`, `RD_PARK`; create vehicles with `pos` = park waypoint, `heading` 0, `state` IDLE, `follower` new; fill `dock_free` and `xfer_state` and `rack_slots` from layout.

`step(dt)`: `time += dt; step_count += 1` (movement and dispatch added in Task 8).

Expose `PalletStatus` alias: `const PalletStatus = Pallet.Status` and `TaskStatus = Task.Status` in engine for tests.

- [ ] **Step 5: Run tests** → `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add scripts/simulation/event_log.gd scripts/simulation/simulation_engine.gd tests/engine_test.gd tests/test_runner.gd
git commit -m "feat: event log and simulation engine scaffolding"
```

---

## Task 8: Dispatcher + Full Autonomous Workflow

**Files:**
- Create: `scripts/simulation/dispatcher.gd`
- Modify: `scripts/simulation/simulation_engine.gd`, `tests/engine_test.gd` (add workflow test), `tests/test_runner.gd` (no change if engine suite already registered)

**Interfaces:**
- Consumes: engine fields from Task 7.
- Produces: `Dispatcher`: `func step(engine) -> void` — assigns PE tasks for pallets at dock, assigns RD tasks for pallets at handoff with a reserved rack slot, and reserves/releases resources per leg. Engine `step()` calls `dispatcher.step(self)` first, then advances each vehicle.

- [ ] **Step 1: Add failing workflow test to `tests/engine_test.gd`**

```gdscript
func test_full_workflow() -> int:
	var before := failures
	var e := SimulationEngine.new()
	e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
	var pid := e.add_pallet("SKU-A")
	var task_id := ""
	var limit := 40000
	var steps := 0
	while steps < limit:
		e.step(1.0 / 60.0)
		steps += 1
		var p = e.inventory.get_pallet(pid)
		if p == null:
			_check(false, "pallet vanished")
			break
		if p.status == e.PalletStatus.STORED:
			break
		if p.task_id != "":
			task_id = p.task_id
		if e.vehicles["RD-01"]["pallet_id"] != "":
			var carried = e.inventory.get_pallet(e.vehicles["RD-01"]["pallet_id"])
			_check(carried != null and carried.status == e.PalletStatus.IN_TRANSIT_RD, "RD only carries IN_TRANSIT_RD pallets")
	_check(e.inventory.get_pallet(pid).status == e.PalletStatus.STORED, "pallet stored after %d steps" % steps)
	_check(e.tasks.get_task(task_id)["status"] == e.TaskStatus.COMPLETED, "task completed")
	var placed := false
	for slot_id in e.rack_slots:
		if e.rack_slots[slot_id]["pallet"] == pid:
			placed = true
	_check(placed, "pallet occupies a rack slot")
	_check(e.vehicles["PE-01"]["pallet_id"] == "" and e.vehicles["PE-02"]["pallet_id"] == "", "PEs released pallet")
	_check(e.vehicles["RD-01"]["pallet_id"] == "", "RD released pallet")
	_check(e.events.entries.size() > 5, "events logged")
	return failures - before
```

Call `test_full_workflow()` from `run()` after existing checks.

- [ ] **Step 2: Run to verify failure**

Expected: FAIL — pallet never leaves AT_DOCK because `step()` still only advances time.

- [ ] **Step 3: Implement `dispatcher.gd`**

Logic, in order:
1. **Release** finished legs: if a vehicle's `pallet_id` is empty and state is `IDLE`, release all resources it still holds.
2. **PE assignment:** for each pallet with status `AT_DOCK` and no task, in FIFO creation order: if some PE is `IDLE`, a dock position is free, and `resources.request("DOCK-" + nn, pe_id, seq)` succeeds, create task (`tm.create_task`), set `task.pe_id`, pallet `ASSIGNED_TO_PE`, `location_id` = dock id, task → `ASSIGNED_PE`; build path `pe.pos → dock pickup → DOCK_EXIT → MAIN_W → MAIN_E → XFER_JUNCTION → XFER_DROP_y` (choose the first free handoff station, reserve it via `resources.request(station_id, pe_id, seq)`); store `vehicle["path"]`, `path_index = 0`, state `TO_DOCK`.
3. **PE dropoff completion:** when PE reaches the handoff waypoint and drop timer elapsed, set pallet `AT_XFER`, `location_id` = station, release `DOCK-xx`, task → `AT_XFER`; path becomes dropoff → `XFER_EXIT` → return lane → `PE_PARK_xx`; state `RETURNING`.
4. **RD assignment:** for each pallet with status `AT_XFER` and no RD: if RD `IDLE` and hands: choose first free rack slot; `resources.request(rack_slot_id, "RD-01", seq)` → on success mark slot `RESERVED`; build path `RD_PARK → RD_XFER_QUEUE → RD_XFER_APPROACH_x → XFER_DROP_x → RD_XFER_APPROACH_x → SD_ENTRY → SD_xx → RACK_APP_xx → RACK_PLACE_xx`; pallet `ASSIGNED_TO_RD`, task → `ASSIGNED_RD`, state `TO_XFER`.
5. **RD completion:** on rack place arrival + timer, pallet `STORED`, slot `OCCUPIED` with pallet id, task → `STORED` then `COMPLETED`; release station and rack resource; return path to `RD_PARK`, state `RETURNING`.

Wait timing for pick/drop: on arrival at pickup/dropoff waypoint, enter `PICKING`/`DROPPING`, use `pickup_seconds`/`dropoff_seconds` from config as `phase_timer`; when it expires, apply the state change. This prevents instant pickups.

- [ ] **Step 4: Extend `simulation_engine.gd`** with the per-step loop:

```
step(dt):
  time += dt; step_count += 1
  dispatcher.step(self)
  for each vehicle:
    if path empty or blocked: continue
    target = graph.waypoint_pos(path[path_index])
    result = follower.step_toward(target, speed, turn_rate, dt, tolerance)
    vehicle.pos = follower.position; vehicle.heading = follower.heading
    if result.arrived: path_index += 1; if path_index >= path.size(): path = []; notify dispatcher arrival
  apply phase timers for PICKING/DROPPING
```

Add `func _vehicle_at(veh_id, waypoint_id) -> bool`.

- [ ] **Step 5: Run tests**

Run: `godot --headless --path . --script tests/test_runner.gd`
Expected: `ALL TESTS PASSED`, including pallet stored. If the workflow stalls, inspect `e.events.entries` in the test output (add a temporary print of the last 10 events) and fix the blocking resource; do not increase the step limit as a fix.

- [ ] **Step 6: Add a second workflow test for two PEs**

Add `test_two_pallets`: add two pallets, run until both stored, assert both `STORED`, both rack slots `OCCUPIED`, and no pallet id appears in two slots. This exercises concurrent dock/handoff reservations.

- [ ] **Step 7: Commit**

```bash
git add scripts/simulation/dispatcher.gd scripts/simulation/simulation_engine.gd tests/engine_test.gd
git commit -m "feat: dispatcher and full autonomous pallet workflow"
```

---

## Task 9: 3D World Blockout + Visual Sync

**Files:**
- Create: `scripts/app/warehouse_builder.gd`
- Modify: `scenes/main.tscn`, `scripts/app/main.gd`

**Interfaces:**
- Consumes: engine, layout, graph.
- Produces:
  - `WarehouseBuilder.build_world(parent: Node3D, layout, graph) -> Dictionary` returning `{"vehicles": {id: MeshInstance3D}, "pallets_root": Node3D, "rack_nodes": {slot_id: MeshInstance3D}, "xfer_nodes": {station_id: MeshInstance3D}, "dock_nodes": {dock_id: MeshInstance3D}}`.
  - `WarehouseBuilder.build_pallet_mesh() -> MeshInstance3D` (1.2×0.15×1.0 BoxMesh).
  - `WarehouseBuilder.build_pe_mesh(color: Color)`, `WarehouseBuilder.build_rd_mesh()`.
  - `main.gd`: `Sim` engine instance; `_physics_process` steps the engine at fixed 60 Hz with accumulator; `_process` syncs visuals and HUD.

- [ ] **Step 1: Implement `warehouse_builder.gd`**

- Floor: `PlaneMesh` 36×8 (or BoxMesh) with dark gray material, at y=0.
- Perimeter walls: thin BoxMesh strips matching layout obstacle strips (y 0..3), medium gray.
- Racks: for each rack row and each of the two z cells, one BoxMesh you can see through? No — solid box 1×2×1.2 at the obstacle AABB center, dark blue-gray; plus 2 post meshes optional (skip; keep draw calls low).
- Dock positions: 2×2 flat quad + `Label3D` text `DOCK-01..03` at y=0.05.
- Handoff stations: flat quad with yellow material + `Label3D` `XFER-01/02`.
- Rack slot indicators: thin flat quad (1×1) at slot position, unlit green (free), yellow (reserved), red (occupied), updated each frame from engine.
- Vehicles: PE = BoxMesh 1.2×0.3×0.8, color blue (`Color(0.2,0.4,0.9)`) or orange (`Color(0.95,0.55,0.1)`) per id; RD = BoxMesh 1.5×1.0×0.9 gray + mast BoxMesh 0.2×1.6×0.2 at front + fork BoxMesh 0.9×0.08×0.15 (two forks optional; one is enough visually).
- `Label3D` for `PE-01`, `PE-02`, `RD-01` above each vehicle (billboard on).
- Area labels: `Label3D` at area centers.
- Pallet visuals: created/removed in `main.gd` sync based on engine inventory (parent under `pallets_root`).

Keep total node count under ~120.

- [ ] **Step 2: Update `main.gd`**

```gdscript
extends Node3D

const SimulationEngine = preload("res://scripts/simulation/simulation_engine.gd")
const WarehouseBuilder = preload("res://scripts/app/warehouse_builder.gd")

var sim
var world := {}
var accumulator := 0.0
var paused := false
var speed_multiplier := 1.0
var selected_vehicle := "PE-01"
const FIXED := 1.0 / 60.0

func _ready() -> void:
	sim = SimulationEngine.new()
	if not sim.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json"):
		push_error("Simulation setup failed")
		return
	world = WarehouseBuilder.build_world(self, sim.layout, sim.graph)
	_build_camera_and_light()

func _physics_process(delta: float) -> void:
	if paused: return
	accumulator += delta * speed_multiplier
	while accumulator >= FIXED:
		sim.step(FIXED)
		accumulator -= FIXED

func _process(_delta: float) -> void:
	_sync_visuals()
```

Variables `paused`, `speed_multiplier`, `selected_vehicle` consumed by HUD in Task 11.

- [ ] **Step 3: Headless scene smoke test**

Run:
```bash
godot --headless --path . --quit-after 180 2>&1 | tee /tmp/sam_scene.log
grep -cE "SCRIPT ERROR|ERROR:" /tmp/sam_scene.log
```
Expected: `0` errors.

- [ ] **Step 4: Physical visual check (user-run)**

Ask the user to run `godot --path .` on the laptop display. Success: floor, walls, racks, lanes, three vehicles, labels visible; no flicker; FPS readable. Do not claim visual success without this check; record result in `README.md` in Task 12.

- [ ] **Step 5: Commit**

```bash
git add scripts/app/warehouse_builder.gd scripts/app/main.gd scenes/main.tscn
git commit -m "feat: 3D warehouse blockout and engine visual sync"
```

---

## Task 10: HUD

**Files:**
- Create: `scripts/ui/hud.gd`
- Modify: `scenes/main.tscn` (add `CanvasLayer` with script), `scripts/app/main.gd` (wire signals)

**Interfaces:**
- Consumes: `main.gd` fields `sim`, `paused`, `speed_multiplier`, `selected_vehicle`.
- Produces: `Hud` (extends `CanvasLayer`) signals: `start_pressed`, `pause_toggled(is_paused)`, `reset_pressed`, `speed_changed(mult)`, `add_pallet_pressed`, `demo_pressed`, `route_overlay_toggled(visible)`, `waypoint_labels_toggled(visible)`, `camera_preset_changed(preset: String)`, `vehicle_selected(veh_id: String)`; `func update_state(sim, paused: bool, fps: float) -> void`; `func set_selected_vehicle(veh_id: String) -> void`.

- [ ] **Step 1: Implement `hud.gd` procedurally**

Left panel (VBoxContainer): title, Start button, Pause button (toggle text), Reset, speed `OptionButton` (0.5x/1x/2x/4x), Add Pallet, Run Demo. Toggles (CheckButton): Routes, Waypoint IDs. Camera `OptionButton`: Overview / Top-down / Follow. Clock label.

Right panel: vehicle cards for `PE-01`, `PE-02`, `RD-01` — labels `State`, `Task`, `Load`, `Next WP`, `Blocked`; each card is a Button that emits `vehicle_selected`.

Bottom panel: task queue (up to 8 rows), rack occupancy summary (`Occupied n/8`), event log (`RichTextLabel`, last 10 events). Counts row: Dock/PE/Xfer/RD/Stored/Completed. FPS + sim tick time label.

`update_state` refreshes every label from engine state each frame. Use `Theme` defaults; set `theme_override_font_sizes` for compactness.

- [ ] **Step 2: Wire in `main.gd`**

Connect each HUD signal to the corresponding action:
- start → `paused = false`
- pause → `paused = not paused`
- reset → `sim.reset(); accumulator = 0`
- speed → `speed_multiplier = mult`
- add_pallet → `sim.add_pallet("SKU-X")`
- demo → `sim.run_demo()`
- toggles → `route_overlay.visible`, `waypoint_labels.visible`
- camera → `_set_camera_preset(preset)`
- vehicle_selected → `selected_vehicle = id`

`_process` calls `hud.update_state(sim, paused, Engine.get_frames_per_second())`.

- [ ] **Step 3: Headless smoke test**

Run:
```bash
godot --headless --path . --quit-after 180 2>&1 | tee /tmp/sam_hud.log
grep -cE "SCRIPT ERROR|ERROR:" /tmp/sam_hud.log
```
Expected: `0`.

- [ ] **Step 4: Add a headless HUD instantiation test** `tests/hud_test.gd` that loads `scripts/ui/hud.gd`, instantiates it, calls `update_state` with a fresh engine after 1 step, and asserts no errors and that the clock label text contains `"0.0"` or greater. Register in the runner. (HUD nodes require a SceneTree; instantiate inside the runner's `_initialize` via `root.add_child(hud)` then `hud.queue_free()`.)

- [ ] **Step 5: Run full test suite** → `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/hud.gd scripts/app/main.gd scenes/main.tscn tests/hud_test.gd tests/test_runner.gd
git commit -m "feat: simulation HUD with controls, vehicle cards, and event log"
```

---

## Task 11: Route Debug Overlay + Camera Presets

**Files:**
- Create: `scripts/app/route_overlay.gd`
- Modify: `scripts/app/main.gd`

**Interfaces:**
- Consumes: `graph`, `world`, camera.
- Produces: `RouteOverlay` (extends `Node3D`): `func build(graph, layout) -> void`; `func set_labels_visible(v: bool) -> void`; `func update_vehicle_markers(vehicles: Dictionary) -> void` (small spheres at current target waypoint).

- [ ] **Step 1: Implement `route_overlay.gd`**

- For each edge: a `MeshInstance3D` with `ImmediateMesh` line (2 points, thin `StandardMaterial3D` unlit cyan). Merge all edges into **one** ImmediateMesh for low draw calls.
- Waypoint markers: one `MeshInstance3D` with `ImmediateMesh` points? Use small `BoxMesh` instances only for `turn`/`wait`/`pickup`/`handoff` types; keep under 40 nodes.
- Waypoint id labels: `Label3D` per waypoint (billboard, `font_size=32`, `no_depth_test=true`), hidden by default; `set_labels_visible` toggles.
- Target markers: 3 small `MeshInstance3D` spheres (radius 0.12, green), moved each frame to each vehicle's current target waypoint.

- [ ] **Step 2: Wire into `main.gd`**

Create overlay in `_ready` after world build, `overlay.visible = false` by default; toggle via HUD. `_process` calls `overlay.update_vehicle_markers(sim.vehicles)`.

Camera presets:
- `overview`: position `(18, 24, 20)`, look at `(18, 0, 4)`
- `top_down`: position `(18, 30, 4.01)`, look at `(18, 0, 4)` (slight z offset avoids up-vector degeneracy)
- `follow`: each frame position `vehicle.pos + Vector3(-8, 6, 8)`, look at `vehicle.pos`; lerp with `lerp(a, b, min(1.0, delta * 4.0))`.

- [ ] **Step 3: Headless smoke test** — same grep pattern; expected `0`.

- [ ] **Step 4: Commit**

```bash
git add scripts/app/route_overlay.gd scripts/app/main.gd
git commit -m "feat: route debug overlay and camera presets"
```

---

## Task 12: Performance Settings, README, Final Verification

**Files:**
- Modify: `project.godot`, `scripts/ui/hud.gd` (Low/Medium graphics option), `README.md` (create)
- Modify: `tests/engine_test.gd` (determinism test)

**Interfaces:**
- Produces: final documented state; `README.md` with engine version, renderer, hardware, run/test commands, measured results.

- [ ] **Step 1: Add determinism test to `tests/engine_test.gd`**

```gdscript
func test_determinism() -> int:
	var out: Array = []
	for run_index in [0, 1]:
		var e := SimulationEngine.new()
		e.setup("res://data/warehouse_layout.json", "res://data/routes.json", "res://data/vehicle_config.json")
		e.run_demo()
		for i in range(20000):
			e.step(1.0 / 60.0)
		var snap := []
		for vid in ["PE-01", "PE-02", "RD-01"]:
			snap.append([vid, e.vehicles[vid]["pos"], e.vehicles[vid]["state"]])
		for pid in sorted(e.inventory.pallets.keys()):
			snap.append([pid, e.inventory.get_pallet(pid).status])
		out.append(snap)
	_check(str(out[0]) == str(out[1]), "identical replay after 20000 steps")
	return 0
```

Call it from `run()`.

- [ ] **Step 2: Run to verify**

Run: `godot --headless --path . --script tests/test_runner.gd`
Expected: `ALL TESTS PASSED`. If determinism fails, find iteration-order dependence (dictionary iteration is insertion-ordered in Godot 4 — ensure IDs are generated in the same order and no RNG is used) and fix it; do not seed RNG to mask it.

- [ ] **Step 3: Add Low/Medium graphics option to HUD**

`OptionButton` "Graphics: Low/Medium": Low sets `get_viewport().scaling_3d_scale = 0.6` and light shadows off; Medium sets `1.0` and shadows off (shadow toggle exists separately). Keep shadows off by default on this laptop.

- [ ] **Step 4: Fix project settings for laptop**

Ensure in `project.godot`:
```ini
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
viewport/scale_3d=1.0
```
Confirm no `shadow_enabled = true` anywhere (`grep -rn "shadow_enabled" scripts/`).

- [ ] **Step 5: Write `README.md`**

Include:
- Project description and workflow.
- Hardware tested: Acer Aspire 4750, i5-2520M, Intel HD 3000, 7.6 GiB RAM, Mesa 25.2.8, OpenGL 3.3 Core — Compatibility renderer.
- Godot version used (record actual version output from `godot --version`).
- Run: `godot --path .`
- Tests: `godot --headless --path . --script tests/test_runner.gd`
- Controls summary.
- Data files and how to edit routes/layout.
- Known limitations: primitives only, no sensors, rack aisle bidirectional for single RD, no ROS.
- Verification results table (date, test suite result, scene smoke result, physically observed FPS if the user ran it).

- [ ] **Step 6: Final headless verification**

```bash
godot --headless --path . --import
godot --headless --path . --script tests/test_runner.gd
godot --headless --path . --quit-after 300 2>&1 | tee /tmp/sam_final.log
grep -cE "SCRIPT ERROR|ERROR:" /tmp/sam_final.log
```
Expected: `ALL TESTS PASSED`; grep count `0`.

- [ ] **Step 7: Ask the user for the physical performance check**

Have the user run `godot --path .`, press Run Demo, and report FPS at 1366×768. Record it in `README.md`. Do not claim performance is acceptable without this.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: laptop performance settings, README, and final verification"
```

---

## Self-Review Notes

- Spec coverage: workflow (Tasks 7–8), routing (Task 3), 3D/nav (Tasks 9, 11), traffic (Task 4 + 8), HUD (Task 10), tests (all tasks), performance (Tasks 9, 12), run instructions (Task 12).
- `Dispatcher` interfaces are defined in Task 8 and consumed by the engine, both in that task.
- `RouteFollower` emits `{arrived, aligned}` everywhere it is used in Task 8.
- All resource names in `routes.json` are declared in `ResourceManager` during `setup`.
- Physical GPU verification remains a user-run gate in Tasks 9 and 12.

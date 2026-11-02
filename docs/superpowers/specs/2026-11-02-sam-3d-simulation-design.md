# S.A.M. 3D Warehouse Simulation — Design Specification

**Date**: 2026-11-02  
**Project**: Smart Autonom Mover (S.A.M.)  
**Target Hardware**: Acer Aspire 4750, Intel i5-2520M, Intel HD Graphics 3000, 8 GB RAM, Ubuntu 24.04  
**Confirmed OpenGL**: 3.3 Core Profile (Mesa 25.2.8) — Godot 4 Compatibility renderer viable

---

## 1. Architecture & Engine Setup

**Engine**: Godot 4.3+ (LTS), Compatibility Renderer (OpenGL 3.3)  
**Language**: GDScript  
**Project Structure** (per brief):
```
project.godot
scenes/
  main.tscn
  warehouse/
    warehouse_world.tscn
    dock_room.tscn
    transfer_area.tscn
    storage_room.tscn
  vehicles/
    pallet_mover.tscn
    forklift_rd.tscn
  props/
    pallet.tscn
    rack.tscn
scripts/
  app/
    simulation_controller.gd
    simulation_config.gd
  simulation/
    simulation_engine.gd
    dispatcher.gd
    task_manager.gd
    inventory_manager.gd
    resource_manager.gd
    event_log.gd
  entities/
    vehicle.gd
    pallet.gd
    rack_slot.gd
  navigation/
    waypoint.gd
    route_graph.gd
    route_validator.gd
    route_follower.gd
  ui/
    hud.gd
    vehicle_panel.gd
    task_queue_panel.gd
    inventory_panel.gd
data/
  warehouse_layout.json
  routes.json
  vehicle_config.json
tests/
  route_validation.gd
  resource_manager_test.gd
  task_lifecycle_test.gd
  full_workflow_test.gd
assets/
  models/
  materials/
  textures/
```

**Key Architectural Decisions**:
- **Separation of concerns**: `SimulationEngine` (pure GDScript class, no Node) holds authoritative state; 3D scene reads state each frame and interpolates visuals.
- **Fixed timestep**: the main scene controller (`scripts/app/main.gd`) runs the simulation at 60 Hz with an accumulator; render interpolation smooths visuals without affecting logic. It is a scene node, not an autoload, so headless tests stay isolated.
- **Headless-capable**: Simulation can run without 3D scene for automated tests.
- **Configuration-driven**: Warehouse layout, routes, vehicle params in JSON for portability.

---

## 2. Warehouse Layout & Waypoint System

**Coordinate System**: 1 world unit = 1 meter, Y-up, origin at Dock Room corner (0,0,0).

**Area Bounds**:
| Area | X Range | Z Range | Purpose |
|------|---------|---------|---------|
| Dock Room | 0–12 | 0–8 | Receiving, 3 dock positions |
| Transfer Area | 12–16 | 0–8 | 2 handoff stations (XFER-01, XFER-02) |
| Storage Room | 16–36 | 0–8 | 4 rack rows (x=18,22,26,30), 2 bays each = 8 slots |

**Key Positions** (x, z):
- `DOCK-01`: (2, 2), `DOCK-02`: (2, 4), `DOCK-03`: (2, 6)
- `XFER-01`: (14, 2), `XFER-02`: (14, 6)
- Rack slots: `RACK-A-01`(18,2), `RACK-A-02`(18,6), `RACK-B-01`(22,2), `RACK-B-02`(22,6), `RACK-C-01`(26,2), `RACK-C-02`(26,6), `RACK-D-01`(30,2), `RACK-D-02`(30,6)

**Waypoint Graph** (`data/routes.json`):
- Waypoints: stable ID, Vector3 position, type (lane/pickup/dropoff/turn/wait/parking/rack-approach), allowed vehicle classes (PE/RD/both), optional resource ID, optional desired heading.
- Edges: from/to waypoint IDs, directionality, allowed classes, resource ID for exclusive segments, optional speed limit.
- Required PE route: `PE_PARK → DOCK_QUEUE → DOCK_PICKUP_X → DOCK_EXIT → MAIN_LANE_MID → XFER_APPROACH → XFER_DROP_X → PE_RETURN → PE_PARK`
- Required RD route: `RD_PARK → XFER_QUEUE → XFER_PICKUP_X → STORAGE_MAIN_LANE → RACK_APPROACH_X → RACK_PLACE_X → RD_RETURN → RD_PARK`

**Route Validation**: `RouteValidator` checks graph connectivity, AABB clearance from walls/racks (0.5m margin), and that all required sequences exist for both vehicle classes.

---

## 3. Vehicle Models & State Machines

**Base Class**: `Vehicle` (extends `CharacterBody3D` for kinematic control)
- Fields: `id`, `vehicle_class`, `state`, `position`, `heading`, `route`, `route_index`, `task_id`, `pallet_id`, `speed`, `accel`, `turn_rate`, `reservations[]`, `blocked_reason`, `phase_timer`
- Movement: `RouteFollower` drives kinematic velocity toward next waypoint; aligns heading at turn waypoints; snaps within `arrival_tolerance` (0.15m).

**PE (Pallet Mover)** — `scenes/vehicles/pallet_mover.tscn`:
- Geometry: Low-profile box (1.2×0.8×0.3m) + pallet attachment point (MeshInstance3D).
- Two instances: `PE-01` (blue accent material), `PE-02` (orange accent).
- States: `IDLE → TO_DOCK → ALIGN_PICKUP → PICKING → LOADED_TO_XFER → ALIGN_DROPOFF → DROPPING → RETURNING → IDLE`
- Transitions guarded by: resource acquired, waypoint reached, pickup/dropoff animation complete.

**RD (Forklift)** — `scenes/vehicles/forklift_rd.tscn`:
- Geometry: Chassis (1.5×0.9×1.0m) + mast + forks (animated via `AnimationPlayer` for raise/lower).
- States: `IDLE → TO_XFER → ALIGN_PICKUP → PICKING → LOADED_TO_RACK → ALIGN_RACK → PLACING → RETURNING → IDLE`

**State Machine**: `VehicleStateMachine` (pure class) with `transition_to(new_state)` validating against allowed transitions; invalid attempts log warning in debug. Each state has `enter()`, `update(delta)`, `exit()`.

---

## 4. Pallet, Inventory & Task Dispatcher

**Pallet Data** (`Pallet` class):
- `id`: `PLT-####`, `sku`, `status` (enum: `AT_DOCK`, `ASSIGNED_TO_PE`, `IN_TRANSIT_PE`, `AT_XFER`, `ASSIGNED_TO_RD`, `IN_TRANSIT_RD`, `STORED`), `location_id`, `destination_rack_id`, `task_id`

**Task Lifecycle**:
`CREATED → ASSIGNED_PE → PE_PICKED → AT_XFER → ASSIGNED_RD → RD_PICKED → STORED → COMPLETED`
Every transition validated; duplicate assignment prevented.

**Dispatcher** (`Dispatcher` class):
- FIFO queue for incoming pallets.
- Assigns pallet to idle PE only when: pickup position free, transfer station capacity available.
- After PE dropoff, notifies dispatcher → assigns RD when: pallet physically at handoff, rack slot reserved.
- Rack slot reserved before RD starts loaded trip.
- Queue with blocked reason if resources unavailable.
- Assignment logic independent of rendering.

---

## 5. Traffic Control & Collision Prevention

**ResourceManager** (`ResourceManager` class):
- Exclusive resources: narrow aisles, intersections, handoff positions, dock pickups, rack approaches, parking slots.
- Capacity: default 1 for narrow aisles/conflict zones.
- Protocol: request before entry, release after fully cleared.
- Wait waypoints defined for each resource.
- Deterministic FIFO queue ordering to avoid starvation.
- Safety gap: vehicles maintain 1.5m separation on same lane.
- One-way traffic on single-lane aisles (MAIN_AISLE: Dock→Xfer; STORAGE_AISLE: Xfer→Racks).
- Deadlock detection: if vehicle blocked >30s, log diagnostics.
- Event log: grant, wait, entry, exit, release.

---

## 6. Simulation HUD & Controls

**HUD** (`scenes/ui/hud.tscn`, `scripts/ui/hud.gd`):
- Controls: Start/Pause/Reset, Speed (0.5x/1x/2x/4x), Add Pallet, Run Demo.
- Toggles: Route overlays, Waypoint IDs, Collision bounds.
- Camera presets: Overview, Top-down, Follow selected vehicle.
- Readouts: Simulation clock, Counts (at Dock, PE transport, at Xfer, RD transport, Stored, Completed).
- Vehicle cards: PE-01, PE-02, RD-01 — state, task, load, next waypoint, blocked reason.
- Task queue panel, Rack occupancy panel, Timestamped event log.
- All actions call `SimulationController`, never modify vehicle nodes directly.

---

## 7. Performance Budget (Target: Intel HD 3000)

- Low-poly primitives (BoxMesh, CylinderMesh) for all geometry; no imported meshes initially.
- Unlit `StandardMaterial3D` or `CanvasItemMaterial`; no real-time shadows by default.
- Single `DirectionalLight3D` (baked feel) + minimal `Environment` (no SSAO, no volumetrics, no reflections).
- Max ~200 visible meshes, 1 light, 0 dynamic shadows.
- Simple collision: `BoxShape3D`/`CylinderShape3D` only; no physics simulation for static props.
- Graphics settings: Low/Medium (render scale 0.5/1.0), Shadows on/off, Debug overlays on/off.
- FPS + simulation tick time displayed in HUD.
- Target: 30+ FPS at 1366×768 on target hardware.

---

## 8. Simulation Timing & Separation

- The main scene controller (`scripts/app/main.gd`) owns the fixed timestep (1/60s default) with accumulator.
- `SimulationEngine` advances state; 3D scene `_process(delta)` interpolates visual positions.
- Pause freezes simulation time and state transitions.
- Reset returns to deterministic initial snapshot (seeded RNG if any).
- Speed control scales simulation timestep multiplier.
- Event log: pallet received, task assigned, pickup, handoff, rack reservation, placement, resource wait/release, completion.
- Model portable for future ROS 2/Webots backend.

---

## 9. Acceptance Criteria (from Brief)

### Workflow
- [ ] Exactly PE-01, PE-02, RD-01 present.
- [ ] Pallets arrive at Dock Room.
- [ ] PE receives task, follows fixed route, picks up, drops at handoff.
- [ ] RD cannot collect before PE confirms dropoff.
- [ ] RD reserves rack slot, collects, stores.
- [ ] Inventory/task status update correctly.
- [ ] Multiple pallets processed without duplicate assignment.

### 3D & Navigation
- [ ] Dock, Transfer, Storage, racks, lanes, pallets visible.
- [ ] Vehicles follow exact authored waypoint sequences.
- [ ] Route overlays and waypoint IDs inspectable.
- [ ] Routes don't intersect walls/racks.
- [ ] Vehicle turns and alignment stable.
- [ ] Resource reservations prevent simultaneous exclusive zone use.
- [ ] Vehicles wait safely when blocked.

### Runtime
- [ ] Godot editor/runtime launch on target laptop.
- [ ] Default scene responsive at laptop resolution.
- [ ] Start, pause, reset, speed controls work.
- [ ] No errors during deterministic demo.
- [ ] Headless tests validate routing, resource locking, task transitions, full workflow.

---

## 10. Implementation Phases (from Brief)

1. Inspect repository & laptop GPU/OpenGL — **DONE** (OpenGL 3.3 confirmed)
2. Create minimal Godot 4.3 project; verify Compatibility renderer.
3. Build warehouse blockout: floor, rooms, lanes, racks (primitives).
4. Author exact waypoint graph (`routes.json`); validate.
5. Add one PE; test route following.
6. Add PE-02 and RD-01 with state machines.
7. Add pallet pickup/dropoff and task lifecycle.
8. Add traffic reservations and resource queues.
9. Add HUD, route debug overlay, event log.
10. Add tests and optimize for laptop.
11. Polish models, lighting, camera, materials after functional criteria pass.

---

## 11. Known Limitations & Next Steps

**Limitations**:
- No sensor simulation (lidar, proximity) — later phase.
- No visual route editor — JSON authoring only.
- No ROS 2 integration — simulation model separated for future backend.
- Primitive meshes only — GLTF assets can replace later.

**Later Enhancements** (post-acceptance):
- Visual route editor with draggable waypoints.
- Import/export layout/routes as JSON.
- Scenario presets (congested dock, full racks, blocked aisle).
- Metrics: throughput, avg task time, utilization, queue time.
- Replay system.
- Sensor visualization.
- ROS 2 / Webots / Gazebo backend integration.

---

## 12. Run Instructions (Planned)

```bash
# Install Godot 4.3+ (Flatpak recommended for Ubuntu 24.04)
flatpak install flathub org.godotengine.Godot

# Or download from https://godotengine.org/download

# Open project
godot --path /home/bentar-raya/Documents/S.A.M

# Run headless tests
godot --headless --path /home/bentar-raya/Documents/S.A.M --script tests/full_workflow_test.gd
```

---

**Design Status**: Approved for implementation. Ready for `writing-plans` skill.
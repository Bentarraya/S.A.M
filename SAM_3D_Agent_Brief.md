# Smart Autonom Mover (S.A.M)
## 3D Simulation Agent Brief

> Build S.A.M as a local 3D warehouse intralogistics simulation. Inspect the current repository and laptop runtime before selecting or installing dependencies. Preserve working code. This document supersedes the previous 2D/Phaser direction.

---

## 1. Project Goal

Create a 3D warehouse simulation with exactly three autonomous vehicles:

- `PE-01`: Pallet Mover
- `PE-02`: Pallet Mover
- `RD-01`: Forklift

The operational flow:

1. Goods arrive at the **Dock Room**.
2. An available PE receives a transport task, approaches a pallet, picks it up, and carries it to the transfer/handoff area.
3. PE places the pallet at a reserved handoff point and confirms the handoff.
4. RD receives the available pallet, reserves a rack slot, picks up the pallet, and carries it into the **Storage Room**.
5. RD aligns with the assigned rack slot, places the pallet, and updates inventory/task status.
6. The vehicles return to their designated waiting/parking positions or accept another task.

This is a software simulation on the laptop. Do not invent real hardware, PLC, ROS, or sensor integrations unless they are explicitly added as a later phase.

## 2. Engine Decision and Hardware Fit

### Primary recommendation: Godot 4, 3D Compatibility renderer

Use Godot if the main goal is a polished, interactive 3D digital-twin-style visualization that can run locally with a relatively small codebase.

Why:
- Integrated 3D scene editor, physics, camera, animation, UI, and scripting.
- GDScript avoids adding a separate runtime/toolchain for the initial simulation.
- The project can keep simulation logic separate from the 3D presentation.
- The Compatibility renderer uses OpenGL and is a better first test for older integrated graphics than a Vulkan-only renderer.

**Important hardware constraint:** the known laptop is an Acer Aspire 4750 with Intel Core i5-2520M and Intel HD Graphics 3000, with RAM previously upgraded/discussed to 8 GB. This is old integrated graphics. Do not assume Godot 4 will run smoothly or that the GPU driver exposes the required OpenGL level. First test the actual system:

```bash
lscpu
free -h
glxinfo -B
```

If `glxinfo` is missing, it can be installed through the Ubuntu package `mesa-utils`. Check the reported OpenGL version and renderer. Godot 4 Compatibility requires OpenGL 3.3; the GPU/driver must actually expose it. If it does not, do not waste time fighting the renderer.

Godot official system requirements: https://docs.godotengine.org/en/stable/about/system_requirements.html

### Fallback if Godot 4 Compatibility cannot run acceptably

Use **Godot 3.6 with GLES2** only if the installed build and feature needs are compatible. This is a fallback for older graphics, not the default. Confirm the version's support status and avoid mixing Godot 3 and Godot 4 project files.

If a reliable 3D scene is still not feasible, reduce rendering cost before changing engines:
- Low-resolution viewport / render scale
- Simple materials and unlit shading
- Baked or minimal lighting
- No real-time shadows by default
- Low-poly meshes
- Limited draw calls and visible objects
- Fixed camera options: isometric, top-down, and follow view

### Other engine options

| Engine | Best fit | Main trade-off for this project |
|---|---|---|
| Godot 4 | Visual 3D warehouse simulation and interactive UI | Must validate OpenGL 3.3 support on the old Intel GPU |
| Webots | Robotics behavior, sensors, kinematics, controller experiments | Official docs caution about Intel graphics; may be a poor fit for this laptop's GPU |
| Gazebo | ROS 2 integration, robotics physics and sensor ecosystem | More setup and runtime overhead than needed for a first local workflow simulator |
| raylib | Custom lightweight 3D renderer if the user means raylib | More engine systems must be built manually: scene tools, UI, collision, editor workflow, asset pipeline |

Do not install or migrate to Webots/Gazebo just because they are robotics simulators. Choose them if the project specifically needs realistic robot sensors, ROS 2, controller integration, or robotics research. For the requested warehouse workflow and visual demonstration, Godot is the preferred starting point, subject to the GPU smoke test.

Gazebo version note: for Ubuntu 24.04, Gazebo Harmonic is a supported pairing particularly with ROS 2 Jazzy; newer Gazebo releases also exist. Do not install an arbitrary Gazebo release without checking the chosen ROS 2 distribution compatibility.
Gazebo docs: https://gazebosim.org/docs/harmonic/

Webots system requirements: https://github.com/cyberbotics/webots/blob/master/docs/guide/system-requirements.md

---

## 3. Technology and Dependency Policy

### Godot path (preferred)

- Godot 4.x, Compatibility renderer, GDScript.
- Native Godot scenes/nodes for world, vehicles, racks, pallets, camera, and HUD.
- Godot built-in physics only where needed for collision checks; route movement is controlled by the simulation engine.
- JSON or `.tres`/`.res` configuration for warehouse layout and route data.
- GDScript unit tests or a small headless test harness for core logic.
- Git for version control.

Do not add Node.js, React, Vite, Python, ROS 2, or external physics packages unless an existing project or a specific feature requires them. Keep dependencies small.

### If the existing repository is web-based

Do not silently force Godot into the existing Vite app. First report the trade-off:
- Godot is a separate native project and has its own scene/project files.
- A web dashboard can be a separate optional client later.
- Keep the simulation model/data format portable (JSON) so a future dashboard can consume it.

### Dependency inspection

Before changing files:
1. Inspect repository tree, current engine/framework, package manifests, lockfiles, scripts, and Git status.
2. Inspect laptop CPU, RAM, GPU, OpenGL/Vulkan support, and Ubuntu version when accessible.
3. Run a minimal engine/rendering smoke test before building the full environment.
4. Record exact engine version and renderer in `README.md`.
5. Do not upgrade system packages or install a large robotics stack without explaining why.

---

## 4. 3D Warehouse Layout

Build a top-down/isometric-friendly warehouse with world coordinates and clear physical geometry.

### Areas

**Dock Room**
- Receiving zone for new goods.
- Receiving positions: `DOCK-01`, `DOCK-02`, `DOCK-03` at minimum.
- PE pickup alignment points and queue/wait points.
- A defined outbound lane.

**Transfer / Handoff Area**
- A clearly marked boundary between Dock Room and Storage Room.
- Handoff stations: `XFER-01` and `XFER-02`.
- PE drops a pallet only after reserving an available station.
- RD can collect only after PE has completed placement and released the pallet.
- Handoff stations are exclusive shared resources.

**Storage Room**
- Rack rows and visible bays/slots.
- Stable IDs such as `RACK-A-01`, `RACK-A-02`, `RACK-B-01`.
- Each slot has a rack approach waypoint and a precise placement transform.
- Placement points must not obstruct the main traffic aisle.
- Show occupied/reserved/free slots with distinct visual states.

### 3D scene requirements

- Use a consistent metric-like scale, e.g. 1 world unit = 1 meter.
- Floor, room walls, racks, aisle markings, safety boundaries, and signs.
- Use simple low-poly assets or primitive meshes first.
- Ensure rack geometry and walls do not intersect the navigation lane.
- Vehicle and pallet dimensions must be configurable.
- Provide a default camera that shows the complete workflow and a close-up/follow camera for inspection.
- Provide clear labels for Dock Room, Transfer Area, Storage Room, vehicle IDs, and rack IDs.

The map must be authored from explicit coordinates, not generated by arbitrary random placement.

---

## 5. Route System: Exact, Fixed, and Inspectable

### Navigation representation

Use a **waypoint graph with authored 3D coordinates**. For this first version, routes should be deterministic and fixed. Do not use free-roaming steering or unconstrained navigation mesh paths as the primary route definition.

Each waypoint contains:
- Stable ID
- `Vector3` position
- Type: lane, pickup, dropoff, turn, wait, rack-approach, parking
- Optional resource/conflict-zone ID
- Allowed vehicle classes
- Optional desired heading at the waypoint

Each edge contains:
- From/to waypoint IDs
- Directionality
- Allowed vehicle classes (`PE`, `RD`, or both)
- Resource ID for exclusive segments/conflict zones
- Optional speed limit

### Required logical routes

PE:
`PE-PARK → DOCK-QUEUE → DOCK-PICKUP → DOCK-EXIT → MAIN-LANE → XFER-APPROACH → XFER-DROP → PE-RETURN → PE-PARK`

RD:
`RD-PARK → XFER-QUEUE → XFER-PICKUP → STORAGE-MAIN-LANE → RACK-APPROACH → RACK-PLACE → RD-RETURN → RD-PARK`

These are operational stages. Define the actual waypoint IDs and exact coordinates in configuration files. The route geometry must be visible and reviewable in the editor/debug overlay.

### Precision rules

- Vehicles move waypoint-to-waypoint along authored lane centerlines.
- No arbitrary shortcuts through Euclidean movement.
- No corner cutting: reach the turn waypoint and align heading before proceeding.
- Use a configurable arrival tolerance and snap to waypoint only within that tolerance.
- Define a stop/alignment pose for pickup, handoff, and rack placement.
- Validate route connectivity and collision clearance against walls/racks.
- Draw route lines, arrows, waypoint IDs, and current target in debug mode.
- Show route progress and next waypoint in the vehicle panel.

### Vehicle movement

- Use delta-time or a fixed simulation timestep.
- Speed, acceleration, turning rate, braking distance, and safety clearance are configurable.
- Keep the collision footprint stable and separate from visual model rotation.
- Use simple kinematic motion for reliable fixed-route behavior. Do not rely on rigid-body forces to make a vehicle follow a precise path.
- Optional later feature: wheel rotation and steering animation derived from movement.

---

## 6. Vehicle Models and Roles

Create three distinct 3D vehicle scenes with configurable dimensions and clear visual differences.

### PE-01 and PE-02: Pallet Movers

- Low-profile pallet mover model.
- Same base geometry, different unit ID and visual accent.
- Carries one pallet at a time.
- Picks up from Dock Room and transports to transfer station.
- Returns to parking or accepts another task.

States:
`IDLE → TO_DOCK → ALIGN_PICKUP → PICKING → LOADED_TO_XFER → ALIGN_DROPOFF → DROPPING → RETURNING → IDLE`

### RD-01: Forklift

- Forklift model with mast and fork geometry.
- Forks visibly lower/raise during pickup and placement.
- Carries one pallet at a time.
- Picks up from transfer station.
- Stores pallet at a reserved rack slot.
- Returns to a waiting position.

States:
`IDLE → TO_XFER → ALIGN_PICKUP → PICKING → LOADED_TO_RACK → ALIGN_RACK → PLACING → RETURNING → IDLE`

Use explicit typed/enumerated states and guarded transitions. Invalid transitions must be logged in debug mode.

### Vehicle state fields

- ID and class
- Current state
- Position and heading
- Current route and route progress
- Current/next waypoint
- Current task ID
- Carried pallet ID
- Speed/acceleration/turning configuration
- Held resource reservations
- Blocked reason
- Operation phase duration

---

## 7. Pallet, Inventory, and Task Dispatcher

### Pallet data

- Unique ID: `PLT-0001`, `PLT-0002`, etc.
- SKU or goods label
- Status: `AT_DOCK`, `ASSIGNED_TO_PE`, `IN_TRANSIT_PE`, `AT_XFER`, `ASSIGNED_TO_RD`, `IN_TRANSIT_RD`, `STORED`
- Current location ID
- Destination rack slot ID
- Task ID

### Task lifecycle

`CREATED → ASSIGNED_PE → PE_PICKED → AT_XFER → ASSIGNED_RD → RD_PICKED → STORED → COMPLETED`

Validate every transition. Prevent duplicate task/pallet assignment.

### Assignment policy

- Use FIFO for incoming pallets in the initial implementation.
- Assign a pallet to an idle PE only when the pickup position and transfer capacity are available.
- After PE completes dropoff, notify the dispatcher.
- Assign RD only when a pallet is physically available at a handoff point and a rack slot is reserved.
- Reserve the rack slot before RD starts its loaded trip.
- If no resource is free, queue the task and show the blocked reason.
- Keep task assignment independent from rendering.

---

## 8. Traffic Control and Collision Prevention

Use a conservative reservation-based traffic manager.

### Exclusive resources

- Narrow aisle segments
- Intersections
- Handoff positions
- Dock pickup positions
- Rack approach/placement zones
- Parking slots

### Rules

1. Request a resource before entering it.
2. Default capacity is one for narrow aisles and conflict zones.
3. Release the resource only after the vehicle fully clears it.
4. Stop at a designated wait waypoint if a resource is unavailable.
5. Use deterministic queue ordering to avoid starvation.
6. Keep a safety gap between vehicles on the same lane.
7. Avoid opposing directions on narrow single-lane aisles; use one-way traffic where practical.
8. Do not teleport vehicles to recover from a deadlock.
9. Detect deadlock or prolonged blocking and display diagnostics.
10. Log reservation grant, wait, entry, exit, and release events.

Start with stop-and-go resource reservations. Do not build a complex multi-agent optimizer before the basic workflow works.

---

## 9. Simulation HUD and Controls

Provide a clean, compact 3D control panel:

- Start / Pause
- Reset
- Simulation speed: `0.5x`, `1x`, `2x`, `4x`
- Add incoming pallet
- Run deterministic demo scenario
- Toggle route overlays
- Toggle waypoint IDs and collision bounds
- Camera presets: overview, top-down, follow selected vehicle
- Simulation clock
- Counts: at Dock, PE transport, at transfer, RD transport, stored, completed
- Vehicle cards for PE-01, PE-02, RD-01: state, task, load, next waypoint, blocked reason
- Task queue
- Rack occupancy
- Timestamped event log

HUD actions must call the simulation controller, not directly modify vehicle nodes.

---

## 10. Performance Budget for the Laptop

Optimize for the known older laptop: Intel Core i5-2520M, Intel HD Graphics 3000, and approximately 8 GB RAM if that remains the installed configuration. Confirm actual system specs before final tuning.

Target a responsive prototype, not a cinematic renderer.

Recommended initial constraints:
- Low-poly geometry and simple materials.
- No real-time shadows by default.
- Avoid expensive post-processing, SSAO, volumetrics, reflections, and high-resolution textures.
- Keep the number of visible meshes and lights low.
- Use simple collision shapes.
- Avoid physics simulation for every pallet/rack item.
- Add graphics settings: low/medium, render scale, shadows on/off, debug overlays.
- Track FPS and simulation tick time.
- Do not equate rendering FPS with simulation correctness.

If the editor or runtime is unstable, capture the actual renderer/GPU error and diagnose it. Do not claim the app is “optimized” without testing on the target hardware.

---

## 11. Suggested Godot Project Structure

Adapt to the repository; do not force a full rewrite.

```text
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

The simulation model must not depend on visual node transforms as its only source of truth. Maintain authoritative simulation state and apply it to the 3D scene.

---

## 12. Simulation Timing and Separation

- Simulation engine owns authoritative state.
- Renderer reads simulation state; it does not assign tasks.
- Use a fixed timestep or accumulator for deterministic logic.
- Render interpolation may smooth visual movement without changing simulation state.
- Pause freezes simulation time and state transitions.
- Reset returns to a deterministic initial snapshot.
- Speed control scales simulation time.
- Log major events: pallet received, task assigned, pickup, handoff, rack reservation, placement, resource wait/release, completion.
- Separate operational simulation from 3D presentation so a future ROS 2/Webots/Gazebo backend can reuse the workflow model.

---

## 13. Acceptance Criteria

### Workflow
- [ ] Exactly PE-01, PE-02, and RD-01 are present.
- [ ] Pallets arrive at Dock Room.
- [ ] PE receives a task, follows its fixed route, picks up, and drops at a handoff station.
- [ ] RD cannot collect a pallet before PE confirms dropoff.
- [ ] RD reserves a rack slot, collects the pallet, and stores it.
- [ ] Inventory and task status update correctly.
- [ ] Multiple pallets are processed without duplicate assignment.

### 3D and navigation
- [ ] Dock Room, transfer area, Storage Room, racks, lanes, and pallets are visible in 3D.
- [ ] Vehicles follow exact authored waypoint sequences.
- [ ] Route overlays and waypoint IDs can be inspected.
- [ ] Routes do not pass through walls/racks.
- [ ] Vehicle turns and pickup/dropoff alignment are stable.
- [ ] Resource reservations prevent simultaneous use of exclusive zones.
- [ ] Vehicles wait safely when blocked.

### Runtime
- [ ] Godot editor and runtime launch on the target laptop, or the exact incompatibility is documented.
- [ ] Default scene is responsive at laptop resolution.
- [ ] Start, pause, reset, and speed controls work.
- [ ] No errors during the deterministic demo.
- [ ] Headless or automated tests validate routing, resource locking, task transitions, and one full pallet workflow.

---

## 14. Implementation Plan

Do this incrementally:

1. Inspect repository and laptop GPU/OpenGL support.
2. Create a minimal Godot 3D project and verify Compatibility renderer.
3. Build warehouse blockout: floor, rooms, lanes, racks.
4. Author exact waypoint graph and validate it.
5. Add one PE and test route following.
6. Add PE-02 and RD-01 with their state machines.
7. Add pallet pickup/dropoff and task lifecycle.
8. Add traffic reservations and resource queues.
9. Add HUD, route debug overlay, and event log.
10. Add tests and optimize for the laptop.
11. Polish vehicle models, lighting, camera, and materials only after functional acceptance criteria pass.

Keep the project runnable after every milestone. Prefer small, verifiable changes.

---

## 15. Agent Instructions and Final Report

Before implementation:
- Report repository framework, current dependencies, entry points, and Git status.
- Report actual laptop CPU/RAM/GPU/OpenGL data if accessible.
- Verify the selected engine/renderer with a minimal smoke test.
- Explain any engine migration before performing it.

During implementation:
- Do not rewrite the repository wholesale without a reason.
- Do not add unnecessary dependencies or cloud services.
- Do not use random movement as a substitute for authored routes.
- Do not fake task completion with animation.
- Do not claim hardware compatibility without a test.
- Keep logic typed and modular.
- Document assumptions and chosen defaults.

At completion, report:
1. Implemented features.
2. Files created/modified.
3. Engine version, renderer, and dependency changes.
4. Run instructions.
5. Test/build/smoke-test results.
6. Measured performance on available hardware, if tested.
7. Known limitations and next steps.

## 16. Later Enhancements

Only after the basic workflow is stable:
- Visual route editor with draggable waypoint handles.
- Import/export layout and routes as JSON.
- Scenario presets: normal, congested Dock, full racks, blocked aisle.
- Metrics: throughput, average task time, vehicle utilization, queue time.
- Replay of simulation runs.
- Sensor visualization: lidar/range rays, proximity sensors.
- ROS 2 integration or a Webots/Gazebo robotics backend if actual robot-control research becomes a goal.

**Definition of done:** A deterministic, local 3D simulation where two PE pallet movers carry incoming pallets from Dock Room to a handoff station, and one RD forklift picks them up and places them into Storage Room racks using explicit, validated, conflict-managed routes.

# S.A.M. Warehouse Simulation

A deterministic 3D warehouse simulation of the S.A.M. material-flow concept, built with
Godot 4 and GDScript. Pallets arrive at dock positions, PE vehicles pick them up and
deliver them to transfer stations, and a single RD vehicle stores them in rack slots.
The simulation is fixed-step (60 Hz), uses no RNG, and replays identically from the same
inputs.

## Requirements

- Godot **4.7.2.stable.official.ed1daf0bf**
- Compatibility renderer (`gl_compatibility`), OpenGL 3.3 Core

## Run

```sh
godot --path .
```

Press **Run Demo** in the left panel to spawn four pallets and watch the autonomous flow.
Press **Start** if the simulation is paused.

## Tests

```sh
godot --headless --path . --script tests/test_runner.gd
```

Expected output: `ALL TESTS PASSED`.

The engine test includes a determinism check that replays two identical simulations for
20,000 fixed steps and compares vehicle positions/states and pallet statuses.

## Controls

All controls are in the on-screen HUD; there are no keyboard bindings.

| Control | Action |
| --- | --- |
| Start | Resume the simulation |
| Pause / Resume | Toggle pausing |
| Reset | Restore the initial simulation snapshot |
| Speed | Simulation speed: 0.5x, 1x, 2x, 4x |
| Add Pallet | Spawn one `SKU-X` pallet at the first free dock |
| Run Demo | Spawn four pallets (`SKU-A`..`SKU-D`) |
| Routes | Show/hide the route graph overlay |
| Waypoint IDs | Show/hide waypoint labels on the overlay |
| Camera | Overview, Top-down, or Follow (follows the selected vehicle) |
| Vehicle cards | Select a vehicle (used by the Follow camera) |
| Graphics | Low (3D scale 0.6) or Medium (3D scale 1.0) |

Shadows are disabled in `scenes/main.tscn` (`shadow_enabled = false`) and stay off in
both graphics presets.

## Data files

| File | Contents |
| --- | --- |
| `data/warehouse_layout.json` | Floor size, areas, dock positions, handoff stations, rack slots, and obstacle AABBs |
| `data/routes.json` | Waypoints (id, position, type, class, resource) and directed route legs |
| `data/vehicle_config.json` | Vehicle id, class, start waypoint, speed, turn rate, and arrival tolerance |

To change the layout, edit `warehouse_layout.json` and keep the matching waypoints and
legs in `routes.json` consistent. Route validation runs on startup; unknown waypoints,
missing resources, or invalid leg references are reported and the scene refuses to set
up. Restart the simulation after editing any data file.

## Known limitations

- Visuals use engine primitives only (boxes/cylinders); no imported meshes.
- No sensors are modelled (no lidar, camera, or obstacle sensing). Route-following is
  graph-based.
- The rack aisle is bidirectional for the single RD vehicle; there is no multi-vehicle
  aisle arbitration beyond the transfer-station resource locks.
- No ROS or external integration; the simulation is self-contained.

## Verification results

| Date | Test suite | Scene smoke (headless, 300 frames) | Observed FPS (1366x768) |
| --- | --- | --- | --- |
| 2026-11-03 | `ALL TESTS PASSED` | Passed, 0 `SCRIPT ERROR`/`ERROR:` lines | Low (0.6×): avg 59 / min 58 • Medium (1.0×): avg 58 / min 52 |

The FPS figure is only recorded after a physical run on the test laptop
(`godot --path .`, press Run Demo, observe the in-HUD FPS counter).

### Hardware tested

- Acer Aspire 4750
- Intel Core i5-2520M
- Intel HD Graphics 3000
- 7.6 GiB RAM
- Mesa 25.2.8, OpenGL 3.3 Core
- Godot Compatibility renderer

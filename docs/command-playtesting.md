# Command-Line Control and Visual Inspection

This is a standalone testing entry point at `<span>tools/playtest/session.tscn</span>`, which loads the existing `<span>main.tscn</span>`.

No changes are required to the existing game scripts, scenes, or project configuration.The testing interface is not loaded during normal gameplay.

## Run the Full Workflow with One Command

First, open Meta XR Simulator. Then run the following command from the project root:

```
python tools/playtest/client.py demo
```

Python 3 and Godot are required. By default, the tool uses the existing local Godot installation path. You can also set the `<span>GODOT</span>`environment variable or pass `<span>--godot </span><span><exe></span>`.

If the simulator path exists, `<span>XR_RUNTIME_JSON</span>`is configured only for the test process. The system-wide OpenXR settings are not modified. For other installation locations, you can set this environment variable manually.

On Windows, the project uses the Quest color space supported by the simulator. Android retains the plugin's default Rec.709 color space. This prevents the startup error `<span>Color </span><span>space </span><span>is </span><span>not </span><span>supported: </span><span>3</span>`without filtering error logs.

The automated workflow follows these steps:

Touch the wrist star → Settings tab → Start over → Yes → Grab the welcome ball → Open/close the menu → Go to the picnic station → Deliberately select the wrong item once → Complete five rounds correctly → Go to the meadow and catch five butterflies → Buy a chair in Shop → Open Bag → Retrieve the chair inside the house → Release the grip to place it → Pick it up again → Touch the storage button with the other hand → Verify Bag and the repeatable task list.

By default, results are saved to `<span>build/playtest/</span>`:

* `<span>01-*.png</span>`through `<span>16-*.png</span>`: Actual rendered screenshots of key steps. These must be visually inspected.
* `<span>events.jsonl</span>`: Every coordinate/button command, returned state, instruction, and game event.
* `<span>observations.txt</span>`: Script progress, objects still held after successful grabs, and failure reasons.
* `<span>godot.log</span>`/ `<span>console.log</span>`: Engine logs.
* `<span>review.html</span>`: Screenshot index. It is generated automatically but does not determine whether the visuals are correct.

The game remains running after the script finishes, allowing further inspection.

To end the current test session:

```
python tools/playtest/client.py quit
```

The tool uses a separate `<span>playtest</span>`save profile and settings by default. Restarting through the menu only clears this test profile.

You can preserve separate test records using:

```
python tools/playtest/client.py demo --profile playtest_other --out build/playtest-other
```

Only one test can use the same port at a time. For parallel testing, add `<span>--port </span><span>18766</span>`before the command.

## Step-by-Step Control

```
python tools/playtest/client.py launch
python tools/playtest/client.py state
python tools/playtest/client.py where
python tools/playtest/client.py where ball
python tools/playtest/client.py where target
python tools/playtest/client.py move right --to magic_ball --offset 0,0.02,0 --seconds 0.8
python tools/playtest/client.py grip right on
python tools/playtest/client.py grip right off
python tools/playtest/client.py poke star
python tools/playtest/client.py aim menu_tab_shop
python tools/playtest/client.py click menu_tab_shop
python tools/playtest/client.py capture shop
```

`<span>state</span>`returns object IDs, node paths, world coordinates (in meters), the current target, hand/fingertip coordinates, held objects, visible menu buttons, tasks, and recent events.

Actions return a shorter summary by default. Add `<span>--full</span>`before a command to inspect the complete observation results.

`<span>where</span>`displays only visible object positions and the coordinate offsets from each hand to the object, making it useful for concise, step-by-step control.

`<span>where </span><span>ball</span>`filters objects by IDs containing `<span>ball</span>`, while `<span>where </span><span>target</span>`displays only the current training target.

`<span>move</span>`accepts an actual object ID, a full node path, or the current target aliases `<span>target</span>`/ `<span>butterfly</span>`.

* `<span>--offset</span>`: Offset in world coordinates.
* `<span>--position </span><span>x,y,z</span>`: Absolute position.
* `<span>--rotation </span><span>x,y,z</span>`: Euler angles in degrees.
* `<span>--seconds</span>`: Movement duration.

Menu buttons are located by their IDs. `<span>aim</span>`points the controller from a position below the head toward a button. `<span>click</span>`applies the same aiming pose, then presses and releases the trigger instead of directly invoking the button callback.

`<span>poke</span>`is used for the wrist star and touch targets in the world. Poke interaction has been removed from menu buttons.

The wrist star only opens the menu. Once the menu is open, the wrist entry point is hidden. Use Home → Close to close it.

The full workflow also moves through the wrist star's position again, interacts with pages through ray-based clicks, and verifies that correctly selected objects rise independently after being released.

Less frequently used actions can be sent directly as JSON:

```
python tools/playtest/client.py send '{"op":"stick","hand":"left","axis":[0,1],"seconds":1}'
python tools/playtest/client.py send '{"op":"button","hand":"right","action":"by_button","pressed":true}'
python tools/playtest/client.py send '{"op":"button","hand":"right","action":"by_button","pressed":false}'
python tools/playtest/client.py teleport picnic
python tools/playtest/client.py send '{"op":"look","rotation":[-20,0,0]}'
python tools/playtest/client.py send '{"op":"view","mode":"fixed","position":[10,2,5],"at":[9.5,0.7,2.4]}'
python tools/playtest/client.py capture table
```

`<span>look</span>`changes the player's facing direction.

`<span>view</span>`changes only the observation camera used for screenshots, without affecting player controls.

In `<span>eyes</span>`mode, the observation camera follows the actual headset position. Screenshots are captured using a monocular camera in the same game world. This allows you to inspect menus from the player's viewpoint or examine furniture from the side, but it cannot verify stereoscopic comfort.

## What Real Gameplay Paths Are Tested?

The tool attaches a dedicated `<span>XRControllerTracker</span>`to the original player's `<span>XRController3D</span>`nodes, sending controller poses and button inputs.

The existing gameplay systems continue to operate normally, including:

* Hand physics overlap detection and grip signals.
* Menu raycasting and trigger detection.
* Butterfly touch interactions.
* Tasks, rewards, and shop purchases.
* Inventory and object storage.

The tool does not emit fake events such as `<span>finished</span>`, `<span>bought</span>`, or `<span>placed</span>`. It does not throw rocks or directly complete tasks, and it provides no arbitrary script-execution command.

The server listens only on `<span>127.0.0.1</span>`.

`<span>teleport</span>`explicitly relocates the player by calling the existing `<span>Teleport.teleport_to</span>`method. Teleportation is still rejected while the menu is paused.

Teleportation does not test teleport rays, routes, or obstacles.By contrast, `<span>stick</span>`uses the original joystick movement logic.

The simulated hands do not have realistic human shoulder or arm constraints. Therefore, this tool cannot replace testing for children's reachability, physical comfort, haptic feedback, or Quest hardware performance.

Synthetic controllers do not have vibration motors, so haptics are disabled only in the test settings.

Each run reads the current randomized targets and coordinates before interacting with them. The test steps are reproducible, but the randomized layouts are not guaranteed to be identical across runs.

Internal assertions stop the workflow when a step fails. Even when the workflow completes successfully, every PNG must still be inspected before recording visual test conclusions.

For interaction regression tests that do not require rendering, use:

```
python tools/playtest/client.py demo --headless
```

This does not generate screenshots and cannot be considered a visual test.

## Menu Button and Debug UI

The regular menu toggles when the left controller's `<span>menu_button</span>`is released. The corresponding key in the simulator is `<span>M</span>`.

Holding Menu together with the left controller's `<span>by_button</span>`(`<span>Y</span>`) toggles the Debug UI.

The buttons can be pressed or released in either order. The Debug UI will not toggle again until both buttons have been released. This combination also prevents the regular menu from opening and does not trigger the help action.

Releasing `<span>Y</span>`by itself still triggers help.

```
python tools/playtest/client.py send '{"op":"button","hand":"left","action":"menu_button","pressed":true}'
python tools/playtest/client.py send '{"op":"button","hand":"left","action":"by_button","pressed":true}'
python tools/playtest/client.py send '{"op":"button","hand":"left","action":"by_button","pressed":false}'
python tools/playtest/client.py send '{"op":"button","hand":"left","action":"menu_button","pressed":false}'
python tools/playtest/client.py click dbg_saves --hand left
python tools/playtest/client.py click dbg_training
python tools/playtest/client.py click dbg_close
```

The `<span>debug_open</span>`field in `<span>state</span>`indicates whether the Debug UI is open. The `<span>buttons</span>`field also lists the native UI buttons that are currently visible.

`<span>aim</span>`and `<span>click</span>`target the center of each button's rectangle after layout and perform clicks through actual `<span>SubViewport</span>`mouse input. They do not directly invoke Debug UI action functions.

During training, you can use axis-specific buttons such as `<span>dbg_overlap_up</span>`. The `<span>dbg_auto</span>`button clears all pins.

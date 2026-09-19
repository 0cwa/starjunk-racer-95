# Course presentation director

`SongCueTimeline` answers *which declarative cues are crossed at a song time*. `CoursePresentationDirector` turns those cues into renderer-facing state and signals.

## Persistent vs transient cues

Persistent kinds are `palette`, `lighting`, `scenery`, and `post_process`. Their payload dictionaries are shallow-merged into current state, so a later lighting cue can change only `energy` without discarding an earlier `color`.

`particles` and `beat` are transient. They emit when crossed during forward playback but are not stored as presentation state.

## Seeking

Configuration applies time-zero persistent cues silently. `seek_to()` rebuilds persistent state from the cue set without replaying render signals or transient bursts. This is important for restarting a race, spectating mid-song, or recovering after browser/audio suspension.

After a seek, `emit_current_state()` can push reconstructed palette/lighting/scenery/post-process state to a rendering adapter in deterministic kind order.

## Rendering boundary

The director exposes typed signals but contains no renderer code. A Godot course adapter may connect them to Environment resources, lights, particle emitters, shader uniforms, geometry phase controllers, or post-process materials.

This keeps song timing declarative and portable. A WebGPU/native renderer difference belongs in the rendering adapter, not cue data or race physics.

## Safety

Cue sets cannot introduce new signal kinds at runtime. Unknown kinds fail validation in `SongCueTimeline`. The director has no authority to change vehicle forces, checkpoints, lap state, filesystem state, or networking capabilities.


## Godot visual adapter

`CourseVisualAdapter` is the narrow Godot renderer adapter used by the playable scene. It receives only explicit game-owned render references: the course `Environment`, one key light, an optional GPU-particle emitter, and an allowlisted array of scenery materials.

Generation-1 payload fields have deliberately small authority:

- **palette:** `background_color`, `ambient_color`, `ambient_energy`;
- **lighting:** `energy`, `color`;
- **particles:** `intensity` and optional `restart`;
- **scenery:** `emission_energy` on the allowlisted presentation materials;
- **post_process:** `glow_intensity`;
- **beat:** bounded temporary key-light pulse via `strength` and `duration_ms`.

All numeric inputs are clamped. Cue data never names a node, material, property path, collision object, or vehicle. Community track visuals therefore cannot use presentation cues to move collision or alter race state.

`PrototypeRace.configure_presentation()`, `advance_presentation_to()`, and `seek_presentation_to()` expose the timing seam while keeping audio-clock ownership separate. Seeking clears transient pulses and reapplies reconstructed persistent state.

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

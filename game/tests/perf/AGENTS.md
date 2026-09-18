# Godot performance-test instructions

The renderer torture test is permanent production infrastructure.

Keep benchmark behavior deterministic. Changes to stress parameters or scene composition require a scenario-version bump. Do not remove an expensive representative feature merely to improve numbers. Headless smoke tests prove loadability only; authoritative performance requires a real GPU runner.

# CI instructions

PR CI should be deterministic and reasonably fast. GitHub-hosted runners perform repository/unit/Godot load smoke tests, not authoritative GPU comparisons.

Authoritative performance jobs require the named self-hosted GPU runner and must upload raw result artifacts even on failure.


## Issue tracking

`.github/ISSUE_TEMPLATE/workstream.md` defines the standard shape for multi-PR engineering workstreams. Keep it compact and operational: goal, current state, evidence, next steps, dependencies, done criteria, and relevant durable constraints.

The canonical project orientation issue is #48. CI or issue-template changes that materially affect agent workflow should be reflected in `docs/development-state.md` and, when necessary, issue #48.

# CI instructions

PR CI should be deterministic and reasonably fast. GitHub-hosted runners perform repository/unit/Godot load smoke tests, not authoritative GPU comparisons.

Authoritative performance jobs require the named self-hosted GPU runner and must upload raw result artifacts even on failure.

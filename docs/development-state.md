# Development state and agent handoff

The repository uses GitHub Issues as a small operational state layer so a new human or agent can determine what is happening without relying on prior chat context.

## Canonical orientation issue

Start with [Development State — Start Here (#48)](https://github.com/0cwa/starjunk-racer-95/issues/48).

That issue is intentionally a compact snapshot of:

- the current primary engineering focus;
- active workstreams;
- material blockers;
- priority order;
- recently completed context that affects what comes next.

It is not a changelog and it is not an architecture document.

## Source-of-truth hierarchy

When sources disagree, use this order:

1. repository implementation, tests, and CI evidence;
2. applicable `AGENTS.md` instructions and durable ADR/docs constraints;
3. active workstream issue state;
4. canonical issue #48;
5. prior conversation/session context.

The issue layer should be corrected when it falls behind executable evidence.

## Workstream issues

Create a `[Workstream]` issue when an effort is likely to span multiple commits/PRs, has meaningful dependencies, or needs a clean handoff between agents.

Use `.github/ISSUE_TEMPLATE/workstream.md` and keep these fields current:

- **Goal** — the milestone this issue exists to complete.
- **Current state** — what is true now, not a historical narrative.
- **Latest evidence** — commits, PRs, CI run results, measurements, or reproduced failures.
- **Next** — ordered actions the next agent should take.
- **Blockers / dependencies** — work that must land first or external constraints.
- **Done** — objective completion criteria.
- **Constraints** — only the durable project constraints especially relevant to this workstream.

Prefer editing the body for current state. Use comments for useful historical breadcrumbs or investigation details that would make the body noisy.

## Agent orientation protocol

At the start of substantive work:

1. read the root and nearest `AGENTS.md`;
2. read `docs/README.md` and relevant durable docs/ADRs;
3. fetch issue #48;
4. fetch linked workstream issue(s);
5. fetch current `main`, referenced PR heads, and exact-head CI;
6. do not treat unrelated open PRs as active work merely because they are open; inspect their stated disposition before reusing them;
7. reconcile stale issue state against the repository before selecting work.

During work, update a workstream issue when a material fact changes, such as:

- a blocker is resolved or replaced by a new root cause;
- a milestone becomes green;
- a PR is merged or abandoned;
- measurements change the intended implementation;
- execution order changes.

Before ending a substantial slice:

1. ensure the workstream issue reflects the latest state/evidence/next action;
2. update #48 if the project-level primary focus, active workstreams, or priority order changed;
3. update durable docs/ADRs if architecture or policy changed.

This makes handoff part of the development task rather than optional cleanup.

## Current workstreams

The canonical list lives in issue #48. At the time this protocol was introduced:

- #46 — Browser-first Godot WebGPU renderer.
- #47 — Reproducible playable Web build.

Always use issue #48 for the current list rather than assuming this historical list is complete.

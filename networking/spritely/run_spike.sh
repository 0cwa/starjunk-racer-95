#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

docker run --rm   -v "$ROOT:/work"   -w /work   debian:sid   bash networking/spritely/run_in_container.sh

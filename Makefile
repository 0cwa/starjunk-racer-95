.PHONY: check perf-test

check:
	python3 tools/validate_repo.py
	python3 -m unittest discover -s tools/perf/tests -p 'test_*.py'
	bash -n tools/perf/run_godot_benchmark.sh
	bash -n tools/engine/fetch_sources.sh
	bash -n tools/engine/build_reference_webgpu.sh

perf-test:
	python3 -m unittest discover -s tools/perf/tests -p 'test_*.py'

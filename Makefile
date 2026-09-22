.PHONY: check godot-test perf-test

check:
	python3 tools/validate_repo.py
	python3 tools/godot/run_test_suite.py --validate-only
	python3 -m unittest discover -s tools/perf/tests -p 'test_*.py'
	bash -n tools/perf/run_godot_benchmark.sh
	bash -n tools/engine/fetch_sources.sh
	bash -n tools/engine/build_reference_webgpu.sh
	bash -n tools/networking/package_spritely_web.sh

godot-test:
	python3 tools/godot/run_test_suite.py

perf-test:
	python3 -m unittest discover -s tools/perf/tests -p 'test_*.py'

.PHONY: check perf-test

check:
	python3 tools/validate_repo.py
	python3 -m unittest discover -s tools/perf/tests -p 'test_*.py'
	bash -n tools/perf/run_godot_benchmark.sh
	bash -n tools/engine/fetch_sources.sh
	bash -n tools/engine/build_reference_webgpu.sh
	bash -n tools/engine/prepare_port_candidate.sh
	bash -n tools/engine/build_webgpu_rust_deps.sh
	git apply --numstat engine/patches/spirv-webgpu-transform-fix-opnop.patch >/dev/null
	bash -n tools/engine/forward_port_probe.sh
	bash -n tools/engine/export_webgpu_benchmark.sh
	bash -n tools/engine/analyze_spirv_dumps.sh
	bash -n tools/networking/package_spritely_web.sh
	python3 -m py_compile tools/engine/apply_starjunk_port_patches.py tools/perf/webgpu_browser_smoke.py

perf-test:
	python3 -m unittest discover -s tools/perf/tests -p 'test_*.py'

extends RefCounted

func publish(result: Dictionary) -> void:
	var payload := JSON.stringify(result)
	JavaScriptBridge.eval("window.__STARJUNK_PERF_RESULT__ = %s;" % payload)

class_name PerformanceProfileRegistry
extends RefCounted

# Community packages may name one of these IDs, but cannot provide or replace
# the underlying physics resource.
const PROFILE_PATHS: Dictionary = {
	&"prototype_balanced_01": "res://src/vehicle/profiles/prototype_balanced_01.tres",
}

static func has_profile(profile_id: StringName) -> bool:
	return PROFILE_PATHS.has(profile_id)

static func load_profile(profile_id: StringName) -> VehiclePerformanceProfile:
	if not has_profile(profile_id):
		return null
	var resource = load(str(PROFILE_PATHS[profile_id]))
	if resource is VehiclePerformanceProfile:
		return resource
	push_error("Registered performance profile did not load as VehiclePerformanceProfile: %s" % profile_id)
	return null

static func registered_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in PROFILE_PATHS.keys():
		ids.append(StringName(key))
	ids.sort()
	return ids

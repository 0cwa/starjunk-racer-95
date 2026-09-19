class_name RoadSurfaceRegistry
extends RefCounted

const DEFAULT_ID := &"asphalt"
const METADATA_KEY := &"starjunk_surface_profile"

const _PROFILES := {
	"asphalt": {
		"grip_multiplier": 1.0,
		"lateral_stiffness_multiplier": 1.0,
		"longitudinal_stiffness_multiplier": 1.0,
		"peak_slip_angle_multiplier": 1.0,
		"peak_longitudinal_slip_multiplier": 1.0,
	},
	"wet": {
		"grip_multiplier": 0.68,
		"lateral_stiffness_multiplier": 0.78,
		"longitudinal_stiffness_multiplier": 0.72,
		"peak_slip_angle_multiplier": 1.15,
		"peak_longitudinal_slip_multiplier": 1.18,
	},
	"gravel": {
		"grip_multiplier": 0.55,
		"lateral_stiffness_multiplier": 0.48,
		"longitudinal_stiffness_multiplier": 0.45,
		"peak_slip_angle_multiplier": 1.65,
		"peak_longitudinal_slip_multiplier": 1.75,
	},
}

static func has_profile(profile_id: StringName) -> bool:
	return _PROFILES.has(str(profile_id))

static func resolve(profile_id: StringName) -> Dictionary:
	var key := str(profile_id)
	if not _PROFILES.has(key):
		key = str(DEFAULT_ID)
	return _PROFILES[key].duplicate(true)

static func profile_id_for_collider(collider: Variant) -> StringName:
	if collider is Object:
		var object := collider as Object
		if object.has_meta(METADATA_KEY):
			var requested := StringName(str(object.get_meta(METADATA_KEY)))
			if has_profile(requested):
				return requested
	return DEFAULT_ID

static func profile_for_collider(collider: Variant) -> Dictionary:
	return resolve(profile_id_for_collider(collider))

static func supported_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for key in _PROFILES.keys():
		ids.append(str(key))
	ids.sort()
	return ids

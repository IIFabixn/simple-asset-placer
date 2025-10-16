@tool
extends RefCounted

class_name SensitivityCurve

## Utility for remapping mouse deltas using simple response curves.
## Keeps extreme deltas linear while allowing nuanced control near zero.

const CURVE_LINEAR := "linear"
const CURVE_EASE_IN := "ease_in"
const CURVE_EASE_OUT := "ease_out"
const CURVE_EASE_IN_OUT := "ease_in_out"

static func apply(value: float, curve: String, reference_delta: float = 200.0) -> float:
	"""Remap the provided value according to the selected sensitivity curve.
	
	Args:
		value: Raw delta (e.g. mouse pixels).
		curve: Curve name (linear/ease_in/ease_out/ease_in_out).
		reference_delta: Delta magnitude treated as the upper bound for curve remapping.
	
	Returns:
		Remapped value preserving input sign. Large deltas remain linear to avoid jumps.
	"""
	if abs(value) <= 0.0001:
		return 0.0

	var curve_id := curve.to_lower()
	if curve_id == CURVE_LINEAR:
		return value

	var magnitude := absf(value)
	var sign := signf(value)
	var reference := max(reference_delta, 1.0)

	# Keep very large deltas linear so fast mouse flicks still feel responsive.
	if magnitude >= reference:
		return value

	var normalized := clampf(magnitude / reference, 0.0, 1.0)
	match curve_id:
		CURVE_EASE_IN:
			normalized = normalized * normalized
		CURVE_EASE_OUT:
			normalized = 1.0 - pow(1.0 - normalized, 2.0)
		CURVE_EASE_IN_OUT:
			if normalized < 0.5:
				normalized = 2.0 * normalized * normalized
			else:
				normalized = 1.0 - pow(-2.0 * normalized + 2.0, 2.0) * 0.5
		_:
			return value

	return sign * normalized * reference

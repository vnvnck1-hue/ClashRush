class_name CameraRig
extends Camera3D
## Trauma-based screen shake + hitstop (time freeze) + gentle punch zoom.

var base_pos := Vector3.ZERO
var base_rot := Vector3.ZERO
var base_fov := 34.0
var trauma := 0.0
var _t := 0.0
var _stop_left := 0.0
var _fov_kick := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup(pos: Vector3, look: Vector3, fov_deg: float) -> void:
	base_fov = fov_deg
	fov = fov_deg
	position = pos
	look_at(look, Vector3.UP)
	base_pos = position
	base_rot = rotation

func add_trauma(v: float) -> void:
	trauma = clampf(trauma + v, 0.0, 1.0)

func kick_fov(v: float) -> void:
	_fov_kick = v

func hitstop(dur: float) -> void:
	Engine.time_scale = 0.04
	_stop_left = maxf(_stop_left, dur)

func _process(delta: float) -> void:
	# delta is scaled by time_scale; use real time for camera feel.
	var real := delta / maxf(Engine.time_scale, 0.001)
	real = minf(real, 0.05)
	_t += real
	if _stop_left > 0.0:
		_stop_left -= real
		if _stop_left <= 0.0:
			_stop_left = 0.0
			Engine.time_scale = 1.0
	trauma = maxf(trauma - real * 1.6, 0.0)
	var s := trauma * trauma
	var off := Vector3(
		sin(_t * 47.0) + sin(_t * 31.0) * 0.5,
		sin(_t * 53.0 + 1.3) * 0.6,
		cos(_t * 41.0) * 0.5) * 0.18 * s
	position = base_pos + off
	rotation = base_rot + Vector3(0, 0, sin(_t * 37.0) * 0.02 * s)
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-real * 8.0))
	fov = base_fov + _fov_kick

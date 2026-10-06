class_name CameraRig
extends Camera3D
## Quarter-view follow camera (yaw 45 deg). Smooth follow, wheel zoom, hold-Tab overview,
## trauma shake. "Hitstop" is visual only here (sim must keep real time for co-op).

const YAW := deg_to_rad(45.0)
const PITCH := deg_to_rad(52.0)

var focus := Vector3.ZERO
var target := Vector3.ZERO
var dist := 17.0
var dist_goal := 17.0
var overview := false
var trauma := 0.0
var _t := 0.0
var _kick := 0.0

func _ready() -> void:
	fov = 38.0
	far = 300.0

func add_trauma(v: float) -> void:
	trauma = clampf(trauma + v, 0.0, 1.0)

func hitstop(_dur: float) -> void:
	_kick = -2.5
	add_trauma(0.15)

func kick_fov(v: float) -> void:
	_kick = v

func zoom(step: float) -> void:
	dist_goal = clampf(dist_goal + step, 13.0, 34.0)

## Ground direction (x,z) that corresponds to screen-up / screen-right
func forward_2d() -> Vector2:
	return Vector2(-sin(YAW), -cos(YAW))

func right_2d() -> Vector2:
	return Vector2(cos(YAW), -sin(YAW))

func snap_to(p: Vector3) -> void:
	target = p
	focus = p
	_apply(0.0)

func _process(delta: float) -> void:
	_t += delta
	var goal_focus := Vector3.ZERO if overview else target
	var goal_dist := 78.0 if overview else dist_goal
	focus = focus.lerp(goal_focus, 1.0 - exp(-delta * (3.0 if overview else 7.0)))
	dist = lerpf(dist, goal_dist, 1.0 - exp(-delta * 5.0))
	trauma = maxf(trauma - delta * 1.5, 0.0)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-delta * 8.0))
	RenderingServer.global_shader_parameter_set("outline_scale", clampf(17.0 / maxf(dist, 1.0), 0.45, 1.1))
	_apply(delta)

func _apply(_delta: float) -> void:
	var back := Vector3(sin(YAW) * cos(PITCH), sin(PITCH), cos(YAW) * cos(PITCH))
	var s := trauma * trauma
	var shake := Vector3(sin(_t * 47.0) + sin(_t * 31.0) * 0.5, sin(_t * 53.0 + 1.3) * 0.6, cos(_t * 41.0) * 0.5) * 0.35 * s
	position = focus + back * dist + shake
	look_at(focus + shake * 0.5, Vector3.UP)
	fov = 38.0 + _kick

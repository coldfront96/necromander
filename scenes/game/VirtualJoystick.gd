extends Control
## A simple on-screen joystick for touch (mobile-first). Drag within the base to
## steer; output is a vector with length 0..1 via get_vector(). Desktop players
## can ignore it and use the arrow keys (handled in DungeonRoom).

@export var radius: float = 90.0
@export var knob_radius: float = 38.0

var _knob: Vector2 = Vector2.ZERO  # offset from center, length clamped to radius
var _touch_index: int = -1         # which finger owns the stick (-1 = none)

func _ready() -> void:
	# Not in a container, so set an explicit size — this is both the draw area
	# and the touch hit-box.
	size = Vector2(radius * 2.0, radius * 2.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP

func _center() -> Vector2:
	return size * 0.5

## Normalized steering vector, length 0..1.
func get_vector() -> Vector2:
	return _knob / radius

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1:
				_touch_index = event.index
				_update_knob(event.position)
		elif event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_knob(event.position)
	# Mouse fallback so it's testable on desktop too.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _touch_index == -1:
			_touch_index = -2
			_update_knob(event.position)
		elif not event.pressed and _touch_index == -2:
			_release()
	elif event is InputEventMouseMotion and _touch_index == -2:
		_update_knob(event.position)

func _update_knob(local_pos: Vector2) -> void:
	_knob = (local_pos - _center()).limit_length(radius)
	queue_redraw()

func _release() -> void:
	_touch_index = -1
	_knob = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	var c := _center()
	draw_circle(c, radius, Color(1, 1, 1, 0.08))
	draw_arc(c, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0, true)
	draw_circle(c + _knob, knob_radius, Color(0.61, 0.42, 1.0, 0.55))

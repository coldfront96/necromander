class_name Token
extends Node2D
## A drawn token (player circle, enemy square, loot diamond, or a portal) with
## a name label and HP bar. No art assets needed yet. Shared by the dungeon
## (v0.2+) and the arena (v0.9).

var radius: float = 22.0
var color: Color = Color.WHITE
var is_local: bool = false
var is_square: bool = false
var is_open: bool = false    # portal only: draw an inviting ring
var hp_ratio: float = -1.0   # <0 hides the bar
var dead: bool = false
var _label: Label

func set_label(text: String) -> void:
	if _label == null:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.position = Vector2(-60, -radius - 38)
		_label.custom_minimum_size = Vector2(120, 0)
		add_child(_label)
	_label.text = text

func set_hp(hp: float, maxhp: float) -> void:
	var r := -1.0 if hp < 0.0 or maxhp <= 0.0 else clamp(hp / maxhp, 0.0, 1.0)
	if r != hp_ratio:
		hp_ratio = r
		queue_redraw()

func set_dead(value: bool) -> void:
	if value != dead:
		dead = value
		queue_redraw()

func _draw() -> void:
	var c := color
	c.a = 0.35 if dead else 1.0
	if is_square:
		var s := radius
		draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), c)
	else:
		draw_circle(Vector2.ZERO, radius, c)
	if is_local and not dead:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color.WHITE, 2.5, true)
	if is_open:
		draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 40, Color(0.85, 0.75, 1.0), 3.0, true)
	if hp_ratio >= 0.0:
		var w := radius * 2.0
		var y := -radius - 12.0
		draw_rect(Rect2(-radius, y, w, 5.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-radius, y, w * hp_ratio, 5.0), Color(0.35, 0.85, 0.4))

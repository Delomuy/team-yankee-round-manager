class_name ModelSymbol
extends Control
## The drawn icon of a model that has no picture: a framed map symbol for its type letter
## (I infantry: crossed box, T tanks: oval, A artillery: dot, C carriers: box on wheels, H helicopters: bow-tie,
## P planes: arrow head).

var letter: String = "I"
var color: Color = Color(0.2, 0.2, 0.2)


func _init(p_letter: String = "I", p_color: Color = Color(0.2, 0.2, 0.2)) -> void:
	letter = p_letter
	color = p_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var box: Rect2 = Rect2(Vector2(2, 2), size - Vector2(4, 4))
	if box.size.x < 8.0 or box.size.y < 8.0:
		return
	draw_rect(box, Color(1, 1, 1, 0.55), true)
	draw_rect(box, color, false, 2.0)
	var c: Vector2 = box.get_center()
	var w: float = box.size.x
	var h: float = box.size.y
	match letter:
		"I":
			draw_line(box.position, box.end, color, 2.0, true)
			draw_line(Vector2(box.position.x, box.end.y), Vector2(box.end.x, box.position.y), color, 2.0, true)
		"T":
			draw_polyline(_oval(c, w * 0.32, h * 0.24), color, 2.0, true)
		"A":
			draw_circle(c, minf(w, h) * 0.16, color)
		"C":
			draw_rect(Rect2(c - Vector2(w * 0.28, h * 0.22), Vector2(w * 0.56, h * 0.30)), color, false, 2.0)
			draw_circle(c + Vector2(-w * 0.17, h * 0.22), 3.0, color)
			draw_circle(c + Vector2(w * 0.17, h * 0.22), 3.0, color)
		"H":
			var a: float = w * 0.30
			var b: float = h * 0.24
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(-a, -b), c + Vector2(-a, b)]), color)
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(a, -b), c + Vector2(a, b)]), color)
		"P":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.30), c + Vector2(w * 0.30, h * 0.26),
					c + Vector2(0, h * 0.10), c + Vector2(-w * 0.30, h * 0.26)]), color)
		_:
			draw_circle(c, 3.0, color)


func _oval(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in 25:
		var a: float = TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

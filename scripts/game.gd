extends Control
## One state machine owns the turn clock and both players' cut animations.
## Undo/restart reset that clock, so no delayed AI callback can mutate a new turn.

const Forest = preload("res://scripts/forest.gd")
const INK := Color("#393346")
const MUTED := Color("#89818c")
const PURPLE := Color("#7960aa")
const PAPER := Color("#f8f5ef")
const BOARD := Rect2(48, 256, 1344, 484)
const COLORS := [Color("#b2a0df"), Color("#eeaa96"), Color("#e5bf6f"), Color("#8dc5ae")]
const TREE_NAMES := ["LAVENDER", "PEACH", "HONEY", "MINT"]
const CUT_DURATION := 0.62
const THINK_DURATION := 0.70
const AIM_DURATION := 0.45
enum Phase { PLAYER, CUTTING, AI_THINK, AI_AIM, FINISHED }

var forest := Forest.new()
var rng := RandomNumberGenerator.new()
var phase: Phase = Phase.PLAYER
var clock := 0.0
var debug_mode := false
var hovered := -1
var aimed := -1
var cutting: Array[int] = []
var cutting_player := true
var history: Array[Dictionary] = []
var positions: Array[Vector2] = []
var tree_indices: Array[int] = []
var moves_taken := 0
var seed_value := 0
var note := "A little strategy. A few sweet decisions."
var winner := ""
var font: Font
var undo_button: Button
var debug_button: Button
var restart_button: Button
var new_button: Button


func _ready() -> void:
	font = ThemeDB.fallback_font
	rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_create_buttons()
	new_game()


func _button(text: String, rect: Rect2, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE if primary else PURPLE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE if primary else PURPLE)
	button.add_theme_color_override("font_disabled_color", Color("#bcb5bf"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = PURPLE if primary else Color("#fefcf8")
		if state == "hover":
			style.bg_color = Color("#695198") if primary else Color("#eee7f6")
		if state == "pressed":
			style.bg_color = Color("#594382") if primary else Color("#e2d8ef")
		style.set_corner_radius_all(12)
		style.set_border_width_all(1 if state != "focus" else 2)
		style.border_color = PURPLE if primary or state == "focus" else Color("#e3dce2")
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	add_child(button)
	return button


func _create_buttons() -> void:
	restart_button = _button("Restart   R", Rect2(1050, 86, 148, 46), restart)
	restart_button.tooltip_text = "Replay this exact grove from the beginning"
	new_button = _button("New grove  +", Rect2(1212, 86, 180, 46), new_game, true)
	new_button.tooltip_text = "Generate a fresh set of four trees (N)"
	undo_button = _button("Undo round   Z", Rect2(48, 778, 184, 46), undo)
	undo_button.tooltip_text = "Undo your last choice and the AI reply, including an animation in progress"
	debug_button = _button("Show SG   D", Rect2(244, 778, 164, 46), toggle_debug)
	debug_button.tooltip_text = "Show subtree Sprague–Grundy values and the forest XOR"


func new_game() -> void:
	seed_value = rng.randi()
	rng.seed = seed_value
	forest.generate(rng)
	_reset()
	_layout_forest()
	queue_redraw()


func restart() -> void:
	forest.setup(forest.parents.duplicate())
	_reset()
	note = "Same grove, fresh thinking."
	queue_redraw()


func _reset() -> void:
	phase = Phase.PLAYER
	clock = 0.0
	hovered = -1
	aimed = -1
	cutting.clear()
	history.clear()
	moves_taken = 0
	winner = ""
	note = "A little strategy. A few sweet decisions."
	_sync_controls()


func undo() -> void:
	if history.is_empty():
		note = "You're at the beginning of this grove."
		queue_redraw()
		return
	var previous: Dictionary = history.pop_back()
	forest.restore(previous.alive)
	moves_taken = previous.moves
	phase = Phase.PLAYER
	clock = 0.0
	cutting.clear()
	aimed = -1
	hovered = -1
	winner = ""
	note = "One round back. Try another branch."
	_sync_controls()
	queue_redraw()


func toggle_debug() -> void:
	debug_mode = not debug_mode
	_sync_controls()
	queue_redraw()


func _sync_controls() -> void:
	undo_button.disabled = history.is_empty()
	debug_button.text = "Hide SG   D" if debug_mode else "Show SG   D"


func _layout_forest() -> void:
	positions.resize(forest.parents.size())
	tree_indices.resize(forest.parents.size())
	for t in forest.roots.size():
		var root: int = forest.roots[t]
		var widths := {}
		_leaf_width(root, widths)
		var left := 84.0 + t * 326.0
		_place(root, left, left + 294.0, 0, t, widths)


func _leaf_width(node: int, widths: Dictionary) -> int:
	var width := 0
	for child in forest.children[node]:
		width += _leaf_width(child, widths)
	widths[node] = maxi(1, width)
	return widths[node]


func _place(node: int, left: float, right: float, depth: int, tree: int, widths: Dictionary) -> void:
	positions[node] = Vector2((left + right) / 2.0, 384.0 + depth * 94.0)
	tree_indices[node] = tree
	var cursor := left
	for child in forest.children[node]:
		var span: float = (right - left) * float(widths[child]) / float(widths[node])
		_place(child, cursor, cursor + span, depth + 1, tree, widths)
		cursor += span


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var target := _hit(event.position) if phase == Phase.PLAYER else -1
		if target != hovered:
			hovered = target
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovered >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if phase == Phase.PLAYER:
			var target := _hit(event.position)
			if target >= 0:
				player_cut(target)
			elif BOARD.has_point(event.position):
				note = "Click a candy to take it and every candy below it."
				queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Preserve browser shortcuts such as Cmd+R / Ctrl+R.
		if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
			return
		match event.keycode:
			KEY_Z:
				undo()
			KEY_R:
				restart()
			KEY_D:
				toggle_debug()
			KEY_N:
				new_game()
			_:
				return
		get_viewport().set_input_as_handled()


func _hit(point: Vector2) -> int:
	for i in positions.size():
		if forest.alive[i] and positions[i].distance_to(point) <= 25.0:
			return i
	return -1


func player_cut(node: int) -> void:
	if phase != Phase.PLAYER or node < 0 or node >= forest.alive.size() or not forest.alive[node]:
		return
	history.append({"alive": forest.alive.duplicate(), "moves": moves_taken})
	_start_cut(node, true)


func _start_cut(node: int, by_player: bool) -> void:
	cutting_player = by_player
	cutting = forest.remove(node)
	moves_taken += 1
	phase = Phase.CUTTING
	clock = 0.0
	hovered = -1
	aimed = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	note = "%s took %d %s." % [
		"You" if by_player else "The grove",
		cutting.size(), "candy" if cutting.size() == 1 else "candies"
	]
	_sync_controls()
	queue_redraw()


func _process(delta: float) -> void:
	if phase == Phase.PLAYER or phase == Phase.FINISHED:
		return
	clock += delta
	match phase:
		Phase.CUTTING:
			if clock >= CUT_DURATION:
				cutting.clear()
				clock = 0.0
				if forest.remaining() == 0:
					winner = "You" if cutting_player else "The grove"
					phase = Phase.FINISHED
					note = "You took the last candy." if cutting_player else "The grove took the last candy. A rematch?"
				else:
					phase = Phase.AI_THINK if cutting_player else Phase.PLAYER
		Phase.AI_THINK:
			if clock >= THINK_DURATION:
				aimed = forest.choose_ai(rng)
				phase = Phase.AI_AIM
				clock = 0.0
		Phase.AI_AIM:
			if clock >= AIM_DURATION:
				_start_cut(aimed, false)
	queue_redraw()


func _text(value: String, at: Vector2, size_px: int, color := INK) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _center(value: String, at: Vector2, size_px: int, color := INK) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	_text(value, at - Vector2(width / 2.0, 0), size_px, color)


func _panel(rect: Rect2, color: Color, radius: int, border := Color.TRANSPARENT) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	if border.a > 0:
		style.set_border_width_all(1)
		style.border_color = border
	draw_style_box(style, rect)


func _draw() -> void:
	if font == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	_draw_header()
	_draw_board()
	_draw_footer()


func _draw_header() -> void:
	_candy(Vector2(65, 43), COLORS[0], 0.65, -0.25, 1.0, 0)
	_text("T H E   L I T T L E   S T R A T E G Y   C L U B", Vector2(94, 49), 13, PURPLE)
	_text("Candy Grove", Vector2(48, 127), 55)
	_text("Pick a candy. Take its branch. Leave nothing behind.", Vector2(51, 164), 19, MUTED)
	draw_line(Vector2(48, 190), Vector2(1392, 190), Color("#e2dce0"), 1)
	var turn_title := "Your turn"
	var turn_hint := "Choose a candy to snip"
	var dot_color := Color("#80b69d")
	match phase:
		Phase.CUTTING:
			turn_title = "Your pick" if cutting_player else "Grove's pick"
			turn_hint = "A sweet little snip..."
			dot_color = COLORS[0]
		Phase.AI_THINK:
			turn_title = "Grove's turn"
			turn_hint = "Thinking about the next branch..."
			dot_color = COLORS[0]
		Phase.AI_AIM:
			turn_title = "Grove's turn"
			turn_hint = "This branch looks tempting"
			dot_color = COLORS[0]
		Phase.FINISHED:
			turn_title = "You win!" if winner == "You" else "The grove wins"
			turn_hint = "The last candy decides it"
	draw_circle(Vector2(61, 225), 5, dot_color)
	_text(turn_title, Vector2(79, 233), 23)
	_text(turn_hint, Vector2(282, 232), 17, MUTED)
	_panel(Rect2(1154, 207, 238, 35), Color("#eee8f1"), 17)
	_center("%02d candies   /   %02d moves" % [forest.remaining(), moves_taken], Vector2(1273, 231), 16, PURPLE)


func _draw_board() -> void:
	_panel(BOARD, Color("#fefcf8"), 22, Color("#e4dde2"))
	# Small, quiet dot grid gives the strings a little depth.
	for x in range(72, 1380, 26):
		for y in range(278, 726, 26):
			draw_circle(Vector2(x, y), 0.85, Color("#ebe6e8"))
	for t in forest.roots.size():
		var root: int = forest.roots[t]
		var center_x := 231.0 + t * 326.0
		_panel(Rect2(center_x - 68, 282, 136, 30), COLORS[t].lightened(0.82), 15)
		_center(TREE_NAMES[t], Vector2(center_x, 302), 12, COLORS[t].darkened(0.36))
		if forest.alive[root]:
			draw_line(Vector2(positions[root].x, 333), positions[root], Color("#dad2df"), 2, true)
			draw_circle(Vector2(positions[root].x, 333), 3, COLORS[t])
		else:
			_center("all picked", Vector2(center_x, 353), 14, MUTED)
	var selected: Array[int] = []
	var focus_node := hovered if phase == Phase.PLAYER else aimed
	if focus_node >= 0:
		selected = forest.subtree(focus_node)
	for i in forest.parents.size():
		if not forest.alive[i] or forest.parents[i] < 0:
			continue
		var parent: int = forest.parents[i]
		var color := Color("#d5cdd8")
		if selected.has(i):
			color = COLORS[tree_indices[i]].darkened(0.10)
		draw_line(positions[parent], positions[i], color, 2.5, true)
	for i in forest.parents.size():
		if not forest.alive[i]:
			continue
		var position_i := positions[i]
		if selected.has(i):
			draw_circle(position_i, 29, Color(COLORS[tree_indices[i]], 0.16))
			if i == focus_node:
				draw_arc(position_i, 30, 0, TAU, 64, COLORS[tree_indices[i]].darkened(0.12), 1.7, true)
		_candy(position_i, COLORS[tree_indices[i]], 1.08 if i == focus_node else 1.0, 0.0, 1.0, tree_indices[i])
		if debug_mode:
			_panel(Rect2(position_i + Vector2(-19, 25), Vector2(38, 20)), Color("#eee8f5"), 6)
			_center("g:%d" % forest.sg[i], position_i + Vector2(0, 40), 12, PURPLE)
	if phase == Phase.CUTTING:
		_draw_cut()
	if phase == Phase.FINISHED:
		_panel(Rect2(474, 397, 492, 204), Color("#f4edf8"), 22, Color("#ded1ed"))
		_center("S W E E T   V I C T O R Y" if winner == "You" else "O N E   M O R E   B R A N C H ?", Vector2(720, 441), 13, PURPLE)
		_center("You win!" if winner == "You" else "The grove wins", Vector2(720, 493), 38)
		_center("No candies left. No moves left.", Vector2(720, 532), 18, MUTED)
		_center("R  replay     /     Z  rethink     /     N  new grove", Vector2(720, 574), 16, PURPLE)


func _draw_cut() -> void:
	var progress := clampf(clock / CUT_DURATION, 0, 1)
	for i in cutting:
		var drift := Vector2(sin(float(i) * 2.3) * 38.0 * progress, 110.0 * progress * progress)
		var origin := positions[i] + drift
		var opacity := 1.0 - progress
		var parent: int = forest.parents[i]
		if cutting.has(parent):
			var parent_drift := Vector2(sin(float(parent) * 2.3) * 38.0 * progress, 110.0 * progress * progress)
			draw_line(positions[parent] + parent_drift, origin, Color(0.72, 0.65, 0.76, opacity), 2, true)
		_candy(origin, COLORS[tree_indices[i]], 1.0 - 0.3 * progress, sin(float(i)) * progress, opacity, tree_indices[i])
		for spark in 3:
			var direction := Vector2.from_angle(float(spark) * TAU / 3.0 + float(i))
			draw_circle(positions[i] + direction * (22 + progress * 42), 2.6 * opacity, Color(COLORS[tree_indices[i]], opacity))


func _candy(at: Vector2, color: Color, scale_value: float, angle: float, opacity: float, kind: int) -> void:
	draw_set_transform(at, angle, Vector2.ONE * scale_value)
	var tint := Color(color, opacity)
	var dark := Color(color.darkened(0.16), opacity)
	var light := Color(color.lightened(0.45), opacity)
	var wrapper_left := PackedVector2Array([Vector2(-14, 0), Vector2(-27, -11), Vector2(-25, 0), Vector2(-27, 11)])
	var wrapper_right := PackedVector2Array([Vector2(14, 0), Vector2(27, -11), Vector2(25, 0), Vector2(27, 11)])
	draw_colored_polygon(wrapper_left, light)
	draw_colored_polygon(wrapper_right, light)
	draw_line(Vector2(-25, -6), Vector2(-17, 0), tint, 1.0, true)
	draw_line(Vector2(25, 6), Vector2(17, 0), tint, 1.0, true)
	draw_circle(Vector2(0, 3), 17, Color(0.28, 0.21, 0.34, 0.08 * opacity))
	draw_circle(Vector2.ZERO, 17, dark)
	draw_circle(Vector2(0, -1), 15.5, tint)
	if kind % 2 == 0:
		draw_arc(Vector2.ZERO, 9, -1.2, 3.8, 32, light, 3.2, true)
		draw_arc(Vector2(0, 0), 4, 1.5, 5.7, 24, light, 2.5, true)
	else:
		draw_line(Vector2(-8, -10), Vector2(7, 10), light, 4.5, true)
		draw_line(Vector2(0, -12), Vector2(11, 3), light, 3.0, true)
	draw_circle(Vector2(-6, -8), 3.0, Color(1, 1, 1, 0.55 * opacity))
	draw_set_transform(Vector2.ZERO)


func _draw_footer() -> void:
	var caption := note
	if hovered >= 0 and phase == Phase.PLAYER:
		caption = "Snip here to take %d %s." % [
			forest.subtree_sizes[hovered],
			"candy" if forest.subtree_sizes[hovered] == 1 else "candies"
		]
	_text(caption, Vector2(437, 807), 18, PURPLE)
	if debug_mode:
		var root_values: Array[String] = []
		for root in forest.roots:
			root_values.append(str(forest.sg[root]))
		_text("SG  %s = %d   |   %s to move" % [
			" xor ".join(root_values), forest.total_sg,
			"WINNING" if forest.total_sg != 0 else "LOSING"
		], Vector2(51, 862), 15, PURPLE)
	else:
		_text("HOW TO PLAY", Vector2(51, 860), 12, PURPLE)
		_text("Take a candy and everything below it. You and the grove alternate. Last pick wins.", Vector2(161, 860), 15, MUTED)
	_text("TREE NIM  /  %06d" % (seed_value % 1000000), Vector2(1202, 862), 12, MUTED)

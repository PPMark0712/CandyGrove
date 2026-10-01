extends Control
## One state machine owns the turn clock and both players' cut animations.
## Undo/restart reset that clock, so no delayed AI callback can mutate a new turn.

const Forest = preload("res://scripts/forest.gd")
const INK := Color("#393346")
const MUTED := Color("#89818c")
const PURPLE := Color("#7960aa")
const CUT_RED := Color("#c92f46")
const PAPER := Color("#f8f5ef")
const DESIGN_SIZE := Vector2(1440, 900)
const BOARD := Rect2(36, 190, 1368, 570)
const COLORS := [
	Color("#a996d7"), Color("#e99a83"), Color("#deb04d"), Color("#72b99a"),
	Color("#d681a8"), Color("#70a9cf"), Color("#91b95f")
]
const TREE_NAMES := ["LAVENDER", "PEACH", "HONEY", "MINT", "BERRY", "SKY", "LIME"]
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
var tree_centers: Array[float] = []
var moves_taken := 0
var seed_value := 0
var configured_tree_count := 4
var configured_max_depth := 3
var configured_layer_width := 12
var note := "A little strategy. A few sweet decisions."
var winner := ""
var font: Font
var undo_button: Button
var debug_button: Button
var restart_button: Button
var new_button: Button
var config_overlay: ColorRect
var config_panel: Panel
var tree_count_input: SpinBox
var depth_input: SpinBox
var width_input: SpinBox
var config_was_processing := true
var draw_offset := Vector2.ZERO


func _ready() -> void:
	font = ThemeDB.fallback_font
	rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_create_buttons()
	_create_config_panel()
	resized.connect(_update_layout)
	_update_layout()
	new_game()


func _button(
	text: String,
	rect: Rect2,
	callback: Callable,
	primary := false,
	parent: Control = self
) -> Button:
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
	parent.add_child(button)
	return button


func _create_buttons() -> void:
	restart_button = _button("Restart   R", Rect2(1060, 40, 148, 42), restart)
	restart_button.tooltip_text = "Replay this exact grove from the beginning"
	new_button = _button("New grove  +", Rect2(1222, 40, 170, 42), open_config, true)
	new_button.tooltip_text = "Configure and generate a fresh grove (N)"
	undo_button = _button("Undo round   Z", Rect2(48, 782, 184, 42), undo)
	undo_button.tooltip_text = "Undo your last choice and the AI reply, including an animation in progress"
	debug_button = _button("Show SG   D", Rect2(244, 782, 164, 42), toggle_debug)
	debug_button.tooltip_text = "Show subtree Sprague–Grundy values and the forest XOR"


func _create_config_panel() -> void:
	config_overlay = ColorRect.new()
	config_overlay.position = Vector2.ZERO
	config_overlay.size = Vector2(1440, 900)
	config_overlay.color = Color(0.12, 0.10, 0.16, 0.36)
	config_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	config_overlay.visible = false
	add_child(config_overlay)
	config_panel = Panel.new()
	config_panel.position = Vector2(470, 244)
	config_panel.size = Vector2(500, 412)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fefcf8")
	style.border_color = Color("#dcd3df")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.15, 0.10, 0.20, 0.16)
	style.shadow_size = 14
	config_panel.add_theme_stylebox_override("panel", style)
	config_overlay.add_child(config_panel)
	var title := _label("New grove", Vector2(36, 40), 31, INK, config_panel)
	title.size = Vector2(300, 44)
	var close := _button("x", Rect2(440, 28, 36, 36), close_config, false, config_panel)
	close.tooltip_text = "Close"
	tree_count_input = _number_input("Trees", 1, 7, configured_tree_count, 104, config_panel)
	depth_input = _number_input("Max depth", 1, 6, configured_max_depth, 178, config_panel)
	width_input = _number_input("Layer width", 1, 20, configured_layer_width, 252, config_panel)
	tree_count_input.value_changed.connect(_tree_count_changed)
	_button("Cancel", Rect2(236, 338, 104, 44), close_config, false, config_panel)
	_button("Generate", Rect2(352, 338, 124, 44), _apply_config, true, config_panel)


func _update_layout() -> void:
	draw_offset = Vector2(
		maxf(0.0, (size.x - DESIGN_SIZE.x) / 2.0),
		maxf(0.0, (size.y - DESIGN_SIZE.y) / 2.0)
	)
	if restart_button == null:
		return
	restart_button.position = draw_offset + Vector2(1060, 40)
	new_button.position = draw_offset + Vector2(1222, 40)
	undo_button.position = draw_offset + Vector2(48, 782)
	debug_button.position = draw_offset + Vector2(244, 782)
	config_overlay.size = size
	config_panel.position = draw_offset + Vector2(470, 244)
	queue_redraw()


func _label(
	text: String,
	at: Vector2,
	size_px: int,
	color: Color,
	parent: Control
) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _number_input(
	label_text: String,
	minimum: int,
	maximum: int,
	value: int,
	y: float,
	parent: Control
) -> SpinBox:
	var label := _label(label_text, Vector2(38, y + 11), 17, MUTED, parent)
	label.size = Vector2(180, 34)
	var input := SpinBox.new()
	input.position = Vector2(290, y)
	input.size = Vector2(172, 46)
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.value = value
	input.allow_greater = false
	input.allow_lesser = false
	input.add_theme_font_size_override("font_size", 17)
	parent.add_child(input)
	return input


func open_config() -> void:
	if config_overlay.visible:
		return
	config_was_processing = is_processing()
	set_process(false)
	tree_count_input.value = configured_tree_count
	depth_input.value = configured_max_depth
	width_input.min_value = configured_tree_count
	width_input.value = maxi(configured_layer_width, configured_tree_count)
	config_overlay.visible = true
	tree_count_input.get_line_edit().grab_focus()


func close_config() -> void:
	config_overlay.visible = false
	set_process(config_was_processing)


func _tree_count_changed(value: float) -> void:
	width_input.min_value = value
	if width_input.value < value:
		width_input.value = value


func _apply_config() -> void:
	configured_tree_count = int(tree_count_input.value)
	configured_max_depth = int(depth_input.value)
	configured_layer_width = maxi(configured_tree_count, int(width_input.value))
	config_overlay.visible = false
	new_game()
	set_process(config_was_processing)


func new_game() -> void:
	seed_value = rng.randi()
	rng.seed = seed_value
	forest.generate(
		rng,
		configured_tree_count,
		configured_max_depth,
		configured_layer_width
	)
	assert(forest.total_sg != 0)
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
	tree_indices.fill(-1)
	tree_centers.clear()
	var tree_layers: Array = []
	var weights: Array[float] = []
	for t in forest.roots.size():
		var root: int = forest.roots[t]
		var layers: Array = []
		_collect_layers(root, 0, t, layers)
		tree_layers.append(layers)
		var widest := 1
		for layer in layers:
			widest = maxi(widest, layer.size())
		weights.append(float(widest))
	var inner_left := BOARD.position.x + 24.0
	var inner_width := BOARD.size.x - 48.0
	var gap := 8.0
	var usable := inner_width - gap * maxi(0, forest.roots.size() - 1)
	var total_weight: float = weights.reduce(func(sum, value): return sum + value, 0.0)
	var cursor := inner_left
	var root_y := BOARD.position.y + 62.0
	var depth_gap := 78.0
	if forest.max_depth() > 0:
		depth_gap = minf(
			depth_gap,
			(BOARD.end.y - 31.0 - root_y) / float(forest.max_depth())
		)
	for t in forest.roots.size():
		var segment_width: float = usable * weights[t] / total_weight
		var center := cursor + segment_width / 2.0
		tree_centers.append(center)
		var layers: Array = tree_layers[t]
		var slot_width := segment_width / weights[t]
		for depth in layers.size():
			var layer: Array = layers[depth]
			var layer_width := slot_width * layer.size()
			var start := center - layer_width / 2.0 + slot_width / 2.0
			for rank in layer.size():
				positions[layer[rank]] = Vector2(
					start + rank * slot_width,
					root_y + depth * depth_gap
				)
		cursor += segment_width + gap


func _collect_layers(node: int, depth: int, tree: int, layers: Array) -> void:
	while layers.size() <= depth:
		layers.append([])
	layers[depth].append(node)
	tree_indices[node] = tree
	for child in forest.children[node]:
		_collect_layers(child, depth + 1, tree, layers)


func _gui_input(event: InputEvent) -> void:
	if config_overlay.visible:
		return
	if event is InputEventMouseMotion:
		var design_position: Vector2 = event.position - draw_offset
		var target := _hit(design_position) if phase == Phase.PLAYER else -1
		if target != hovered:
			hovered = target
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovered >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if phase == Phase.PLAYER:
			var design_position: Vector2 = event.position - draw_offset
			var target := _hit(design_position)
			if target >= 0:
				player_cut(target)
			elif BOARD.has_point(design_position):
				note = "Click a candy to take it and every candy below it."
				queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Preserve browser shortcuts such as Cmd+R / Ctrl+R.
		if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
			return
		if config_overlay.visible:
			if event.keycode == KEY_ESCAPE:
				close_config()
				get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_Z:
				undo()
			KEY_R:
				restart()
			KEY_D:
				toggle_debug()
			KEY_N:
				open_config()
			_:
				return
		get_viewport().set_input_as_handled()


func _hit(point: Vector2) -> int:
	for i in positions.size():
		var offset := point - positions[i]
		if forest.alive[i] and absf(offset.x) <= 24.0 and absf(offset.y) <= 16.0:
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
	draw_set_transform(draw_offset)
	_draw_header()
	_draw_board()
	_draw_footer()
	draw_set_transform(Vector2.ZERO)


func _draw_header() -> void:
	_text("Candy Grove", Vector2(42, 78), 44)
	_text("Pick a candy. Take its branch. Leave nothing behind.", Vector2(44, 111), 17, MUTED)
	draw_line(Vector2(42, 138), Vector2(1398, 138), Color("#e2dce0"), 1)
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
	draw_circle(Vector2(49, 164), 5, dot_color)
	_text(turn_title, Vector2(67, 172), 21)
	_text(turn_hint, Vector2(252, 171), 16, MUTED)
	_panel(Rect2(1160, 148, 238, 32), Color("#eee8f1"), 16)
	_center(
		"%02d candies   /   %02d moves" % [forest.remaining(), moves_taken],
		Vector2(1279, 170),
		15,
		PURPLE
	)


func _draw_board() -> void:
	_panel(BOARD, Color("#fefcf8"), 22, Color("#e4dde2"))
	# Small, quiet dot grid gives the strings a little depth.
	for x in range(58, 1390, 26):
		for y in range(208, 748, 26):
			draw_circle(Vector2(x, y), 0.85, Color("#ebe6e8"))
	for t in forest.roots.size():
		var root: int = forest.roots[t]
		var center_x: float = tree_centers[t]
		var label_width := minf(116.0, BOARD.size.x / forest.roots.size() - 16.0)
		_panel(
			Rect2(center_x - label_width / 2.0, 204, label_width, 26),
			COLORS[t].lightened(0.82),
			13
		)
		_center(TREE_NAMES[t], Vector2(center_x, 222), 10, COLORS[t].darkened(0.36))
		if forest.alive[root]:
			var stem_color := CUT_RED if hovered == root else Color("#dad2df")
			draw_line(
				Vector2(positions[root].x, 236),
				Vector2(positions[root].x, positions[root].y - 11),
				stem_color,
				3.0 if hovered == root else 1.5,
				true
			)
			draw_circle(
				Vector2(positions[root].x, 236),
				2.5,
				CUT_RED if hovered == root else COLORS[t]
			)
			if hovered == root:
				_draw_cut_marker(
					Vector2(positions[root].x, 236),
					Vector2(positions[root].x, positions[root].y - 11)
				)
		else:
			_center("all picked", Vector2(center_x, 253), 11, MUTED)
	var selected: Array[int] = []
	var focus_node := hovered if phase == Phase.PLAYER else aimed
	var projected := {}
	if focus_node >= 0:
		selected = forest.subtree(focus_node)
		if debug_mode and hovered >= 0:
			projected = forest.sg_path_after_cut(hovered)
	for i in forest.parents.size():
		if not forest.alive[i] or forest.parents[i] < 0:
			continue
		var parent: int = forest.parents[i]
		var color := Color("#d5cdd8")
		if selected.has(i):
			color = COLORS[tree_indices[i]].darkened(0.10)
		var line_width := 2.5
		if i == hovered:
			color = CUT_RED
			line_width = 3.5
		draw_line(positions[parent], positions[i], color, line_width, true)
	if hovered >= 0 and forest.parents[hovered] >= 0:
		_draw_cut_marker(positions[forest.parents[hovered]], positions[hovered])
	for i in forest.parents.size():
		if not forest.alive[i]:
			continue
		var position_i := positions[i]
		if selected.has(i):
			_ellipse(position_i, 25.0, Color(COLORS[tree_indices[i]], 0.16), 1.15, 0.70)
			if i == focus_node:
				draw_set_transform(draw_offset + position_i, 0.0, Vector2(1.15, 0.70))
				draw_arc(
					Vector2.ZERO,
					25,
					0,
					TAU,
					48,
					COLORS[tree_indices[i]].darkened(0.12),
					1.5,
					true
				)
				draw_set_transform(draw_offset)
		_candy(
			position_i,
			COLORS[tree_indices[i]],
			1.06 if i == focus_node else 1.0,
			0.0,
			1.0,
			tree_indices[i]
		)
		if debug_mode:
			var sg_text := "g:%d" % forest.sg[i]
			var label_color := PURPLE
			var background := Color("#eee8f5")
			if projected.has(i):
				sg_text = "%d>%d" % [forest.sg[i], int(projected[i])]
				label_color = Color("#a15178")
				background = Color("#f6e2eb")
			_panel(Rect2(position_i + Vector2(-18, 17), Vector2(36, 16)), background, 5)
			_center(sg_text, position_i + Vector2(0, 29), 9, label_color)
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
			draw_circle(
				positions[i] + direction * (18 + progress * 36),
				2.2 * opacity,
				Color(COLORS[tree_indices[i]], opacity)
			)


func _candy(at: Vector2, color: Color, scale_value: float, angle: float, opacity: float, kind: int) -> void:
	draw_set_transform(draw_offset + at, angle, Vector2(1.05, 0.68) * scale_value)
	var tint := Color(color, opacity)
	var dark := Color(color.darkened(0.16), opacity)
	var light := Color(color.lightened(0.45), opacity)
	var wrapper_left := PackedVector2Array([
		Vector2(-12, 0), Vector2(-22, -10), Vector2(-20, 0), Vector2(-22, 10)
	])
	var wrapper_right := PackedVector2Array([
		Vector2(12, 0), Vector2(22, -10), Vector2(20, 0), Vector2(22, 10)
	])
	draw_colored_polygon(wrapper_left, light)
	draw_colored_polygon(wrapper_right, light)
	draw_line(Vector2(-20, -5), Vector2(-14, 0), tint, 1.0, true)
	draw_line(Vector2(20, 5), Vector2(14, 0), tint, 1.0, true)
	draw_circle(Vector2(0, 2), 14, Color(0.28, 0.21, 0.34, 0.08 * opacity))
	draw_circle(Vector2.ZERO, 14, dark)
	draw_circle(Vector2(0, -1), 12.8, tint)
	if kind % 2 == 0:
		draw_arc(Vector2.ZERO, 7.5, -1.2, 3.8, 28, light, 2.7, true)
		draw_arc(Vector2.ZERO, 3.5, 1.5, 5.7, 20, light, 2.0, true)
	else:
		draw_line(Vector2(-7, -8), Vector2(6, 8), light, 3.5, true)
		draw_line(Vector2(0, -10), Vector2(9, 2), light, 2.5, true)
	draw_circle(Vector2(-5, -7), 2.4, Color(1, 1, 1, 0.55 * opacity))
	draw_set_transform(draw_offset)


func _ellipse(at: Vector2, radius: float, color: Color, x_scale: float, y_scale: float) -> void:
	draw_set_transform(draw_offset + at, 0.0, Vector2(x_scale, y_scale))
	draw_circle(Vector2.ZERO, radius, color)
	draw_set_transform(draw_offset)


func _draw_cut_marker(edge_start: Vector2, edge_end: Vector2) -> void:
	var direction := edge_start.direction_to(edge_end)
	if direction.is_zero_approx():
		return
	var normal := Vector2(-direction.y, direction.x)
	var marker := edge_start.lerp(edge_end, 0.62)
	for offset in [-12.0, -5.0, 2.0, 9.0]:
		draw_line(
			marker + normal * offset,
			marker + normal * (offset + 3.0),
			Color("#25212b"),
			1.7,
			true
		)
	var metal := Color("#25212b")
	var pivot := marker + normal * 27.0
	var handle_base := pivot + normal * 7.0
	var upper_handle := handle_base + direction * 7.0
	var lower_handle := handle_base - direction * 7.0
	draw_line(pivot, upper_handle, metal, 2.8, true)
	draw_line(pivot, lower_handle, metal, 2.8, true)
	draw_circle(upper_handle, 4.6, CUT_RED)
	draw_circle(lower_handle, 4.6, CUT_RED)
	draw_circle(upper_handle, 2.0, PAPER)
	draw_circle(lower_handle, 2.0, PAPER)
	var upper_tip := marker + normal * 17.0 + direction * 7.5
	var lower_tip := marker + normal * 17.0 - direction * 7.5
	_draw_tapered_blade(pivot, upper_tip, 4.2, 0.8, metal)
	_draw_tapered_blade(pivot, lower_tip, 4.2, 0.8, metal)
	draw_circle(pivot, 2.4, metal)
	draw_circle(pivot, 0.8, PAPER)


func _draw_tapered_blade(
	base: Vector2,
	tip: Vector2,
	base_width: float,
	tip_width: float,
	color: Color
) -> void:
	var axis := base.direction_to(tip)
	var side := Vector2(-axis.y, axis.x)
	draw_colored_polygon(PackedVector2Array([
		base + side * base_width / 2.0,
		base - side * base_width / 2.0,
		tip - side * tip_width / 2.0,
		tip + side * tip_width / 2.0
	]), color)


func _draw_footer() -> void:
	var caption := note
	if hovered >= 0 and phase == Phase.PLAYER:
		caption = "Snip here to take %d %s." % [
			forest.subtree_sizes[hovered],
			"candy" if forest.subtree_sizes[hovered] == 1 else "candies"
		]
	_text(caption, Vector2(437, 807), 17, PURPLE)
	if debug_mode:
		var root_values: Array[String] = []
		for root in forest.roots:
			root_values.append(str(forest.sg[root]))
		var debug_text := "SG  %s = %d   |   %s to move" % [
			" xor ".join(root_values),
			forest.total_sg,
			"WINNING" if forest.total_sg != 0 else "LOSING"
		]
		if hovered >= 0 and phase == Phase.PLAYER:
			debug_text += "   |   after cut = %d" % forest.sg_after_cut(hovered)
		_text(debug_text, Vector2(51, 862), 13, PURPLE)
	else:
		_text("HOW TO PLAY", Vector2(51, 860), 12, PURPLE)
		_text("Take a candy and everything below it. You and the grove alternate. Last pick wins.", Vector2(161, 860), 15, MUTED)
	_text("TREE NIM  /  %06d" % (seed_value % 1000000), Vector2(1202, 862), 12, MUTED)

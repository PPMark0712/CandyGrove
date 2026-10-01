extends SceneTree
const GameScene = preload("res://scenes/main.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func verify(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	game.set_process(false)
	var original: Array = game.forest.alive.duplicate()
	var topology: Array = game.forest.parents.duplicate()
	var selected: int = game.forest.roots[0]
	var removed: int = game.forest.subtree_sizes[selected]
	game.player_cut(selected)
	verify(game.forest.remaining() == original.size() - removed, "Click removes whole subtree")
	verify(game.phase == game.Phase.CUTTING, "Player has a cut animation")
	game.player_cut(game.forest.roots[1])
	verify(game.moves_taken == 1, "Double click cannot play during animation")
	game.undo()
	verify(game.forest.alive == original, "Undo during player animation restores snapshot")
	game._process(5.0)
	verify(game.moves_taken == 0, "Undo cancels future AI actions")
	for stage in 4:
		game.player_cut(selected)
		game._process(game.CUT_DURATION)
		verify(game.phase == game.Phase.AI_THINK, "AI thinks before selecting")
		if stage >= 1:
			game._process(game.THINK_DURATION)
			verify(game.phase == game.Phase.AI_AIM, "AI previews its cut")
		if stage >= 2:
			game._process(game.AIM_DURATION)
			verify(game.phase == game.Phase.CUTTING and not game.cutting_player,
				"AI uses the same cut animation")
		if stage >= 3:
			game._process(game.CUT_DURATION)
			verify(game.phase == game.Phase.PLAYER, "AI returns control")
		game.undo()
		game._process(10.0)
		verify(game.forest.alive == original and game.moves_taken == 0,
			"Undo restores full round at every stage")
	game.player_cut(selected)
	game.restart()
	game._process(10.0)
	verify(game.forest.parents == topology and game.forest.alive == original,
		"Restart preserves the original topology")
	verify(game.history.is_empty(), "Restart clears history")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_D
	game._input(key)
	verify(game.debug_mode, "D toggles debug")
	game.player_cut(selected)
	key.keycode = KEY_Z
	game._input(key)
	verify(game.forest.alive == original, "Z invokes undo")
	game.player_cut(selected)
	key.keycode = KEY_R
	game._input(key)
	verify(game.moves_taken == 0 and game.history.is_empty(), "R restarts")
	game.open_config()
	verify(game.config_overlay.visible, "New grove opens its configuration")
	verify(not game.is_processing(), "Configuration pauses the current turn")
	game.tree_count_input.value = 7
	game.depth_input.value = 6
	game.width_input.value = 20
	game._apply_config()
	verify(not game.config_overlay.visible, "Generate closes configuration")
	verify(game.forest.roots.size() == 7, "Configuration applies tree count")
	verify(game.forest.max_depth() <= 6, "Configuration applies maximum depth")
	verify(game.forest.layer_counts().max() <= 20, "Configuration applies layer width")
	verify(game.forest.total_sg != 0, "Configured initial position is winning")
	for tree in range(7):
		verify(game.tree_indices.has(tree), "Every configured tree is laid out")
	game.configured_tree_count = 4
	game.configured_max_depth = 3
	game.configured_layer_width = 12
	game.new_game()
	original = game.forest.alive.duplicate()
	selected = game.forest.roots[0]
	# Both possible terminal results, with undo after game over.
	var single: Array[int] = [-1]
	game.forest.setup(single)
	game._reset()
	game._layout_forest()
	game.player_cut(0)
	game._process(game.CUT_DURATION)
	verify(game.phase == game.Phase.FINISHED and game.winner == "You", "Player last pick wins")
	game.undo()
	verify(game.forest.remaining() == 1 and game.phase == game.Phase.PLAYER,
		"Can undo a finished game")
	var pair: Array[int] = [-1, -1]
	game.forest.setup(pair)
	game._reset()
	game._layout_forest()
	game.player_cut(0)
	game._process(game.CUT_DURATION)
	game._process(game.THINK_DURATION)
	game._process(game.AIM_DURATION)
	game._process(game.CUT_DURATION)
	verify(game.phase == game.Phase.FINISHED and game.winner == "The grove", "AI last pick wins")
	game.undo()
	verify(game.forest.remaining() == 2, "Undo AI victory restores both moves")
	# Exercise generated layouts and actual hit regions at normal and maximum scale.
	for settings in [[4, 3, 12, 100], [7, 6, 20, 100]]:
		game.configured_tree_count = settings[0]
		game.configured_max_depth = settings[1]
		game.configured_layer_width = settings[2]
		for sample in settings[3]:
			game.new_game()
			var first_y: float = game.positions[game.forest.roots[0]].y
			for node in game.forest.roots:
				verify(game.positions[node].y == first_y, "Roots align")
			for i in game.positions.size():
				verify(game.BOARD.grow(-20).has_point(game.positions[i]), "Candy inside frame")
				verify(game._hit(game.positions[i]) == i, "Candy hit test reaches correct node")
				for j in range(i):
					if game.forest.depths[i] == game.forest.depths[j]:
						verify(
							game.positions[i].distance_to(game.positions[j]) >= 36,
							"Candy bodies on a layer must not overlap"
						)
			game.player_cut(game.forest.roots[0])
			game.new_game()
			game._process(10.0)
			verify(
				game.moves_taken == 0 and game.phase == game.Phase.PLAYER,
				"New grove cancels animation"
			)
	game.set_anchors_preset(Control.PRESET_TOP_LEFT)
	game.size = Vector2(1800, 900)
	game._update_layout()
	verify(game.draw_offset == Vector2(180, 0), "Wide screens center the fixed design area")
	verify(
		game.restart_button.position == Vector2(1240, 40),
		"Controls follow the centered design area"
	)
	verify(game.config_overlay.size == Vector2(1800, 900), "Configuration shade fills the screen")
	var motion := InputEventMouseMotion.new()
	motion.position = game.positions[game.forest.roots[0]] + game.draw_offset
	game._gui_input(motion)
	verify(game.hovered == game.forest.roots[0], "Mouse hit testing accounts for screen offset")
	game.size = Vector2(1440, 1100)
	game._update_layout()
	verify(game.draw_offset == Vector2(0, 100), "Tall screens vertically center the design area")
	verify(game.config_panel.position == Vector2(470, 344), "Configuration follows vertical offset")
	game.queue_free()
	print("Game tests: responsive/config/animation/undo/terminal/keys + 200 layouts, %d failures" % failures)
	quit(0 if failures == 0 else 1)

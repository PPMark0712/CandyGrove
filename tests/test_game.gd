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
	# Exercise generated layouts and actual hit regions.
	for sample in 200:
		game.new_game()
		var first_y: float = game.positions[game.forest.roots[0]].y
		for node in game.forest.roots:
			verify(game.positions[node].y == first_y, "Roots align")
		for i in game.positions.size():
			verify(game.BOARD.grow(-30).has_point(game.positions[i]), "Candy inside frame")
			verify(game._hit(game.positions[i]) == i, "Candy hit test reaches correct node")
			for j in range(i):
				verify(game.positions[i].distance_to(game.positions[j]) >= 38,
					"Candy bodies must not overlap")
		game.player_cut(game.forest.roots[0])
		game.new_game()
		game._process(10.0)
		verify(game.moves_taken == 0 and game.phase == game.Phase.PLAYER,
			"New grove cancels animation")
	game.queue_free()
	print("Game tests: animation/undo/restart/terminal/keys + 200 layouts, %d failures" % failures)
	quit(0 if failures == 0 else 1)

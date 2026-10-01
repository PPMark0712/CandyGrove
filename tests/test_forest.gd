extends SceneTree
## Independent bitmask / mex oracle: does not use the production SG recurrence.
const Forest = preload("res://scripts/forest.gd")
var checked_states := 0
var checked_forests := 0
var failures := 0
var memo: Dictionary = {}
var descendants: Array[int] = []
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 20261001
	for count in range(1, 7):
		enumerate_topologies([], count)
	for sample in 120:
		var topology: Array[int] = [-1]
		for i in range(1, 10):
			topology.append(rng.randi_range(-1, i - 1))
		check_topology(topology)
	check_random_ties()
	check_generation_limits()
	print("Forest tests: %d topologies, %d states, %d failures" % [
		checked_forests, checked_states, failures
	])
	quit(0 if failures == 0 else 1)


func verify(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures <= 10:
			push_error(message)


func enumerate_topologies(prefix: Array[int], count: int) -> void:
	if prefix.size() == count:
		check_topology(prefix)
		return
	for parent in range(-1, prefix.size()):
		var next := prefix.duplicate()
		next.append(parent)
		enumerate_topologies(next, count)


func oracle(mask: int) -> int:
	if memo.has(mask):
		return memo[mask]
	var options := {}
	for i in descendants.size():
		if mask & (1 << i):
			options[oracle(mask & ~descendants[i])] = true
	var value := 0
	while options.has(value):
		value += 1
	memo[mask] = value
	return value


func check_topology(topology: Array[int]) -> void:
	checked_forests += 1
	var game := Forest.new()
	game.setup(topology)
	descendants.clear()
	for i in topology.size():
		var mask := 0
		for j in topology.size():
			var cursor := j
			while cursor >= 0:
				if cursor == i:
					mask |= 1 << j
					break
				cursor = topology[cursor]
		descendants.append(mask)
	memo = {0: 0}
	for mask in range(1 << topology.size()):
		var snapshot: Array[bool] = []
		var valid := true
		for i in topology.size():
			snapshot.append((mask & (1 << i)) != 0)
			if snapshot[i] and topology[i] >= 0 and not snapshot[topology[i]]:
				valid = false
		if not valid:
			continue
		checked_states += 1
		game.restore(snapshot)
		var expected := oracle(mask)
		verify(game.total_sg == expected, "Forest SG disagrees with mex oracle")
		var optimal: Array[int] = []
		var best := -1 if expected != 0 else 999
		for i in topology.size():
			if not snapshot[i]:
				continue
			verify(game.sg[i] == oracle(mask & descendants[i]), "Subtree SG incorrect")
			var after := mask & ~descendants[i]
			verify(game.sg_after_cut(i) == oracle(after), "Ancestor update incorrect")
			var projected := game.sg_path_after_cut(i)
			game.remove(i)
			for ancestor in projected:
				verify(
					game.sg[ancestor] == projected[ancestor],
					"Hover SG projection disagrees with actual cut"
				)
			game.restore(snapshot)
			var removed_count := 0
			for j in topology.size():
				if (mask & descendants[i]) & (1 << j):
					removed_count += 1
			if expected != 0 and oracle(after) != 0:
				continue
			if (expected != 0 and removed_count > best) or (expected == 0 and removed_count < best):
				optimal.clear()
				best = removed_count
			if removed_count == best:
				optimal.append(i)
		verify(game.best_moves() == optimal, "AI candidates do not satisfy priority")
		var choice := game.choose_ai(rng)
		verify(choice == -1 if mask == 0 else optimal.has(choice), "AI chose illegal/nonoptimal move")
		if choice >= 0:
			game.remove(choice)
			verify(game.total_sg == oracle(mask & ~descendants[choice]), "Cut result wrong")
			game.restore(snapshot)
			verify(game.alive == snapshot and game.total_sg == expected, "Restore changed state")


func check_random_ties() -> void:
	var game := Forest.new()
	game.setup([-1, -1, -1, -1])
	var seen := {}
	for attempt in 128:
		seen[game.choose_ai(rng)] = true
	verify(seen.size() == 4, "Losing-state ties must vary randomly")


func check_generation_limits() -> void:
	var game := Forest.new()
	for tree_count in range(1, 8):
		for maximum_depth in range(1, 7):
			for width in [tree_count, 20]:
				for sample in 4:
					game.generate(rng, tree_count, maximum_depth, width)
					verify(game.roots.size() == tree_count, "Generated tree count is wrong")
					verify(game.max_depth() <= maximum_depth, "Generated tree is too deep")
					verify(game.total_sg != 0, "Initial position must be winning")
					for count in game.layer_counts():
						verify(count <= width, "Generated layer is wider than its limit")

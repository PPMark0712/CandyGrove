class_name NimForest
extends RefCounted
## Root deletion is legal. A node's SG is 1 + XOR(child SG).
## Indices are topological: every parent precedes its children.

var parents: Array[int] = []
var children: Array = []
var alive: Array[bool] = []
var sg: Array[int] = []
var subtree_sizes: Array[int] = []
var roots: Array[int] = []
var depths: Array[int] = []
var total_sg := 0


func setup(topology: Array[int]) -> void:
	parents = topology.duplicate()
	children.clear()
	roots.clear()
	alive.clear()
	sg.clear()
	subtree_sizes.clear()
	depths.clear()
	for i in parents.size():
		assert(parents[i] >= -1 and parents[i] < i, "Parents must precede children")
		children.append([])
		alive.append(true)
		sg.append(0)
		subtree_sizes.append(0)
		if parents[i] < 0:
			roots.append(i)
			depths.append(0)
		else:
			children[parents[i]].append(i)
			depths.append(depths[parents[i]] + 1)
	refresh()


func generate(
	rng: RandomNumberGenerator,
	tree_count := 4,
	maximum_depth := 3,
	maximum_layer_width := 12
) -> void:
	tree_count = clampi(tree_count, 1, 7)
	maximum_depth = clampi(maximum_depth, 1, 6)
	maximum_layer_width = clampi(maximum_layer_width, tree_count, 20)
	for attempt in 256:
		setup(_random_topology(rng, tree_count, maximum_depth, maximum_layer_width))
		if total_sg != 0:
			return
	# This compact fallback is always winning and respects every selected limit.
	var topology: Array[int] = []
	for tree in tree_count:
		topology.append(-1)
	if tree_count % 2 == 0:
		topology.append(0)
	setup(topology)


func _random_topology(
	rng: RandomNumberGenerator,
	tree_count: int,
	maximum_depth: int,
	maximum_layer_width: int
) -> Array[int]:
	var topology: Array[int] = []
	var budgets: Array[int] = []
	for tree in tree_count:
		budgets.append(1)
	for extra in maximum_layer_width - tree_count:
		budgets[rng.randi_range(0, tree_count - 1)] += 1
	for tree in tree_count:
		var root := topology.size()
		topology.append(-1)
		var previous: Array[int] = [root]
		var actual_depth := maximum_depth if tree == 0 else rng.randi_range(
			maxi(1, maximum_depth - 2), maximum_depth
		)
		for depth in range(1, actual_depth + 1):
			var capacity := mini(budgets[tree], previous.size() * 3)
			var minimum := maxi(1, int(ceil(capacity * 0.55)))
			var child_count := rng.randi_range(minimum, capacity)
			var parent_counts: Array[int] = []
			for parent in previous:
				parent_counts.append(0)
			var next: Array[int] = []
			for child in child_count:
				var candidates: Array[int] = []
				for i in previous.size():
					if parent_counts[i] < 3:
						candidates.append(i)
				var parent_slot: int = candidates[rng.randi_range(0, candidates.size() - 1)]
				parent_counts[parent_slot] += 1
			for parent_slot in previous.size():
				for child in parent_counts[parent_slot]:
					next.append(topology.size())
					topology.append(previous[parent_slot])
			previous = next
	return topology


func refresh() -> void:
	total_sg = 0
	for i in range(parents.size() - 1, -1, -1):
		sg[i] = 0
		subtree_sizes[i] = 0
		if not alive[i]:
			continue
		var child_xor := 0
		subtree_sizes[i] = 1
		for child in children[i]:
			child_xor ^= sg[child]
			subtree_sizes[i] += subtree_sizes[child]
		sg[i] = child_xor + 1
	for root in roots:
		total_sg ^= sg[root]


func subtree(node: int) -> Array[int]:
	var result: Array[int] = []
	if node < 0 or node >= alive.size() or not alive[node]:
		return result
	result.append(node)
	for child in children[node]:
		result.append_array(subtree(child))
	return result


func remove(node: int) -> Array[int]:
	var removed := subtree(node)
	for i in removed:
		alive[i] = false
	refresh()
	return removed


func restore(snapshot: Array[bool]) -> void:
	assert(snapshot.size() == alive.size())
	alive = snapshot.duplicate()
	refresh()


func remaining() -> int:
	return alive.count(true)


func max_depth() -> int:
	return depths.max() if not depths.is_empty() else 0


func layer_counts() -> Array[int]:
	var counts: Array[int] = []
	for depth in depths:
		while counts.size() <= depth:
			counts.append(0)
		counts[depth] += 1
	return counts


func sg_path_after_cut(node: int) -> Dictionary:
	var projected := {node: 0}
	var replacement := 0
	var current := node
	while parents[current] >= 0:
		var parent := parents[current]
		var child_xor := (sg[parent] - 1) ^ sg[current] ^ replacement
		replacement = child_xor + 1
		projected[parent] = replacement
		current = parent
	return projected


func sg_after_cut(node: int) -> int:
	# Only the ancestors of the cut change; cached sibling values stay valid.
	var projected := sg_path_after_cut(node)
	var root := node
	while parents[root] >= 0:
		root = parents[root]
	return total_sg ^ sg[root] ^ int(projected[root])


func best_moves() -> Array[int]:
	var candidates: Array[int] = []
	var winning := total_sg != 0
	var best_size := -1 if winning else 2147483647
	for i in alive.size():
		if not alive[i]:
			continue
		if winning and sg_after_cut(i) != 0:
			continue
		var count := subtree_sizes[i]
		if (winning and count > best_size) or (not winning and count < best_size):
			best_size = count
			candidates.clear()
		if count == best_size:
			candidates.append(i)
	return candidates


func choose_ai(rng: RandomNumberGenerator) -> int:
	var candidates := best_moves()
	if candidates.is_empty():
		return -1
	return candidates[rng.randi_range(0, candidates.size() - 1)]

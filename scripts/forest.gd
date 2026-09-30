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
var total_sg := 0


func setup(topology: Array[int]) -> void:
	parents = topology.duplicate()
	children.clear()
	roots.clear()
	alive.clear()
	sg.clear()
	subtree_sizes.clear()
	for i in parents.size():
		assert(parents[i] >= -1 and parents[i] < i, "Parents must precede children")
		children.append([])
		alive.append(true)
		sg.append(0)
		subtree_sizes.append(0)
		if parents[i] < 0:
			roots.append(i)
		else:
			children[parents[i]].append(i)
	refresh()


func generate(rng: RandomNumberGenerator) -> void:
	var topology: Array[int] = []
	for tree in 4:
		var start := topology.size()
		topology.append(-1)
		var depths: Array[int] = [0]
		var counts: Array[int] = [0]
		for j in rng.randi_range(7, 10):
			var candidates: Array[int] = []
			for k in depths.size():
				if depths[k] < 3 and counts[k] < 2:
					candidates.append(k)
			var parent: int = candidates[rng.randi_range(0, candidates.size() - 1)]
			topology.append(start + parent)
			depths.append(depths[parent] + 1)
			counts.append(0)
			counts[parent] += 1
	setup(topology)


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


func sg_after_cut(node: int) -> int:
	# Only the ancestors of the cut change; cached sibling values stay valid.
	var replacement := 0
	var current := node
	while parents[current] >= 0:
		var parent := parents[current]
		var child_xor := (sg[parent] - 1) ^ sg[current] ^ replacement
		replacement = child_xor + 1
		current = parent
	return total_sg ^ sg[current] ^ replacement


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

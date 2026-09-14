package physics

import "core:mem"

@(private)
Tree_Node :: struct {
	bounds:   AABB,
	parent:   int,
	children: [2]int,
	height:   int,
	collider: Collider_Handle,
}

@(private)
Tree :: struct {
	nodes:      []Tree_Node,
	root, free: int,
	allocator:  mem.Allocator,
}

@(private)
create_tree :: proc(capacity: int, allocator: mem.Allocator) -> (Tree, Error) {
	if capacity <= 0 || capacity > (max(int) / size_of(Tree_Node)) / 2 {
		return {}, .Invalid_Capacity
	}
	nodes, err := make([]Tree_Node, capacity * 2 - 1, allocator)
	if err != .None {
		return {}, .Allocation_Failed
	}
	for &node, i in nodes {
		node.parent = i + 1 if i + 1 < len(nodes) else -1
		node.height = -1
	}
	return {nodes = nodes, root = -1, free = 0, allocator = allocator}, .None
}

@(private)
tree_alloc :: proc(tree: ^Tree) -> int {
	index := tree.free
	assert(index >= 0)
	tree.free = tree.nodes[index].parent
	tree.nodes[index] = {
		parent   = -1,
		children = {-1, -1},
	}
	return index
}

@(private)
tree_free :: proc(tree: ^Tree, index: int) {
	tree.nodes[index] = {
		parent = tree.free,
		height = -1,
	}
	tree.free = index
}

@(private)
tree_insert :: proc(tree: ^Tree, leaf: int) {
	if tree.root == -1 {
		tree.root = leaf
		return
	}
	bounds := tree.nodes[leaf].bounds
	sibling := tree.root
	for tree.nodes[sibling].height > 0 {
		node := &tree.nodes[sibling]
		inherited :=
			2 * (bounds_area(combine_bounds(node.bounds, bounds)) - bounds_area(node.bounds))
		cost: [2]f64
		for child, i in node.children {
			cost[i] = bounds_area(combine_bounds(tree.nodes[child].bounds, bounds)) + inherited
			if tree.nodes[child].height > 0 {
				cost[i] -= bounds_area(tree.nodes[child].bounds)
			}
		}
		if 2 * bounds_area(combine_bounds(node.bounds, bounds)) < min(cost.x, cost.y) {
			break
		}
		sibling = node.children[0 if cost.x < cost.y else 1]
	}
	old_parent := tree.nodes[sibling].parent
	parent := tree_alloc(tree)
	tree.nodes[parent] = {
		parent   = old_parent,
		children = {sibling, leaf},
		bounds   = combine_bounds(bounds, tree.nodes[sibling].bounds),
		height   = tree.nodes[sibling].height + 1,
	}
	tree.nodes[sibling].parent = parent
	tree.nodes[leaf].parent = parent
	tree_replace_child(tree, old_parent, sibling, parent)
	tree_refit(tree, parent)
}

@(private)
tree_remove :: proc(tree: ^Tree, leaf: int) {
	if tree.root == leaf {
		tree.root = -1
		return
	}
	parent := tree.nodes[leaf].parent
	grandparent := tree.nodes[parent].parent
	sibling := tree.nodes[parent].children[1 if tree.nodes[parent].children[0] == leaf else 0]
	tree_replace_child(tree, grandparent, parent, sibling)
	tree.nodes[sibling].parent = grandparent
	tree.nodes[leaf].parent = -1
	tree_free(tree, parent)
	tree_refit(tree, grandparent)
}

@(private)
tree_replace_child :: proc(tree: ^Tree, parent, old, replacement: int) {
	if parent == -1 {
		tree.root = replacement
	} else {
		children := &tree.nodes[parent].children
		children[0 if children[0] == old else 1] = replacement
	}
}

@(private)
tree_recompute :: proc(tree: ^Tree, index: int) {
	node := &tree.nodes[index]
	a, b := tree.nodes[node.children[0]], tree.nodes[node.children[1]]
	node.bounds = combine_bounds(a.bounds, b.bounds)
	node.height = 1 + max(a.height, b.height)
}

@(private)
tree_refit :: proc(tree: ^Tree, start: int) {
	index := start
	for index != -1 {
		tree_recompute(tree, index)
		node := &tree.nodes[index]
		balance := tree.nodes[node.children[1]].height - tree.nodes[node.children[0]].height
		if abs(balance) > 1 {
			heavy := 1 if balance > 0 else 0
			other := 1 - heavy
			promoted_index := node.children[heavy]
			promoted := &tree.nodes[promoted_index]
			a, b := promoted.children[0], promoted.children[1]
			tall := a if tree.nodes[a].height > tree.nodes[b].height else b
			short := b if tall == a else a
			parent := node.parent
			tree_replace_child(tree, parent, index, promoted_index)
			promoted.parent = parent
			promoted.children[other] = index
			promoted.children[heavy] = tall
			node.parent = promoted_index
			node.children[heavy] = short
			tree.nodes[short].parent = index
			tree.nodes[tall].parent = promoted_index
			tree_recompute(tree, index)
			tree_recompute(tree, promoted_index)
			index = promoted_index
		}
		index = tree.nodes[index].parent
	}
}

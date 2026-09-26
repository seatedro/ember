package collision

import emath "../../core/math"
// mem.Allocator only appears inside generic types, which are checked when used,
// so without @(require) the import looks unused.
@(require) import "core:mem"

// A dynamic AABB tree. Leaves hold whatever the caller gives them; the tree
// just stores them and hands them back from queries.
Tree :: struct($Leaf: typeid) {
	nodes:      []Tree_Node(Leaf),
	root, free: int,
	allocator:  mem.Allocator,
}

@(private)
Tree_Node :: struct($Leaf: typeid) {
	bounds:   AABB,
	parent:   int,
	children: [2]int,
	height:   int,
	leaf:     Leaf,
}

create_tree :: proc(
	$Leaf: typeid,
	capacity: int,
	allocator := context.allocator,
) -> (
	Tree(Leaf),
	Error,
) {
	if capacity <= 0 || capacity > (max(int) / size_of(Tree_Node(Leaf))) / 2 {
		return {}, .Invalid_Capacity
	}
	nodes, err := make([]Tree_Node(Leaf), capacity * 2 - 1, allocator)
	if err != .None {
		return {}, .Allocation_Failed
	}
	for &node, i in nodes {
		node.parent = i + 1 if i + 1 < len(nodes) else -1
		node.height = -1
	}
	return {nodes = nodes, root = -1, free = 0, allocator = allocator}, .None
}

destroy_tree :: proc(tree: ^Tree($Leaf)) {
	delete(tree.nodes, tree.allocator)
	tree^ = {}
}

// Returns the proxy index you'll need to move or destroy the leaf later.
create_proxy :: proc(tree: ^Tree($Leaf), bounds: AABB, leaf: Leaf) -> int {
	proxy := alloc_node(tree)
	tree.nodes[proxy].bounds = bounds
	tree.nodes[proxy].leaf = leaf
	insert_leaf(tree, proxy)
	return proxy
}

destroy_proxy :: proc(tree: ^Tree($Leaf), proxy: int) {
	remove_leaf(tree, proxy)
	free_node(tree, proxy)
}

// Leaves keep exact bounds, so any change reinserts the leaf. Returns true if
// the bounds changed.
move_proxy :: proc(tree: ^Tree($Leaf), proxy: int, bounds: AABB) -> bool {
	if tree.nodes[proxy].bounds == bounds {
		return false
	}
	remove_leaf(tree, proxy)
	tree.nodes[proxy].bounds = bounds
	insert_leaf(tree, proxy)
	return true
}

proxy_bounds :: proc(tree: ^Tree($Leaf), proxy: int) -> AABB {
	return tree.nodes[proxy].bounds
}

// Calls visit for every leaf whose bounds overlap. Return false from visit to
// stop.
query_tree :: proc(
	tree: ^Tree($Leaf),
	bounds: AABB,
	ctx: ^$Context,
	visit: proc(ctx: ^Context, leaf: Leaf) -> bool,
) {
	query_node(tree, tree.root, bounds, ctx, visit)
}

// Calls visit for leaves the ray reaches before the current limit, which starts
// at 1 (the end of displacement). visit returns the new limit.
raycast_tree :: proc(
	tree: ^Tree($Leaf),
	origin, displacement: emath.Vec3,
	ctx: ^$Context,
	visit: proc(ctx: ^Context, leaf: Leaf) -> f32,
) {
	limit := f32(1)
	raycast_node(tree, tree.root, origin, displacement, &limit, ctx, visit)
}

@(private)
query_node :: proc(
	tree: ^Tree($Leaf),
	index: int,
	bounds: AABB,
	ctx: ^$Context,
	visit: proc(ctx: ^Context, leaf: Leaf) -> bool,
) -> bool {
	if index == -1 {
		return true
	}
	node := &tree.nodes[index]
	if !bounds_overlap(bounds, node.bounds) {
		return true
	}
	if node.height > 0 {
		return(
			query_node(tree, node.children[0], bounds, ctx, visit) &&
			query_node(tree, node.children[1], bounds, ctx, visit) \
		)
	}
	return visit(ctx, node.leaf)
}

@(private)
raycast_node :: proc(
	tree: ^Tree($Leaf),
	index: int,
	origin, displacement: emath.Vec3,
	limit: ^f32,
	ctx: ^$Context,
	visit: proc(ctx: ^Context, leaf: Leaf) -> f32,
) {
	if index == -1 {
		return
	}
	node := &tree.nodes[index]
	if !ray_bounds(origin, displacement, node.bounds, limit^) {
		return
	}
	if node.height > 0 {
		raycast_node(tree, node.children[0], origin, displacement, limit, ctx, visit)
		raycast_node(tree, node.children[1], origin, displacement, limit, ctx, visit)
		return
	}
	limit^ = visit(ctx, node.leaf)
}

@(private)
alloc_node :: proc(tree: ^Tree($Leaf)) -> int {
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
free_node :: proc(tree: ^Tree($Leaf), index: int) {
	tree.nodes[index] = {
		parent = tree.free,
		height = -1,
	}
	tree.free = index
}

@(private)
insert_leaf :: proc(tree: ^Tree($Leaf), leaf: int) {
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
	parent := alloc_node(tree)
	tree.nodes[parent] = {
		parent   = old_parent,
		children = {sibling, leaf},
		bounds   = combine_bounds(bounds, tree.nodes[sibling].bounds),
		height   = tree.nodes[sibling].height + 1,
	}
	tree.nodes[sibling].parent = parent
	tree.nodes[leaf].parent = parent
	replace_child(tree, old_parent, sibling, parent)
	refit(tree, parent)
}

@(private)
remove_leaf :: proc(tree: ^Tree($Leaf), leaf: int) {
	if tree.root == leaf {
		tree.root = -1
		return
	}
	parent := tree.nodes[leaf].parent
	grandparent := tree.nodes[parent].parent
	sibling := tree.nodes[parent].children[1 if tree.nodes[parent].children[0] == leaf else 0]
	replace_child(tree, grandparent, parent, sibling)
	tree.nodes[sibling].parent = grandparent
	tree.nodes[leaf].parent = -1
	free_node(tree, parent)
	refit(tree, grandparent)
}

@(private)
replace_child :: proc(tree: ^Tree($Leaf), parent, old, replacement: int) {
	if parent == -1 {
		tree.root = replacement
	} else {
		children := &tree.nodes[parent].children
		children[0 if children[0] == old else 1] = replacement
	}
}

@(private)
recompute_node :: proc(tree: ^Tree($Leaf), index: int) {
	node := &tree.nodes[index]
	a, b := tree.nodes[node.children[0]], tree.nodes[node.children[1]]
	node.bounds = combine_bounds(a.bounds, b.bounds)
	node.height = 1 + max(a.height, b.height)
}

@(private)
refit :: proc(tree: ^Tree($Leaf), start: int) {
	index := start
	for index != -1 {
		recompute_node(tree, index)
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
			replace_child(tree, parent, index, promoted_index)
			promoted.parent = parent
			promoted.children[other] = index
			promoted.children[heavy] = tall
			node.parent = promoted_index
			node.children[heavy] = short
			tree.nodes[short].parent = index
			tree.nodes[tall].parent = promoted_index
			recompute_node(tree, index)
			recompute_node(tree, promoted_index)
			index = promoted_index
		}
		index = tree.nodes[index].parent
	}
}

@(private)
bounds_area :: proc(bounds: AABB) -> f64 {
	d := cast([3]f64)(bounds.max) - cast([3]f64)(bounds.min)
	return 2 * (d.x * d.y + d.y * d.z + d.z * d.x)
}

@(private)
ray_bounds :: proc(origin, displacement: emath.Vec3, bounds: AABB, limit: f32) -> bool {
	lo, hi := f64(0), f64(limit)
	for i in 0 ..< 3 {
		if displacement[i] == 0 {
			if origin[i] < bounds.min[i] || origin[i] > bounds.max[i] {
				return false
			}
			continue
		}
		a := (f64(bounds.min[i]) - f64(origin[i])) / f64(displacement[i])
		b := (f64(bounds.max[i]) - f64(origin[i])) / f64(displacement[i])
		lo, hi = max(lo, min(a, b)), min(hi, max(a, b))
		if lo > hi {
			return false
		}
	}
	return true
}

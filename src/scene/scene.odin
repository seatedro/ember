package scene

import emath "../core/math"
import "../core/pool"
import "../physics"

Object :: struct {
	index, generation: u32,
}

INVALID_OBJECT :: Object{}

Scene :: struct {
	objects: pool.Pool(Node, Object),
	physics: physics.World,
}

@(private)
Node :: struct {
	local:                                               emath.Mat4,
	body:                                                physics.Body_Handle,
	body_offset:                                         emath.Mat4,
	parent, first_child, previous_sibling, next_sibling: Object,
}

Reparent_Mode :: enum {
	Keep_World,
	Keep_Local,
}

Error :: enum {
	None,
	Invalid_Capacity,
	Allocation_Failed,
	Capacity_Exceeded,
	Invalid_Object,
	Invalid_Transform,
	Invalid_Mode,
	Cycle,
	Invalid_Body,
	Already_Bound,
	Physics_Controlled,
}

create :: proc(
	capacity: int,
	allocator := context.allocator,
	collider_capacity: int = 0,
) -> (
	Scene,
	Error,
) {
	objects, err := pool.create(Node, Object, capacity, allocator)
	switch err {
	case .Invalid_Capacity:
		return {}, .Invalid_Capacity
	case .Allocation_Failed:
		return {}, .Allocation_Failed
	case .None:
		world, physics_error := physics.create(capacity, allocator, collider_capacity)
		if physics_error != .None {
			pool.destroy(&objects)
			return {},
				.Invalid_Capacity if physics_error == .Invalid_Capacity else .Allocation_Failed
		}
		return {objects = objects, physics = world}, .None
	}

	unreachable()
}

destroy :: proc(scene: ^Scene) {
	physics.destroy(&scene.physics)
	for slot, index in scene.objects.slots {
		if slot.used {
			pool.free(&scene.objects, Object{index = u32(index), generation = slot.generation})
		}
	}
	pool.destroy(&scene.objects)
	scene^ = {}
}

create_object :: proc(
	scene: ^Scene,
	local: emath.Mat4 = emath.Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
	parent: Object = {},
) -> (
	Object,
	Error,
) {
	if parent != INVALID_OBJECT && !contains(scene, parent) {
		return {}, .Invalid_Object
	}
	if !emath.valid_affine(local) {
		return {}, .Invalid_Transform
	}

	object, node := pool.alloc(&scene.objects)
	if node == nil {
		return {}, .Capacity_Exceeded
	}

	node.local = local
	attach(scene, object, parent)
	return object, .None
}

contains :: proc(scene: ^Scene, object: Object) -> bool {
	return pool.get(&scene.objects, object) != nil
}

local_transform :: proc(scene: ^Scene, object: Object) -> (emath.Mat4, bool) {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return {}, false
	}

	if node.body.generation != 0 {
		world, ok := world_transform(scene, object)
		if !ok {
			return {}, false
		}
		return relative_transform(scene, node.parent, world)
	}

	return node.local, true
}

set_local_transform :: proc(scene: ^Scene, object: Object, local: emath.Mat4) -> Error {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return .Invalid_Object
	}
	if node.body.generation != 0 {
		return .Physics_Controlled
	}
	if !emath.valid_affine(local) {
		return .Invalid_Transform
	}

	node.local = local
	return .None
}

world_transform :: proc(scene: ^Scene, object: Object, alpha: f32 = 1) -> (emath.Mat4, bool) {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return {}, false
	}

	world := emath.identity()
	for {
		if node.body.generation != 0 {
			pose, ok := physics.body_pose(&scene.physics, node.body, alpha)
			if !ok {
				return {}, false
			}
			world = emath.pose_matrix(pose) * node.body_offset * world
			break
		}
		world = node.local * world
		if node.parent == INVALID_OBJECT {
			break
		}
		node = pool.get(&scene.objects, node.parent)
	}

	return world, emath.valid_affine(world)
}

parent :: proc(scene: ^Scene, object: Object) -> Object {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return {}
	}

	return node.parent
}

first_child :: proc(scene: ^Scene, object: Object) -> Object {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return {}
	}

	return node.first_child
}

next_sibling :: proc(scene: ^Scene, object: Object) -> Object {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return {}
	}

	return node.next_sibling
}

reparent :: proc(
	scene: ^Scene,
	object, new_parent: Object,
	mode: Reparent_Mode = .Keep_World,
) -> Error {
	node := pool.get(&scene.objects, object)
	if node == nil || (new_parent != INVALID_OBJECT && !contains(scene, new_parent)) {
		return .Invalid_Object
	}
	if mode != .Keep_World && mode != .Keep_Local {
		return .Invalid_Mode
	}

	for ancestor := new_parent; ancestor != INVALID_OBJECT; ancestor = parent(scene, ancestor) {
		if ancestor == object {
			return .Cycle
		}
	}
	if node.parent == new_parent {
		return .None
	}

	if node.body.generation != 0 && mode == .Keep_Local {
		return .Physics_Controlled
	}

	local := node.local
	if mode == .Keep_World {
		world, ok := world_transform(scene, object)
		if !ok {
			return .Invalid_Transform
		}
		local, ok = relative_transform(scene, new_parent, world)
		if !ok {
			return .Invalid_Transform
		}
	}

	detach(scene, object)
	attach(scene, object, new_parent)
	node.local = local
	return .None
}

destroy_object :: proc(scene: ^Scene, object: Object) -> Error {
	if !contains(scene, object) {
		return .Invalid_Object
	}

	current := object
	for {
		node := pool.get(&scene.objects, current)
		if node.first_child != INVALID_OBJECT {
			current = node.first_child
			continue
		}

		ancestor := node.parent
		if node.body.generation != 0 {
			physics.destroy_body(&scene.physics, node.body)
		}
		detach(scene, current)
		pool.free(&scene.objects, current)
		if current == object {
			break
		}
		current = ancestor
	}

	return .None
}

@(private)
attach :: proc(scene: ^Scene, object, parent: Object) {
	node := pool.get(&scene.objects, object)
	node.parent = parent
	if parent == INVALID_OBJECT {
		return
	}

	ancestor := pool.get(&scene.objects, parent)
	node.next_sibling = ancestor.first_child
	if sibling := pool.get(&scene.objects, node.next_sibling); sibling != nil {
		sibling.previous_sibling = object
	}
	ancestor.first_child = object
}

@(private)
detach :: proc(scene: ^Scene, object: Object) {
	node := pool.get(&scene.objects, object)
	if previous := pool.get(&scene.objects, node.previous_sibling); previous != nil {
		previous.next_sibling = node.next_sibling
	} else if ancestor := pool.get(&scene.objects, node.parent); ancestor != nil {
		ancestor.first_child = node.next_sibling
	}
	if next := pool.get(&scene.objects, node.next_sibling); next != nil {
		next.previous_sibling = node.previous_sibling
	}

	node.parent = {}
	node.previous_sibling = {}
	node.next_sibling = {}
}

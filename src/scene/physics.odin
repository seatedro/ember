package scene

import emath "../core/math"
import "../core/pool"
import "../physics"
import "core:math/linalg"

bind_body :: proc(scene: ^Scene, object: Object, body: physics.Body_Handle) -> Error {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return .Invalid_Object
	}
	position, orientation, valid_body := physics.body_position_and_orientation(
		&scene.physics,
		body,
	)
	if !valid_body {
		return .Invalid_Body
	}
	if node.body.generation != 0 {
		return .Already_Bound
	}
	for slot in scene.objects.slots {
		if slot.used && slot.value.body == body {
			return .Already_Bound
		}
	}

	world, ok := world_transform(scene, object)
	if !ok {
		return .Invalid_Transform
	}
	// Keep the rendered transform fixed relative to the body's center of mass.
	// Visual scale and shear don't affect the body's inertia.
	inverse_body := emath.rotation_matrix(conj(orientation)) * emath.translation(-position)
	offset := inverse_body * world
	if !emath.valid_affine(offset) {
		return .Invalid_Transform
	}

	node.body = body
	node.body_offset = offset
	return .None
}

remove_body :: proc(scene: ^Scene, object: Object) -> Error {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return .Invalid_Object
	}
	if node.body.generation == 0 {
		return .Invalid_Body
	}

	local, ok := local_transform(scene, object)
	if !ok {
		return .Invalid_Transform
	}
	physics.destroy_body(&scene.physics, node.body)
	node.body = {}
	node.body_offset = {}
	node.local = local
	return .None
}

object_body :: proc(scene: ^Scene, object: Object) -> physics.Body_Handle {
	node := pool.get(&scene.objects, object)
	if node == nil {
		return {}
	}

	return node.body
}

@(private)
relative_transform :: proc(
	scene: ^Scene,
	parent: Object,
	world: emath.Mat4,
) -> (
	emath.Mat4,
	bool,
) {
	if parent == INVALID_OBJECT {
		return world, emath.valid_affine(world)
	}

	parent_world, ok := world_transform(scene, parent)
	if !ok {
		return {}, false
	}
	inverse := linalg.inverse(parent_world)
	// Put the bottom row back to exactly 0, 0, 0, 1 after rounding in the
	// inverse.
	inverse[3, 0], inverse[3, 1], inverse[3, 2], inverse[3, 3] = 0, 0, 0, 1
	local := inverse * world
	return local, emath.valid_affine(local)
}

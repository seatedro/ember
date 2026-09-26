package physics

import emath "../core/math"
import "core:mem"
import "core:testing"

// A static floor with its top at y = 0.
@(private = "file")
create_floor :: proc(
	t: ^testing.T,
	world: ^World,
	position := emath.Vec3{0, -0.5, 0},
) -> Body_Handle {
	floor, err := create_body(
		world,
		{motion = .Static, state = {position = position, orientation = 1}},
	)
	testing.expect_value(t, err, Error.None)
	_, err = create_collider(world, floor, Box{{10, 0.5, 10}})
	testing.expect_value(t, err, Error.None)
	return floor
}

// A ball of radius 0.5. At height 0.5 it rests on the floor, and with no
// gravity it stays put.
@(private = "file")
create_ball :: proc(
	t: ^testing.T,
	world: ^World,
	position: emath.Vec3,
) -> (
	Body_Handle,
	Collider_Handle,
) {
	ball, err := create_body(
		world,
		{state = {position = position, orientation = 1}, mass = sphere_mass(1, 0.5)},
	)
	testing.expect_value(t, err, Error.None)
	collider: Collider_Handle
	collider, err = create_collider(world, ball, Sphere{0.5})
	testing.expect_value(t, err, Error.None)
	return ball, collider
}

// 49 balls fill a 49-pair cache. A map reserved for exactly 49 entries would
// grow on the 49th insert, because it resizes at 75% full.
@(test)
test_full_cache_does_not_allocate :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	world, err := create(50, mem.tracking_allocator(&track), contact_capacity = 49)
	testing.expect_value(t, err, Error.None)
	defer destroy(&world)
	create_floor(t, &world)
	for i in 0 ..< 49 {
		create_ball(t, &world, {f32(i % 7) * 1.5 - 4.5, 0.5, f32(i / 7) * 1.5 - 4.5})
	}

	allocations := track.total_allocation_count
	allocator := context.allocator
	context.allocator = mem.panic_allocator()
	for _ in 0 ..< 3 {
		testing.expect_value(t, step(&world, 1.0 / 60), Error.None)
	}
	context.allocator = allocator
	testing.expect_value(t, track.total_allocation_count, allocations)
	_, touching := contacts(&world, nil)
	testing.expect(t, touching == 49 && dropped_contacts(&world) == 0)
}

@(test)
test_failed_step_keeps_published_contacts :: proc(t: ^testing.T) {
	world, err := create(4)
	testing.expect_value(t, err, Error.None)
	defer destroy(&world)
	create_floor(t, &world)
	ball, _ := create_ball(t, &world, {0, 0.5, 0})
	testing.expect_value(t, step(&world, 1.0 / 60), Error.None)
	testing.expect_value(t, len(contact_events(&world)), 1)
	_, touching := contacts(&world, nil)
	testing.expect_value(t, touching, 1)

	// This body's position overflows, so the step fails after contacts were
	// already rebuilt.
	_, err = create_body(
		&world,
		{
			state = {position = {3e38, 0, 0}, orientation = 1, velocity = {3e38, 0, 0}},
			mass = sphere_mass(1, 0.5),
		},
	)
	testing.expect_value(t, err, Error.None)
	before, _ := body_state(&world, ball)
	testing.expect_value(t, step(&world, 1), Error.Invalid_Value)

	after, _ := body_state(&world, ball)
	testing.expect_value(t, after, before)
	events := contact_events(&world)
	testing.expect(t, len(events) == 1 && events[0].kind == .Begin)
	_, touching = contacts(&world, nil)
	testing.expect_value(t, touching, 1)
}

@(test)
test_full_cache_drops_new_pairs_and_retries :: proc(t: ^testing.T) {
	world, err := create(4, contact_capacity = 1)
	testing.expect_value(t, err, Error.None)
	defer destroy(&world)
	create_floor(t, &world)
	first, _ := create_ball(t, &world, {-2, 0.5, 0})
	_, second := create_ball(t, &world, {2, 0.5, 0})

	testing.expect_value(t, step(&world, 1.0 / 60), Error.None)
	testing.expect_value(t, dropped_contacts(&world), 1)
	testing.expect_value(t, step(&world, 1.0 / 60), Error.None)
	testing.expect_value(t, dropped_contacts(&world), 1)
	buffer: [2]Contact
	written, _ := contacts(&world, buffer[:])
	testing.expect(t, written == 1 && buffer[0].body_b == first)

	// Freeing a slot lets the dropped pair in, even though neither collider has
	// moved since.
	testing.expect(t, destroy_body(&world, first))
	testing.expect_value(t, step(&world, 1.0 / 60), Error.None)
	testing.expect_value(t, dropped_contacts(&world), 0)
	written, _ = contacts(&world, buffer[:])
	testing.expect(t, written == 1 && buffer[0].collider_b == second)
}

@(test)
test_filter_change_ends_contact :: proc(t: ^testing.T) {
	world, err := create(4)
	testing.expect_value(t, err, Error.None)
	defer destroy(&world)
	create_floor(t, &world)
	_, ball := create_ball(t, &world, {0, 0.5, 0})
	testing.expect_value(t, step(&world, 1.0 / 60), Error.None)

	testing.expect_value(
		t,
		set_collider_filter(&world, ball, {category = 1, mask = 0}),
		Error.None,
	)
	testing.expect_value(t, step(&world, 1.0 / 60), Error.None)
	events := contact_events(&world)
	testing.expect(t, len(events) == 1 && events[0].kind == .End)
	_, touching := contacts(&world, nil)
	testing.expect_value(t, touching, 0)
}

@(test)
test_teleported_static_body_finds_resting_body :: proc(t: ^testing.T) {
	world, err := create(4)
	testing.expect_value(t, err, Error.None)
	defer destroy(&world)
	floor := create_floor(t, &world, {0, -50, 0})
	create_ball(t, &world, {0, 0.5, 0})
	for _ in 0 ..< 3 {
		testing.expect_value(t, step(&world, 1.0 / 60), Error.None)
	}

	testing.expect_value(t, teleport(&world, floor, {0, -0.5, 0}, 1), Error.None)
	testing.expect_value(t, step(&world, 1.0 / 60), Error.None)
	events := contact_events(&world)
	testing.expect(t, len(events) == 1 && events[0].kind == .Begin)
}

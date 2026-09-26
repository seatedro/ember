package physics

import emath "../core/math"
import "../core/pool"
import "collision"
import "core:math"

Contact_Event_Kind :: enum {
	Begin,
	End,
}

// The handles might already be dead by the time you read this. A destroyed
// collider gets its End event on the next step.
Contact_Event :: struct {
	kind:                   Contact_Event_Kind,
	body_a, body_b:         Body_Handle,
	collider_a, collider_b: Collider_Handle,
	sensor:                 bool,
}

// The normal points from A to B. Separation is negative while they overlap.
// Impulse is how hard this point pushed during the last step.
Contact :: struct {
	body_a, body_b:         Body_Handle,
	collider_a, collider_b: Collider_Handle,
	position, normal:       emath.Vec3,
	separation, impulse:    f32,
	sensor:                 bool,
}

// a is always the collider with the lower index.
@(private)
Pair_Key :: struct {
	a, b: Collider_Handle,
}

// What we remember about a point between steps: where it sits on each body and
// the impulses it had, so we can start from them if we find it again.
@(private)
Cached_Point :: struct {
	local_a, local_b: emath.Vec3,
	separation:       f32,
	normal_impulse:   f32,
	tangent_impulse:  [2]f32,
}

// A manifold lives while the two colliders' expanded bounds overlap. It's
// touching while it has points, and events fire when that changes.
@(private)
Cached_Manifold :: struct {
	key:                   Pair_Key,
	body_a, body_b:        Body_Handle,
	normal:                emath.Vec3,
	friction, restitution: f32,
	points:                [collision.MANIFOLD_CAPACITY]Cached_Point,
	count:                 int,
	sensor, touching:      bool,
}

// Each pair sends at most one event per step, and a step only sees the pairs in
// the two caches, so twice the manifold capacity is always enough room for
// events.
@(private)
Contact_Cache :: struct {
	manifolds:      []Cached_Manifold,
	manifold_count: int,
	events:         []Contact_Event,
	event_count:    int,
	dropped:        int,
}

// One collider looking for new partners.
@(private)
Pair_Search :: struct {
	world:   ^World,
	cache:   ^Contact_Cache,
	first:   Collider_Handle,
	dropped: bool,
}

contact_events :: proc(world: ^World) -> []Contact_Event {
	cache := published_cache(world)
	return cache.events[:cache.event_count]
}

// How many overlapping pairs the last step had no room for. Those pairs don't
// collide until space frees up. If this isn't zero, raise contact_capacity.
dropped_contacts :: proc(world: ^World) -> int {
	return published_cache(world).dropped
}

// Results come in no particular order. total also counts contacts that didn't
// fit in output.
contacts :: proc(world: ^World, output: []Contact) -> (written, total: int) {
	cache := published_cache(world)
	for &manifold in cache.manifolds[:cache.manifold_count] {
		body_a := pool.get(&world.bodies, manifold.body_a)
		body_b := pool.get(&world.bodies, manifold.body_b)
		if !manifold.touching || body_a == nil || body_b == nil {
			continue
		}

		for point in manifold.points[:manifold.count] {
			if total < len(output) {
				a := emath.transform_point(
					body_a.state.position,
					body_a.state.orientation,
					point.local_a,
				)
				b := emath.transform_point(
					body_b.state.position,
					body_b.state.orientation,
					point.local_b,
				)
				output[total] = {
					body_a     = manifold.body_a,
					body_b     = manifold.body_b,
					collider_a = manifold.key.a,
					collider_b = manifold.key.b,
					position   = (a + b) * 0.5,
					normal     = manifold.normal,
					separation = point.separation,
					impulse    = point.normal_impulse,
					sensor     = manifold.sensor,
				}
			}
			total += 1
		}
	}
	return min(len(output), total), total
}

@(private)
published_cache :: proc(world: ^World) -> ^Contact_Cache {
	return &world.caches[world.published]
}

@(private)
unpublished_cache :: proc(world: ^World) -> ^Contact_Cache {
	return &world.caches[1 - world.published]
}

// Builds this step's manifolds in the spare cache. Pairs from last step carry
// over while they still overlap, then colliders with a pending search look for
// new partners. Old pairs go in first, so a full cache drops new pairs, never
// existing ones.
@(private)
update_contacts :: proc(world: ^World) {
	read := published_cache(world)
	write := unpublished_cache(world)
	write.manifold_count, write.event_count, write.dropped = 0, 0, 0
	scratch := &world.scratch
	clear(&scratch.pair_index)
	scratch.searched_count = 0

	for &previous in read.manifolds[:read.manifold_count] {
		a := pool.get(&world.colliders, previous.key.a)
		b := pool.get(&world.colliders, previous.key.b)
		if a != nil && b != nil {
			_, pairs := should_pair(world, a, b)
			if pairs &&
			   collision.bounds_overlap(collider_bounds(world, a), collider_bounds(world, b)) {
				manifold := add_manifold(world, write, previous)
				refresh_manifold(world, write, manifold, a, b, previous.points[:previous.count])
				continue
			}
		}

		if previous.touching {
			push_event(write, &previous, .End)
		}
	}

	first_found := write.manifold_count
	for &slot, index in world.colliders.slots {
		if !slot.used || !slot.value.pending_pair_search {
			continue
		}
		search := Pair_Search {
			world = world,
			cache = write,
			first = Collider_Handle{u32(index), slot.generation},
		}
		collision.query_tree(&world.tree, collider_bounds(world, &slot.value), &search, add_pair)
		if !search.dropped {
			scratch.searched[scratch.searched_count] = search.first
			scratch.searched_count += 1
		}
	}

	for &manifold in write.manifolds[first_found:write.manifold_count] {
		a := pool.get(&world.colliders, manifold.key.a)
		b := pool.get(&world.colliders, manifold.key.b)
		refresh_manifold(world, write, &manifold, a, b, nil)
	}
}

@(private)
collider_bounds :: proc(world: ^World, collider: ^Collider) -> collision.AABB {
	return collision.expanded_bounds(
		collision.proxy_bounds(&world.tree, collider.proxy),
		world.settings.speculative_distance,
	)
}

// Some pairs can never respond, so they get no manifold: two colliders on one
// body, filters that don't match, two sensors, a sensor between static bodies,
// or two solid colliders where neither is dynamic.
@(private)
should_pair :: proc(world: ^World, a, b: ^Collider) -> (sensor: bool, pairs: bool) {
	if a.state.body == b.state.body ||
	   !filters_match(a.state.filter, b.state.filter) ||
	   (a.state.sensor && b.state.sensor) {
		return false, false
	}

	motion_a := pool.get(&world.bodies, a.state.body).motion
	motion_b := pool.get(&world.bodies, b.state.body).motion
	if a.state.sensor || b.state.sensor {
		return true, motion_a != .Static || motion_b != .Static
	}
	return false, motion_a == .Dynamic || motion_b == .Dynamic
}

// If both colliders are searching, only the one with the lower index records
// the pair, so it's added or dropped once.
@(private)
add_pair :: proc(search: ^Pair_Search, other: Collider_Handle) -> bool {
	world := search.world
	if other == search.first {
		return true
	}
	if pool.get(&world.colliders, other).pending_pair_search && other.index < search.first.index {
		return true
	}
	key := Pair_Key{search.first, other}
	if other.index < search.first.index {
		key = {other, search.first}
	}
	if key in world.scratch.pair_index {
		return true
	}
	a := pool.get(&world.colliders, key.a)
	b := pool.get(&world.colliders, key.b)
	sensor, pairs := should_pair(world, a, b)
	if !pairs {
		return true
	}

	cache := search.cache
	if cache.manifold_count == len(cache.manifolds) {
		cache.dropped += 1
		search.dropped = true
		return true
	}
	add_manifold(
		world,
		cache,
		{key = key, body_a = a.state.body, body_b = b.state.body, sensor = sensor},
	)
	return true
}

@(private)
add_manifold :: proc(
	world: ^World,
	cache: ^Contact_Cache,
	manifold: Cached_Manifold,
) -> ^Cached_Manifold {
	index := cache.manifold_count
	cache.manifolds[index] = manifold
	cache.manifold_count += 1
	world.scratch.pair_index[manifold.key] = index
	return &cache.manifolds[index]
}

// The points are rebuilt every step. A point that lands where an old one was
// takes over its impulses for warm starting. If the narrowphase can't resolve
// the pair this step, we treat it as separated.
@(private)
refresh_manifold :: proc(
	world: ^World,
	cache: ^Contact_Cache,
	manifold: ^Cached_Manifold,
	a, b: ^Collider,
	previous: []Cached_Point,
) {
	body_a := pool.get(&world.bodies, a.state.body)
	body_b := pool.get(&world.bodies, b.state.body)
	position_a, orientation_a := collider_placement(
		a,
		body_a.state.position,
		body_a.state.orientation,
	)
	position_b, orientation_b := collider_placement(
		b,
		body_b.state.position,
		body_b.state.orientation,
	)
	max_separation := f32(0) if manifold.sensor else world.settings.speculative_distance
	found, err := collision.collide(
		a.state.shape,
		position_a,
		orientation_a,
		b.state.shape,
		position_b,
		orientation_b,
		max_separation,
	)
	if err != .None {
		found = {}
	}

	manifold.normal = found.normal
	manifold.count = found.count
	manifold.friction = math.sqrt(a.state.material.friction * b.state.material.friction)
	manifold.restitution = max(a.state.material.restitution, b.state.material.restitution)

	radius_sq := world.settings.warm_start_distance * world.settings.warm_start_distance
	claimed: [collision.MANIFOLD_CAPACITY]bool
	for point, i in found.points[:found.count] {
		cached := Cached_Point {
			local_a    = emath.inverse_transform_point(
				body_a.state.position,
				body_a.state.orientation,
				point.a,
			),
			local_b    = emath.inverse_transform_point(
				body_b.state.position,
				body_b.state.orientation,
				point.b,
			),
			separation = point.separation,
		}
		for old, j in previous {
			if claimed[j] ||
			   distance_sq(old.local_a, cached.local_a) > radius_sq ||
			   distance_sq(old.local_b, cached.local_b) > radius_sq {
				continue
			}
			cached.normal_impulse = old.normal_impulse
			cached.tangent_impulse = old.tangent_impulse
			claimed[j] = true
			break
		}
		manifold.points[i] = cached
	}

	touching := manifold.count > 0
	if touching != manifold.touching {
		manifold.touching = touching
		push_event(cache, manifold, .Begin if touching else .End)
	}
}

@(private)
push_event :: proc(cache: ^Contact_Cache, manifold: ^Cached_Manifold, kind: Contact_Event_Kind) {
	cache.events[cache.event_count] = {
		kind       = kind,
		body_a     = manifold.body_a,
		body_b     = manifold.body_b,
		collider_a = manifold.key.a,
		collider_b = manifold.key.b,
		sensor     = manifold.sensor,
	}
	cache.event_count += 1
}

@(private)
distance_sq :: proc(a, b: emath.Vec3) -> f32 {
	delta := b - a
	return emath.dot(delta, delta)
}

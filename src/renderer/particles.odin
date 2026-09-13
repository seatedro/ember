package renderer

import "../particles"

append_particle_billboards :: proc(
	list: ^[dynamic]Billboard,
	emitter: ^particles.Emitter,
) -> Error {
	first := len(list)
	if emitter.count > max(int) - first {
		return .Invalid_Size
	}

	if err := resize(list, first + emitter.count); err != .None {
		return .Allocation_Failed
	}

	index := first
	for particle in emitter.particles {
		if !particle.active {
			continue
		}
		size, color := particles.appearance(particle)
		list[index] = {
			position = particle.position,
			size     = {size, size},
			rotation = particle.rotation,
			color    = color,
		}

		index += 1
	}

	return .None
}

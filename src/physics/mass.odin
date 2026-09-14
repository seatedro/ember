package physics

import emath "../core/math"
import "core:math/linalg"

Mass_Properties :: struct {
	mass:    f32,
	inertia: matrix[3, 3]f32,
}

sphere_mass :: proc(mass, radius: f32) -> Mass_Properties {
	assert(mass > 0 && radius > 0)
	moment := 0.4 * mass * radius * radius
	return {mass = mass, inertia = {moment, 0, 0, 0, moment, 0, 0, 0, moment}}
}

box_mass :: proc(mass: f32, half_extent: emath.Vec3) -> Mass_Properties {
	assert(mass > 0 && half_extent.x > 0 && half_extent.y > 0 && half_extent.z > 0)
	squared := half_extent * half_extent
	moments :=
		mass / 3 * emath.Vec3{squared.y + squared.z, squared.x + squared.z, squared.x + squared.y}
	return {mass = mass, inertia = {moments.x, 0, 0, 0, moments.y, 0, 0, 0, moments.z}}
}

@(private)
valid_mass :: proc(properties: Mass_Properties) -> bool {
	if !finite(properties.mass) || properties.mass <= 0 {
		return false
	}

	m := properties.inertia
	for row in 0 ..< 3 {
		for column in 0 ..< 3 {
			if !finite(m[row, column]) || m[row, column] != m[column, row] {
				return false
			}
		}
	}
	// Sylvester's criterion: a symmetric inertia tensor must be positive definite.
	determinant := linalg.determinant(m)
	return(
		m[0, 0] > 0 &&
		m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0] > 0 &&
		determinant > 0 &&
		finite(determinant) \
	)
}

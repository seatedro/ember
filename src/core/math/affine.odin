package ember_math

import "core:math"
import "core:math/linalg"

// Hierarchies can add shear, so we keep full affine matrices. The determinant
// has to be positive: a flip would break triangle winding, and a singular
// matrix has no inverse for normals or reparenting.
valid_affine :: proc(model: Mat4) -> bool {
	for row in 0 ..< 4 {
		for column in 0 ..< 4 {
			value := model[row, column]
			if math.is_nan(value) || math.is_inf(value) {
				return false
			}
		}
	}
	if model[3, 0] != 0 || model[3, 1] != 0 || model[3, 2] != 0 || model[3, 3] != 1 {
		return false
	}

	determinant := linalg.determinant(model)
	return determinant > 0 && !math.is_inf(determinant)
}

transform_sphere_matrix :: proc(sphere: Bounding_Sphere, model: Mat4) -> Bounding_Sphere {
	center := model * Vec4{sphere.center.x, sphere.center.y, sphere.center.z, 1}
	// The largest row sum of |A^T A| bounds its biggest eigenvalue. Its square
	// root bounds how far the matrix can stretch a vector, and it's exact when
	// the axes are orthogonal.
	linear: Mat3
	for row in 0 ..< 3 {
		for column in 0 ..< 3 {
			linear[row, column] = model[row, column]
		}
	}
	gram := linalg.transpose(linear) * linear
	stretch_squared: f32
	for row in 0 ..< 3 {
		stretch_squared = max(
			stretch_squared,
			abs(gram[row, 0]) + abs(gram[row, 1]) + abs(gram[row, 2]),
		)
	}

	return {center = Vec3(center.xyz), radius = sphere.radius * math.sqrt(stretch_squared)}
}

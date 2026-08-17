package ember_math

import stdmath "core:math"
Vec3 :: distinct [3]f32

/*
	dot - Computes the dot product of two 3D vectors.

	The dot product a · b yields a scalar equal to the sum of the products
	of the corresponding components. Its value equals
	|a| * |b| * cos(theta), which is also the signed length of the
	projection of `a` onto `b` scaled by |b|.

	It is the sum of the component-wise products:

	a . b = a.x*b.x + a.y*b.y + a.z*b.z

	or as a matrix product using the transpose (row vector) of `a`:

	a . b = a^T b = [a.x  a.y  a.z]   *   | b.y |

*/
dot :: proc(a, b: Vec3) -> f32 {
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

/*
 cross - Computes the cross product of two 3D vectors.

 The cross product a × b yields a vector that is perpendicular to both
 `a` and `b`, following the right-hand rule. Its magnitude equals
 |a| * |b| * sin(theta), which is also the area of the parallelogram
 spanned by the two vectors.

 Each component is the 2x2 determinant of the other two axes:

	        | i     j     k   |
	a x b = | a.x   a.y   a.z |
	        | b.x   b.y   b.z |

 or as a matrix-vector product using the skew-symmetric matrix of `a`:

              		  |  0    -a.z   a.y |   | b.x |
    a x b = [a]_x b = |  a.z   0    -a.x | * | b.y |
              		  | -a.y   a.x   0   |   | b.z |
*/
cross :: proc(a, b: Vec3) -> Vec3 {
	return Vec3{a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}
}

/*
	length - Computes the length (magnitude) of a 3D vector.
*/
length :: proc(v: Vec3) -> f32 {
	return stdmath.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
}

/*
	normalize - Normalizes a 3D vector, returning a unit vector in the same direction.

	The normalized vector v_hat is obtained by dividing each component of `v`
	by its length |v|, producing a vector of length 1 that preserves the
	original direction:

	v_hat = v / |v| = { v.x/|v|, v.y/|v|, v.z/|v| }

	where |v| = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)

	If |v| is zero (or near zero), the vector has no direction and cannot be
	normalized; the zero vector is returned in that case.
*/

normalize :: proc(v: Vec3) -> Vec3 {
	len := length(v)
	assert(len != 0, "Cannot normalize zero vector")
	return Vec3{v[0] / len, v[1] / len, v[2] / len}
}

/*
	normalize_or_zero - Normalizes a 3D vector, returning a unit vector in the same direction,
	or the zero vector if the input is zero-length.
*/
normalize_or_zero :: proc(v: Vec3) -> Vec3 {
	len := length(v)
	if len == 0 {
		return Vec3{}
	}
	return Vec3{v[0] / len, v[1] / len, v[2] / len}
}

package ember_math

import stdmath "core:math"
import glm "core:math/linalg/glsl"
import "core:testing"

EPSILON :: f32(0.00001)

approximately_equal :: proc(a, b: f32) -> bool {
	return stdmath.abs(a - b) <= EPSILON
}

expect_f32_approximately_equal :: proc(t: ^testing.T, actual, expected: f32) {
	testing.expectf(
		t,
		approximately_equal(actual, expected),
		"expected %v, got %v",
		expected,
		actual,
	)
}

expect_vec3_approximately_equal :: proc(t: ^testing.T, actual, expected: Vec3) {
	for component in 0 ..< 3 {
		testing.expectf(
			t,
			approximately_equal(actual[component], expected[component]),
			"component %d: expected %v, got %v",
			component,
			expected[component],
			actual[component],
		)
	}
}

@(test)
test_dot :: proc(t: ^testing.T) {
	a := Vec3{1, 2, 3}
	b := Vec3{4, 5, 6}

	result := dot(a, b)

	testing.expectf(t, result == 32, "expected 32, got %f", result)
}

@(test)
test_cross_basis_vectors :: proc(t: ^testing.T) {
	a := Vec3{1, 0, 0}
	b := Vec3{0, 1, 0}

	result := cross(a, b)

	testing.expectf(t, result == Vec3{0, 0, 1}, "expected (0, 0, 1), got %v", result)
}

@(test)
test_normalize :: proc(t: ^testing.T) {
	vec := Vec3{0, 3, 4}
	normalized := normalize(vec)

	expected := Vec3{0, 0.6, 0.8}
	expect_vec3_approximately_equal(t, normalized, expected)
}

@(test)
test_length :: proc(t: ^testing.T) {
	result := length(Vec3{3, 4, 0})

	expect_f32_approximately_equal(t, result, 5)
}

@(test)
test_normalize_or_zero :: proc(t: ^testing.T) {
	zero := normalize_or_zero(Vec3{})
	normalized := normalize_or_zero(Vec3{0, 3, 4})

	testing.expect_value(t, zero, Vec3{})
	expect_vec3_approximately_equal(t, normalized, Vec3{0, 0.6, 0.8})
}

@(test)
test_cross_is_perpendicular :: proc(t: ^testing.T) {
	a := Vec3{2, 3, 4}
	b := Vec3{5, 6, 7}
	result := cross(a, b)

	expect_f32_approximately_equal(t, dot(result, a), 0)
	expect_f32_approximately_equal(t, dot(result, b), 0)
}

@(test)
test_dot_matches_glsl :: proc(t: ^testing.T) {
	a := Vec3{2, 3, 4}
	b := Vec3{5, 6, 7}

	actual := dot(a, b)
	oracle := glm.dot(glm.vec3(a), glm.vec3(b))

	expect_f32_approximately_equal(t, actual, oracle)
}

@(test)
test_cross_matches_glsl :: proc(t: ^testing.T) {
	a := Vec3{2, 3, 4}
	b := Vec3{5, 6, 7}

	actual := cross(a, b)
	oracle := glm.cross(glm.vec3(a), glm.vec3(b))

	expect_vec3_approximately_equal(t, actual, Vec3(oracle))
}

@(test)
test_length_matches_glsl :: proc(t: ^testing.T) {
	value := Vec3{2, 3, 4}

	actual := length(value)
	oracle := glm.length(glm.vec3(value))

	expect_f32_approximately_equal(t, actual, oracle)
}

@(test)
test_normalize_matches_glsl :: proc(t: ^testing.T) {
	value := Vec3{2, 3, 4}

	actual := normalize(value)
	oracle := glm.normalize(glm.vec3(value))

	expect_vec3_approximately_equal(t, actual, Vec3(oracle))
}

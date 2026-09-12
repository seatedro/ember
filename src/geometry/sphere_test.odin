package geometry

import emath "../core/math"
import "core:testing"

@(test)
test_sphere_topology_and_normals :: proc(t: ^testing.T) {
	for resolution in ([3][2]int{{3, 2}, {16, 8}, {48, 24}}) {
		segments, stacks := resolution[0], resolution[1]
		mesh, err := create_sphere(segments, stacks, 1.5)
		testing.expect_value(t, err, Sphere_Error.None)
		if err != .None {
			return
		}
		defer destroy_sphere(&mesh)
		testing.expect_value(t, len(mesh.vertices), 2 + segments * (stacks - 1))
		testing.expect_value(t, len(mesh.indices), 6 * segments * (stacks - 1))

		for vertex in mesh.vertices {
			position := emath.Vec3(vertex.position)
			normal := emath.Vec3(vertex.normal)
			testing.expect(t, abs(emath.length(position) - 1.5) < 0.00001)
			testing.expect(t, abs(emath.length(normal) - 1) < 0.00001)
			testing.expect(t, abs(emath.dot(position, normal) - 1.5) < 0.00001)
		}

		edges := make(map[u64]int)
		defer delete(edges)
		for i := 0; i < len(mesh.indices); i += 3 {
			triangle := mesh.indices[i:i + 3]
			for index in triangle {
				testing.expect(t, int(index) < len(mesh.vertices))
			}
			a := emath.Vec3(mesh.vertices[triangle[0]].position)
			b := emath.Vec3(mesh.vertices[triangle[1]].position)
			c := emath.Vec3(mesh.vertices[triangle[2]].position)
			face_normal := emath.cross(b - a, c - a)
			testing.expect(t, emath.dot(face_normal, a + b + c) > 0)

			for edge in 0 ..< 3 {
				first, second := triangle[edge], triangle[(edge + 1) % 3]
				key := u64(min(first, second)) << 32 | u64(max(first, second))
				edges[key] += 1
			}
		}
		for _, count in edges {
			testing.expect_value(t, count, 2)
		}
		testing.expect_value(t, len(mesh.vertices) - len(edges) + len(mesh.indices) / 3, 2)
	}
}

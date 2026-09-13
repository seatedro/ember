package geometry

import emath "../core/math"
import "core:math"
import "core:testing"

@(test)
test_sphere_topology_normals_and_uvs :: proc(t: ^testing.T) {
	for resolution in ([3][2]int{{3, 2}, {16, 8}, {48, 24}}) {
		segments, stacks := resolution[0], resolution[1]
		mesh, err := create_sphere(segments, stacks, 1.5)
		testing.expect_value(t, err, Sphere_Error.None)
		if err != .None {
			return
		}

		defer destroy_sphere(&mesh)
		testing.expect_value(t, len(mesh.vertices), 2 * segments + (segments + 1) * (stacks - 1))
		testing.expect_value(t, len(mesh.indices), 6 * segments * (stacks - 1))

		for vertex in mesh.vertices {
			position := emath.Vec3(vertex.position)
			normal := emath.Vec3(vertex.normal)
			testing.expect(t, abs(emath.length(position) - 1.5) < 0.00001)
			testing.expect(t, abs(emath.length(normal) - 1) < 0.00001)
			testing.expect(t, abs(emath.dot(position, normal) - 1.5) < 0.00001)
		}

		positions := make(map[[3]f32]u32)
		defer delete(positions)
		welded := make([]u32, len(mesh.vertices))
		defer delete(welded)
		for vertex, i in mesh.vertices {
			id, found := positions[vertex.position]
			if !found {
				id = u32(len(positions))
				positions[vertex.position] = id
			}
			welded[i] = id

			u, v := vertex.uv.x, vertex.uv.y
			testing.expect(t, u >= 0 && u <= 1 && v >= 0 && v <= 1)
			theta := f32(math.PI) * v
			phi := f32(2 * math.PI) * (u - 0.5)
			expected := emath.Vec3 {
				math.sin(theta) * math.cos(phi),
				math.cos(theta),
				math.sin(theta) * math.sin(phi),
			}
			testing.expect(t, emath.length(emath.Vec3(vertex.normal) - expected) < 0.00001)
		}

		for ring in 0 ..< stacks - 1 {
			first := segments + ring * (segments + 1)
			left, right := mesh.vertices[first], mesh.vertices[first + segments]
			testing.expect_value(t, left.position, right.position)
			testing.expect_value(t, left.normal, right.normal)
			testing.expect_value(t, left.uv.x, f32(0))
			testing.expect_value(t, right.uv.x, f32(1))
			testing.expect_value(t, left.uv.y, right.uv.y)
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

			u0 := mesh.vertices[triangle[0]].uv.x
			u1 := mesh.vertices[triangle[1]].uv.x
			u2 := mesh.vertices[triangle[2]].uv.x
			testing.expect(t, max(u0, u1, u2) - min(u0, u1, u2) <= 1 / f32(segments) + 0.00001)

			for edge in 0 ..< 3 {
				first, second := welded[triangle[edge]], welded[triangle[(edge + 1) % 3]]
				key := u64(min(first, second)) << 32 | u64(max(first, second))
				edges[key] += 1
			}
		}

		for _, count in edges {
			testing.expect_value(t, count, 2)
		}

		testing.expect_value(t, len(positions) - len(edges) + len(mesh.indices) / 3, 2)
	}
}

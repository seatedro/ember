package geometry

Quad_Mesh :: struct {
	vertices: [4]Vertex,
	indices:  [6]u32,
}

create_quad :: proc() -> Quad_Mesh {
	return {
		vertices = {
			{{-1, -1, 0}, {0, 0, 1}, {0, 0}},
			{{1, -1, 0}, {0, 0, 1}, {1, 0}},
			{{1, 1, 0}, {0, 0, 1}, {1, 1}},
			{{-1, 1, 0}, {0, 0, 1}, {0, 1}},
		},
		indices = {0, 1, 2, 0, 2, 3},
	}
}

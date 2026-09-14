package geometry

Vertex :: struct {
	position:  [3]f32,
	normal:    [3]f32,
	uv:        [2]f32,
	tangent:   [3]f32,
	bitangent: [3]f32,
}

Color_Vertex :: struct {
	position: [3]f32,
	color:    [3]f32,
}

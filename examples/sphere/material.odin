package game

// vec4 keeps the colors aligned with the shader's std140 Material block.
Banded_Parameters :: struct {
	color_a, color_b: [4]f32,
}

BANDED_PALETTES :: [2]Banded_Parameters {
	{{1, 1, 1, 1}, {1, 1, 1, 1}},
	{{0.12, 0.55, 0.35, 1}, {0.65, 0.18, 0.48, 1}},
}

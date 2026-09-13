package renderer

import "../geometry"

VERTEX_LAYOUT :: Vertex_Layout {
	stride = size_of(geometry.Vertex),
	attribute_count = 3,
	attributes = {
		0 = {location = 0, format = .F32x3, offset = u32(offset_of(geometry.Vertex, position))},
		1 = {location = 1, format = .F32x3, offset = u32(offset_of(geometry.Vertex, normal))},
		2 = {location = 2, format = .F32x2, offset = u32(offset_of(geometry.Vertex, uv))},
	},
}

COLOR_VERTEX_LAYOUT :: Vertex_Layout {
	stride = size_of(geometry.Color_Vertex),
	attribute_count = 2,
	attributes = {
		0 = {
			location = 0,
			format = .F32x3,
			offset = u32(offset_of(geometry.Color_Vertex, position)),
		},
		1 = {location = 1, format = .F32x3, offset = u32(offset_of(geometry.Color_Vertex, color))},
	},
}

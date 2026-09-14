package rhi_types

Error :: enum {
	None,
	Device_Not_Initialized,
	Invalid_Capacity,
	Allocation_Failed,
	Wrong_Context,
	Unsupported_Backend,
	Backend_Failed,
	Invalid_Size,
	Invalid_Usage,
	Unsupported_Usage,
	Unsupported_Memory,
	Initial_Data_Too_Large,
	Pool_Exhausted,
	Invalid_Handle,
	Invalid_Shader_Source,
	Unsupported_Shader_Stage,
	Unsupported_Shader_Language,
	Invalid_Shader_Entry_Point,
	Shader_Compile_Failed,
	Pipeline_Link_Failed,
	Invalid_Vertex_Layout,
	Invalid_Pipeline_State,
	Invalid_Buffer_Binding,
	Invalid_Draw,
	Invalid_Buffer_Range,
	Invalid_Uniform_Binding,
	Invalid_Texture,
	Invalid_Texture_Binding,
	Invalid_Pass,
	Invalid_Frame,
	Surface_Unavailable,
	Resource_In_Use,
	Feedback_Loop,
}

Texture_Format :: enum {
	RGBA8,
	RGBA8_SRGB,
	RGBA16F,
	Depth32F,
}

Texture_Filter :: enum {
	Linear,
	Nearest,
}

Texture_Wrap :: enum {
	Repeat,
	Clamp,
}

Texture_Kind :: enum {
	Image_2D,
	Cube,
}

Texture_Desc :: struct {
	kind:           Texture_Kind,
	mip_levels:     u32,
	width, height:  i32,
	format:         Texture_Format,
	filter:         Texture_Filter,
	wrap_u, wrap_v: Texture_Wrap,
	label:          string,
}

Buffer_Usage :: enum {
	Vertex,
	Index,
	Uniform,
	Storage,
	Indirect,
	Copy_Source,
	Copy_Destination,
}

Buffer_Usages :: bit_set[Buffer_Usage]

Memory_Preference :: enum {
	GPU,
	Upload,
	Readback,
}

Buffer_Desc :: struct {
	size:              u64,
	usage:             Buffer_Usages,
	memory_preference: Memory_Preference,
	label:             string,
}

Shader_Stage :: enum {
	Vertex,
	Fragment,
}

Shader_Handle :: struct {
	index:      u32,
	generation: u32,
}

Shader_Language :: enum {
	GLSL,
	MSL,
}

Shader_Source :: struct {
	code:        string,
	entry_point: string,
}

Shader_Desc :: struct {
	stage:    Shader_Stage,
	language: Shader_Language,
	source:   Shader_Source,
	label:    string,
}

MAX_VERTEX_ATTRIBUTES :: 16

Vertex_Format :: enum {
	F32,
	F32x2,
	F32x3,
	F32x4,
}

Vertex_Attribute :: struct {
	location: u32,
	format:   Vertex_Format,
	offset:   u32,
}

Vertex_Layout :: struct {
	attributes:      [MAX_VERTEX_ATTRIBUTES]Vertex_Attribute,
	attribute_count: u32,
	stride:          u32,
}

Compare :: enum {
	Less,
	Less_Equal,
	Equal,
	Greater,
	Greater_Equal,
	Not_Equal,
	Never,
	Always,
}

Cull_Mode :: enum {
	None,
	Back,
	Front,
}

Winding :: enum {
	CCW,
	CW,
}

Primitive :: enum {
	Triangles,
	Lines,
	Points,
}

Index_Type :: enum {
	U16,
	U32,
}

Depth_State :: struct {
	test_enabled:  bool,
	write_enabled: bool,
	compare:       Compare,
}

Raster_State :: struct {
	cull:      Cull_Mode,
	winding:   Winding,
	wireframe: bool,
}

Blend_Factor :: enum {
	Zero,
	One,
	Src_Color,
	One_Minus_Src_Color,
	Dst_Color,
	One_Minus_Dst_Color,
	Src_Alpha,
	One_Minus_Src_Alpha,
	Dst_Alpha,
	One_Minus_Dst_Alpha,
}

Blend_Op :: enum {
	Add,
	Subtract,
	Reverse_Subtract,
	Min,
	Max,
}

Blend_State :: struct {
	enabled:          bool,
	src_factor_rgb:   Blend_Factor,
	dst_factor_rgb:   Blend_Factor,
	op_rgb:           Blend_Op,
	src_factor_alpha: Blend_Factor,
	dst_factor_alpha: Blend_Factor,
	op_alpha:         Blend_Op,
}

Pipeline_Settings :: struct {
	depth_only:      bool,
	layout:          Vertex_Layout,
	instance_layout: Vertex_Layout,
	depth:           Depth_State,
	raster:          Raster_State,
	blend:           Blend_State,
	primitive:       Primitive,
}

Pipeline_Desc :: struct {
	vertex_shader:   Shader_Handle,
	fragment_shader: Shader_Handle,
	settings:        Pipeline_Settings,
	label:           string,
	uniform_blocks:  []Uniform_Block_Desc,
	textures:        []Texture_Binding_Desc,
}

MAX_TEXTURE_BINDINGS :: 8

Texture_Binding_Desc :: struct {
	name:    string,
	binding: u32,
}

MAX_UNIFORM_BINDINGS :: 8

Uniform_Block_Desc :: struct {
	name:    string,
	binding: u32,
}

// Shader resource requirements reported by a backend after pipeline creation.
// A zero uniform size or false texture flag means the binding is unused.
Pipeline_Requirements :: struct {
	uniform_sizes:    [MAX_UNIFORM_BINDINGS]u64,
	texture_bindings: [MAX_TEXTURE_BINDINGS]bool,
	texture_kinds:    [MAX_TEXTURE_BINDINGS]Texture_Kind,
}

Draw_Indexed_Desc :: struct {
	index_count:    u32,
	first_index:    u32,
	instance_count: u32,
	scissor:        Scissor,
}

Scissor :: struct {
	enabled:             bool,
	x, y, width, height: i32,
}

Render_Target_Desc :: struct {
	kind:          Texture_Kind,
	mip_levels:    u32,
	depth_only:    bool,
	color_format:  Texture_Format,
	color_filter:  Texture_Filter,
	width, height: i32,
	label:         string,
}

Load_Op :: enum {
	Clear,
	Load,
}

Viewport :: struct {
	x, y, width, height: i32,
}

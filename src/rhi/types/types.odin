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
	Shader_Compile_Failed,
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

Shader_Desc :: struct {
	stage:  Shader_Stage,
	source: string,
	label:  string,
}

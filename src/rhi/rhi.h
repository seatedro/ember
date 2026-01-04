#pragma once
#include "core/core.h"
#include "core/math.h"
#include "platform/window.h"

#define HANDLE_INVALID_ID UINT32_MAX

namespace ember {

struct BufferHandle {
    u32 id;
};

struct ShaderHandle {
    u32 id;
};

struct PipelineHandle {
    u32 id;
};

inline b32 handle_valid(BufferHandle h) { return h.id != HANDLE_INVALID_ID; }
inline b32 handle_valid(ShaderHandle h) { return h.id != HANDLE_INVALID_ID; }
inline b32 handle_valid(PipelineHandle h) { return h.id != HANDLE_INVALID_ID; }

enum class BufferType : u32 { Vertex, Index, Uniform };
enum class BufferUsage : u32 { Static, Dynamic };
enum class Primitive : u32 { Triangles, Lines, Points };
enum class Winding : u32 { CW, CCW };
enum class CullMode : u32 { None, Front, Back };
enum class CompareFn : u32 {
    Never = 0,
    Less = 1,
    Equal = 2,
    LessEqual = 3,
    Greater = 4,
    NotEqual = 5,
    GreaterEqual = 6,
    Always = 7
};
enum class VertexFormat : u32 { F32 = 1, F32x2 = 2, F32x3 = 3, F32x4 = 4 };
enum class ShaderStage : u32 { Vertex, Fragment, Compute };

struct BufferDesc {
    BufferType  type;
    BufferUsage usage;
    void*       data;
    u64         size;
};

// TODO: make this use the fs
struct ShaderDesc {
    const char* vertex_src;
    const char* fragment_src;
    const char* name;
};

struct VertexAttrib {
    VertexFormat format;
    u32          offset;
};

struct VertexLayout {
    VertexAttrib* attribs;
    u32           attrib_count;
    u32           stride;
};

struct DepthState {
    b32       test_enabled;
    b32       write_enabled;
    CompareFn compare;
};

struct RasterState {
    CullMode cull;
    Winding  winding;
    b32      wireframe;
};

struct PipelineDesc {
    ShaderHandle shader;
    VertexLayout layout;
    DepthState   depth;
    RasterState  raster;
    Primitive    primitive;
};

struct DrawDesc {
    u32 vertex_count;
    u32 index_count;
    u32 first_vertex;
    u32 first_index;
};

struct Device; // opaque type, defined per backend

// API
Device* create_device(Window* window);
void    destroy_device(Device* d);

BufferHandle create_buffer(Device* d, BufferDesc* desc);
void         destroy_buffer(Device* d, BufferHandle h);

ShaderHandle create_shader(Device* d, ShaderDesc* desc);
void         destroy_shader(Device* d, ShaderHandle h);

PipelineHandle create_pipeline(Device* d, PipelineDesc* desc);
void           destroy_pipeline(Device* d, PipelineHandle h);

void bind_pipeline(Device* d, PipelineHandle h);
void bind_vertex_buffer(Device* d, BufferHandle h);
void bind_index_buffer(Device* d, BufferHandle h);

void set_uniform_mat4(Device* d, ShaderHandle sh, const char* name, mat4* m);

void set_viewport(u32 x, u32 y, u32 w, u32 h);
void clear(f32 r, f32 g, f32 b, f32 a, f32 depth);
void draw(Device* d, DrawDesc* desc);

} // namespace ember

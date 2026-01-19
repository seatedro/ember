#pragma once
#include "core/core.h"
#include "core/math.h"
#include "platform/window.h"

#define HANDLE_INVALID_ID  UINT32_MAX
#define MAX_VERTEX_ATTRIBS 16

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

struct TextureHandle {
    u32 id;
};

struct DrawConfig {
    u32 first_vertex;
    u32 vertex_count;
    u32 first_index;
    u32 index_count;
    u32 instance_count;
    i32 base_vertex;
};

struct ClearValue {
    f32 color[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
    f32 depth = 1.0f;
    u8  stencil = 0;
};

enum ClearFlags : u32 {
    CLEAR_FLAG_NONE = 0,
    CLEAR_FLAG_COLOR = 1 << 0,
    CLEAR_FLAG_DEPTH = 1 << 1,
    CLEAR_FLAG_STENCIL = 1 << 2,
    ALL = CLEAR_FLAG_COLOR | CLEAR_FLAG_DEPTH | CLEAR_FLAG_STENCIL,
};

inline b32 handle_valid(BufferHandle h) { return h.id != HANDLE_INVALID_ID; }
inline b32 handle_valid(ShaderHandle h) { return h.id != HANDLE_INVALID_ID; }
inline b32 handle_valid(PipelineHandle h) { return h.id != HANDLE_INVALID_ID; }

enum class BufferType : u32 { Vertex, Index, Uniform };
enum class IndexType : u32 { U16, U32 };
// clang-format off
enum class BufferUsage : u32 {
    Static,  // upload once
    Dynamic, // upload occasionally
    Stream   // upload every frame
};
// clang-format on

struct BufferConfig {
    BufferType  type;
    BufferUsage usage;
    void*       data;
    u64         size;
};

enum class ShaderStage : u32 { Vertex, Fragment, Compute };

enum class UniformType : u32 { F32, I32, Vec3, Vec4, Mat4 };

struct UniformMember {
    const char* name;
    UniformType type;
    u32         offset;
};

struct UniformBlockLayout {
    const UniformMember* members;
    u32                  member_count;
    u32                  size;
};

struct ShaderConfig {
    const char*               vertex_src;
    const char*               fragment_src;
    const char*               name;
    const UniformBlockLayout* blocks;
    u32                       block_count;
};

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
enum class Primitive : u32 { Triangles, Lines, Points };
enum class Winding : u32 { CW, CCW };
enum class VertexFormat : u32 { F32 = 1, F32x2 = 2, F32x3 = 3, F32x4 = 4 };
enum class BlendFactor : u32 {
    Zero,
    One,
    SrcColor,
    OneMinusSrcColor,
    DstColor,
    OneMinusDstColor,
    SrcAlpha,
    OneMinusSrcAlpha,
    DstAlpha,
    OneMinusDstAlpha,
    SrcAlphaSaturate,
    ConstantColor,
    OneMinusConstantColor,
};
enum class BlendOp : u32 { Add, Subtract, ReverseSubtract, Min, Max };

struct VertexAttrib {
    VertexFormat format;
    u32          offset;
};

struct VertexLayout {
    VertexAttrib attribs[MAX_VERTEX_ATTRIBS];
    u32          attrib_count;
    u32          stride;
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

struct BlendState {
    b32         enabled;
    BlendFactor src_rgb;
    BlendFactor dst_rgb;
    BlendOp     op_rgb;
    BlendFactor src_alpha;
    BlendFactor dst_alpha;
    BlendOp     op_alpha;
};

namespace BlendPresets {

    constexpr BlendState Opaque = {
        .enabled = false,
        .src_rgb = BlendFactor::One,
        .dst_rgb = BlendFactor::Zero,
        .op_rgb = BlendOp::Add,
        .src_alpha = BlendFactor::One,
        .dst_alpha = BlendFactor::Zero,
        .op_alpha = BlendOp::Add,
    };

    constexpr BlendState Alpha = {
        .enabled = true,
        .src_rgb = BlendFactor::SrcAlpha,
        .dst_rgb = BlendFactor::OneMinusSrcAlpha,
        .op_rgb = BlendOp::Add,
        .src_alpha = BlendFactor::One,
        .dst_alpha = BlendFactor::OneMinusSrcAlpha,
        .op_alpha = BlendOp::Add,
    };

    constexpr BlendState Additive = {
        .enabled = true,
        .src_rgb = BlendFactor::SrcAlpha,
        .dst_rgb = BlendFactor::One,
        .op_rgb = BlendOp::Add,
        .src_alpha = BlendFactor::One,
        .dst_alpha = BlendFactor::One,
        .op_alpha = BlendOp::Add,
    };

    constexpr BlendState Multiply = {
        .enabled = true,
        .src_rgb = BlendFactor::DstColor,
        .dst_rgb = BlendFactor::Zero,
        .op_rgb = BlendOp::Add,
        .src_alpha = BlendFactor::DstAlpha,
        .dst_alpha = BlendFactor::Zero,
        .op_alpha = BlendOp::Add,
    };

    constexpr BlendState PremultipliedAlpha = {
        .enabled = true,
        .src_rgb = BlendFactor::One,
        .dst_rgb = BlendFactor::OneMinusSrcAlpha,
        .op_rgb = BlendOp::Add,
        .src_alpha = BlendFactor::One,
        .dst_alpha = BlendFactor::OneMinusSrcAlpha,
        .op_alpha = BlendOp::Add,
    };

} // namespace BlendPresets

struct PipelineConfig {
    ShaderHandle shader;
    VertexLayout layout;
    DepthState   depth;
    RasterState  raster;
    BlendState   blend;
    Primitive    primitive;
};

enum class TextureFormat : u32 { R8, RG8, RGB8, RGBA8, Depth24Stencil8 };
enum class TextureFilter : u32 { Nearest, Linear };
enum class TextureWrap : u32 { Repeat, Clamp, Mirror };

struct TextureConfig {
    u32           width;
    u32           height;
    TextureFormat format;
    TextureFilter min_filter;
    TextureFilter mag_filter;
    TextureWrap   wrap_s;
    TextureWrap   wrap_t;
    const void*   data;
    b32           generate_mips;
    const char*   debug_name;
};

struct Device; // opaque type, defined per backend

// API
Device* device_create(Window* window);
void device_destroy(Device* d);

BufferHandle buffer_create(Device* d, BufferConfig* cfg);
void buffer_destroy(Device* d, BufferHandle h);

ShaderHandle shader_create(Device* d, ShaderConfig* cfg);
ShaderHandle shader_load_from_files(
    Arena*                    arena,
    Device*                   device,
    const char*               vert_path,
    const char*               frag_path,
    const UniformBlockLayout* blocks,
    u32                       block_count

);
ShaderHandle shader_load_combined(
    Arena*                    arena,
    Device*                   device,
    const char*               path,
    const char*               name,
    const UniformBlockLayout* blocks,
    u32                       block_count
);
void shader_destroy(Device* d, ShaderHandle h);

PipelineHandle pipeline_create(Device* d, PipelineConfig* cfg);
void pipeline_destroy(Device* d, PipelineHandle h);

void bind_pipeline(Device* d, PipelineHandle h);
void bind_vertex_buffer(Device* d, BufferHandle h, u32 offset);
void bind_index_buffer(Device* d, BufferHandle h, IndexType t);
void bind_uniform_block(Device* d, u32 slot, const void* data, u32 size);

void set_uniform_mat4(Device* d, ShaderHandle sh, const char* name, mat4* m);
void set_uniform_i32(Device* d, ShaderHandle sh, const char* name, i32 value);
void set_uniform_f32(Device* d, ShaderHandle sh, const char* name, f32 value);
void set_uniform_vec3(Device* d, ShaderHandle sh, const char* name, vec3* v);
void set_uniform_vec4(Device* d, ShaderHandle sh, const char* name, vec4* v);

void set_viewport(u32 x, u32 y, u32 w, u32 h);
void clear(f32 r, f32 g, f32 b, f32 a, f32 depth);
void present(Device* d);

void set_scissor(u32 x, u32 y, u32 w, u32 h);
void set_scissor_enabled(b32 enabled);

void begin_pass(Device* d, ClearFlags flags, const ClearValue* clear);
void clear_pass(Device* d, ClearFlags flags, const ClearValue* clear);
void end_pass(Device* d);
void draw_submit(Device* d, const DrawConfig* cfg);

// TODO
TextureHandle texture_create(Device* d, const TextureConfig* cfg);
void texture_destroy(Device* d, TextureHandle handle);
void texture_bind(Device* d, TextureHandle handle, u32 slot);
void texture_update(Device* d, TextureHandle handle, const void* data);

} // namespace ember

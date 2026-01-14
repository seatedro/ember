#include "core/core.h"
#include "core/file.h"
#include "platform/window.h"
#include "rhi.h"
#include <cstdint>
#include <cstring>
#include <glad/glad.h>
#include <utility>

#if defined(EMBER_DEBUG)
#define GL_CHECK() EMBER_ASSERT(glGetError() == GL_NO_ERROR)
#else
#define GL_CHECK() ((void)0)
#endif

namespace ember {

// Internal types
struct Buffer {
    u32        id;
    BufferType type;
    u64        size;
};

struct Shader {
    u32 program;
    u32 uniform_hashes[64];
    i32 uniform_locations[64];
    u32 uniform_count;
};

struct Pipeline {
    ShaderHandle shader;
    VertexLayout layout;
    DepthState   depth;
    RasterState  raster;
    Primitive    primitive;
    BlendState   blend;
    u32          vao;
};

struct Texture {
    u32           id;
    u32           width;
    u32           height;
    TextureFormat format;
};

struct Device {
    Pool<Buffer, 4096>  buffers;
    Pool<Shader, 256>   shaders;
    Pool<Pipeline, 256> pipelines;

    PipelineHandle bound_pipeline;
    BufferHandle   bound_vbo;
    BufferHandle   bound_ibo;

    Window* window;
};

internal Device g_device;

internal u32 buffer_type_to_gl(BufferType t) {
    switch (t) {
    case BufferType::Vertex:
        return GL_ARRAY_BUFFER;
    case BufferType::Index:
        return GL_ELEMENT_ARRAY_BUFFER;
    case BufferType::Uniform:
        return GL_UNIFORM_BUFFER;
    }
}

internal u32 buffer_usage_to_gl(BufferUsage u) {
    switch (u) {
    case BufferUsage::Static:
        return GL_STATIC_DRAW;
    case BufferUsage::Dynamic:
        return GL_DYNAMIC_DRAW;
    case BufferUsage::Stream:
        return GL_STREAM_DRAW;
    }
}

internal u32 primitive_to_gl(Primitive p) {
    switch (p) {
    case Primitive::Triangles:
        return GL_TRIANGLES;
    case Primitive::Lines:
        return GL_LINES;
    case Primitive::Points:
        return GL_POINTS;
    }
}

internal u32 compare_to_gl(CompareFn fn) {
    switch (fn) {
    case CompareFn::Less:
        return GL_LESS;
    case CompareFn::LessEqual:
        return GL_LEQUAL;
    case CompareFn::Equal:
        return GL_EQUAL;
    case CompareFn::GreaterEqual:
        return GL_GEQUAL;
    case CompareFn::Greater:
        return GL_GREATER;
    case CompareFn::NotEqual:
        return GL_NOTEQUAL;
    case CompareFn::Never:
        return GL_NEVER;
    case CompareFn::Always:
        return GL_ALWAYS;
    }
}

internal u32 blend_factor_to_gl(BlendFactor f) {
    switch (f) {
    case BlendFactor::Zero:
        return GL_ZERO;
    case BlendFactor::One:
        return GL_ONE;
    case BlendFactor::SrcColor:
        return GL_SRC_COLOR;
    case BlendFactor::OneMinusSrcColor:
        return GL_ONE_MINUS_SRC_COLOR;
    case BlendFactor::DstColor:
        return GL_DST_COLOR;
    case BlendFactor::OneMinusDstColor:
        return GL_ONE_MINUS_DST_COLOR;
    case BlendFactor::SrcAlpha:
        return GL_SRC_ALPHA;
    case BlendFactor::OneMinusSrcAlpha:
        return GL_ONE_MINUS_SRC_ALPHA;
    case BlendFactor::DstAlpha:
        return GL_DST_ALPHA;
    case BlendFactor::OneMinusDstAlpha:
        return GL_ONE_MINUS_DST_ALPHA;
    case BlendFactor::SrcAlphaSaturate:
        return GL_SRC_ALPHA_SATURATE;
    case BlendFactor::ConstantColor:
        return GL_CONSTANT_COLOR;
    case BlendFactor::OneMinusConstantColor:
        return GL_ONE_MINUS_CONSTANT_COLOR;
    }
    return GL_ONE;
}

internal u32 blend_op_to_gl(BlendOp op) {
    switch (op) {
    case BlendOp::Add:
        return GL_FUNC_ADD;
    case BlendOp::Subtract:
        return GL_FUNC_SUBTRACT;
    case BlendOp::ReverseSubtract:
        return GL_FUNC_REVERSE_SUBTRACT;
    case BlendOp::Min:
        return GL_MIN;
    case BlendOp::Max:
        return GL_MAX;
    }
    return GL_FUNC_ADD;
}

Device* device_create(Window* window) {
    g_device = {};
    g_device.window = window;
    g_device.bound_pipeline.id = HANDLE_INVALID_ID;

    glEnable(GL_DEPTH_TEST);

    return &g_device;
}

void device_destroy(Device* d) { *d = {}; }

BufferHandle buffer_create(Device* d, BufferConfig* cfg) {
    EMBER_ASSERT(d);
    EMBER_ASSERT(cfg);
    EMBER_ASSERT(cfg->size > 0);

    u32     id = d->buffers.alloc();
    Buffer* buf = d->buffers.get(id);

    glGenBuffers(1, &buf->id);
    GL_CHECK();
    u32 target = buffer_type_to_gl(cfg->type);
    glBindBuffer(target, buf->id);
    glBufferData(target, cfg->size, cfg->data, buffer_usage_to_gl(cfg->usage));
    GL_CHECK();
    glBindBuffer(target, 0);

    buf->type = cfg->type;
    buf->size = cfg->size;

    return { id };
}

void buffer_destroy(Device* d, BufferHandle h) {
    EMBER_ASSERT(d);
    if (!handle_valid(h))
        return;

    Buffer* buf = d->buffers.get(h.id);
    glDeleteBuffers(1, &buf->id);
    GL_CHECK();
    d->buffers.release(h.id);
}

/// djb2 string hash
/// ref: http://www.cse.yorku.ca/~oz/hash.html
internal u32 hash_string(const char* str) {
    u32 hash = 5381;
    int c;
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c;
    }
    return hash;
}

internal i32 get_uniform_location(Device* d, ShaderHandle sh, const char* name) {
    Shader* s = d->shaders.get(sh.id);
    u32     hash = hash_string(name);

    for (u32 i = 0; i < s->uniform_count; i++) {
        if (s->uniform_hashes[i] == hash) {
            return s->uniform_locations[i];
        }
    }

    i32 loc = glGetUniformLocation(s->program, name);
    if (s->uniform_count < 64) {
        s->uniform_hashes[s->uniform_count] = hash;
        s->uniform_locations[s->uniform_count] = loc;
        s->uniform_count++;
    }

    return loc;
}

void set_uniform_mat4(Device* d, ShaderHandle sh, const char* name, mat4* m) {
    Shader* s = d->shaders.get(sh.id);
    glUseProgram(s->program);
    i32 loc = get_uniform_location(d, sh, name);
    if (loc >= 0) {
        glUniformMatrix4fv(loc, 1, GL_FALSE, m->data);
    }
}

void set_uniform_i32(Device* d, ShaderHandle sh, const char* name, i32 value) {
    Shader* s = d->shaders.get(sh.id);
    glUseProgram(s->program);
    i32 loc = get_uniform_location(d, sh, name);
    if (loc >= 0) {
        glUniform1i(loc, value);
    }
}

void set_uniform_f32(Device* d, ShaderHandle sh, const char* name, f32 value) {
    Shader* s = d->shaders.get(sh.id);
    glUseProgram(s->program);
    i32 loc = get_uniform_location(d, sh, name);
    if (loc >= 0) {
        glUniform1f(loc, value);
    }
}

void set_uniform_vec3(Device* d, ShaderHandle sh, const char* name, vec3* v) {
    Shader* s = d->shaders.get(sh.id);
    glUseProgram(s->program);
    i32 loc = get_uniform_location(d, sh, name);
    if (loc >= 0) {
        glUniform3fv(loc, 1, &v->x);
    }
}

void set_uniform_vec4(Device* d, ShaderHandle sh, const char* name, vec4* v) {
    Shader* s = d->shaders.get(sh.id);
    glUseProgram(s->program);
    i32 loc = get_uniform_location(d, sh, name);
    if (loc >= 0) {
        glUniform4fv(loc, 1, &v->x);
    }
}

// internal u32 shader_link_program(u32 vert, u32 frag, const char* name) {
//     u32 prog = glCreateProgram();
//     glAttachShader(prog, vert);
//     glAttachShader(prog, frag);
//     glLinkProgram(prog);
//     GL_CHECK();
//
//     i32 ok = 0;
//     glGetProgramiv(prog, GL_LINK_STATUS, &ok);
//     if (!ok) {
//         char log[512];
//         glGetProgramInfoLog(prog, sizeof(log), null, log);
//         LOG_ERROR("rhi", "shader link error (%s): %s", name, log);
//         glDeleteProgram(prog);
//         return 0;
//     }
//
//     glDetachShader(prog, vert);
//     glDetachShader(prog, frag);
//
//     return prog;
// }

ShaderHandle shader_load_files(
    Arena*      arena,
    Device*     device,
    const char* vert_path,
    const char* frag_path,
    const char* name
) {
    u64 mark = arena->used;

    EmberFile vert_file = read_file_text(arena, vert_path);
    EmberFile frag_file = read_file_text(arena, frag_path);

    if (!vert_file.success || !frag_file.success) {
        arena->used = mark; // rollback arena
        return { HANDLE_INVALID_ID };
    }

    ShaderConfig shader_cfg = {
        .vertex_src = (const char*)vert_file.data,
        .fragment_src = (const char*)frag_file.data,
        .name = name,
    };

    ShaderHandle handle = shader_create(device, &shader_cfg);

    arena->used = mark; // rollback arena

    return handle;
}

internal b32 parse_combined_shader(
    const char*  src,
    const char** out_vert,
    u64*         out_vert_len,
    const char** out_frag,
    u64*         out_frag_len
) {
    const char* vert_start = null;
    const char* frag_start = null;
    const char* vert_end = null;
    const char* frag_end = null;

    const char* cursor = src;
    while (*cursor) {
        if (strncmp(cursor, "#pragma stage:", 14) == 0) {
            cursor += 14;

            while (*cursor == ' ' || *cursor == '\t')
                cursor++;

            if (strncmp(cursor, "vertex", 6) == 0 || strncmp(cursor, "vert", 4) == 0) {
                while (*cursor && *cursor != '\n')
                    cursor++;
                if (*cursor == '\n')
                    cursor++;
                vert_start = cursor;
            } else if (strncmp(cursor, "fragment", 8) == 0 || strncmp(cursor, "frag", 4) == 0) {
                if (vert_start && !vert_end) {
                    vert_end = cursor - 14;
                    while (vert_end > vert_start
                           && (*(vert_end - 1) == ' ' || *(vert_end - 1) == '\n')) {
                        vert_end--;
                    }
                }
                while (*cursor && *cursor != '\n')
                    cursor++;
                if (*cursor == '\n')
                    cursor++;
                frag_start = cursor;
            }
        }

        if (*cursor)
            cursor++;
    }

    if (frag_start)
        frag_end = cursor;

    if (!vert_start || !frag_start) {
        LOG_ERROR("shader", "missing #pragma stage:vertex or #pragma stage:fragment");
        return false;
    }

    *out_vert = vert_start;
    *out_vert_len = (u64)(vert_end - vert_start);
    *out_frag = frag_start;
    *out_frag_len = (u64)(frag_end - frag_start);

    return true;
}

ShaderHandle
shader_load_combined(Arena* arena, Device* device, const char* path, const char* name) {
    u64 mark = arena->used;

    EmberFile file = read_file_text(arena, path);
    if (!file.success) {
        arena->used = mark;
        return { HANDLE_INVALID_ID };
    }

    const char* src = (const char*)file.data;
    const char* vert_src = null;
    const char* frag_src = null;
    u64         vert_len = 0;
    u64         frag_len = 0;

    if (!parse_combined_shader(src, &vert_src, &vert_len, &frag_src, &frag_len)) {
        arena->used = mark;
        return { HANDLE_INVALID_ID };
    }

    char* vert_copy = Arena::alloc_array<char>(arena, vert_len + 1);
    char* frag_copy = Arena::alloc_array<char>(arena, frag_len + 1);
    memcpy(vert_copy, vert_src, vert_len);
    memcpy(frag_copy, frag_src, vert_len);
    vert_copy[vert_len] = '\0';
    frag_copy[frag_len] = '\0';

    ShaderConfig config = {
        .vertex_src = vert_copy,
        .fragment_src = frag_copy,
        .name = name,
    };

    ShaderHandle handle = shader_create(device, &config);

    arena->used = mark;

    return handle;
}

internal u32 compile_shader(const char* src, u32 type, const char* name) {
    u32 shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, null);
    GL_CHECK();
    glCompileShader(shader);
    GL_CHECK();

    i32 ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(shader, sizeof(log), null, log);
        LOG_ERROR("rhi", "shader compile error (%s): %s", name, log);
        glDeleteShader(shader);
        GL_CHECK();
        return 0;
    }
    return shader;
}

ShaderHandle shader_create(Device* d, ShaderConfig* cfg) {
    u32 vs = compile_shader(cfg->vertex_src, GL_VERTEX_SHADER, cfg->name);
    u32 fs = compile_shader(cfg->fragment_src, GL_FRAGMENT_SHADER, cfg->name);

    if (!vs || !fs) {
        if (vs)
            glDeleteShader(vs);
        if (fs)
            glDeleteShader(fs);
        return { HANDLE_INVALID_ID };
    }

    u32 prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glLinkProgram(prog);
    GL_CHECK();

    glDeleteShader(vs);
    glDeleteShader(fs);

    i32 ok;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetProgramInfoLog(prog, sizeof(log), null, log);
        LOG_ERROR("rhi", "shader compile error (%s): %s", cfg->name, log);
        glDeleteProgram(prog);
        GL_CHECK();
        return { HANDLE_INVALID_ID };
    }

    u32     id = d->shaders.alloc();
    Shader* sh = d->shaders.get(id);
    sh->program = prog;
    sh->uniform_count = 0;

    LOG_INFO("rhi", "shader '%s' created", cfg->name);
    return { id };
}

void shader_destroy(Device* d, ShaderHandle h) {
    Shader* sh = d->shaders.get(h.id);
    glDeleteProgram(sh->program);
    GL_CHECK();
}

PipelineHandle pipeline_create(Device* d, PipelineConfig* cfg) {
    EMBER_ASSERT(d);
    EMBER_ASSERT(cfg);
    EMBER_ASSERT(handle_valid(cfg->shader));
    EMBER_ASSERT(cfg->layout.attribs);
    EMBER_ASSERT(cfg->layout.attrib_count > 0);
    EMBER_ASSERT(cfg->layout.stride > 0);

    u32       id = d->pipelines.alloc();
    Pipeline* pip = d->pipelines.get(id);

    pip->shader = cfg->shader;
    pip->layout = cfg->layout;
    pip->depth = cfg->depth;
    pip->raster = cfg->raster;
    pip->primitive = cfg->primitive;

    glGenVertexArrays(1, &pip->vao);
    GL_CHECK();

    return { id };
}

void pipeline_destroy(Device* d, PipelineHandle h) {
    Pipeline* pip = d->pipelines.get(h.id);
    glDeleteVertexArrays(1, &pip->vao);
    GL_CHECK();
}

void bind_pipeline(Device* d, PipelineHandle h) {
    EMBER_ASSERT(d);
    EMBER_ASSERT(handle_valid(h));

    Pipeline* pip = d->pipelines.get(h.id);
    Shader*   sh = d->shaders.get(pip->shader.id);

    d->bound_pipeline = h;

    glUseProgram(sh->program);
    GL_CHECK();

    glBindVertexArray(pip->vao);
    GL_CHECK();

    if (pip->depth.test_enabled) {
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(compare_to_gl(pip->depth.compare));
        glDepthMask(pip->depth.write_enabled ? GL_TRUE : GL_FALSE);
    } else {
        glDisable(GL_DEPTH_TEST);
    }

    if (pip->raster.cull != CullMode::None) {
        glEnable(GL_CULL_FACE);
        glCullFace(pip->raster.cull == CullMode::Front ? GL_FRONT : GL_BACK);
        glFrontFace(pip->raster.winding == Winding::CCW ? GL_CCW : GL_CW);
    } else {
        glDisable(GL_CULL_FACE);
    }

    if (pip->raster.wireframe) {
        glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    } else {
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    }

    if (pip->blend.enabled) {
        glEnable(GL_BLEND);
        glBlendEquationSeparate(
            blend_op_to_gl(pip->blend.op_rgb), blend_op_to_gl(pip->blend.op_alpha)
        );
        glBlendFuncSeparate(
            blend_factor_to_gl(pip->blend.src_rgb),
            blend_factor_to_gl(pip->blend.dst_rgb),
            blend_factor_to_gl(pip->blend.src_alpha),
            blend_factor_to_gl(pip->blend.dst_alpha)
        );
    } else {
        glDisable(GL_BLEND);
    }
}

void bind_vertex_buffer(Device* d, BufferHandle h) {
    EMBER_ASSERT(d);
    EMBER_ASSERT(handle_valid(h));
    EMBER_ASSERT(handle_valid(d->bound_pipeline));

    Buffer* buf = d->buffers.get(h.id);
    EMBER_ASSERT(buf->type == BufferType::Vertex);

    Pipeline* pip = d->pipelines.get(d->bound_pipeline.id);

    glBindBuffer(GL_ARRAY_BUFFER, buf->id);
    GL_CHECK();

    for (u32 i = 0; i < pip->layout.attrib_count; i++) {
        VertexAttrib* a = &pip->layout.attribs[i];

        glEnableVertexAttribArray(i);
        // TODO: need to add some helpers when we add more vertex formats
        glVertexAttribPointer(
            i,
            std::to_underlying(a->format),
            GL_FLOAT,
            GL_FALSE,
            pip->layout.stride,
            (void*)(uintptr_t)a->offset
        );
    }
    GL_CHECK();

    d->bound_vbo = h;
}

void bind_index_buffer(Device* d, BufferHandle h) {
    EMBER_ASSERT(d);
    EMBER_ASSERT(handle_valid(h));

    Buffer* buf = d->buffers.get(h.id);
    EMBER_ASSERT(buf->type == BufferType::Index);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buf->id);
    GL_CHECK();

    d->bound_ibo = h;
}

void set_viewport(u32 x, u32 y, u32 w, u32 h) { glViewport(x, y, w, h); }

void clear(f32 r, f32 g, f32 b, f32 a, f32 depth) {
    glClearColor(r, g, b, a);
    glClearDepth(depth);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

void draw(Device* d, DrawConfig* cfg) {
    Pipeline* pip = d->pipelines.get(d->bound_pipeline.id);
    GLenum    prim = primitive_to_gl(pip->primitive);

    if (cfg->index_count > 0) {
        glDrawElements(
            prim,
            cfg->index_count,
            GL_UNSIGNED_INT,
            (void*)(uintptr_t)(cfg->first_index * sizeof(u32))
        );
    } else {
        glDrawArrays(prim, cfg->first_vertex, cfg->vertex_count);
    }
}

void present(Device* d) {
    EMBER_ASSERT(d);
    EMBER_ASSERT(d->window);
    window_swap_buffers(d->window);
}

void set_scissor(u32 x, u32 y, u32 w, u32 h) {
    glEnable(GL_SCISSOR_TEST);
    glScissor(x, y, w, h);
}

void set_scissor_enabled(b32 enabled) {
    if (enabled) {
        glEnable(GL_SCISSOR_TEST);
    } else {
        glDisable(GL_SCISSOR_TEST);
    }
}

} // namespace ember

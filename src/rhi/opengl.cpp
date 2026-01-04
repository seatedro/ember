#include "core/core.h"
#include "platform/window.h"
#include "rhi.h"
#include <cstdint>
#include <glad/glad.h>
#include <utility>

#if defined(EMBER_DEBUG)
#define GL_CHECK() EMBER_ASSERT(glGetError() == GL_NO_ERROR)
#else
#define GL_CHECK() ((void)0)
#endif

namespace ember {

// using template here for convenience
template <typename T, u32 MAX>
struct Pool {
    T   data[MAX];
    u32 free_list[MAX];
    u32 free_count;
    u32 count;

    void init() {
        count = 0;
        free_count = 0;
    }

    u32 alloc() {
        if (free_count > 0) {
            u32 id = free_list[--free_count];
            EMBER_ASSERT(id < count);
            return id;
        }
        EMBER_ASSERT(count < MAX);
        return count++;
    }

    void release(u32 id) {
        EMBER_ASSERT(id < count);
        EMBER_ASSERT(free_count < MAX);

#if defined(EMBER_DEBUG)
        // double free detection
        for (u32 i = 0; i < free_count; i++) {
            EMBER_ASSERT(free_list[i] != id);
        }
#endif

        free_list[free_count++] = id;
    }

    T* get(u32 id) {
        EMBER_ASSERT(id < count);
        return &data[id];
    }
};

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
    u32          vao;
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

Device* create_device(Window* window) {
    g_device = {};
    g_device.window = window;
    g_device.bound_pipeline.id = HANDLE_INVALID_ID;

    glEnable(GL_DEPTH_TEST);

    return &g_device;
}

void destroy_device(Device* d) { *d = {}; }

BufferHandle create_buffer(Device* d, BufferDesc* desc) {
    EMBER_ASSERT(d);
    EMBER_ASSERT(desc);
    EMBER_ASSERT(desc->size > 0);

    u32     id = d->buffers.alloc();
    Buffer* buf = d->buffers.get(id);

    glGenBuffers(1, &buf->id);
    GL_CHECK();
    u32 target = buffer_type_to_gl(desc->type);
    glBindBuffer(target, buf->id);
    glBufferData(target, desc->size, desc->data, buffer_usage_to_gl(desc->usage));
    GL_CHECK();
    glBindBuffer(target, 0);

    buf->type = desc->type;
    buf->size = desc->size;

    return { id };
}

void destroy_buffer(Device* d, BufferHandle h) {
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

ShaderHandle create_shader(Device* d, ShaderDesc* desc) {
    u32 vs = compile_shader(desc->vertex_src, GL_VERTEX_SHADER, desc->name);
    u32 fs = compile_shader(desc->fragment_src, GL_FRAGMENT_SHADER, desc->name);

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
        LOG_ERROR("rhi", "shader compile error (%s): %s", desc->name, log);
        glDeleteProgram(prog);
        GL_CHECK();
        return { HANDLE_INVALID_ID };
    }

    u32     id = d->shaders.alloc();
    Shader* sh = d->shaders.get(id);
    sh->program = prog;
    sh->uniform_count = 0;

    LOG_INFO("rhi", "shader '%s' created", desc->name);
    return { id };
}

void destroy_shader(Device* d, ShaderHandle h) {
    Shader* sh = d->shaders.get(h.id);
    glDeleteProgram(sh->program);
    GL_CHECK();
}

PipelineHandle create_pipeline(Device* d, PipelineDesc* desc) {
    EMBER_ASSERT(d);
    EMBER_ASSERT(desc);
    EMBER_ASSERT(handle_valid(desc->shader));
    EMBER_ASSERT(desc->layout.attribs);
    EMBER_ASSERT(desc->layout.attrib_count > 0);
    EMBER_ASSERT(desc->layout.stride > 0);

    u32       id = d->pipelines.alloc();
    Pipeline* pip = d->pipelines.get(id);

    pip->shader = desc->shader;
    pip->layout = desc->layout;
    pip->depth = desc->depth;
    pip->raster = desc->raster;
    pip->primitive = desc->primitive;

    glGenVertexArrays(1, &pip->vao);
    GL_CHECK();

    return { id };
}

void destroy_pipeline(Device* d, PipelineHandle h) {
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
        glVertexAttribPointer(i, std::to_underlying(a->format), GL_FLOAT, GL_FALSE,
            pip->layout.stride, (void*)(uintptr_t)a->offset);
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

void draw(Device* d, DrawDesc* desc) {
    Pipeline* pip = d->pipelines.get(d->bound_pipeline.id);
    GLenum    prim = primitive_to_gl(pip->primitive);

    if (desc->index_count > 0) {
        glDrawElements(prim, desc->index_count, GL_UNSIGNED_INT,
            (void*)(uintptr_t)(desc->first_index * sizeof(u32)));
    } else {
        glDrawArrays(prim, desc->first_vertex, desc->vertex_count);
    }
}

} // namespace ember

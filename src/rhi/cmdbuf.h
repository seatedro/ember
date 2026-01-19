#pragma once
#include "core/core.h"
#include "rhi/rhi.h"

namespace ember {

enum class CmdOp : u32 {
    BeginPass,
    EndPass,
    SetViewport,
    SetScissor,
    Clear,
    BindPipeline,
    BindVertexBuffer,
    BindIndexBuffer,
    BindUniformBlock,
    BindTexture,
    Draw,
};

struct CommandBuffer {
    ByteBuffer commands;
    u32        num_commands;

    pub CommandBuffer create() {
        CommandBuffer cb = {};
        cb.commands = ByteBuffer::create(KB(64));
        cb.num_commands = 0;
        return cb;
    }

    pub void destroy(CommandBuffer* cb) {
        ByteBuffer::destroy(&cb->commands);
        cb->num_commands = 0;
    }

    pub void reset(CommandBuffer* cb) {
        ByteBuffer::clear(&cb->commands);
        cb->num_commands = 0;
    }
};

void cmd_begin_pass(CommandBuffer* cb, ClearFlags flags, const ClearValue* clear);
void cmd_end_pass(CommandBuffer* cb);
void cmd_set_viewport(CommandBuffer* cb, i32 x, i32 y, i32 w, i32 h);
void cmd_set_scissor(CommandBuffer* cb, i32 x, i32 y, i32 w, i32 h);
void cmd_bind_pipeline(CommandBuffer* cb, PipelineHandle pip);
void cmd_bind_vertex_buffer(CommandBuffer* cb, BufferHandle buf, u32 offset);
void cmd_bind_index_buffer(CommandBuffer* cb, BufferHandle buf, IndexType type);
void cmd_bind_uniform_block(CommandBuffer* cb, u32 slot, const void* data, u32 size);
void cmd_bind_texture(CommandBuffer* cb, u32 slot, TextureHandle tex);
void cmd_draw(CommandBuffer* cb, u32 first_vertex, u32 vertex_count, u32 instance_count);
void cmd_draw_indexed(
    CommandBuffer* cb,
    u32            index_count,
    u32            instance_count,
    u32            first_index,
    i32            base_vertex
);
void cmd_submit(CommandBuffer* cb, Device* device);

} // namespace ember

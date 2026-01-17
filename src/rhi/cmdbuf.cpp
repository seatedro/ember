
#include "cmdbuf.h"
#include "rhi.h"

// clang-format off
#define CMD_WRITE(cb, op, ...) do {                \
    ByteBuffer::write(&(cb)->commands, (u32)(op)); \
    __VA_ARGS__                                    \
    (cb)->num_commands++;                          \
} while(0)
// clang-format on

namespace ember {

void cmd_begin_pass(CommandBuffer* cb, ClearFlags flags, const ClearValue* clear) {
    CMD_WRITE(cb, CmdOp::BeginPass, {
        ByteBuffer::write(&cb->commands, (u32)flags);
        ByteBuffer::write(&cb->commands, clear ? *clear : ClearValue {});
    });
}

void cmd_end_pass(CommandBuffer* cb) { CMD_WRITE(cb, CmdOp::EndPass, {}); }

void cmd_set_viewport(CommandBuffer* cb, i32 x, i32 y, i32 w, i32 h) {
    CMD_WRITE(cb, CmdOp::SetViewport, {
        ByteBuffer::write(&cb->commands, x);
        ByteBuffer::write(&cb->commands, y);
        ByteBuffer::write(&cb->commands, w);
        ByteBuffer::write(&cb->commands, h);
    });
}

void cmd_set_scissor(CommandBuffer* cb, i32 x, i32 y, i32 w, i32 h) {
    CMD_WRITE(cb, CmdOp::SetScissor, {
        ByteBuffer::write(&cb->commands, x);
        ByteBuffer::write(&cb->commands, y);
        ByteBuffer::write(&cb->commands, w);
        ByteBuffer::write(&cb->commands, h);
    });
}

void cmd_bind_pipeline(CommandBuffer* cb, PipelineHandle pip) {
    CMD_WRITE(cb, CmdOp::BindPipeline, { ByteBuffer::write(&cb->commands, pip.id); });
}

void cmd_bind_vertex_buffer(CommandBuffer* cb, BufferHandle buf, u32 offset) {
    CMD_WRITE(cb, CmdOp::BindVertexBuffer, {
        ByteBuffer::write(&cb->commands, buf.id);
        ByteBuffer::write(&cb->commands, offset);
    });
}

void cmd_bind_index_buffer(CommandBuffer* cb, BufferHandle buf, IndexType type) {
    CMD_WRITE(cb, CmdOp::BindIndexBuffer, {
        ByteBuffer::write(&cb->commands, buf.id);
        ByteBuffer::write(&cb->commands, (u32)type);
    });
}

void cmd_bind_uniform_block(CommandBuffer* cb, u32 slot, const void* data, u32 size) {
    CMD_WRITE(cb, CmdOp::BindUniformBlock, {
        ByteBuffer::write(&cb->commands, slot);
        ByteBuffer::write(&cb->commands, size);
        ByteBuffer::write_bytes(&cb->commands, data, size);
    });
}

void cmd_bind_texture(CommandBuffer* cb, u32 slot, TextureHandle tex) {
    CMD_WRITE(cb, CmdOp::BindTexture, {
        ByteBuffer::write(&cb->commands, slot);
        ByteBuffer::write(&cb->commands, tex.id);
    });
}

void cmd_draw(CommandBuffer* cb, u32 first_vertex, u32 vertex_count, u32 instance_count) {
    CMD_WRITE(cb, CmdOp::Draw, {
        ByteBuffer::write(&cb->commands, first_vertex);
        ByteBuffer::write(&cb->commands, vertex_count);
        ByteBuffer::write(&cb->commands, instance_count);
    });
}

void cmd_draw_indexed(
    CommandBuffer* cb,
    u32            index_count,
    u32            instance_count,
    u32            first_index,
    i32            base_vertex
) {
    CMD_WRITE(cb, CmdOp::Draw, {
        ByteBuffer::write(&cb->commands, index_count);
        ByteBuffer::write(&cb->commands, instance_count);
        ByteBuffer::write(&cb->commands, first_index);
        ByteBuffer::write(&cb->commands, base_vertex);
    });
}

} // namespace ember

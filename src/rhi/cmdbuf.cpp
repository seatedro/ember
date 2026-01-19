
#include "cmdbuf.h"
#include "core/core.h"
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

// uses an indexed flag to control if we draw
// with an index buffer or vertex buffer
void cmd_draw_internal(
    CommandBuffer* cb,
    u32            first_element,
    u32            count,
    u32            instance_count,
    i32            base_vertex,
    b32            indexed
) {
    CMD_WRITE(cb, CmdOp::Draw, {
        ByteBuffer::write(&cb->commands, first_element);
        ByteBuffer::write(&cb->commands, count);
        ByteBuffer::write(&cb->commands, instance_count);
        ByteBuffer::write(&cb->commands, base_vertex);
        ByteBuffer::write(&cb->commands, (u32)indexed);
    });
}

void cmd_draw(CommandBuffer* cb, u32 first_vertex, u32 vertex_count, u32 instance_count) {
    cmd_draw_internal(cb, first_vertex, vertex_count, instance_count, 0, false);
}

void cmd_draw_indexed(
    CommandBuffer* cb,
    u32            index_count,
    u32            instance_count,
    u32            first_index,
    i32            base_vertex
) {
    cmd_draw_internal(cb, first_index, index_count, instance_count, base_vertex, true);
}

void cmd_submit(CommandBuffer* cb, Device* device) {
    ByteReader r = ByteReader::from(&cb->commands);

    while (ByteReader::has_more(&r)) {
        CmdOp op = (CmdOp)ByteReader::read<u32>(&r);

        switch (op) {
        case CmdOp::BeginPass: {
            ClearFlags flags = (ClearFlags)ByteReader::read<u32>(&r);
            ClearValue clear = ByteReader::read<ClearValue>(&r);

            begin_pass(device, flags, &clear);
        } break;
        case CmdOp::EndPass: {
            end_pass(device);
        } break;
        case CmdOp::SetViewport: {
            i32 x = ByteReader::read<i32>(&r);
            i32 y = ByteReader::read<i32>(&r);
            i32 w = ByteReader::read<i32>(&r);
            i32 h = ByteReader::read<i32>(&r);

            set_viewport(x, y, w, h);
        } break;
        case CmdOp::SetScissor: {
            i32 x = ByteReader::read<i32>(&r);
            i32 y = ByteReader::read<i32>(&r);
            i32 w = ByteReader::read<i32>(&r);
            i32 h = ByteReader::read<i32>(&r);

            set_scissor(x, y, w, h);
        } break;
        case CmdOp::BindPipeline: {
            u32 id = ByteReader::read<u32>(&r);

            bind_pipeline(device, { id });
        } break;
        case CmdOp::BindVertexBuffer: {
            u32 id = ByteReader::read<u32>(&r);
            u32 offset = ByteReader::read<u32>(&r);

            bind_vertex_buffer(device, { id }, offset);
        } break;
        case CmdOp::BindIndexBuffer: {
            u32       id = ByteReader::read<u32>(&r);
            IndexType type = (IndexType)ByteReader::read<u32>(&r);

            bind_index_buffer(device, { id }, type);
        } break;
        case CmdOp::BindTexture: {
            u32 slot = ByteReader::read<u32>(&r);
            u32 id = ByteReader::read<u32>(&r);

            texture_bind(device, { id }, slot);
        } break;
        case CmdOp::BindUniformBlock: {
            u32         slot = ByteReader::read<u32>(&r);
            u32         size = ByteReader::read<u32>(&r);
            const void* data = r.data + r.pos;
            r.pos += size;

            bind_uniform_block(device, slot, data, size);
        } break;
        case CmdOp::Draw: {
            u32 first = ByteReader::read<u32>(&r);
            u32 count = ByteReader::read<u32>(&r);
            u32 instances = ByteReader::read<u32>(&r);
            i32 base_vertex = ByteReader::read<i32>(&r);
            b32 indexed = (b32)ByteReader::read<u32>(&r);

            DrawConfig cfg = {
                .first_vertex = indexed ? 0 : first,
                .vertex_count = indexed ? 0 : count,
                .first_index = indexed ? first : 0,
                .index_count = indexed ? count : 0,
                .instance_count = instances,
                .base_vertex = base_vertex,
            };

            draw_submit(device, &cfg);
        } break;
        case CmdOp::Clear: {
            ClearFlags flags = (ClearFlags)ByteReader::read<u32>(&r);
            ClearValue clear = ByteReader::read<ClearValue>(&r);

            clear_pass(device, flags, &clear);
        } break;
        }
    }
}

} // namespace ember

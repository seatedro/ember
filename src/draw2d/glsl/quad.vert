#version 410 core
layout(location = 0) in vec2 position;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 tint;
layout(location = 3) in float distance_range;

layout(std140) uniform View {
    vec2 logical_size;
};

out vec2 texture_uv;
out vec4 vertex_color;
flat out float pixel_range;

void main() {
    gl_Position = vec4(position / logical_size * vec2(2.0, -2.0) + vec2(-1.0, 1.0), 0.0, 1.0);
    texture_uv = uv;
    vertex_color = tint;
    pixel_range = distance_range;
}

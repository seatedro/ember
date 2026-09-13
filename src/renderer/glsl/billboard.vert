#version 410 core
layout(location = 0) in vec2 corner;
layout(location = 1) in vec2 uv;
layout(location = 3) in vec3 center;
layout(location = 4) in vec2 size;
layout(location = 5) in float rotation;
layout(location = 6) in vec4 color;

layout(std140) uniform View {
    mat4 view_projection;
    vec4 camera_right;
    vec4 camera_up;
};

out vec2 texture_uv;
out vec4 vertex_color;

void main() {
    vec2 offset = corner * size;
    float c = cos(rotation), s = sin(rotation);
    offset = mat2(c, s, -s, c) * offset;
    vec3 world = center + camera_right.xyz * offset.x + camera_up.xyz * offset.y;
    gl_Position = view_projection * vec4(world, 1.0);
    texture_uv = uv;
    vertex_color = color;
}

#version 410 core
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 vertex_color;

layout(std140) uniform Grid_View {
    mat4 view_projection;
};

out vec3 line_color;

void main() {
    gl_Position = view_projection * vec4(position, 1.0);
    line_color = vertex_color;
}

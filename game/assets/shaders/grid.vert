#version 410 core
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 vertex_color;

layout(std140) uniform Per_Object {
    mat4 mvp;
    mat4 normals;
};

out vec3 line_color;

void main() {
    gl_Position = mvp * vec4(position, 1.0);
    line_color = vertex_color;
}

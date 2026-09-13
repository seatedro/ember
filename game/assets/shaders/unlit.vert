#version 410 core
layout(location = 0) in vec3 position;

layout(std140) uniform Per_View {
    mat4 view_projection;
};

layout(std140) uniform Per_Object {
    mat4 model;
    mat4 normals;
};

void main() {
    gl_Position = view_projection * (model * vec4(position, 1.0));
}

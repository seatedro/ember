#version 410 core
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(std140) uniform Per_View {
    mat4 view_projection;
};

layout(std140) uniform Per_Object {
    mat4 model;
    mat4 normals;
};

out vec3 world_normal;
out vec3 local_normal;

void main() {
    vec4 world_position = model * vec4(position, 1.0);
    gl_Position = view_projection * world_position;
    world_normal = mat3(normals) * normal;
    local_normal = normal;
}

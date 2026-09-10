#version 410 core
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(std140) uniform Per_Object {
    mat4 mvp;
    mat4 model;
};

out vec3 world_normal;
out vec3 local_normal;

void main() {
    gl_Position = mvp * vec4(position, 1.0);
    world_normal = mat3(model) * normal;
    local_normal = normal;
}

#version 410 core
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;

layout(std140) uniform Per_View {
    mat4 view_projection;
};

layout(std140) uniform Per_Object {
    mat4 model;
    mat4 normals;
};

out vec3 world_position;
out vec3 world_normal;
out vec3 local_normal;
out vec2 texture_uv;

void main() {
    vec4 world = model * vec4(position, 1.0);
    world_position = world.xyz;
    gl_Position = view_projection * world;
    world_normal = mat3(normals) * normal;
    local_normal = normal;
    texture_uv = uv;
}

#version 450
#extension GL_GOOGLE_include_directive : require
#include "instance.glsl"
#include "view.glsl"

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;
layout(location = 6) in vec3 tangent;
layout(location = 7) in vec3 bitangent;

layout(location = 0) out vec3 world_position;
layout(location = 1) out vec3 view_direction;
layout(location = 2) out vec3 world_normal;
layout(location = 3) out vec3 world_tangent;
layout(location = 4) out vec3 world_bitangent;
layout(location = 5) out vec3 local_normal;
layout(location = 6) out vec2 texture_uv;

void main() {
    mat4 model = instance_model();
    vec4 world = model * vec4(position, 1.0);
    world_position = world.xyz;
    view_direction = camera_position.xyz - world.xyz;
    gl_Position = view_projection * world;
    world_normal = transpose(inverse(mat3(model))) * normal;
    world_tangent = mat3(model) * tangent;
    world_bitangent = mat3(model) * bitangent;
    local_normal = normal;
    texture_uv = uv;
}

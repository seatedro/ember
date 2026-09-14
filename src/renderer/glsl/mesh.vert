layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;
layout(location = 6) in vec3 tangent;
layout(location = 7) in vec3 bitangent;

layout(std140) uniform Per_View {
    mat4 view_projection;
};

out vec3 world_position;
out vec3 world_normal;
out vec3 world_tangent;
out vec3 world_bitangent;
out vec3 local_normal;
out vec2 texture_uv;

void main() {
    mat4 model = instance_model();
    vec4 world = model * vec4(position, 1.0);
    world_position = world.xyz;
    gl_Position = view_projection * world;
    world_normal = transpose(inverse(mat3(model))) * normal;
    world_tangent = mat3(model) * tangent;
    world_bitangent = mat3(model) * bitangent;
    local_normal = normal;
    texture_uv = uv;
}

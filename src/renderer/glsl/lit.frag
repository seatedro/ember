in vec3 world_position;
in vec3 world_normal;
in vec3 world_tangent;
in vec3 world_bitangent;
in vec2 texture_uv;
layout(location = 0) out vec4 color;
uniform sampler2D albedo_texture;
uniform sampler2D normal_texture;
layout(std140) uniform Material {
    vec4 tint;
    float emission;
    bool use_normal_map;
};
void main() {
    vec4 albedo = texture(albedo_texture, texture_uv) * tint;
    vec3 normal = world_normal;
    if (use_normal_map) {
        normal = mapped_normal(world_normal, world_tangent, world_bitangent, texture(normal_texture, texture_uv).rgb);
    }
    color = vec4(albedo.rgb * (diffuse_lighting(world_position, normal) + emission), albedo.a);
}

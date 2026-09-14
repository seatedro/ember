in vec3 world_position;
in vec3 view_direction;
in vec3 world_normal;
in vec3 world_tangent;
in vec3 world_bitangent;
in vec2 texture_uv;
layout(location = 0) out vec4 color;
uniform sampler2D albedo_texture;
uniform sampler2D normal_texture;
uniform sampler2D metallic_texture;
uniform sampler2D roughness_texture;

layout(std140) uniform Material {
    vec4 tint;
    float emission;
    bool use_normal_map;
    float metallic;
    float roughness;
};

void main() {
    vec4 albedo = texture(albedo_texture, texture_uv) * tint;
    vec3 normal = world_normal;
    if (use_normal_map) {
        normal = mapped_normal(world_normal, world_tangent, world_bitangent, texture(normal_texture, texture_uv).rgb);
    }
    float metal = texture(metallic_texture, texture_uv).b * metallic;
    float rough = texture(roughness_texture, texture_uv).g * roughness;
    float visibility = directional_visibility(world_position, world_normal);
    vec3 illumination = pbr_lighting(world_position, normal, view_direction, albedo.rgb, metal, rough, visibility);
    illumination += environment_lighting(normal, view_direction, albedo.rgb, metal, rough, environment);
    color = vec4(illumination + albedo.rgb * emission, albedo.a);
}

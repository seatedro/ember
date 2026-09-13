in vec3 world_position;
in vec3 world_normal;
in vec2 texture_uv;
layout(location = 0) out vec4 color;
uniform sampler2D albedo_texture;

layout(std140) uniform Material {
    vec4 tint;
    float emission;
};

void main() {
    vec4 albedo = texture(albedo_texture, texture_uv) * tint;
    color = vec4(albedo.rgb * (diffuse_lighting(world_position, world_normal, directional_visibility(world_position, world_normal)) + emission), albedo.a);
}

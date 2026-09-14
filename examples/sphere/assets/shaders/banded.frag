in vec3 world_position;
in vec3 world_normal;
in vec3 local_normal;
in vec2 texture_uv;
layout(location = 0) out vec4 color;
uniform sampler2D albedo_texture;

layout(std140) uniform Material {
    vec4 color_a;
    vec4 color_b;
};

void main() {
    vec3 local = normalize(local_normal);
    float bands = smoothstep(-0.2, 0.2, sin(local.x * 8.0 + local.z * 6.0));
    vec4 albedo = mix(color_a, color_b, bands) * texture(albedo_texture, texture_uv);
    color = vec4(albedo.rgb * diffuse_lighting(world_position, world_normal), albedo.a);
}

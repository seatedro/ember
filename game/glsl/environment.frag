#version 410 core
in vec2 texture_uv;
layout(location = 0) out vec4 color;
layout(std140) uniform Material { mat4 inverse_view_projection; vec4 sun; };
void main() {
    vec4 p = inverse_view_projection * vec4(texture_uv * 2.0 - 1.0, 1.0, 1.0);
    vec3 d = normalize(p.xyz / p.w);
    float band = pow(max(0.0, 1.0 - abs(d.y + 0.25 * sin(d.x * 4.0))), 8.0);
    vec3 sky = mix(vec3(0.008, 0.012, 0.025), vec3(0.12, 0.18, 0.32), band);
    float disk = smoothstep(0.97, 0.995, dot(d, sun.xyz));
    color = vec4(sky + vec3(1.0, 0.75, 0.4) * disk * sun.w, 1.0);
}

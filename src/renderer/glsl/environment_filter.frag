in vec2 texture_uv;
layout(location = 0) out vec4 color;
layout(std140) uniform Material { uint face; float roughness; uint mode; uint samples; };
uniform samplerCube source_texture;
vec4 evaluate(vec2 uv) {
    vec3 n = cube_direction(face, uv);
    if (mode == 0u) {
        return vec4(textureLod(source_texture, n, 0.0).rgb, 1.0);
    }
    vec3 up = abs(n.z) < 0.999 ? vec3(0,0,1) : vec3(1,0,0);
    vec3 tangent = normalize(cross(up, n));
    vec3 bitangent = cross(n, tangent);
    vec3 sum = vec3(0);
    float weight = 0.0;
    for (uint i = 0u; i < samples; ++i) {
        vec2 u = environment_sample(i, samples);
        vec3 l;
        if (mode == 1u) {
            float phi = 6.28318530718 * u.x;
            float radius = sqrt(u.y);
            l = tangent * (radius * cos(phi)) + bitangent * (radius * sin(phi)) + n * sqrt(1.0 - u.y);
        } else {
            vec3 h = environment_half(u, roughness);
            h = tangent * h.x + bitangent * h.y + n * h.z;
            l = 2.0 * dot(n, h) * h - n;
        }
        float w = mode == 1u ? 1.0 : max(dot(n, l), 0.0);
        sum += textureLod(source_texture, l, 0.0).rgb * w;
        weight += w;
    }
    return vec4(sum / max(weight, 0.00001), 1.0);
}
void main() { color = evaluate(texture_uv); }

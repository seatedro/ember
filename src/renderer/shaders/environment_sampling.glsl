vec2 environment_sample(uint i, uint count) {
    uint bits = i;
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return vec2(float(i) / float(count), float(bits) * 2.3283064365386963e-10);
}
vec3 environment_half(vec2 u, float roughness) {
    float a = roughness * roughness;
    float phi = 6.28318530718 * u.x;
    float z = sqrt((1.0 - u.y) / (1.0 + (a * a - 1.0) * u.y));
    float radius = sqrt(max(0.0, 1.0 - z * z));
    return vec3(radius * cos(phi), radius * sin(phi), z);
}
vec3 cube_direction(uint face, vec2 uv) {
    vec2 p = uv * 2.0 - 1.0;
    if (face == 0u) return normalize(vec3(1.0, -p.y, -p.x));
    if (face == 1u) return normalize(vec3(-1.0, -p.y, p.x));
    if (face == 2u) return normalize(vec3(p.x, 1.0, p.y));
    if (face == 3u) return normalize(vec3(p.x, -1.0, -p.y));
    if (face == 4u) return normalize(vec3(p.x, -p.y, 1.0));
    return normalize(vec3(-p.x, -p.y, -1.0));
}

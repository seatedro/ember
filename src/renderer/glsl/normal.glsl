vec3 mapped_normal(vec3 normal, vec3 tangent, vec3 bitangent, vec3 sample_value) {
    vec3 n = normalize(normal);
    float tangent_scale = max(abs(tangent.x), max(abs(tangent.y), abs(tangent.z)));
    if (tangent_scale == 0.0) {
        return n;
    }
    // Rebuild an orthonormal frame after interpolation and nonuniform scaling.
    vec3 t = tangent / tangent_scale;
    t -= n * dot(n, t);
    float tangent_length = dot(t, t);
    if (tangent_length < 0.000001) {
        return n;
    }
    t *= inversesqrt(tangent_length);
    vec3 b = cross(n, t);
    b *= dot(b, bitangent) < 0.0 ? -1.0 : 1.0;
    vec3 mapped = sample_value * 2.0 - 1.0;
    vec3 world = t * mapped.x + b * mapped.y + n * mapped.z;
    return dot(world, world) > 0.000001 ? normalize(world) : n;
}

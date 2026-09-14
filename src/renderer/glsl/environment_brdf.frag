in vec2 texture_uv;
layout(location = 0) out vec4 color;
layout(std140) uniform Material { uint face; float roughness; uint mode; uint samples; };
vec4 evaluate(vec2 uv) {
    float nv = max(uv.x, 0.0001);
    float roughness = max(uv.y, 0.001);
    vec3 v = vec3(sqrt(1.0 - nv * nv), 0, nv);
    vec2 result = vec2(0);
    for (uint i = 0u; i < samples; ++i) {
        vec3 h = environment_half(environment_sample(i, samples), roughness);
        vec3 l = 2.0 * dot(v, h) * h - v;
        float nl = max(l.z, 0.0);
        float nh = max(h.z, 0.0);
        float vh = max(dot(v, h), 0.0);
        if (nl > 0.0) {
            float k = roughness * roughness * 0.5;
            float g = (nv / (nv * (1.0 - k) + k)) * (nl / (nl * (1.0 - k) + k));
            float visibility = g * vh / max(nh * nv, 0.00001);
            float f = pow(1.0 - vh, 5.0);
            result += vec2(1.0 - f, f) * visibility;
        }
    }
    return vec4(result / float(samples), 0, 1);
}
void main() { color = evaluate(texture_uv); }

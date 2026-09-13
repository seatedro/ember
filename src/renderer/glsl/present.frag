#version 410 core
in vec2 texture_uv;
layout(location = 0) out vec4 color;
uniform sampler2D source_texture;
uniform sampler2D bloom_texture;

layout(std140) uniform Material {
    float exposure;
    uint tone_mapping;
    float bloom_strength;
};

vec3 aces_fitted(vec3 linear_color) {
    // ACES fit by Stephen Hill; matrices convert into and out of the fit's color space.
    mat3 input_matrix = mat3(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    mat3 output_matrix = mat3(
         1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    vec3 v = input_matrix * linear_color;
    vec3 numerator = v * (v + 0.0245786) - 0.000090537;
    vec3 denominator = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(output_matrix * (numerator / denominator), 0.0, 1.0);
}

vec3 linear_to_srgb(vec3 linear_color) {
    return mix(
        12.92 * linear_color,
        1.055 * pow(linear_color, vec3(1.0 / 2.4)) - 0.055,
        step(vec3(0.0031308), linear_color)
    );
}

void main() {
    vec4 source = texture(source_texture, texture_uv);
    vec3 linear_color = source.rgb;
    if (bloom_strength > 0.0) {
        linear_color += texture(bloom_texture, texture_uv).rgb * bloom_strength;
    }
    vec3 exposed = max(linear_color, vec3(0.0)) * exposure;
    vec3 mapped = tone_mapping == 0u ? exposed / (vec3(1.0) + exposed) : aces_fitted(exposed);
    color = vec4(linear_to_srgb(mapped), source.a);
}

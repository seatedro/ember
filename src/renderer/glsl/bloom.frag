#version 410 core
in vec2 texture_uv;
layout(location = 0) out vec4 color;
uniform sampler2D source_texture;

layout(std140) uniform Material {
    float threshold;
    float knee;
    uint mode;
    float level_weight;
};

vec3 sample_source(vec2 uv) {
    if (mode != 0u) {
        return texture(source_texture, uv).rgb;
    }

    // The scene texture may use nearest filtering for pixel-art presentation.
    ivec2 size = textureSize(source_texture, 0);
    vec2 pixel = uv * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(pixel));
    vec2 fraction = fract(pixel);
    vec3 a = texelFetch(source_texture, clamp(base, ivec2(0), size - 1), 0).rgb;
    vec3 b = texelFetch(source_texture, clamp(base + ivec2(1, 0), ivec2(0), size - 1), 0).rgb;
    vec3 c = texelFetch(source_texture, clamp(base + ivec2(0, 1), ivec2(0), size - 1), 0).rgb;
    vec3 d = texelFetch(source_texture, clamp(base + ivec2(1, 1), ivec2(0), size - 1), 0).rgb;
    return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
}

vec3 downsample(vec2 texel) {
    vec3 result = sample_source(texture_uv) * 0.125;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) {
                continue;
            }
            vec2 offset = vec2(x, y) * texel;
            bool corner = x != 0 && y != 0;
            result += sample_source(texture_uv + offset) * (corner ? 0.03125 : 0.0625);
            if (corner) {
                result += sample_source(texture_uv + offset * 0.5) * 0.125;
            }
        }
    }
    return result;
}

vec3 upsample(vec2 texel) {
    vec3 result = vec3(0.0);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float weight = float((2 - abs(x)) * (2 - abs(y))) / 16.0;
            result += texture(source_texture, texture_uv + vec2(x, y) * texel).rgb * weight;
        }
    }
    return result;
}

void main() {
    vec2 texel = 1.0 / vec2(textureSize(source_texture, 0));
    vec3 result = mode == 2u ? upsample(texel) : downsample(texel);
    if (mode == 0u) {
        result = max(result, vec3(0.0));
        float brightness = max(max(result.r, result.g), result.b);
        float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
        soft = soft * soft / max(4.0 * knee, 0.0001);
        // Keep strength stable when resizing changes the number of bloom levels.
        result *= level_weight * max(soft, brightness - threshold) / max(brightness, 0.0001);
    }
    color = vec4(result, 0.0);
}

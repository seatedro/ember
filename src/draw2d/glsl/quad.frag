#version 410 core
in vec2 texture_uv;
in vec4 vertex_color;
flat in float pixel_range;
uniform sampler2D source_texture;
layout(location = 0) out vec4 color;

float median(vec3 value) {
    return max(min(value.r, value.g), min(max(value.r, value.g), value.b));
}

void main() {
    vec4 sample_color = texture(source_texture, texture_uv);
    if (pixel_range > 0.0) {
        // Convert atlas distances to screen pixels so edge coverage follows text scale.
        vec2 unit_range = vec2(pixel_range) / vec2(textureSize(source_texture, 0));
        float screen_range = max(0.5 * dot(unit_range, 1.0 / fwidth(texture_uv)), 1.0);
        float coverage = clamp(screen_range * (median(sample_color.rgb) - 0.5) + 0.5, 0.0, 1.0);
        color = vec4(vertex_color.rgb, vertex_color.a * coverage);
    } else {
        color = sample_color * vertex_color;
    }
}

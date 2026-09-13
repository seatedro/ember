#version 410 core
in vec2 texture_uv;
layout(location = 0) out vec4 color;
uniform sampler2D source_texture;

layout(std140) uniform Material {
    ivec2 scale;
    uvec2 padding;
};

void main() {
    ivec2 size = textureSize(source_texture, 0) / scale;
    ivec2 base = clamp(ivec2(texture_uv * vec2(size)), ivec2(0), size - 1) * scale;
    vec4 sum = vec4(0.0);
    for (int y = 0; y < scale.y; ++y) {
        for (int x = 0; x < scale.x; ++x) {
            sum += texelFetch(source_texture, base + ivec2(x, y), 0);
        }
    }
    color = sum / float(scale.x * scale.y);
}

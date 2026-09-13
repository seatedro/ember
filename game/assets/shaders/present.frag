#version 410 core
in vec2 texture_uv;
layout(location = 0) out vec4 color;
uniform sampler2D source_texture;

layout(std140) uniform Material {
    vec4 tint;
};

void main() {
    color = texture(source_texture, texture_uv) * tint;
}

#version 450
#extension GL_GOOGLE_include_directive : require
#include "shaders/texture.glsl"

layout(location = 0) in vec2 texture_uv;
layout(location = 1) in vec4 vertex_color;
layout(binding = 0) uniform sampler2D source_texture;
layout(location = 0) out vec4 output_color;

void main() {
    output_color = sample_texture(source_texture, texture_uv) * vertex_color;
}

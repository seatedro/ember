#version 410 core
in vec2 texture_uv;
in vec4 vertex_color;
uniform sampler2D source_texture;
out vec4 output_color;

void main() {
    output_color = texture(source_texture, texture_uv) * vertex_color;
}

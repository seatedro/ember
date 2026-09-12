#version 410 core
in vec3 line_color;
layout(location = 0) out vec4 color;

layout(std140) uniform Material {
    vec4 tint;
};

void main() {
    color = vec4(line_color, 1.0) * tint;
}

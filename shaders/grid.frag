#version 410 core
in vec3 line_color;
layout(location = 0) out vec4 color;

void main() {
    color = vec4(line_color, 1.0);
}

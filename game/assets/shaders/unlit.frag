#version 410 core
layout(location = 0) out vec4 color;

layout(std140) uniform Material {
    vec4 tint;
};

void main() {
    color = tint;
}

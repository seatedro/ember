#version 450
layout(location = 0) out vec4 color;

layout(std140, binding = 2) uniform Material {
    vec4 tint;
};

void main() {
    color = tint;
}

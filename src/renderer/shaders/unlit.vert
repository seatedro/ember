#version 450
#extension GL_GOOGLE_include_directive : require
#include "instance.glsl"
#include "view.glsl"

layout(location = 0) in vec3 position;

void main() {
    gl_Position = view_projection * (instance_model() * vec4(position, 1.0));
}

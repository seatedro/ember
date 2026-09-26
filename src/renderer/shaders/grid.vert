#version 450
#extension GL_GOOGLE_include_directive : require
#include "instance.glsl"
#include "view.glsl"

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 vertex_color;

layout(location = 0) out vec3 line_color;

void main() {
    vec4 world_position = instance_model() * vec4(position, 1.0);
    gl_Position = view_projection * world_position;
    line_color = vertex_color;
}

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 vertex_color;

layout(std140) uniform Per_View {
    mat4 view_projection;
};

out vec3 line_color;

void main() {
    vec4 world_position = instance_model() * vec4(position, 1.0);
    gl_Position = view_projection * world_position;
    line_color = vertex_color;
}

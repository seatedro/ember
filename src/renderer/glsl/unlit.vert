layout(location = 0) in vec3 position;

layout(std140) uniform Per_View {
    mat4 view_projection;
};

void main() {
    gl_Position = view_projection * (instance_model() * vec4(position, 1.0));
}

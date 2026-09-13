layout(location = 0) in vec3 position;
layout(location = 2) in vec2 uv;

layout(std140) uniform Per_View {
    mat4 view_projection;
};

out vec2 texture_uv;

void main() {
    gl_Position = view_projection * (instance_model() * vec4(position, 1.0));
    texture_uv = uv;
}

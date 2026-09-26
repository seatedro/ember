layout(std140, binding = 0) uniform Per_View {
    mat4 view_projection;
    vec4 camera_position;
};

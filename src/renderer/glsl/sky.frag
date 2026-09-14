#version 410 core
in vec2 texture_uv;
layout(location = 0) out vec4 color;
layout(std140) uniform Material { mat4 inverse_view_projection; vec4 settings; };
uniform samplerCube source_texture;
void main() {
    vec4 p = inverse_view_projection * vec4(texture_uv * 2.0 - 1.0, 1.0, 1.0);
    vec3 d = normalize(p.xyz / p.w);
    float c = cos(settings.y), s = sin(settings.y);
    d = vec3(c*d.x + s*d.z, d.y, -s*d.x + c*d.z);
    color = vec4(textureLod(source_texture, d, 0.0).rgb * settings.x, 1.0);
}

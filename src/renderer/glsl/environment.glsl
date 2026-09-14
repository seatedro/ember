uniform samplerCube environment_diffuse;
uniform samplerCube environment_specular;
uniform sampler2D environment_brdf;
vec3 environment_direction(vec3 d, float angle) {
    float c = cos(angle), s = sin(angle);
    return vec3(c*d.x + s*d.z, d.y, -s*d.x + c*d.z);
}
vec3 environment_lighting(vec3 normal, vec3 view, vec3 albedo, float metallic, float roughness, vec4 settings) {
    if (settings.x == 0.0) return vec3(0);
    normal = normalize(normal);
    view = pbr_direction(view);
    metallic = clamp(metallic, 0.0, 1.0);
    roughness = clamp(roughness, 0.05, 1.0);
    float nv = max(dot(normal, view), 0.0);
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 f = f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(1.0 - nv, 5.0);
    vec3 n = environment_direction(normal, settings.y);
    vec3 reflection = environment_direction(reflect(-view, normal), settings.y);
    vec3 diffuse = texture(environment_diffuse, n).rgb;
    vec3 specular = textureLod(environment_specular, reflection, roughness * settings.z).rgb;
    vec2 brdf = texture(environment_brdf, vec2(nv, roughness)).rg;
    return ((1.0 - f) * (1.0 - metallic) * albedo * diffuse + specular * (f0 * brdf.x + brdf.y)) * settings.x;
}

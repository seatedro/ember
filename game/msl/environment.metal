struct Environment_Uniforms { float4x4 inverse_view_projection; float4 sun; };
fragment float4 environment_fragment(Screen_Varyings input [[stage_in]], constant Environment_Uniforms &Material [[buffer(4)]]) {
    float4 p = Material.inverse_view_projection * float4(input.texture_uv * 2.0 - 1.0, 1.0, 1.0);
    float3 d = normalize(p.xyz / p.w);
    float band = pow(max(0.0, 1.0 - abs(d.y + 0.25 * sin(d.x * 4.0))), 8.0);
    float3 sky = mix(float3(0.008, 0.012, 0.025), float3(0.12, 0.18, 0.32), band);
    float disk = smoothstep(0.97, 0.995, dot(d, Material.sun.xyz));
    return float4(sky + float3(1.0, 0.75, 0.4) * disk * Material.sun.w, 1.0);
}

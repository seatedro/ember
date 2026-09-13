#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 corner [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float3 center [[attribute(3)]];
    float2 size [[attribute(4)]];
    float rotation [[attribute(5)]];
    float4 color [[attribute(6)]];
};

struct View_Uniforms {
    float4x4 view_projection;
    float4 camera_right;
    float4 camera_up;
};

struct Varyings {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex Varyings vertex_main(Vertex input [[stage_in]], constant View_Uniforms &View [[buffer(2)]]) {
    float2 offset = input.corner * input.size;
    float c = cos(input.rotation), s = sin(input.rotation);
    offset = float2(c * offset.x - s * offset.y, s * offset.x + c * offset.y);
    float3 world = input.center + View.camera_right.xyz * offset.x + View.camera_up.xyz * offset.y;
    float4 position = View.view_projection * float4(world, 1);
    position.z = (position.z + position.w) * 0.5;
    return {position, input.uv, input.color};
}

fragment float4 fragment_main(Varyings input [[stage_in]], texture2d<float> source_texture [[texture(0)]], sampler source_texture_sampler [[sampler(0)]]) {
    return source_texture.sample(source_texture_sampler, float2(input.uv.x, 1 - input.uv.y)) * input.color;
}

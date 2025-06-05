#include <metal_stdlib>
using namespace metal;

struct VertexInput {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOutput {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float4x4 projectionMatrix;
};

// Vertex shader for texture rendering
vertex VertexOutput texture_vertex(VertexInput in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOutput out;
    out.position = uniforms.projectionMatrix * float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// Fragment shader for texture rendering
fragment float4 texture_fragment(VertexOutput in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                sampler texSampler [[sampler(0)]]) {
    return tex.sample(texSampler, in.texCoord);
}
#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[attribute(0)]];
    float3 color [[attribute(1)]];
};

struct Varyings {
    float4 position [[position]];
    float3 color;
};

vertex Varyings vertex_main(Vertex input [[stage_in]]) {
    Varyings output;
    output.position = float4(input.position, 1.0);
    // Ember uses OpenGL clip depth [-w, w]; Metal expects [0, w].
    output.position.z = (output.position.z + output.position.w) * 0.5;
    output.color = input.color;
    return output;
}

fragment float4 fragment_main(Varyings input [[stage_in]]) {
    return float4(input.color, 1.0);
}

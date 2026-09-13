#include <metal_stdlib>
using namespace metal;
struct Quad_Vertex {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float4 tint [[attribute(2)]];
    float distance_range [[attribute(3)]];
};

struct Quad_Varyings {
    float4 position [[position]];
    float2 uv;
    float4 tint;
    float pixel_range [[flat]];
};

struct Quad_View { float2 logical_size; float2 padding; };

vertex Quad_Varyings vertex_main(Quad_Vertex input [[stage_in]], constant Quad_View &View [[buffer(2)]]) {
    return {float4(input.position / View.logical_size * float2(2,-2) + float2(-1,1),0.5,1), input.uv, input.tint, input.distance_range};

}

float median(float3 value) {
    return max(min(value.r,value.g),min(max(value.r,value.g),value.b));
}

fragment float4 fragment_main(Quad_Varyings input [[stage_in]], texture2d<float> source_texture [[texture(0)]], sampler source_texture_sampler [[sampler(0)]]) {
    float4 sample_color = source_texture.sample(source_texture_sampler,float2(input.uv.x,1-input.uv.y));
    if (input.pixel_range > 0) {
        float2 unit_range = float2(input.pixel_range)/float2(source_texture.get_width(),source_texture.get_height());
        float screen_range = max(0.5*dot(unit_range,1.0/fwidth(input.uv)),1.0);
        float coverage = clamp(screen_range*(median(sample_color.rgb)-0.5)+0.5,0.0,1.0);
        return float4(input.tint.rgb,input.tint.a*coverage);
    }

    return sample_color*input.tint;
}

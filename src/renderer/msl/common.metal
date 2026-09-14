#include <metal_stdlib>
using namespace metal;

// MSL buffer slots 0 and 1 are vertex and instance streams. Uniform argument
// names are reflected into RHI bindings; samplers use <texture-name>_sampler.
struct View_Uniforms { float4x4 view_projection; float4 camera_position; };

struct Tint_Uniforms { float4 tint; };

struct Point_Light { float4 position_range; float4 color_intensity; };

struct Directional_Light { float4 direction; float4 color_intensity; };

struct Lighting_Data {
    float4 ambient;
    uint point_light_count;
    uint directional_light_count;
    Point_Light point_lights[16];
    Directional_Light directional_lights[4];
    float4x4 shadow_matrix;
    float4 shadow_bias;
    uint shadow_light_index;
    uint shadow_enabled;
    float4 environment;

};

float4 clip_position(float4 position) {
    position.z = (position.z + position.w) * 0.5;
    return position;
}

// RHI texture coordinates have their origin at the bottom left. Uploads and
// render targets both use Metal's top-left storage, so sampling converts here.
float4 sample_texture(texture2d<float> image, sampler state, float2 uv) {
    return image.sample(state, float2(uv.x, 1.0 - uv.y));
}

float4 fetch_texture(texture2d<float> image, int2 pixel) {
    return image.read(uint2(pixel.x, int(image.get_height()) - 1 - pixel.y));
}

float4x4 instance_model(float4 row0, float4 row1, float4 row2) {
    return float4x4(float4(row0.x, row1.x, row2.x, 0),
                    float4(row0.y, row1.y, row2.y, 0),
                    float4(row0.z, row1.z, row2.z, 0),
                    float4(row0.w, row1.w, row2.w, 1));
}

float3 transform_normal(float4x4 model, float3 normal) {
    float3 a = model[0].xyz, b = model[1].xyz, c = model[2].xyz;
    float3x3 cofactors = float3x3(cross(b,c), cross(c,a), cross(a,b));
    return (cofactors * normal) / dot(a, cross(b,c));
}

float3 diffuse_lighting(float3 position, float3 normal, constant Lighting_Data &lighting, float shadow_visibility) {
    normal = normalize(normal);
    float3 illumination = lighting.ambient.rgb;
    for (uint i = 0; i < lighting.point_light_count; ++i) {
        Point_Light light = lighting.point_lights[i];
        float3 to_light = light.position_range.xyz - position;
        float distance_squared = dot(to_light, to_light);
        float radius = light.position_range.w;
        float attenuation = max(1.0 - distance_squared / (radius * radius), 0.0);
        attenuation *= attenuation;
        float3 direction = to_light * rsqrt(max(distance_squared, 0.000001));
        float diffuse = max(dot(normal, direction), 0.0);
        illumination += light.color_intensity.rgb * light.color_intensity.w * attenuation * diffuse;
    }

    for (uint i = 0; i < lighting.directional_light_count; ++i) {
        Directional_Light light = lighting.directional_lights[i];
        float diffuse = max(dot(normal, light.direction.xyz), 0.0);
        float visibility = i == lighting.shadow_light_index ? shadow_visibility : 1.0;
        illumination += light.color_intensity.rgb * light.color_intensity.w * diffuse * visibility;
    }

    return illumination;
}

float3 diffuse_lighting(float3 position, float3 normal, constant Lighting_Data &lighting) {
    return diffuse_lighting(position, normal, lighting, 1.0);
}

struct Mesh_Vertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float3 tangent [[attribute(6)]];
    float3 bitangent [[attribute(7)]];
    float4 row0 [[attribute(3)]];
    float4 row1 [[attribute(4)]];
    float4 row2 [[attribute(5)]];
};

struct Mesh_Varyings {
    float4 position [[position]];
    float3 world_position;
    float3 view_direction;
    float3 world_normal;
    float3 world_tangent;
    float3 world_bitangent;
    float3 local_normal;
    float2 texture_uv;
    float point_size [[point_size]];
};

vertex Mesh_Varyings mesh_vertex(Mesh_Vertex input [[stage_in]], constant View_Uniforms &Per_View [[buffer(2)]]) {
    float4x4 model = instance_model(input.row0, input.row1, input.row2);
    float4 world = model * float4(input.position, 1);
    Mesh_Varyings output;
    output.position = clip_position(Per_View.view_projection * world);
    output.world_position = world.xyz;
    output.view_direction = Per_View.camera_position.xyz - world.xyz;
    output.world_normal = transform_normal(model, input.normal);
    output.world_tangent = (model * float4(input.tangent, 0)).xyz;
    output.world_bitangent = (model * float4(input.bitangent, 0)).xyz;
    output.local_normal = input.normal;
    output.texture_uv = input.uv;
    output.point_size = 1;
    return output;
}

struct Flat_Vertex {
    float3 position [[attribute(0)]];
    float4 row0 [[attribute(3)]];
    float4 row1 [[attribute(4)]];
    float4 row2 [[attribute(5)]];
};

struct Flat_Varyings { float4 position [[position]]; float point_size [[point_size]]; };

vertex Flat_Varyings unlit_vertex(Flat_Vertex input [[stage_in]], constant View_Uniforms &Per_View [[buffer(2)]]) {
    return {clip_position(Per_View.view_projection * (instance_model(input.row0, input.row1, input.row2) * float4(input.position,1))), 1};

}

fragment float4 unlit_fragment(Flat_Varyings input [[stage_in]], constant Tint_Uniforms &Material [[buffer(4)]]) {
    return Material.tint;
}

struct Grid_Vertex {
    float3 position [[attribute(0)]];
    float3 color [[attribute(1)]];
    float4 row0 [[attribute(3)]];
    float4 row1 [[attribute(4)]];
    float4 row2 [[attribute(5)]];
};

struct Grid_Varyings { float4 position [[position]]; float3 color; float point_size [[point_size]]; };

vertex Grid_Varyings grid_vertex(Grid_Vertex input [[stage_in]], constant View_Uniforms &Per_View [[buffer(2)]]) {
    return {clip_position(Per_View.view_projection * (instance_model(input.row0,input.row1,input.row2) * float4(input.position,1))), input.color, 1};

}

fragment float4 grid_fragment(Grid_Varyings input [[stage_in]], constant Tint_Uniforms &Material [[buffer(4)]]) {
    return float4(input.color,1) * Material.tint;
}

struct Screen_Vertex {
    float3 position [[attribute(0)]];
    float2 uv [[attribute(2)]];
    float4 row0 [[attribute(3)]];
    float4 row1 [[attribute(4)]];
    float4 row2 [[attribute(5)]];
};

struct Screen_Varyings { float4 position [[position]]; float2 texture_uv; float point_size [[point_size]]; };

vertex Screen_Varyings screen_vertex(Screen_Vertex input [[stage_in]], constant View_Uniforms &Per_View [[buffer(2)]]) {
    return {clip_position(Per_View.view_projection * (instance_model(input.row0,input.row1,input.row2) * float4(input.position,1))), input.uv, 1};

}

float3 mapped_normal(float3 normal, float3 tangent, float3 bitangent, float3 sample_value) {
    float3 n = normalize(normal);
    float tangent_scale = max(abs(tangent.x), max(abs(tangent.y), abs(tangent.z)));
    if (tangent_scale == 0.0) {
        return n;
    }
    // Rebuild an orthonormal frame after interpolation and nonuniform scaling.
    float3 t = tangent / tangent_scale;
    t -= n * dot(n, t);
    float tangent_length = dot(t, t);
    if (tangent_length < 0.000001) {
        return n;
    }
    t *= rsqrt(tangent_length);
    float3 b = cross(n, t);
    b *= dot(b, bitangent) < 0.0 ? -1.0 : 1.0;
    float3 mapped = sample_value * 2.0 - 1.0;
    float3 world = t * mapped.x + b * mapped.y + n * mapped.z;
    return dot(world, world) > 0.000001 ? normalize(world) : n;
}

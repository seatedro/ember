struct Bloom_Uniforms { float threshold; float knee; uint mode; float level_weight; };

float3 sample_source(texture2d<float> image, sampler state, float2 uv, uint mode) {
    if (mode != 0) {
        return sample_texture(image, state, uv).rgb;
    }

    int2 size = int2(image.get_width(), image.get_height());
    float2 pixel = uv * float2(size) - 0.5;
    int2 base = int2(floor(pixel));
    float2 fraction = fract(pixel);
    float3 a = fetch_texture(image, clamp(base, int2(0), size-1)).rgb;
    float3 b = fetch_texture(image, clamp(base+int2(1,0), int2(0), size-1)).rgb;
    float3 c = fetch_texture(image, clamp(base+int2(0,1), int2(0), size-1)).rgb;
    float3 d = fetch_texture(image, clamp(base+int2(1,1), int2(0), size-1)).rgb;
    return mix(mix(a,b,fraction.x), mix(c,d,fraction.x), fraction.y);
}

fragment float4 bloom_fragment(Screen_Varyings input [[stage_in]],
    constant Bloom_Uniforms &Material [[buffer(4)]],
    texture2d<float> source_texture [[texture(0)]], sampler source_texture_sampler [[sampler(0)]]) {
    float2 texel = 1.0 / float2(source_texture.get_width(), source_texture.get_height());
    float3 result = float3(0);

    if (Material.mode == 2) {
        for (int y=-1; y<=1; ++y) {
            for (int x=-1; x<=1; ++x) {
                float weight = float((2-abs(x))*(2-abs(y))) / 16.0;
                result += sample_texture(source_texture,source_texture_sampler,input.texture_uv+float2(x,y)*texel).rgb * weight;
            }
        }
    } else {
        result = sample_source(source_texture,source_texture_sampler,input.texture_uv,Material.mode) * 0.125;
        for (int y=-1; y<=1; ++y) {
            for (int x=-1; x<=1; ++x) {
                if (x==0 && y==0) {
                    continue;
                }

                float2 offset = float2(x,y)*texel;
                bool corner = x!=0 && y!=0;
                result += sample_source(source_texture,source_texture_sampler,input.texture_uv+offset,Material.mode) * (corner ? 0.03125 : 0.0625);
                if (corner) {
                    result += sample_source(source_texture,source_texture_sampler,input.texture_uv+offset*0.5,Material.mode) * 0.125;
                }

            }

        }

    }

    if (Material.mode == 0) {
        result = max(result,float3(0));
        float brightness = max(max(result.r,result.g),result.b);
        float soft = clamp(brightness-Material.threshold+Material.knee,0.0,2.0*Material.knee);
        soft = soft*soft / max(4.0*Material.knee,0.0001);
        result *= Material.level_weight * max(soft,brightness-Material.threshold) / max(brightness,0.0001);
    }

    return float4(result,0);
}

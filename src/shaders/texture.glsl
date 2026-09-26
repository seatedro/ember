// RHI texture coordinates start at the bottom left. Metal stores uploads and
// render targets top-left, so the MSL build flips rows when reading. Cube maps
// are exempt and are sampled directly.
vec4 sample_texture(sampler2D image, vec2 uv) {
#ifdef EMBER_MSL
    uv.y = 1.0 - uv.y;
#endif
    return texture(image, uv);
}

vec4 fetch_texture(sampler2D image, ivec2 pixel) {
#ifdef EMBER_MSL
    pixel.y = textureSize(image, 0).y - 1 - pixel.y;
#endif
    return texelFetch(image, pixel, 0);
}

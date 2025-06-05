# Metal Backend Texture Rendering

This document describes the Metal backend texture rendering implementation for the Ember rendering engine.

## Overview

The Metal backend now supports hardware-accelerated texture rendering using compiled Metal shaders, similar to the OpenGL and SDL backends. This implementation provides:

- Hardware-accelerated texture rendering using Metal Shading Language (MSL)
- Automatic shader compilation during build process
- Support for texture batching and individual texture drawing
- Proper alpha blending and texture sampling

## Architecture

### Shader Pipeline

The texture rendering uses a separate Metal shader pipeline from the main ImGui rendering:

1. **Vertex Shader** (`texture_vertex`): Transforms screen coordinates to clip space using an orthographic projection matrix
2. **Fragment Shader** (`texture_fragment`): Samples the texture using provided texture coordinates

### Build Process

Metal shaders are automatically compiled during the build process when targeting macOS with the Metal renderer:

1. `texture_shaders.metal` → `texture_shaders.air` (Metal compilation)
2. `texture_shaders.air` → `texture_shaders.metal-ar` (Metal archive)
3. `texture_shaders.metal-ar` → `texture_shaders.metallib` (Metal library)

The compiled `.metallib` file is embedded into the binary using `@embedFile`.

### Key Components

#### Vertex Structure
```zig
const TextureVertex = struct {
    position: [2]f32,    // Screen space coordinates
    texCoord: [2]f32,    // Texture coordinates (0.0 - 1.0)
};
```

#### Uniforms Structure
```zig
const TextureUniforms = struct {
    projectionMatrix: [16]f32,  // Orthographic projection matrix
};
```

#### Context Extensions
The Metal context now includes additional resources for texture rendering:
- `texture_library`: Compiled shader library
- `texture_pipeline_state`: Render pipeline state for textures
- `texture_vertex_buffer`: Buffer for quad vertices
- `texture_uniform_buffer`: Buffer for projection matrix
- `texture_sampler`: Sampler state for texture filtering

## Usage

The Metal backend implements the standard texture rendering interface:

```zig
// Load a texture
const texture = try loadTexture(ctx, "path/to/image.png");

// Draw texture to screen
try drawTexture(ctx, texture, src_rect, dst_rect);

// Draw multiple instances of the same texture
try drawTextureBatch(ctx, texture, src_rect, dst_rects);

// Clean up
destroyTexture(texture);
```

### Parameters

- **ctx**: Metal rendering context
- **texture**: Loaded texture object containing MTLTexture
- **src_rect**: Optional source rectangle for texture clipping (null = full texture)
- **dst_rect**: Destination rectangle in screen coordinates

## Implementation Details

### Coordinate Systems

- **Screen Coordinates**: Origin at top-left, Y increases downward
- **Texture Coordinates**: Origin at top-left, normalized (0.0 - 1.0)
- **Clip Space**: Origin at center, range [-1, 1] for both axes

### Rendering Process

1. **Setup**: Create orthographic projection matrix based on window size
2. **Vertex Generation**: Generate quad vertices for destination rectangle
3. **Buffer Updates**: Update vertex and uniform buffers with current data
4. **Pipeline Binding**: Set texture rendering pipeline state
5. **Resource Binding**: Bind vertex buffer, uniform buffer, texture, and sampler
6. **Draw Call**: Issue triangle draw call (6 vertices = 2 triangles)

### Alpha Blending

The implementation uses standard alpha blending:
- Source Factor: `source_alpha`
- Destination Factor: `one_minus_source_alpha`
- Operation: `add`

This provides proper transparency support for textures with alpha channels.

## Build Requirements

### macOS
- Xcode Command Line Tools (for `xcrun`, `metal`, `metal-ar`, `metallib`)
- macOS SDK with Metal framework

### Build Configuration
The Metal shader compilation only occurs when:
- Target OS is macOS (`target.os.tag == .macos`)
- Renderer backend is Metal (`config.renderer == .Metal`)

## Files

- `texture_shaders.metal`: Metal Shading Language source code
- `compiled/`: Directory for compiled shader artifacts (git-ignored)
- `api.zig`: Metal API definitions and enums
- `shaders.zig`: Existing shader management (for ImGui rendering)
- `../metal.zig`: Main Metal backend implementation

## Performance Considerations

### Current Implementation
- Each `drawTexture` call updates vertex and uniform buffers
- No geometry batching (each call is individual draw)
- Uses shared memory for buffers (accessible to both CPU and GPU)

### Future Optimizations
- **Instanced Rendering**: Use instanced draws for `drawTextureBatch`
- **Persistent Buffers**: Cache uniform data when projection doesn't change
- **Geometry Batching**: Combine multiple texture draws into single draw call
- **Buffer Streaming**: Use multiple buffers to avoid stalls

## Troubleshooting

### Common Issues

1. **Shader Compilation Fails**:
   - Ensure Xcode Command Line Tools are installed
   - Verify `xcrun metal` is available in PATH
   - Check Metal shader syntax in `texture_shaders.metal`

2. **Textures Not Displaying**:
   - Verify texture loading succeeded
   - Check projection matrix calculation
   - Ensure current render encoder exists

3. **Build Errors**:
   - Confirm targeting macOS with Metal renderer
   - Check that shader compilation step dependencies are correct

### Debug Information
Enable Metal validation layers by setting environment variable:
```bash
export METAL_DEVICE_WRAPPER_TYPE=1
export METAL_DEBUG_ERROR_MODE=1
```

## License

This implementation follows the same license as the main project.
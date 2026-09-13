struct Shadow_Varyings { float4 position [[position]]; };

vertex Shadow_Varyings shadow_vertex(Mesh_Vertex input [[stage_in]], constant View_Uniforms &Per_View [[buffer(2)]]) {
    float4 world = instance_model(input.row0, input.row1, input.row2) * float4(input.position, 1);
    return {clip_position(Per_View.view_projection * world)};
}

fragment void shadow_fragment() {}

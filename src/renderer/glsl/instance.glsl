layout(location = 3) in vec4 model_row0;
layout(location = 4) in vec4 model_row1;
layout(location = 5) in vec4 model_row2;

mat4 instance_model() {
    return mat4(
        vec4(model_row0.x, model_row1.x, model_row2.x, 0.0),
        vec4(model_row0.y, model_row1.y, model_row2.y, 0.0),
        vec4(model_row0.z, model_row1.z, model_row2.z, 0.0),
        vec4(model_row0.w, model_row1.w, model_row2.w, 1.0)
    );
}

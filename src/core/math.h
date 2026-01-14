#pragma once

#include "core.h"

namespace ember {

struct vec2 {
    f32 x, y;
};

struct vec3 {
    f32 x, y, z;
};

struct vec4 {
    f32 x, y, z, w;
};

struct mat4 {
    f32 data[16]; // col major
};

struct quat {
    f32 x, y, z, w;
};

// cheating here and overloading ops for ease of use
inline vec3 operator+(vec3 a, vec3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline vec3 operator-(vec3 a, vec3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline vec3 operator*(vec3 a, f32 s) { return { a.x * s, a.y * s, a.z * s }; }
inline vec3 operator*(f32 s, vec3 a) { return { a.x * s, a.y * s, a.z * s }; }

mat4 operator*(mat4 a, mat4 b);

f32 dot(vec3 a, vec3 b);
vec3 cross(vec3 a, vec3 b);
f32 length(vec3 v);
vec3 normalize(vec3 v);

mat4 identity();
mat4 translate(vec3 t);
mat4 rotate(quat q);
mat4 scale(vec3 s);
mat4 perspective(f32 fov, f32 aspect, f32 near, f32 far);
mat4 look_at(vec3 eye, vec3 target, vec3 up);

quat axis_angle(vec3 axis, f32 rads);
mat4 to_mat4(quat q);

inline mat4 rotate_x(f32 rads) { return rotate(axis_angle({ 1, 0, 0 }, rads)); }
inline mat4 rotate_y(f32 rads) { return rotate(axis_angle({ 0, 1, 0 }, rads)); }
inline mat4 rotate_z(f32 rads) { return rotate(axis_angle({ 0, 0, 1 }, rads)); }

} // namespace ember

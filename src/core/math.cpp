#include "math.h"
#include <cmath>

namespace ember {

f32 dot(vec3 a, vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

vec3 cross(vec3 a, vec3 b) {
    return {
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    };
}

f32 length(vec3 v) { return sqrtf(dot(v, v)); }

vec3 normalize(vec3 v) { return v * (1.0f / length(v)); }

mat4 identity() {
    mat4 m = {};
    m.data[0] = 1.0f;
    m.data[5] = 1.0f;
    m.data[10] = 1.0f;
    m.data[15] = 1.0f;
    return m;
}

mat4 operator*(mat4 a, mat4 b) {
    mat4 c = {};
    for (int col = 0; col < 4; col++) {
        for (int row = 0; row < 4; row++) {
            c.data[col * 4 + row] = a.data[0 * 4 + row] * b.data[col * 4 + 0]
                + a.data[1 * 4 + row] * b.data[col * 4 + 1]
                + a.data[2 * 4 + row] * b.data[col * 4 + 2]
                + a.data[3 * 4 + row] * b.data[col * 4 + 3];
        }
    }

    return c;
}

mat4 translate(vec3 t) {
    mat4 m = identity();
    m.data[12] = t.x;
    m.data[13] = t.y;
    m.data[14] = t.z;
    return m;
}

mat4 scale(vec3 s) {
    mat4 m = {};
    m.data[0] = s.x;
    m.data[5] = s.y;
    m.data[10] = s.z;
    m.data[15] = 1.0f;
    return m;
}

mat4 perspective(f32 fov, f32 aspect, f32 near, f32 far) {
    mat4 m = {};
    f32  tan_half_fov = tanf(fov / 2.0f);

    m.data[0] = 1.0f / (aspect * tan_half_fov);
    m.data[5] = 1.0f / tan_half_fov;
    m.data[10] = -(far * near) / (far - near);
    m.data[11] = -1.0f;
    m.data[14] = -(2.0f * far * near) / (far - near);

    return m;
}

mat4 rotate(quat q) {
    mat4 m = identity();

    f32 xx = q.x * q.x;
    f32 yy = q.y * q.y;
    f32 zz = q.z * q.z;
    f32 xy = q.x * q.y;
    f32 xz = q.x * q.z;
    f32 yz = q.y * q.z;
    f32 wx = q.w * q.x;
    f32 wy = q.w * q.y;
    f32 wz = q.w * q.z;

    m.data[0] = 1.0f - 2.0f * (yy + zz);
    m.data[1] = 2.0f * (xy + wz);
    m.data[2] = 2.0f * (xz - wy);

    m.data[4] = 2.0f * (xy - wz);
    m.data[5] = 1.0f - 2.0f * (xx + zz);
    m.data[6] = 2.0f * (yz + wx);

    m.data[8] = 2.0f * (xz + wy);
    m.data[9] = 2.0f * (yz - wx);
    m.data[10] = 1.0f - 2.0f * (xx + yy);

    return m;
}

} // namespace ember

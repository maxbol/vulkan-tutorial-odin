package unitmath

import m "core:math"
import l "core:math/linalg"

Vec2 :: distinct l.Vector2f32
Vec3 :: distinct l.Vector3f32
Vec4 :: distinct l.Vector4f32

Mat2 :: distinct l.Matrix2x2f32
Mat3 :: distinct l.Matrix3x3f32
Mat4 :: distinct l.Matrix4x4f32

vec2 :: proc(x: f32, y: f32) -> Vec2 {
	return {x, y}
}

vec3_literal :: proc(x: f32, y: f32, z: f32) -> Vec3 {
	return {x, y, z}
}

vec3_fromvec2 :: proc(v: Vec2, z: f32) -> Vec3 {
	return {v.x, v.y, z}
}

vec3 :: proc {
	vec3_literal,
	vec3_fromvec2,
}


vec4_literal :: proc(x: f32, y: f32, z: f32, w: f32) -> Vec4 {
	return {x, y, z, w}
}

vec4_fromvec2 :: proc(v: Vec2, z: f32, w: f32) -> Vec4 {
	return {v.x, v.y, z, w}
}

vec4_fromvec3 :: proc(v: Vec3, w: f32) -> Vec4 {
	return {v.x, v.y, v.z, w}
}

vec4 :: proc {
	vec4_literal,
	vec4_fromvec2,
	vec4_fromvec3,
}


normalize_vec :: proc {
	normalize_vec2,
	normalize_vec3,
	normalize_vec4,
}

normalize_vec2 :: proc(vec: Vec2) -> Vec2 {
	l := m.sqrt(vec.x * vec.x + vec.y * vec.y)
	return Vec2{vec.x / l, vec.y / l}
}

normalize_vec3 :: proc(vec: Vec3) -> Vec3 {
	l := m.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
	return Vec3{vec.x / l, vec.y / l, vec.z / l}
}

normalize_vec4 :: proc(vec: Vec4) -> Vec4 {
	l := m.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z + vec.w * vec.w)
	return Vec4{vec.x / l, vec.y / l, vec.z / l, vec.w / l}
}

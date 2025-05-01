package renderer_vulkan_camera

import um "../../../../unitmath"
import m "core:math"
import l "core:math/linalg"

Camera :: struct {
	projection_matrix:   um.Mat4,
	view_matrix:         um.Mat4,
	inverse_view_matrix: um.Mat4,
}

camera_set_orthographic_projection :: proc(
	using camera: ^Camera,
	left: f32,
	right: f32,
	top: f32,
	bottom: f32,
	near: f32,
	far: f32,
) {
	projection_matrix = um.MAT4_ONES
	projection_matrix[0][0] = 2 / (right - left)
	projection_matrix[1][1] = 2 / (bottom - top)
	projection_matrix[2][2] = 1 / (far - near)
	projection_matrix[3][0] = -(right + left) / (right - left)
	projection_matrix[3][1] = -(bottom + top) / (bottom - top)
	projection_matrix[3][2] = -near / (far - near)
}

camera_set_perspective_projection :: proc(
	using camera: ^Camera,
	fovy: f32,
	aspect: f32,
	near: f32,
	far: f32,
) {
	assert(abs(aspect - m.F32_EPSILON) > 0)
	tan_half_fovy := m.tan(fovy / 2)
	projection_matrix = um.Mat4{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
	projection_matrix[0][0] = 1 / (aspect * tan_half_fovy)
	projection_matrix[1][1] = 1 / (tan_half_fovy)
	projection_matrix[2][2] = far / (far - near)
	projection_matrix[2][3] = 1
	projection_matrix[3][2] = -(far * near) / (far - near)
}

camera_set_view_direction :: proc(
	using camera: ^Camera,
	position: um.Vec3,
	direction: um.Vec3,
	up: um.Vec3 = {0, -1, 0},
) {
	using um, l
	w := normalize_vec(direction)
	u := normalize_vec(cross(w, up))
	v := cross(w, u)

	view_matrix = MAT4_ONES
	view_matrix[0][0] = u.x
	view_matrix[1][0] = u.y
	view_matrix[2][0] = u.z
	view_matrix[0][1] = v.x
	view_matrix[1][1] = v.y
	view_matrix[2][1] = v.z
	view_matrix[0][2] = w.x
	view_matrix[1][2] = w.y
	view_matrix[2][2] = w.z
	view_matrix[3][0] = -dot(u, position)
	view_matrix[3][1] = -dot(v, position)
	view_matrix[3][2] = -dot(w, position)

	inverse_view_matrix = MAT4_ONES
	view_matrix[0][0] = u.x
	view_matrix[0][1] = u.y
	view_matrix[0][2] = u.z
	view_matrix[1][0] = v.x
	view_matrix[1][1] = v.y
	view_matrix[1][2] = v.z
	view_matrix[2][0] = w.x
	view_matrix[2][1] = w.y
	view_matrix[2][2] = w.z
	view_matrix[3][0] = position.x
	view_matrix[3][1] = position.y
	view_matrix[3][2] = position.z
}

camera_set_view_target :: proc(
	camera: ^Camera,
	position: um.Vec3,
	target: um.Vec3,
	up: um.Vec3 = {0, -1, 0},
) {
	camera_set_view_direction(camera, target - position, up)
}

camera_set_view_xyz :: proc(using camera: ^Camera, position: um.Vec3, rotation: um.Vec3) {
	using um, l
	c3 := cos(rotation.z)
	s3 := sin(rotation.z)
	c2 := cos(rotation.x)
	s2 := sin(rotation.x)
	c1 := cos(rotation.y)
	s1 := sin(rotation.y)
	u := Vec3{(c1 * c3 + s1 * s2 * s3), (c2 * s3), (c1 * s2 * s3 - c3 * s1)}
	v := Vec3{(c3 * s1 * s2 - c1 * s3), (c2 * c3), (c1 * c3 * s2 + s1 * s3)}
	w := Vec3{(c2 * s1), (-s2), (c1 * c2)}

	view_matrix = MAT4_ONES

	view_matrix[0][0] = u.x
	view_matrix[1][0] = u.y
	view_matrix[2][0] = u.z
	view_matrix[0][1] = v.x
	view_matrix[1][1] = v.y
	view_matrix[2][1] = v.z
	view_matrix[0][2] = w.x
	view_matrix[1][2] = w.y
	view_matrix[2][2] = w.z
	view_matrix[3][0] = -dot(u, position)
	view_matrix[3][1] = -dot(v, position)
	view_matrix[3][2] = -dot(w, position)

	inverse_view_matrix = MAT4_ONES
	inverse_view_matrix[0][0] = u.x
	inverse_view_matrix[0][1] = u.y
	inverse_view_matrix[0][2] = u.z
	inverse_view_matrix[1][0] = v.x
	inverse_view_matrix[1][1] = v.y
	inverse_view_matrix[1][2] = v.z
	inverse_view_matrix[2][0] = w.x
	inverse_view_matrix[2][1] = w.y
	inverse_view_matrix[2][2] = w.z
	inverse_view_matrix[3][0] = position.x
	inverse_view_matrix[3][1] = position.y
	inverse_view_matrix[3][2] = position.z
}

camera_get_position :: proc(using camera: ^Camera) -> um.Vec3 {
	return um.vec3(inverse_view_matrix[3][0], inverse_view_matrix[3][1], inverse_view_matrix[3][2])
}

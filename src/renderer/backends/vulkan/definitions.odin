package renderer_vulkan

import l "core:math/linalg"

vec2 :: distinct l.Vector2f32
vec3 :: distinct l.Vector3f32
vec4 :: distinct l.Vector4f32

mat2 :: distinct l.Matrix2x2f32
mat3 :: distinct l.Matrix3x3f32
mat4 :: distinct l.Matrix4x4f32

MAX_LIGHTS :: 10

PointLight :: struct {
	position: vec4,
	color:    vec4,
}

GlobalUbo :: struct {
	projection:          mat4,
	view:                mat4,
	inverse_view:        mat4,
	ambient_light_color: vec4,
	point_lights:        [MAX_LIGHTS]PointLight,
	num_lights:          int,
}

global_ubo :: proc(
	projection: mat4 = mat4{},
	view := mat4{},
	inverse_view := mat4{},
	ambient_light_color: vec4 = vec4{},
	point_lights: []PointLight = {},
) -> GlobalUbo {
	ubo := GlobalUbo{}

	assert(
		len(point_lights) <= MAX_LIGHTS,
		"Number of point_lights must be less than or equal to MAX_LIGHTS",
	)

	if projection == (mat4{}) {
		for i in 0 ..< 16 {
			ubo.projection[i] = 1
		}
	} else {
		ubo.projection = projection
	}

	if view == (mat4{}) {
		for i in 0 ..< 16 {
			ubo.view[i] = 1
		}
	} else {
		ubo.view = projection
	}

	if inverse_view == (mat4{}) {
		for i in 0 ..< 16 {
			ubo.inverse_view[i] = 1
		}
	} else {
		ubo.inverse_view = projection
	}

	if ambient_light_color == (vec4{}) {
		ubo.ambient_light_color = {1, 1, 1, .02}
	} else {
		ubo.ambient_light_color = ambient_light_color
	}

	ubo.num_lights = len(point_lights)
	for point_light, i in point_lights {
		ubo.point_lights[i] = point_light
	}

	return ubo
}

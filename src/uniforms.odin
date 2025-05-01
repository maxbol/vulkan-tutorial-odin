package main

import um "unitmath"

MAX_LIGHTS :: 10

GlobalUbo :: struct {
	projection:          um.Mat4,
	view:                um.Mat4,
	inverse_view:        um.Mat4,
	ambient_light_color: um.Vec4,
	point_lights:        [MAX_LIGHTS]PointLight,
	num_lights:          int,
}

global_ubo :: proc(
	projection: um.Mat4 = um.Mat4{},
	view := um.Mat4{},
	inverse_view := um.Mat4{},
	ambient_light_color: um.Vec4 = um.Vec4{},
	point_lights: []PointLight = {},
) -> GlobalUbo {
  using um
	ubo := GlobalUbo{}

	assert(
		len(point_lights) <= MAX_LIGHTS,
		"Number of point_lights must be less than or equal to MAX_LIGHTS",
	)

	if projection == (Mat4{}) {
		for i in 0 ..< 16 {
			ubo.projection[i] = 1
		}
	} else {
		ubo.projection = projection
	}

	if view == (Mat4{}) {
		for i in 0 ..< 16 {
			ubo.view[i] = 1
		}
	} else {
		ubo.view = projection
	}

	if inverse_view == (Mat4{}) {
		for i in 0 ..< 16 {
			ubo.inverse_view[i] = 1
		}
	} else {
		ubo.inverse_view = projection
	}

	if ambient_light_color == (Vec4{}) {
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


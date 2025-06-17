package main

import "core:fmt"
import um "unitmath"

MAX_LIGHTS :: 10

GlobalUbo :: struct {
	projection:        um.Mat4,
	view:              um.Mat4,
	inverseView:       um.Mat4,
	ambientLightColor: um.Vec4,
	pointLights:       [MAX_LIGHTS]PointLight,
	numLights:         int,
}

global_ubo :: proc(
	projection: um.Mat4 = um.Mat4{},
	view := um.Mat4{},
	inverse_view := um.Mat4{},
	ambient_light_color: um.Vec4 = um.Vec4{},
	point_lights: []PointLight = {},
) -> GlobalUbo {
	using um
	ubo := GlobalUbo {
		projection        = Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}, // Identity matrix
		view              = Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}, // Identity matrix
		inverseView       = Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}, // Identity matrix
		ambientLightColor = Vec4{1, 1, 1, 0.02}, // Default ambient light color
	}

	assert(
		len(point_lights) <= MAX_LIGHTS,
		"Number of point_lights must be less than or equal to MAX_LIGHTS",
	)

	if projection != (Mat4{}) {
		ubo.projection = projection
	}

	if view != (Mat4{}) {
		ubo.view = view
	}

	if inverse_view != (Mat4{}) {
		ubo.inverseView = inverse_view
	}

	if ambient_light_color != (Vec4{}) {
		ubo.ambientLightColor = ambient_light_color
	}

	ubo.numLights = len(point_lights)
	for point_light, i in point_lights {
		ubo.pointLights[i] = point_light
	}

	return ubo
}

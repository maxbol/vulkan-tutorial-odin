package main

import m "../src/renderer/backends/vulkan/model/"
import "core:math"
import optional "optional"
import um "unitmath"

current_id: GameObjectId = 0

GameObjectId :: distinct uint

GameObject :: struct {
	id:          GameObjectId,
	color:       um.Vec3,
	transform:   TransformComponent,
	model:       optional.Optional(m.Model),
	point_light: optional.Optional(PointLightComponent),
}

GameObjectMap :: distinct map[GameObjectId]GameObject

TransformComponent :: struct {
	translation:   um.Vec3,
	scale:         um.Vec3,
	rotation:      um.Vec3,
	mat4:          um.Mat4,
	normal_matrix: um.Mat3,
}

PointLightComponent :: struct {
	light_intensity: f32,
}

create_game_object :: proc() -> GameObject {
	go := GameObject {
		id = current_id,
	}
	current_id += 1
	return go
}

make_point_light :: proc(
	intensity: f32 = 10,
	radius: f32 = 0.1,
	color: um.Vec3 = {1, 1, 1},
) -> GameObject {
	game_object := create_game_object()
	game_object.color = color
	game_object.transform.scale.x = radius
	game_object.point_light = {
		present = true,
		value = {light_intensity = intensity},
	}
	return game_object
}

transform_to_mat4 :: proc(transform: TransformComponent) -> um.Mat4 {
	using math, um, transform
	c3 := cos(rotation.z)
	s3 := sin(rotation.z)
	c2 := cos(rotation.x)
	s2 := sin(rotation.x)
	c1 := cos(rotation.y)
	s1 := sin(rotation.y)

	return Mat4 {
		scale.x * (c1 * c3 + s1 * s2 * s3),
		scale.x * (c2 * s3),
		scale.x * (c1 * s2 * s3 - c3 * s1),
		translation.x,
		scale.y * (c3 * s1 * s2 - c1 * s3),
		scale.y * (c2 * c3),
		scale.y * (c1 * c3 * s2 + s1 * s3),
		translation.y,
		scale.z * (c2 * s1),
		scale.z * (-s2),
		scale.z * (c1 * c2),
		translation.z,
		0.0,
		0.0,
		0.0,
		1.0,
	}
}

transform_to_normal_mat :: proc(transform: TransformComponent) -> um.Mat3 {
	using math, transform, um
	c3 := cos(rotation.z)
	s3 := sin(rotation.z)
	c2 := cos(rotation.x)
	s2 := sin(rotation.x)
	c1 := cos(rotation.y)
	s1 := sin(rotation.y)
	inv_scale := vec3(1, 1, 1) / scale

	return Mat3 {
		inv_scale.x * (c1 * c3 + s1 * s2 * s3),
		inv_scale.x * (c2 * s3),
		inv_scale.x * (c1 * s2 * s3 - c3 * s1),
		inv_scale.y * (c3 * s1 * s2 - c1 * s3),
		inv_scale.y * (c2 * c3),
		inv_scale.y * (c1 * c3 * s2 + s1 * s3),
		inv_scale.z * (c2 * s1),
		inv_scale.z * (-s2),
		inv_scale.z * (c1 * c2),
	}
}

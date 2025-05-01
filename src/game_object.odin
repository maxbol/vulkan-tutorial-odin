package main

import m "../src/renderer/backends/vulkan/model/"
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

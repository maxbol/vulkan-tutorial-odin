package main

import m "core:math"
import l "core:math/linalg"
import um "unitmath"
import "vendor:glfw"

Mappings :: struct {
	move_left:     i32,
	move_right:    i32,
	move_forward:  i32,
	move_backward: i32,
	move_up:       i32,
	move_down:     i32,
	look_left:     i32,
	look_right:    i32,
	look_up:       i32,
	look_down:     i32,
}

keys := Mappings {
	move_left     = glfw.KEY_A,
	move_right    = glfw.KEY_D,
	move_forward  = glfw.KEY_W,
	move_backward = glfw.KEY_S,
	move_up       = glfw.KEY_E,
	move_down     = glfw.KEY_Q,
	look_left     = glfw.KEY_LEFT,
	look_right    = glfw.KEY_RIGHT,
	look_up       = glfw.KEY_UP,
	look_down     = glfw.KEY_DOWN,
}

move_speed: f32 = 3
look_speed: f32 = 1.5

move_in_plane_xyz :: proc(window: glfw.WindowHandle, dt: f32, game_object: ^GameObject) {
	using m, um

	rotate := Vec3{0, 0, 0}

	if glfw.GetKey(window, keys.look_right) == glfw.PRESS {rotate.y += 1}
	if glfw.GetKey(window, keys.look_left) == glfw.PRESS {rotate.y -= 1}
	if glfw.GetKey(window, keys.look_up) == glfw.PRESS {rotate.x += 1}
	if glfw.GetKey(window, keys.look_down) == glfw.PRESS {rotate.x -= 1}

	if l.dot(rotate, rotate) > m.F32_EPSILON {
		game_object.transform.rotation += look_speed * dt * normalize_vec(rotate)
	}

	game_object.transform.rotation.x = clamp(game_object.transform.rotation.x, -1.5, 1.5)
	game_object.transform.rotation.y = mod(game_object.transform.rotation.y, m.TAU)

	yaw := game_object.transform.rotation.y
	forward_dir := Vec3{sin(yaw), 0, cos(yaw)}
	right_dir := Vec3{forward_dir.z, 0, -forward_dir.x}
	up_dir := Vec3{0, -1, 0}

	move_dir := Vec3{0, 0, 0}
	if glfw.GetKey(window, keys.move_forward) == glfw.PRESS {move_dir += forward_dir}
	if glfw.GetKey(window, keys.move_backward) == glfw.PRESS {move_dir -= forward_dir}
	if glfw.GetKey(window, keys.move_right) == glfw.PRESS {move_dir += right_dir}
	if glfw.GetKey(window, keys.move_left) == glfw.PRESS {move_dir -= right_dir}
	if glfw.GetKey(window, keys.move_up) == glfw.PRESS {move_dir += up_dir}
	if glfw.GetKey(window, keys.move_down) == glfw.PRESS {move_dir -= up_dir}

	if l.dot(move_dir, move_dir) > F32_EPSILON {
		game_object.transform.translation += move_speed * dt * normalize_vec(move_dir)
	}
}

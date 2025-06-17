package main

import "core:fmt"
import "core:math"
import l "core:math/linalg"
import w "renderer/backends/vulkan/window"
import um "unitmath"
import "vendor:glfw"

MousePosition :: struct {
	xpos: f64,
	ypos: f64,
}

position := MousePosition{}
mouse_moved := false

mouse_look_speed: f32 = 3

mouse_lookaround :: proc(window: ^w.Window, dt: f32, camera_object: ^GameObject) {
	using um
	last_pos := position
	xpos, ypos := glfw.GetCursorPos(window.handle)
	position = {xpos, ypos}

	if !mouse_moved {
		mouse_moved = true
		return
	}

	pos_delta_x := position.xpos - last_pos.xpos
	pos_delta_y := position.ypos - last_pos.ypos

	rotate := Vec3{0, 0, 0}
	rotate.y = f32(math.sign(pos_delta_x))
	rotate.x = f32(-math.sign(pos_delta_y))

	if l.dot(rotate, rotate) > math.F32_EPSILON {
		fmt.println("pos_delta_x:", pos_delta_x)
		fmt.println("pos_delta_y:", pos_delta_y)
		camera_object.transform.rotation += look_speed * dt * normalize_vec(rotate)
	}

	camera_object.transform.rotation.x = clamp(camera_object.transform.rotation.x, -1.5, 1.5)
	camera_object.transform.rotation.y = math.mod(camera_object.transform.rotation.y, math.TAU)
}

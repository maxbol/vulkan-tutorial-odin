package main

import "core:fmt"
import "core:math"
import l "core:math/linalg"
import gs "game_state"
import w "renderer/backends/vulkan/window"
import um "unitmath"
import "vendor:glfw"

MousePosition :: struct {
	xpos: f64,
	ypos: f64,
}

position := MousePosition{}
mouse_moved := false

mouse_sensitivity: f32 = 3000

mouse_lookaround :: proc(window: ^w.Window, dt: f32, viewer: ^gs.GameObject) {
	using um
	last_pos := position
	xpos, ypos := glfw.GetCursorPos(window.handle)
	position = {xpos, ypos}

	if !mouse_moved {
		mouse_moved = true
		return
	}

	abs_x_movement := 0 - f32(position.ypos - last_pos.ypos)
	abs_y_movement := f32(position.xpos - last_pos.xpos)

	rel_x_movement := abs_x_movement / f32(window.height)
	rel_y_movement := abs_y_movement / f32(window.width)

	rotate := Vec3{0, 0, 0}
	rotate.x = rel_x_movement
	rotate.y = rel_y_movement

	if rotate.x != 0 || rotate.y != 0 {
		viewer.transform.rotation += mouse_sensitivity * dt * rotate
		viewer.transform.rotation.x = clamp(viewer.transform.rotation.x, -1.5, 1.5)
		viewer.transform.rotation.y = math.mod(viewer.transform.rotation.y, math.TAU)
	}
}

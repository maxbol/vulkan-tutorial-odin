package game_state
import um "../unitmath"
import "core:math"

@(private = "file")
rotate_axis :: proc(axis: ^f32, amount: f32) {
	axis^ = math.mod(axis^ + amount, math.TAU)
}

rotate :: proc(transform: ^TransformComponent, rotation: um.Vec3) {
	if (rotation.x != 0) {
		rotate_axis(&transform.rotation.x, rotation.x)
	}
	if (rotation.y != 0) {
		rotate_axis(&transform.rotation.y, rotation.y)
	}
	if (rotation.z != 0) {
		rotate_axis(&transform.rotation.z, rotation.z)
	}
}

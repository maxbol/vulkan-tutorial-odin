package game_state

import "vendor:vulkan"

import c "../renderer/backends/vulkan/camera"

FrameInfo :: struct {
	frame_index:           int,
	frame_time:            f32,
	command_buffer:        vulkan.CommandBuffer,
	camera:                ^c.Camera,
	global_descriptor_set: vulkan.DescriptorSet,
	game_objects:          ^GameObjectMap,
}

package renderer_vulkan_renderer

import d "../device"
import s "../swapchain"
import w "../window"

import "core:fmt"
import "vendor:glfw"
import "vendor:vulkan"

Renderer :: struct {
	window:              ^w.Window,
	device:              ^d.Device,
	swapchain:           ^s.Swapchain,
	vk_allocator:        ^vulkan.AllocationCallbacks,
	command_buffers:     []vulkan.CommandBuffer,
	current_image_index: u32,
	current_frame_index: int,
	is_frame_started:    bool,
}

CreateRendererError :: enum {
	None,
	RecreateSwapchainFailed,
	CreateCommandBuffersFailed,
}

create_renderer :: proc(
	window: ^w.Window,
	device: ^d.Device,
	renderer: ^Renderer,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> CreateRendererError {
	renderer^ = {
		window       = window,
		device       = device,
		vk_allocator = vk_allocator,
	}

	if !recreate_swap_chain(renderer) {
		return .RecreateSwapchainFailed
	}

	if !create_command_buffers(renderer) {
		return .CreateCommandBuffersFailed
	}

	return .None
}

destroy_renderer :: proc(renderer: ^Renderer) {
	free_command_buffers(renderer)
}

get_swapchain_render_pass :: proc(renderer: ^Renderer) -> vulkan.RenderPass {
	return renderer.swapchain.render_pass
}

get_aspect_ratio :: proc(renderer: ^Renderer) -> f32 {
	return s.extent_aspect_ratio(renderer.swapchain.extent)
}

get_current_command_buffer :: proc(renderer: ^Renderer) -> vulkan.CommandBuffer {
	assert(renderer.is_frame_started, "Cannot get command buffer when frame is not in progress")
	return renderer.command_buffers[renderer.current_frame_index]
}

get_frame_index :: proc(renderer: ^Renderer) -> int {
	assert(renderer.is_frame_started, "Cannot get frame index when frame not in progress")
	return renderer.current_frame_index
}

begin_frame :: proc(renderer: ^Renderer) -> (bool, vulkan.CommandBuffer) {
	assert(!renderer.is_frame_started, "Can't call begin_frame() while already in progress")

	result := s.acquire_next_image(renderer.swapchain, &renderer.current_image_index)
	if result == .ERROR_OUT_OF_DATE_KHR {
		if !recreate_swap_chain(renderer) {
			fmt.println("Error recreating swapchain")
			return false, nil
		}
		return false, nil
	}

	if result != .SUCCESS {
		fmt.println("Error acquiring swap chain image!")
		return false, nil
	}

	renderer.is_frame_started = true

	command_buffer := get_current_command_buffer(renderer)
	begin_info := vulkan.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	if vulkan.BeginCommandBuffer(command_buffer, &begin_info) != .SUCCESS {
		fmt.println("Failed to begin recording command buffer!")
		return false, nil
	}

	return true, command_buffer
}

end_frame :: proc(renderer: ^Renderer) -> bool {
	assert(renderer.is_frame_started, "Can't call end_frame() while frame is not in progress")
	command_buffer := get_current_command_buffer(renderer)
	if vulkan.EndCommandBuffer(command_buffer) != .SUCCESS {
		fmt.println("Failed to record command buffer!")
		return false
	}

	// As of now we only ever deal with one command buffer, so let's create a slice constant
	command_buffers := []vulkan.CommandBuffer{command_buffer}

	result := s.submit_command_buffers(
		renderer.swapchain,
		command_buffers,
		&renderer.current_image_index,
	)
	if result == .ERROR_OUT_OF_DATE_KHR ||
	   result == .SUBOPTIMAL_KHR ||
	   w.was_window_resized(renderer.window) {
		w.reset_window_resize_flag(renderer.window)
		if !recreate_swap_chain(renderer) {
			fmt.println("Error recreating swap chain when ending frame")
			return false
		}
	} else if result != .SUCCESS {
		fmt.println("Failed to present swap chain image")
		return false
	}

	renderer.is_frame_started = false
	renderer.current_frame_index = (renderer.current_frame_index + 1) % s.MAX_FRAMES_IN_FLIGHT

	return true
}

begin_swapchain_render_pass :: proc(renderer: ^Renderer, command_buffer: vulkan.CommandBuffer) {
	assert(
		renderer.is_frame_started,
		"Can't call begin_swapchain_render_pass() if frame is not in progress",
	)
	assert(
		command_buffer == get_current_command_buffer(renderer),
		"Can't begin render pass on command buffer from a different frame",
	)

	clear_values := []vulkan.ClearValue {
		{color = {float32 = {0.01, 0.01, 0.01, 1.0}}},
		{depthStencil = {1, 0}},
	}

	render_pass_info := vulkan.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = renderer.swapchain.render_pass,
		framebuffer = s.get_framebuffer(renderer.swapchain, renderer.current_image_index),
		renderArea = {offset = {0, 0}, extent = renderer.swapchain.extent},
		clearValueCount = u32(len(clear_values)),
		pClearValues = &clear_values[0],
	}

	vulkan.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)
}

end_swapchain_render_pass :: proc(renderer: ^Renderer, command_buffer: vulkan.CommandBuffer) {}

@(private)
create_command_buffers :: proc(renderer: ^Renderer) -> bool {
	renderer.command_buffers = make([]vulkan.CommandBuffer, s.MAX_FRAMES_IN_FLIGHT)
	alloc_info := vulkan.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = renderer.device.command_pool,
		commandBufferCount = u32(len(renderer.command_buffers)),
	}

	if vulkan.AllocateCommandBuffers(
		   renderer.device.logical_device,
		   &alloc_info,
		   &renderer.command_buffers[0],
	   ) !=
	   .SUCCESS {
		fmt.println("Error allocating command buffers")
		return false
	}

	return true
}

@(private)
free_command_buffers :: proc(renderer: ^Renderer) {
	vulkan.FreeCommandBuffers(
		renderer.device.logical_device,
		renderer.device.command_pool,
		u32(len(renderer.command_buffers)),
		&renderer.command_buffers[0],
	)

	delete(renderer.command_buffers)
}

@(private)
recreate_swap_chain :: proc(renderer: ^Renderer) -> bool {
	extent := w.get_extent(renderer.window)
	for extent.width == 0 || extent.height == 0 {
		extent = w.get_extent(renderer.window)
		glfw.WaitEvents()
	}
	vulkan.DeviceWaitIdle(renderer.device.logical_device)

	if renderer.swapchain == nil {
		s.create_swapchain(
			renderer.device,
			extent,
			vk_allocator = renderer.vk_allocator,
			swapchain = renderer.swapchain,
		)

		return true
	}

	old_swapchain := renderer.swapchain
	renderer.swapchain = nil

	s.create_swapchain(
		renderer.device,
		extent,
		old_swapchain,
		renderer.vk_allocator,
		renderer.swapchain,
	)

	if !s.compare_swap_formats(old_swapchain, renderer.swapchain) {
		fmt.println("Error: Swapchain image (or depth) format has changed!")
		return false
	}

	return true
}

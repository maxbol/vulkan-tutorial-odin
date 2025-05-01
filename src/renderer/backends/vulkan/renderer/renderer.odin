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
	swapchain:           s.Swapchain,
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

destroy_renderer :: proc(using renderer: ^Renderer) {
	if swapchain.inited {
		fmt.println("Destroying swapchain...")
		s.destroy_swapchain(&swapchain, vk_allocator)
		swapchain = s.Swapchain{}
	}
	fmt.println("Freeing command buffers...")
	free_command_buffers(renderer)
}

get_swapchain_render_pass :: proc(using renderer: ^Renderer) -> vulkan.RenderPass {
	return swapchain.render_pass
}

get_aspect_ratio :: proc(using renderer: ^Renderer) -> f32 {
	return s.extent_aspect_ratio(swapchain.extent)
}

get_current_command_buffer :: proc(using renderer: ^Renderer) -> vulkan.CommandBuffer {
	assert(is_frame_started, "Cannot get command buffer when frame is not in progress")
	return command_buffers[current_frame_index]
}

get_frame_index :: proc(using renderer: ^Renderer) -> int {
	assert(is_frame_started, "Cannot get frame index when frame not in progress")
	return current_frame_index
}

begin_frame :: proc(using renderer: ^Renderer) -> (bool, vulkan.CommandBuffer) {
	assert(!is_frame_started, "Can't call begin_frame() while already in progress")

	result := s.acquire_next_image(&swapchain, &current_image_index)
	if result == .ERROR_OUT_OF_DATE_KHR {
		if !recreate_swap_chain(renderer) {
			fmt.println("Error recreating swapchain")
			return false, nil
		}
		return true, nil
	}

	if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
		fmt.println("Error acquiring swap chain image:", result)
		return false, nil
	}

	is_frame_started = true

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

end_frame :: proc(using renderer: ^Renderer) -> bool {
	assert(is_frame_started, "Can't call end_frame() while frame is not in progress")
	command_buffer := get_current_command_buffer(renderer)
	if vulkan.EndCommandBuffer(command_buffer) != .SUCCESS {
		fmt.println("Failed to record command buffer!")
		return false
	}

	// As of now we only ever deal with one command buffer, so let's create a slice constant
	buffers := []vulkan.CommandBuffer{command_buffer}

	result := s.submit_command_buffers(&swapchain, buffers, &current_image_index)

	if result == .ERROR_OUT_OF_DATE_KHR ||
	   result == .SUBOPTIMAL_KHR ||
	   w.was_window_resized(window) {
		w.reset_window_resize_flag(window)
		if !recreate_swap_chain(renderer) {
			fmt.println("Error recreating swap chain when ending frame")
			return false
		}
	} else if result != .SUCCESS {
		fmt.println("Failed to present swap chain image")
		return false
	}

	is_frame_started = false
	current_frame_index = (current_frame_index + 1) % s.MAX_FRAMES_IN_FLIGHT

	return true
}

begin_swapchain_render_pass :: proc(
	using renderer: ^Renderer,
	command_buffer: vulkan.CommandBuffer,
) {
	assert(
		is_frame_started,
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
		renderPass = swapchain.render_pass,
		framebuffer = s.get_framebuffer(&swapchain, current_image_index),
		renderArea = {offset = {0, 0}, extent = swapchain.extent},
		clearValueCount = u32(len(clear_values)),
		pClearValues = &clear_values[0],
	}

	vulkan.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)

	viewport := vulkan.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(swapchain.extent.width),
		height   = f32(swapchain.extent.height),
		minDepth = 0,
		maxDepth = 1,
	}

	scissor := vulkan.Rect2D{{0, 0}, swapchain.extent}

	vulkan.CmdSetViewport(command_buffer, 0, 1, &viewport)
	vulkan.CmdSetScissor(command_buffer, 0, 1, &scissor)
}

end_swapchain_render_pass :: proc(
	using renderer: ^Renderer,
	command_buffer: vulkan.CommandBuffer,
) {
	assert(is_frame_started, "Can't call endSwapChainRenderPass if frame is not in progress")
	assert(
		command_buffer == get_current_command_buffer(renderer),
		"Can't end render pass on command buffer from a different frame",
	)
	vulkan.CmdEndRenderPass(command_buffer)
}

@(private)
create_command_buffers :: proc(using renderer: ^Renderer) -> bool {
	command_buffers = make([]vulkan.CommandBuffer, s.MAX_FRAMES_IN_FLIGHT)
	alloc_info := vulkan.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = device.command_pool,
		commandBufferCount = u32(len(command_buffers)),
	}

	if vulkan.AllocateCommandBuffers(device.vk_device, &alloc_info, &command_buffers[0]) !=
	   .SUCCESS {
		fmt.println("Error allocating command buffers")
		return false
	}

	return true
}

@(private)
free_command_buffers :: proc(using renderer: ^Renderer) {
	vulkan.FreeCommandBuffers(
		device.vk_device,
		device.command_pool,
		u32(len(command_buffers)),
		&command_buffers[0],
	)

	delete(command_buffers)
}

@(private)
recreate_swap_chain :: proc(using renderer: ^Renderer) -> bool {
	extent := w.get_extent(window)
	for extent.width == 0 || extent.height == 0 {
		extent = w.get_extent(window)
		glfw.WaitEvents()
	}
	vulkan.DeviceWaitIdle(device.vk_device)

	if !swapchain.inited {
		err := s.create_swapchain(
			device,
			extent,
			vk_allocator = vk_allocator,
			swapchain = &swapchain,
		)
		if err != nil {
			fmt.eprintln("Error: Couldn't create swapchain", err)
			return false
		}
		return true
	}

	new_swapchain := s.Swapchain{}

	err := s.create_swapchain(device, extent, &swapchain, vk_allocator, &new_swapchain)
	if err != nil {
		fmt.eprintln("Error: Couldn't recreate swapchain", err)
		return false
	}

	if !s.compare_swap_formats(&swapchain, &new_swapchain) {
		fmt.println("Error: Swapchain image (or depth) format has changed!")
		return false
	}

	s.destroy_swapchain(&swapchain)
	swapchain = new_swapchain

	return true
}

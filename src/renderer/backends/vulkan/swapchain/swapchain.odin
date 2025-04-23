package renderer_vulkan_swapchain

import d "../device"
import "core:fmt"
import "core:mem"
import "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 5

Swapchain :: struct {
	image_format:               vulkan.Format,
	depth_format:               vulkan.Format,
	extent:                     vulkan.Extent2D,
	framebuffers:               []vulkan.Framebuffer,
	render_pass:                vulkan.RenderPass,
	depth_images:               []vulkan.Image,
	depth_image_memories:       []vulkan.DeviceMemory,
	depth_image_views:          []vulkan.ImageView,
	images:                     []vulkan.Image,
	image_views:                []vulkan.ImageView,
	device:                     ^d.Device,
	window_extent:              vulkan.Extent2D,
	vk_swapchain:               vulkan.SwapchainKHR,
	old_swapchain:              ^Swapchain,
	image_available_sempahores: []vulkan.Semaphore,
	render_finished_semaphores: []vulkan.Semaphore,
	in_flight_fences:           []vulkan.Fence,
	images_in_flight:           []vulkan.Fence,
	current_frame:              uint,
}

CreateSwapchainError :: enum {
	None,
	SwapchainCreationFailed,
	ImageViewsCreationFailed,
	RenderPassCreationFailed,
	DepthResourcesCreationFailed,
	FramebuffersCreationFailed,
	SyncObjectsCreationFailed,
}

acquire_next_image :: proc(swapchain: ^Swapchain, image_index: ^u32) -> vulkan.Result {
	vulkan.WaitForFences(
		swapchain.device.logical_device,
		1,
		&swapchain.in_flight_fences[swapchain.current_frame],
		true,
		max(u64),
	)

	return vulkan.AcquireNextImageKHR(
		swapchain.device.logical_device,
		swapchain.vk_swapchain,
		max(u64),
		swapchain.image_available_sempahores[swapchain.current_frame],
		0,
		image_index,
	)
}

compare_swap_formats :: proc(swapchain: ^Swapchain, other: ^Swapchain) -> bool {
	return(
		swapchain.depth_format == other.depth_format &&
		swapchain.image_format == other.image_format \
	)
}

create_swapchain :: proc(
	device: ^d.Device,
	window_extent: vulkan.Extent2D,
	previous_swapchain: ^Swapchain = nil,
	vk_allocator: ^vulkan.AllocationCallbacks,
	swapchain: ^Swapchain,
) -> CreateSwapchainError {
	swapchain^ = {
		device        = device,
		extent        = window_extent,
		old_swapchain = previous_swapchain,
	}

	swapchain_support := d.alloc_swapchain_support(device)
	defer d.deinit_swap_chain_support(swapchain_support)

	surface_format := choose_swap_surface_format(swapchain_support.formats)
	present_mode := choose_swap_present_mode(swapchain_support.present_modes)
	extent := choose_swap_extent(swapchain, swapchain_support.capabilities)

	image_count := swapchain_support.capabilities.minImageCount + 1
	if swapchain_support.capabilities.maxImageCount > 0 &&
	   image_count > swapchain_support.capabilities.maxImageCount {
		image_count = swapchain_support.capabilities.maxImageCount
	}

	indices := d.find_physical_queue_families(device)
	queue_family_indices := []u32{indices.graphics_family.value, indices.present_family.value}

	create_info := vulkan.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = device.surface,
		imageFormat      = surface_format.format,
		imageColorSpace  = surface_format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = swapchain_support.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
		oldSwapchain     = swapchain.old_swapchain == nil ? 0 : swapchain.old_swapchain.vk_swapchain,
	}

	if indices.graphics_family != indices.present_family {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = &queue_family_indices[0]
	} else {
		create_info.imageSharingMode = .EXCLUSIVE
		create_info.queueFamilyIndexCount = 0
		create_info.pQueueFamilyIndices = nil
	}

	if vulkan.CreateSwapchainKHR(
		   device.logical_device,
		   &create_info,
		   nil,
		   &swapchain.vk_swapchain,
	   ) !=
	   .SUCCESS {
		return .SwapchainCreationFailed
	}

	vulkan.GetSwapchainImagesKHR(device.logical_device, swapchain.vk_swapchain, &image_count, nil)

	swapchain.images = make([]vulkan.Image, image_count)

	vulkan.GetSwapchainImagesKHR(
		device.logical_device,
		swapchain.vk_swapchain,
		&image_count,
		&swapchain.images[0],
	)

	ok: bool

	if !create_image_views(swapchain, vk_allocator) {
		return .ImageViewsCreationFailed
	}

	if !create_render_pass(swapchain, vk_allocator) {
		return .RenderPassCreationFailed
	}

	if !create_depth_resources(swapchain, vk_allocator) {
		return .DepthResourcesCreationFailed
	}

	if !create_framebuffers(swapchain, vk_allocator) {
		return .FramebuffersCreationFailed
	}

	if !create_sync_objects(swapchain, vk_allocator) {
		return .SyncObjectsCreationFailed
	}

	swapchain.old_swapchain = nil

	return .None
}

destroy_swapchain :: proc(swapchain: ^Swapchain, vk_allocator: ^vulkan.AllocationCallbacks = nil) {
	device := swapchain.device.logical_device

	for image_view in swapchain.image_views {
		vulkan.DestroyImageView(device, image_view, vk_allocator)
	}
	delete(swapchain.image_views)

	if swapchain.vk_swapchain != 0 {
		vulkan.DestroySwapchainKHR(device, swapchain.vk_swapchain, vk_allocator)
		swapchain.vk_swapchain = 0
	}

	for i in 0 ..< len(swapchain.depth_images) {
		vulkan.DestroyImageView(device, swapchain.depth_image_views[i], vk_allocator)
		vulkan.DestroyImage(device, swapchain.depth_images[i], vk_allocator)
		vulkan.FreeMemory(device, swapchain.depth_image_memories[i], vk_allocator)
	}
	delete(swapchain.depth_images)
	delete(swapchain.depth_image_views)
	delete(swapchain.depth_image_memories)

	for framebuffer in swapchain.framebuffers {
		vulkan.DestroyFramebuffer(device, framebuffer, vk_allocator)
	}
	delete(swapchain.framebuffers)

	vulkan.DestroyRenderPass(device, swapchain.render_pass, vk_allocator)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vulkan.DestroySemaphore(device, swapchain.render_finished_semaphores[i], vk_allocator)
		vulkan.DestroySemaphore(device, swapchain.image_available_sempahores[i], vk_allocator)
		vulkan.DestroyFence(device, swapchain.in_flight_fences[i], vk_allocator)
	}
}

extent_aspect_ratio :: proc(extent: vulkan.Extent2D) -> f32 {
	return f32(extent.width) / f32(extent.height)
}

find_depth_format :: proc(swapchain: ^Swapchain) -> (d.FindSupportedFormatError, vulkan.Format) {
	return d.find_supported_format(
		swapchain.device,
		{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
	)
}

get_framebuffer :: proc(swapchain: ^Swapchain, index: u32) -> vulkan.Framebuffer {
	return swapchain.framebuffers[index]
}

@(private)
create_sync_objects :: proc(
	swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks,
) -> bool {
	swapchain.image_available_sempahores = make([]vulkan.Semaphore, MAX_FRAMES_IN_FLIGHT)
	swapchain.render_finished_semaphores = make([]vulkan.Semaphore, MAX_FRAMES_IN_FLIGHT)
	swapchain.in_flight_fences = make([]vulkan.Fence, MAX_FRAMES_IN_FLIGHT)
	swapchain.images_in_flight = make([]vulkan.Fence, len(swapchain.images))

	for i in 0 ..< len(swapchain.images) {
		swapchain.images_in_flight[i] = 0
	}

	semaphore_info := vulkan.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	fence_info := vulkan.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if vulkan.CreateSemaphore(
			   swapchain.device.logical_device,
			   &semaphore_info,
			   vk_allocator,
			   &swapchain.image_available_sempahores[i],
		   ) !=
			   .SUCCESS ||
		   vulkan.CreateSemaphore(
			   swapchain.device.logical_device,
			   &semaphore_info,
			   vk_allocator,
			   &swapchain.render_finished_semaphores[i],
		   ) !=
			   .SUCCESS ||
		   vulkan.CreateFence(
			   swapchain.device.logical_device,
			   &fence_info,
			   vk_allocator,
			   &swapchain.in_flight_fences[i],
		   ) !=
			   .SUCCESS {
			fmt.println("Error creating synchronization objects for a frame!")
			return false
		}
	}

	return true
}

@(private)
create_render_pass :: proc(
	swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks,
) -> bool {
	err, depth_format := find_depth_format(swapchain)
	if err != nil {
		fmt.println("Error finding depth format:", err)
		return false
	}

	depth_attachment := vulkan.AttachmentDescription {
		format         = depth_format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .DONT_CARE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	depth_attachment_ref := vulkan.AttachmentReference {
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	color_attachment := vulkan.AttachmentDescription {
		format         = swapchain.image_format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilStoreOp = .DONT_CARE,
		stencilLoadOp  = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_attachment_ref := vulkan.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vulkan.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &color_attachment_ref,
		pDepthStencilAttachment = &depth_attachment_ref,
	}

	dependency := vulkan.SubpassDependency {
		dstSubpass    = 0,
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		srcSubpass    = vulkan.SUBPASS_EXTERNAL,
		srcAccessMask = {},
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
	}

	attachments := []vulkan.AttachmentDescription{color_attachment, depth_attachment}

	render_pass_info := vulkan.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = u32(len(attachments)),
		pAttachments    = &attachments[0],
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	if vulkan.CreateRenderPass(
		   swapchain.device.logical_device,
		   &render_pass_info,
		   vk_allocator,
		   &swapchain.render_pass,
	   ) !=
	   .SUCCESS {
		fmt.println("Error creating render pass!")
		return false
	}

	return true
}

@(private)
create_depth_resources :: proc(
	swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> bool {
	err, depth_format := find_depth_format(swapchain)
	if err != nil {
		fmt.println("Error finding depth format:", err)
		return false
	}

	swapchain.depth_format = depth_format

	swapchain_extent := swapchain.extent

	swapchain.depth_images = make([]vulkan.Image, len(swapchain.images))
	swapchain.depth_image_memories = make([]vulkan.DeviceMemory, len(swapchain.images))
	swapchain.depth_image_views = make([]vulkan.ImageView, len(swapchain.images))

	for i in 0 ..< len(swapchain.depth_images) {
		image_info := vulkan.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = .D2,
			extent = {width = swapchain_extent.width, height = swapchain_extent.height, depth = 1},
			mipLevels = 1,
			arrayLayers = 1,
			format = depth_format,
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = {.DEPTH_STENCIL_ATTACHMENT},
			samples = {._1},
			sharingMode = .EXCLUSIVE,
			flags = {},
		}

		d.create_image_with_info(
			swapchain.device,
			&image_info,
			{.DEVICE_LOCAL},
			&swapchain.depth_images[i],
			&swapchain.depth_image_memories[i],
		)

		view_info := vulkan.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = swapchain.depth_images[i],
			viewType = .D2,
			format = depth_format,
			subresourceRange = {
				aspectMask = {.DEPTH},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		if vulkan.CreateImageView(
			   swapchain.device.logical_device,
			   &view_info,
			   vk_allocator,
			   &swapchain.depth_image_views[i],
		   ) !=
		   .SUCCESS {
			fmt.println("Error creating texture image view")
			return false
		}
	}

	return true
}

@(private)
choose_swap_extent :: proc(
	swapchain: ^Swapchain,
	capabilities: vulkan.SurfaceCapabilitiesKHR,
) -> vulkan.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	actual_extent := swapchain.window_extent
	actual_extent.width = max(
		capabilities.minImageExtent.width,
		min(capabilities.maxImageExtent.width, actual_extent.width),
	)
	actual_extent.height = max(
		capabilities.minImageExtent.height,
		min(capabilities.maxImageExtent.height, actual_extent.height),
	)

	return actual_extent
}
@(private)
create_framebuffers :: proc(
	swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks,
) -> bool {
	swapchain.framebuffers = make([]vulkan.Framebuffer, len(swapchain.images))

	for i in 0 ..< len(swapchain.images) {
		attachments := []vulkan.ImageView{swapchain.image_views[i], swapchain.depth_image_views[i]}
		swapchain_extent := swapchain.extent

		framebuffer_info := vulkan.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = swapchain.render_pass,
			attachmentCount = u32(len(attachments)),
			pAttachments    = &attachments[0],
			width           = swapchain_extent.width,
			height          = swapchain_extent.height,
			layers          = 1,
		}

		if vulkan.CreateFramebuffer(
			   swapchain.device.logical_device,
			   &framebuffer_info,
			   vk_allocator,
			   &swapchain.framebuffers[i],
		   ) !=
		   .SUCCESS {
			fmt.println("Error creating frambuffer")
			return false
		}
	}

	return true
}

@(private)
choose_swap_present_mode :: proc(
	available_present_modes: []vulkan.PresentModeKHR,
) -> vulkan.PresentModeKHR {
	for available_present_mode in available_present_modes {
		if available_present_mode == .MAILBOX {
			fmt.println("Present mode: Mailbox")
			return available_present_mode
		}
	}

	fmt.println("Present mode: V-Sync")
	return .FIFO
}

@(private)
create_image_views :: proc(
	swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> bool {
	swapchain.image_views = make([]vulkan.ImageView, len(swapchain.images))

	for image, i in swapchain.images {
		view_info := vulkan.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = swapchain.images[i],
			viewType = .D2,
			format = swapchain.image_format,
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		if vulkan.CreateImageView(
			   swapchain.device.logical_device,
			   &view_info,
			   vk_allocator,
			   &swapchain.image_views[i],
		   ) !=
		   .SUCCESS {
			return false
		}
	}

	return true
}

@(private)
choose_swap_surface_format :: proc(
	available_formats: []vulkan.SurfaceFormatKHR,
) -> vulkan.SurfaceFormatKHR {
	for available_format in available_formats {
		if available_format.format == .B8G8R8A8_SRGB &&
		   available_format.colorSpace == .COLORSPACE_SRGB_NONLINEAR {
			return available_format
		}
	}

	return available_formats[0]
}

submit_command_buffers :: proc(
	swapchain: ^Swapchain,
	buffers: []vulkan.CommandBuffer,
	image_index: ^u32,
) -> vulkan.Result {
	if swapchain.images_in_flight[image_index^] != 0 {
		vulkan.WaitForFences(
			swapchain.device.logical_device,
			1,
			&swapchain.images_in_flight[image_index^],
			true,
			max(u64),
		)
	}
	swapchain.images_in_flight[image_index^] = swapchain.in_flight_fences[swapchain.current_frame]

	wait_semaphores := []vulkan.Semaphore {
		swapchain.image_available_sempahores[swapchain.current_frame],
	}

	wait_stages := []vulkan.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}

	signal_semaphores := []vulkan.Semaphore {
		swapchain.render_finished_semaphores[swapchain.current_frame],
	}

	submit_info := vulkan.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = u32(len(wait_semaphores)),
		pWaitSemaphores      = &wait_semaphores[0],
		pWaitDstStageMask    = &wait_stages[0],
		commandBufferCount   = u32(len(buffers)),
		pCommandBuffers      = &buffers[0],
		signalSemaphoreCount = u32(len(signal_semaphores)),
		pSignalSemaphores    = &signal_semaphores[0],
	}

	vulkan.ResetFences(
		swapchain.device.logical_device,
		1,
		&swapchain.in_flight_fences[swapchain.current_frame],
	)

	result := vulkan.QueueSubmit(
		swapchain.device.graphics_queue,
		1,
		&submit_info,
		swapchain.in_flight_fences[swapchain.current_frame],
	)

	if result != .SUCCESS {
		return result
	}

	swap_chains := []vulkan.SwapchainKHR{swapchain.vk_swapchain}

	present_info := vulkan.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = u32(len(signal_semaphores)),
		pWaitSemaphores    = &signal_semaphores[0],
		swapchainCount     = u32(len(swap_chains)),
		pSwapchains        = &swap_chains[0],
		pImageIndices      = image_index,
	}

	result = vulkan.QueuePresentKHR(swapchain.device.present_queue, &present_info)

	swapchain.current_frame = (swapchain.current_frame + 1) % MAX_FRAMES_IN_FLIGHT

	return result
}

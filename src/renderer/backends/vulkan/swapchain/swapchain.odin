package renderer_vulkan_swapchain

import d "../device"
import "core:fmt"
import "core:mem"
import "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 5

Swapchain :: struct {
	inited:                     bool,
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

acquire_next_image :: proc(using swapchain: ^Swapchain, image_index: ^u32) -> vulkan.Result {
	vulkan.WaitForFences(device.vk_device, 1, &in_flight_fences[current_frame], true, max(u64))

	return vulkan.AcquireNextImageKHR(
		device.vk_device,
		vk_swapchain,
		max(u64),
		image_available_sempahores[current_frame],
		0,
		image_index,
	)
}

compare_swap_formats :: proc(using swapchain: ^Swapchain, other: ^Swapchain) -> bool {
	return depth_format == other.depth_format && image_format == other.image_format
}

create_swapchain :: proc(
	device: ^d.Device,
	window_extent: vulkan.Extent2D,
	previous_swapchain: ^Swapchain = nil,
	vk_allocator: ^vulkan.AllocationCallbacks,
	swapchain: ^Swapchain,
) -> CreateSwapchainError {
	swapchain^ = {
		inited = true,
		device = device,
		extent = window_extent,
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
		minImageCount    = image_count,
		imageFormat      = surface_format.format,
		imageColorSpace  = surface_format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = swapchain_support.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
		oldSwapchain     = previous_swapchain == nil ? 0 : previous_swapchain.vk_swapchain,
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

	if vulkan.CreateSwapchainKHR(device.vk_device, &create_info, nil, &swapchain.vk_swapchain) !=
	   .SUCCESS {
		return .SwapchainCreationFailed
	}

	vulkan.GetSwapchainImagesKHR(device.vk_device, swapchain.vk_swapchain, &image_count, nil)

	swapchain.images = make([]vulkan.Image, image_count)

	vulkan.GetSwapchainImagesKHR(
		device.vk_device,
		swapchain.vk_swapchain,
		&image_count,
		&swapchain.images[0],
	)

	swapchain.image_format = surface_format.format
	swapchain.extent = extent

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

	return .None
}

destroy_swapchain :: proc(
	using swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) {
	vk_device := device.vk_device

	for image_view in image_views {
		vulkan.DestroyImageView(vk_device, image_view, vk_allocator)
	}
	delete(image_views)

	if vk_swapchain != 0 {
		vulkan.DestroySwapchainKHR(vk_device, vk_swapchain, vk_allocator)
		vk_swapchain = 0
	}
	delete(images)

	for i in 0 ..< len(depth_images) {
		vulkan.DestroyImageView(vk_device, depth_image_views[i], vk_allocator)
		vulkan.DestroyImage(vk_device, depth_images[i], vk_allocator)
		vulkan.FreeMemory(vk_device, depth_image_memories[i], vk_allocator)
	}
	delete(depth_images)
	delete(depth_image_views)
	delete(depth_image_memories)

	for framebuffer in framebuffers {
		vulkan.DestroyFramebuffer(vk_device, framebuffer, vk_allocator)
	}
	delete(framebuffers)

	vulkan.DestroyRenderPass(vk_device, render_pass, vk_allocator)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vulkan.DestroySemaphore(vk_device, render_finished_semaphores[i], vk_allocator)
		vulkan.DestroySemaphore(vk_device, image_available_sempahores[i], vk_allocator)
		vulkan.DestroyFence(vk_device, in_flight_fences[i], vk_allocator)
	}
}

extent_aspect_ratio :: proc(using extent: vulkan.Extent2D) -> f32 {
	return f32(width) / f32(height)
}

find_depth_format :: proc(
	using swapchain: ^Swapchain,
) -> (
	d.FindSupportedFormatError,
	vulkan.Format,
) {
	return d.find_supported_format(
		device,
		{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
	)
}

get_framebuffer :: proc(using swapchain: ^Swapchain, index: u32) -> vulkan.Framebuffer {
	return framebuffers[index]
}

@(private)
create_sync_objects :: proc(
	using swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks,
) -> bool {
	image_available_sempahores = make([]vulkan.Semaphore, MAX_FRAMES_IN_FLIGHT)
	render_finished_semaphores = make([]vulkan.Semaphore, MAX_FRAMES_IN_FLIGHT)
	in_flight_fences = make([]vulkan.Fence, MAX_FRAMES_IN_FLIGHT)
	images_in_flight = make([]vulkan.Fence, len(images))

	for i in 0 ..< len(images) {
		images_in_flight[i] = 0
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
			   device.vk_device,
			   &semaphore_info,
			   vk_allocator,
			   &image_available_sempahores[i],
		   ) !=
			   .SUCCESS ||
		   vulkan.CreateSemaphore(
			   device.vk_device,
			   &semaphore_info,
			   vk_allocator,
			   &render_finished_semaphores[i],
		   ) !=
			   .SUCCESS ||
		   vulkan.CreateFence(device.vk_device, &fence_info, vk_allocator, &in_flight_fences[i]) !=
			   .SUCCESS {
			fmt.println("Error creating synchronization objects for a frame!")
			return false
		}
	}

	return true
}

@(private)
create_render_pass :: proc(
	using swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks,
) -> bool {
	err, df := find_depth_format(swapchain)
	if err != nil {
		fmt.println("Error finding depth format:", err)
		return false
	}

	depth_attachment := vulkan.AttachmentDescription {
		format         = df,
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
		format         = image_format,
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

	if vulkan.CreateRenderPass(device.vk_device, &render_pass_info, vk_allocator, &render_pass) !=
	   .SUCCESS {
		fmt.println("Error creating render pass!")
		return false
	}

	return true
}

@(private)
create_depth_resources :: proc(
	using swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> bool {
	err, df := find_depth_format(swapchain)
	if err != nil {
		fmt.println("Error finding depth format:", err)
		return false
	}

	depth_format = df

	swapchain_extent := extent

	depth_images = make([]vulkan.Image, len(images))
	depth_image_memories = make([]vulkan.DeviceMemory, len(images))
	depth_image_views = make([]vulkan.ImageView, len(images))

	for i in 0 ..< len(depth_images) {
		image_info := vulkan.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = .D2,
			extent = {width = swapchain_extent.width, height = swapchain_extent.height, depth = 1},
			mipLevels = 1,
			arrayLayers = 1,
			format = df,
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = {.DEPTH_STENCIL_ATTACHMENT},
			samples = {._1},
			sharingMode = .EXCLUSIVE,
			flags = {},
		}

		d.create_image_with_info(
			device,
			&image_info,
			{.DEVICE_LOCAL},
			&depth_images[i],
			&depth_image_memories[i],
		)

		view_info := vulkan.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = depth_images[i],
			viewType = .D2,
			format = df,
			subresourceRange = {
				aspectMask = {.DEPTH},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		if vulkan.CreateImageView(
			   device.vk_device,
			   &view_info,
			   vk_allocator,
			   &depth_image_views[i],
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
	using swapchain: ^Swapchain,
	capabilities: vulkan.SurfaceCapabilitiesKHR,
) -> vulkan.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	actual_extent := window_extent
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
	using swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks,
) -> bool {
	framebuffers = make([]vulkan.Framebuffer, len(images))

	for i in 0 ..< len(images) {
		attachments := []vulkan.ImageView{image_views[i], depth_image_views[i]}
		swapchain_extent := extent

		framebuffer_info := vulkan.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = u32(len(attachments)),
			pAttachments    = &attachments[0],
			width           = swapchain_extent.width,
			height          = swapchain_extent.height,
			layers          = 1,
		}

		if vulkan.CreateFramebuffer(
			   device.vk_device,
			   &framebuffer_info,
			   vk_allocator,
			   &framebuffers[i],
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
	using swapchain: ^Swapchain,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> bool {
	image_views = make([]vulkan.ImageView, len(images))

	for image, i in images {
		view_info := vulkan.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = images[i],
			viewType = .D2,
			format = image_format,
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		if vulkan.CreateImageView(device.vk_device, &view_info, vk_allocator, &image_views[i]) !=
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
	using swapchain: ^Swapchain,
	buffers: []vulkan.CommandBuffer,
	image_index: ^u32,
) -> vulkan.Result {
	if images_in_flight[image_index^] != 0 {
		vulkan.WaitForFences(device.vk_device, 1, &images_in_flight[image_index^], true, max(u64))
	}
	images_in_flight[image_index^] = in_flight_fences[current_frame]
	wait_semaphores := []vulkan.Semaphore{image_available_sempahores[current_frame]}
	wait_stages := []vulkan.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	signal_semaphores := []vulkan.Semaphore{render_finished_semaphores[current_frame]}

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

	vulkan.ResetFences(device.vk_device, 1, &in_flight_fences[current_frame])

	result := vulkan.QueueSubmit(
		device.graphics_queue,
		1,
		&submit_info,
		in_flight_fences[current_frame],
	)

	if result != .SUCCESS {
		return result
	}

	swap_chains := []vulkan.SwapchainKHR{vk_swapchain}

	present_info := vulkan.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = u32(len(signal_semaphores)),
		pWaitSemaphores    = &signal_semaphores[0],
		swapchainCount     = u32(len(swap_chains)),
		pSwapchains        = &swap_chains[0],
		pImageIndices      = image_index,
	}

	result = vulkan.QueuePresentKHR(device.present_queue, &present_info)

	current_frame = (current_frame + 1) % MAX_FRAMES_IN_FLIGHT

	return result
}

package renderer_vulkan_model

import d "../device"
import "base:runtime"
import "core:fmt"
import "core:image"
import "vendor:vulkan"

Texture :: struct {
	texture_image:        vulkan.Image,
	texture_image_memory: vulkan.DeviceMemory,
}

CreateImageError :: enum {
	None,
	ImageCreationFailed,
	ImageMemoryAllocationFailed,
	MemoryTypeNotFound,
	LoadImageFailed,
	CreateImageFailed,
}

create_image :: proc(
	device: ^d.Device,
	width: u32,
	height: u32,
	format: vulkan.Format,
	tiling: vulkan.ImageTiling,
	usage: vulkan.ImageUsageFlags,
	properties: vulkan.MemoryPropertyFlags,
	image: ^vulkan.Image,
	image_memory: ^vulkan.DeviceMemory,
) -> CreateImageError {
	image_info := vulkan.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {width = width, height = height, depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		format = format,
		tiling = tiling,
		initialLayout = .UNDEFINED,
		usage = usage,
		samples = {._1},
		sharingMode = .EXCLUSIVE,
	}

	if vulkan.CreateImage(device.vk_device, &image_info, nil, image) != .SUCCESS {
		fmt.println("failed to create image!")
		return .ImageCreationFailed
	}

	mem_requirements: vulkan.MemoryRequirements
	vulkan.GetImageMemoryRequirements(device.vk_device, image^, &mem_requirements)

	err, memory_type_index := d.find_memory_type(
		device,
		mem_requirements.memoryTypeBits,
		properties,
	)

	if err != .None {
		fmt.println("failed to find required memory type!")
		return .MemoryTypeNotFound
	}

	alloc_info := vulkan.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	if vulkan.AllocateMemory(device.vk_device, &alloc_info, nil, image_memory) != .SUCCESS {
		fmt.println("failed to allocate image memory!")
		return .ImageMemoryAllocationFailed
	}

	vulkan.BindImageMemory(device.vk_device, image^, image_memory^, 0)

	return .None
}

create_texture_image :: proc(
	texture: ^Texture,
	device: ^d.Device,
	file_path: string,
	options: image.Options = {},
	allocator := context.allocator,
) -> CreateImageError {
	using texture

	img, err := image.load(file_path, options, allocator)
	if err != nil {
		fmt.println("failed loading file at path", file_path)
		return .LoadImageFailed
	}
	defer image.destroy(img, allocator)
	pixels := img.pixels

	staging_buffer: vulkan.Buffer
	staging_buffer_memory: vulkan.DeviceMemory

	image_size := vulkan.DeviceSize(img.width * img.height * 4)

	d.create_buffer(
		device,
		image_size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
		&staging_buffer_memory,
	)

	data: rawptr

	vulkan.MapMemory(device.vk_device, staging_buffer_memory, 0, image_size, {}, &data)
	defer vulkan.UnmapMemory(device.vk_device, staging_buffer_memory)

	runtime.mem_copy(data, &pixels, int(image_size))

	image_creation_err := create_image(
		device,
		u32(img.width),
		u32(img.height),
		.R8G8B8A8_SRGB,
		.OPTIMAL,
		{.TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
		&texture_image,
		&texture_image_memory,
	)

	if image_creation_err != .None {
		return image_creation_err
	}

	transition_image_layout(
		device,
		texture_image,
		.R8G8B8A8_SRGB,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
	)

	d.copy_buffer_to_image(
		device,
		staging_buffer,
		texture_image,
		u32(img.width),
		u32(img.height),
		1,
	)

	transition_image_layout(
		device,
		texture_image,
		.R8G8B8A8_SRGB,
		.TRANSFER_DST_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
	)

	return .None
}

transition_image_layout :: proc(
	device: ^d.Device,
	image: vulkan.Image,
	format: vulkan.Format,
	old_layout: vulkan.ImageLayout,
	new_layout: vulkan.ImageLayout,
) {
	command_buffer := d.begin_single_time_commands(device)
	defer d.end_single_time_commands(device, command_buffer)

	barrier := vulkan.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vulkan.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vulkan.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		srcAccessMask = {}, // TODO
		dstAccessMask = {}, // TODO
	}

	vulkan.CmdPipelineBarrier(
		command_buffer,
		{}, // TODO
		{}, // TODO
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)
}

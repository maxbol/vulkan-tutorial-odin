package renderer_vulkan_device

import "base:runtime"
import "core:fmt"
import "core:strings"
import "vendor:glfw"
import "vendor:vulkan"

import w "../window"

ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)

validation_layers := []cstring{"VK_LAYER_KHRONOS_validation"}
device_extensions := []cstring{vulkan.KHR_SWAPCHAIN_EXTENSION_NAME}

Device :: struct {
	instance:        vulkan.Instance,
	debug_messenger: vulkan.DebugUtilsMessengerEXT,
	physical_device: vulkan.PhysicalDevice,
	window:          ^w.Window,
	command_pool:    vulkan.CommandPool,
	logical_device:  vulkan.Device,
	surface:         vulkan.SurfaceKHR,
	graphics_queue:  vulkan.Queue,
	present_queue:   vulkan.Queue,
	properties:      vulkan.PhysicalDeviceProperties,
	vk_allocator:    ^vulkan.AllocationCallbacks,
}

Optional :: struct($T: typeid) {
	present: bool,
	value:   T,
}

QueueFamilyIndices :: struct {
	graphics_family: Optional(u32),
	present_family:  Optional(u32),
}

SwapchainSupportDetails :: struct {
	capabilities:  vulkan.SurfaceCapabilitiesKHR,
	formats:       []vulkan.SurfaceFormatKHR,
	present_modes: []vulkan.PresentModeKHR,
}


CreateBufferError :: enum {
	None,
	VertexBufferCreationFailed,
	FindMemoryTypeFailed,
	AllocateBufferFailed,
}

CreateDeviceError :: enum {
	None,
	CreateLogicalDeviceFailed,
	SetupDebugMessengerFailed,
	CreateSurfaceFailed,
	PickPhysicalDeviceFailed,
	CreateCommandPoolFailed,
}

CreateImageWithInfoError :: enum {
	None,
	FailedToCreateImage,
	FailedToAllocateImageMemory,
	FailedToBindImageMemory,
	FailedToFindMemoryType,
}

FindMemoryTypeError :: enum {
	None,
	NoSuitableMemoryType,
}

FindSupportedFormatError :: enum {
	None,
	SupportedFormatNotFound,
}

alloc_swapchain_support :: proc(device: ^Device) -> ^SwapchainSupportDetails {
	return alloc_query_swap_chain_support(device, device.physical_device)
}

begin_single_time_commands :: proc(device: ^Device) -> vulkan.CommandBuffer {
	alloc_info := vulkan.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = device.command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vulkan.CommandBuffer
	vulkan.AllocateCommandBuffers(device.logical_device, &alloc_info, &command_buffer)

	begin_info := vulkan.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vulkan.BeginCommandBuffer(command_buffer, &begin_info)
	return command_buffer
}

copy_buffer :: proc(
	device: ^Device,
	src_buffer: vulkan.Buffer,
	dst_buffer: vulkan.Buffer,
	size: vulkan.DeviceSize,
) {
	command_buffer := begin_single_time_commands(device)

	copy_region := vulkan.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = size,
	}

	vulkan.CmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region)
	end_single_time_commands(device, command_buffer)
}

copy_buffer_to_image :: proc(
	device: ^Device,
	buffer: vulkan.Buffer,
	image: vulkan.Image,
	width: u32,
	height: u32,
	layer_count: u32,
) {
	command_buffer := begin_single_time_commands(device)

	region := vulkan.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = layer_count,
		},
		imageOffset = {0, 0, 0},
		imageExtent = {width, height, 1},
	}

	vulkan.CmdCopyBufferToImage(command_buffer, buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)

	end_single_time_commands(device, command_buffer)
}

create_buffer :: proc(
	device: ^Device,
	size: vulkan.DeviceSize,
	usage: vulkan.BufferUsageFlags,
	properties: vulkan.MemoryPropertyFlags,
	buffer: ^vulkan.Buffer,
	buffer_memory: ^vulkan.DeviceMemory,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> CreateBufferError {
	buffer_info := vulkan.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	if vulkan.CreateBuffer(device.logical_device, &buffer_info, vk_allocator, buffer) != .SUCCESS {
		fmt.println("failed to create vertex buffer!")
		return .VertexBufferCreationFailed
	}

	mem_requirements: vulkan.MemoryRequirements
	vulkan.GetBufferMemoryRequirements(device.logical_device, buffer^, &mem_requirements)

	err, memory_type := find_memory_type(device, mem_requirements.memoryTypeBits, properties)

	if err != .None {
		fmt.println("find memory type failed:", err)
		return .FindMemoryTypeFailed
	}

	alloc_info := vulkan.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type,
	}

	if vulkan.AllocateMemory(device.logical_device, &alloc_info, vk_allocator, buffer_memory) !=
	   .SUCCESS {
		fmt.println("failed to allocate vertex buffer memory!")
		return .AllocateBufferFailed
	}

	vulkan.BindBufferMemory(device.logical_device, buffer^, buffer_memory^, 0)

	return .None
}

create_command_pool :: proc(device: ^Device) -> bool {
	queue_family_indices := find_physical_queue_families(device)

	pool_info := vulkan.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = queue_family_indices.graphics_family.value,
		flags            = {.TRANSIENT, .RESET_COMMAND_BUFFER},
	}

	if vulkan.CreateCommandPool(
		   device.logical_device,
		   &pool_info,
		   device.vk_allocator,
		   &device.command_pool,
	   ) !=
	   .SUCCESS {
		fmt.println("failed to create command pool!")
		return false
	}
	return true
}

create_debug_utils_messenger_ext :: proc(
	instance: vulkan.Instance,
	create_info: ^vulkan.DebugUtilsMessengerCreateInfoEXT,
	allocator: ^vulkan.AllocationCallbacks,
) -> (
	vulkan.Result,
	vulkan.DebugUtilsMessengerEXT,
) {
	debug_messenger: vulkan.DebugUtilsMessengerEXT
	func := cast(vulkan.ProcCreateDebugUtilsMessengerEXT)vulkan.GetInstanceProcAddr(
		instance,
		"vkCreateDebugUtilsMessengerEXT",
	)

	if func != nil {
		result := func(instance, create_info, allocator, &debug_messenger)
		if result != .SUCCESS {
			return result, vulkan.DebugUtilsMessengerEXT{}
		}

		return .SUCCESS, debug_messenger
	} else {
		return .ERROR_EXTENSION_NOT_PRESENT, vulkan.DebugUtilsMessengerEXT{}
	}
}

create_device :: proc(window: ^w.Window, device: ^Device) -> CreateDeviceError {
	device^ = {
		window = window,
	}

	if !create_instance(device) {
		fmt.println("Error creating logical device")
		return .CreateLogicalDeviceFailed
	}

	if !setup_debug_messenger(device) {
		fmt.println("Error setting up debug messenger")
		return .SetupDebugMessengerFailed
	}

	if !create_surface(device) {
		fmt.println("Error creating surface")
		return .CreateSurfaceFailed
	}

	if !pick_physical_device(device) {
		fmt.println("Error picking physical device")
		return .PickPhysicalDeviceFailed
	}

	if !create_logical_device(device) {
		fmt.println("Error creating logical device")
		return .CreateLogicalDeviceFailed
	}

	if !create_command_pool(device) {
		fmt.println("Error creating command pool")
		return .CreateCommandPoolFailed
	}

	return .None
}

create_image_with_info :: proc(
	device: ^Device,
	image_info: ^vulkan.ImageCreateInfo,
	properties: vulkan.MemoryPropertyFlags,
	image: ^vulkan.Image,
	image_memory: ^vulkan.DeviceMemory,
) -> CreateImageWithInfoError {
	if vulkan.CreateImage(device.logical_device, image_info, device.vk_allocator, image) !=
	   .SUCCESS {
		fmt.println("failed to create image!")
		return .FailedToCreateImage
	}

	mem_requirements: vulkan.MemoryRequirements
	vulkan.GetImageMemoryRequirements(device.logical_device, image^, &mem_requirements)

	err, memory_type := find_memory_type(device, mem_requirements.memoryTypeBits, properties)

	if err != .None {
		return .FailedToFindMemoryType
	}

	alloc_info := vulkan.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type,
	}

	if vulkan.AllocateMemory(device.logical_device, &alloc_info, nil, image_memory) != .SUCCESS {
		fmt.println("failed to allocate image memory!")
		return .FailedToAllocateImageMemory
	}

	if vulkan.BindImageMemory(device.logical_device, image^, image_memory^, 0) != .SUCCESS {
		fmt.println("failed to bind image memory!")
		return .FailedToBindImageMemory
	}

	return .None
}

create_instance :: proc(device: ^Device) -> bool {
	if ENABLE_VALIDATION_LAYERS && !check_validation_layer_support(device) {
		fmt.println("validation layers requested, but not available")
		return false
	}

	app_info := vulkan.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Goblin Mode App",
		applicationVersion = vulkan.MAKE_VERSION(1, 0, 0),
		pEngineName        = "Goblin Mode",
		engineVersion      = vulkan.MAKE_VERSION(1, 0, 0),
		apiVersion         = vulkan.API_VERSION_1_0,
	}

	extensions := get_required_extensions(device)

	create_info := vulkan.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = &extensions[0],
	}

	debug_create_info: vulkan.DebugUtilsMessengerCreateInfoEXT
	if ENABLE_VALIDATION_LAYERS {
		create_info.enabledLayerCount = 1
		create_info.ppEnabledLayerNames = &validation_layers[0]

		populate_debug_messenger_create_info(device, &debug_create_info)
		create_info.pNext = &debug_create_info
	} else {
		create_info.enabledLayerCount = 0
		create_info.pNext = nil
	}

	if (vulkan.CreateInstance(&create_info, nil, &device.instance) != .SUCCESS) {
		return false
	}

	return true
}

create_logical_device :: proc(device: ^Device) -> bool {
	indices := find_queue_families(device, device.physical_device)

	unique_queue_families := make(map[u32]bool)
	defer delete(unique_queue_families)

	unique_queue_families[indices.graphics_family.value] = true
	unique_queue_families[indices.present_family.value] = true

	queue_create_infos := make([]vulkan.DeviceQueueCreateInfo, len(unique_queue_families))
	i := 0
	queue_priority: f32 = 1
	for queue_family in unique_queue_families {
		queue_create_infos[i] = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = queue_family,
			queueCount       = 1,
			pQueuePriorities = &queue_priority,
		}
		i += 1
	}

	device_features := vulkan.PhysicalDeviceFeatures {
		samplerAnisotropy = true,
	}

	create_info := vulkan.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(len(queue_create_infos)),
		pQueueCreateInfos       = &queue_create_infos[0],
		pEnabledFeatures        = &device_features,
		enabledExtensionCount   = u32(len(device_extensions)),
		ppEnabledExtensionNames = &device_extensions[0],
	}

	if ENABLE_VALIDATION_LAYERS {
		create_info.enabledLayerCount = u32(len(validation_layers))
		create_info.ppEnabledLayerNames = &validation_layers[0]
	} else {
		create_info.enabledLayerCount = 0
	}

	if vulkan.CreateDevice(
		   device.physical_device,
		   &create_info,
		   device.vk_allocator,
		   &device.logical_device,
	   ) !=
	   .SUCCESS {
		return false
	}

	vulkan.GetDeviceQueue(
		device.logical_device,
		indices.graphics_family.value,
		0,
		&device.graphics_queue,
	)

	vulkan.GetDeviceQueue(
		device.logical_device,
		indices.graphics_family.value,
		0,
		&device.present_queue,
	)

	return true
}
create_surface :: proc(device: ^Device) -> bool {
	err: w.CreateWindowSurfaceError
	err, device.surface = w.create_window_surface(
		device.window,
		device.instance,
		device.vk_allocator,
	)

	if err != .None {
		fmt.println("Error creating surface", err)
		return false
	}

	return true
}

debug_callback :: proc "c" (
	message_severity: vulkan.DebugUtilsMessageSeverityFlagsEXT,
	message_type: vulkan.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vulkan.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = runtime.default_context()
	fmt.printfln("validation layer: %s", callback_data.pMessage)
	return false
}

deinit_swap_chain_support :: proc(details: ^SwapchainSupportDetails) {
	if details.formats != nil {
		delete(details.formats)
	}
	if details.present_modes != nil {
		delete(details.present_modes)
	}
	free(details)
}

destroy_debug_utils_messenger_ext :: proc(
	instance: vulkan.Instance,
	debug_messenger: vulkan.DebugUtilsMessengerEXT,
	allocator: ^vulkan.AllocationCallbacks,
) {
	func: vulkan.ProcDestroyDebugUtilsMessengerEXT = cast(vulkan.ProcDestroyDebugUtilsMessengerEXT)vulkan.GetInstanceProcAddr(
		instance,
		"vkDestroyDebugUtilsMessengerEXT",
	)

	if func != nil {
		func(instance, debug_messenger, allocator)
	}
}

destroy_device :: proc(device: ^Device) {
	vulkan.DestroyCommandPool(device.logical_device, device.command_pool, device.vk_allocator)
	vulkan.DestroyDevice(device.logical_device, device.vk_allocator)

	if ENABLE_VALIDATION_LAYERS {
		vulkan.DestroyDebugUtilsMessengerEXT(
			device.instance,
			device.debug_messenger,
			device.vk_allocator,
		)
	}

	vulkan.DestroySurfaceKHR(device.instance, device.surface, device.vk_allocator)
	vulkan.DestroyInstance(device.instance, device.vk_allocator)
}

end_single_time_commands :: proc(device: ^Device, command_buffer: vulkan.CommandBuffer) {
	vulkan.EndCommandBuffer(command_buffer)

	// This seems to be necessary in Odin, because we can't take pointers to parameters?
	cbuf := command_buffer

	submit_info := vulkan.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cbuf,
	}

	vulkan.QueueSubmit(device.graphics_queue, 1, &submit_info, 0)
	vulkan.QueueWaitIdle(device.graphics_queue)

	vulkan.FreeCommandBuffers(device.logical_device, device.command_pool, 1, &cbuf)
}

find_memory_type :: proc(
	device: ^Device,
	type_filter: u32,
	properties: vulkan.MemoryPropertyFlags,
) -> (
	FindMemoryTypeError,
	u32,
) {
	mem_properties: vulkan.PhysicalDeviceMemoryProperties
	vulkan.GetPhysicalDeviceMemoryProperties(device.physical_device, &mem_properties)
	for i in 0 ..< mem_properties.memoryTypeCount {
		if type_filter & (1 << i) != 0 &&
		   mem_properties.memoryTypes[i].propertyFlags & properties != {} {
			return .None, i
		}
	}

	return .NoSuitableMemoryType, 0
}

find_physical_queue_families :: proc(device: ^Device) -> QueueFamilyIndices {
	return find_queue_families(device, device.physical_device)
}

find_supported_format :: proc(
	device: ^Device,
	candidates: []vulkan.Format,
	tiling: vulkan.ImageTiling,
	features: vulkan.FormatFeatureFlags,
) -> (
	FindSupportedFormatError,
	vulkan.Format,
) {
	for format in candidates {
		props: vulkan.FormatProperties
		vulkan.GetPhysicalDeviceFormatProperties(device.physical_device, format, &props)

		if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
			return .None, format
		} else if (tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features) {
			return .None, format
		}
	}

	return .SupportedFormatNotFound, vulkan.Format{}
}

is_indices_complete :: proc(indices: QueueFamilyIndices) -> bool {
	return indices.present_family.present && indices.graphics_family.present
}

pick_physical_device :: proc(device: ^Device) -> bool {
	device_count: u32 = 0
	vulkan.EnumeratePhysicalDevices(device.instance, &device_count, nil)

	if device_count == 0 {
		fmt.println("failed to find GPUs with Vulkan support!")
		return false
	}

	fmt.println("Device count: ", device_count)
	devices := make([]vulkan.PhysicalDevice, device_count)
	defer delete(devices)

	vulkan.EnumeratePhysicalDevices(device.instance, &device_count, &devices[0])

	for physical_device in devices {
		if is_device_suitable(device, physical_device) {
			device.physical_device = physical_device
			break
		}
	}

	if device.physical_device == nil {
		fmt.println("failed to find a suitable GPU!")
		return false
	}

	vulkan.GetPhysicalDeviceProperties(device.physical_device, &device.properties)
	fmt.println("physical device:", device.properties.deviceName)

	return true
}

@(private)
check_device_extension_support :: proc(physical_device: vulkan.PhysicalDevice) -> bool {
	extension_count: u32
	vulkan.EnumerateDeviceExtensionProperties(physical_device, nil, &extension_count, nil)
	available_extensions := make([]vulkan.ExtensionProperties, extension_count)
	defer delete(available_extensions)
	vulkan.EnumerateDeviceExtensionProperties(physical_device, nil, &extension_count, nil)

	required_extensions := make(map[cstring]bool)
	defer delete(required_extensions)

	for device_extension in device_extensions {
		required_extensions[device_extension] = true
	}

	for &extension in available_extensions {
		extension_name := cstring(&extension.extensionName[0])
		delete_key(&required_extensions, extension_name)
	}

	return len(required_extensions) == 0
}

@(private)
check_validation_layer_support :: proc(device: ^Device) -> bool {
	layer_count: u32
	vulkan.EnumerateInstanceLayerProperties(&layer_count, nil)

	available_layers := make([]vulkan.LayerProperties, layer_count)
	vulkan.EnumerateInstanceLayerProperties(&layer_count, &available_layers[0])

	for layer_name in validation_layers {
		layer_found := false

		for &layer_properties in available_layers {
			if layer_name == cstring(&layer_properties.layerName[0]) {
				layer_found = true
				break
			}
		}

		if !layer_found {
			fmt.println("Missing layer:", layer_name)
			return false
		}
	}

	return true
}

@(private)
alloc_query_swap_chain_support :: proc(
	device: ^Device,
	physical_device: vulkan.PhysicalDevice,
) -> ^SwapchainSupportDetails {
	details := new(SwapchainSupportDetails)

	vulkan.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		physical_device,
		device.surface,
		&details.capabilities,
	)

	format_count: u32
	vulkan.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, device.surface, &format_count, nil)
	if format_count != 0 {
		details.formats = make([]vulkan.SurfaceFormatKHR, format_count)
		vulkan.GetPhysicalDeviceSurfaceFormatsKHR(
			physical_device,
			device.surface,
			&format_count,
			&details.formats[0],
		)
	}

	present_mode_count: u32
	vulkan.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		device.surface,
		&present_mode_count,
		nil,
	)

	if present_mode_count != 0 {
		details.present_modes = make([]vulkan.PresentModeKHR, present_mode_count)
		vulkan.GetPhysicalDeviceSurfacePresentModesKHR(
			physical_device,
			device.surface,
			&present_mode_count,
			&details.present_modes[0],
		)
	}

	return details
}

@(private)
populate_debug_messenger_create_info :: proc(
	device: ^Device,
	create_info: ^vulkan.DebugUtilsMessengerCreateInfoEXT,
) {}

@(private)
is_device_suitable :: proc(device: ^Device, physical_device: vulkan.PhysicalDevice) -> bool {
	indices := find_queue_families(device, device.physical_device)

	extension_supported := check_device_extension_support(physical_device)

	swapchain_adequate := false
	if extension_supported {
		swapchain_support := alloc_query_swap_chain_support(device, physical_device)
		defer deinit_swap_chain_support(swapchain_support)
		swapchain_adequate =
			len(swapchain_support.formats) != 0 && len(swapchain_support.present_modes) != 0
	}

	supported_features: vulkan.PhysicalDeviceFeatures
	vulkan.GetPhysicalDeviceFeatures(physical_device, &supported_features)

	return(
		is_indices_complete(indices) &&
		extension_supported &&
		swapchain_adequate &&
		supported_features.samplerAnisotropy \
	)
}

@(private)
has_glfw_required_instance_extensions :: proc(device: ^Device) -> bool {
	extension_count: u32 = 0
	vulkan.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
	extensions := make([]vulkan.ExtensionProperties, extension_count)
	vulkan.EnumerateInstanceExtensionProperties(nil, &extension_count, &extensions[0])

	available := make(map[cstring]bool)
	defer delete(available)

	fmt.println("available extensions:")
	for &extension in extensions {
		extension_name := cstring(&extension.extensionName[0])
		fmt.println("\t", extension_name)
		available[extension_name] = true
	}

	fmt.println("required extensions:")
	required_extensions := get_required_extensions(device)

	for &required in required_extensions {
		fmt.println("\t", required)
		if !available[required] {
			fmt.println("Missing required GLFW extension")
			return false
		}
	}

	return true
}

@(private)
find_queue_families :: proc(
	device: ^Device,
	physical_device: vulkan.PhysicalDevice,
) -> QueueFamilyIndices {
	indices: QueueFamilyIndices

	queue_family_count: u32 = 0
	vulkan.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)

	queue_families := make([]vulkan.QueueFamilyProperties, queue_family_count)

	vulkan.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&queue_family_count,
		&queue_families[0],
	)

	i: u32 = 0
	for queue_family in queue_families {
		if queue_family.queueCount > 0 && .GRAPHICS in queue_family.queueFlags {
			indices.graphics_family = {
				value   = i,
				present = true,
			}
		}
		present_support: b32 = false
		vulkan.GetPhysicalDeviceSurfaceSupportKHR(
			physical_device,
			i,
			device.surface,
			&present_support,
		)
		if queue_family.queueCount > 0 && present_support {
			indices.present_family = {
				value   = i,
				present = true,
			}
		}
		if is_indices_complete(indices) {
			break
		}
		i += 1
	}

	return indices
}

@(private)
get_required_extensions :: proc(device: ^Device) -> []cstring {
	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	extensions := make([dynamic]cstring)

	for glfw_extension in glfw_extensions {
		append(&extensions, glfw_extension)
	}

	append(&extensions, vulkan.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	append(&extensions, vulkan.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)
	append(&extensions, vulkan.KHR_SURFACE_EXTENSION_NAME)

	if ENABLE_VALIDATION_LAYERS {
		append(&extensions, vulkan.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	return extensions[:]
}

setup_debug_messenger :: proc(device: ^Device) -> bool {
	if !ENABLE_VALIDATION_LAYERS {
		return true
	}

	create_info: vulkan.DebugUtilsMessengerCreateInfoEXT
	populate_debug_messenger_create_info(device, &create_info)

	if (vulkan.CreateDebugUtilsMessengerEXT(
			   device.instance,
			   &create_info,
			   device.vk_allocator,
			   &device.debug_messenger,
		   ) !=
		   .SUCCESS) {
		return false
	}

	return true
}

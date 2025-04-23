package renderer_vulkan_buffer

import d "../device"
import "core:mem"
import "vendor:vulkan"

Buffer :: struct {
	device:                ^d.Device,
	mapped:                rawptr,
	vk_allocator:          ^vulkan.AllocationCallbacks,
	vk_buffer:             vulkan.Buffer,
	memory:                vulkan.DeviceMemory,
	buffer_size:           vulkan.DeviceSize,
	instance_size:         vulkan.DeviceSize,
	instance_count:        u32,
	alignment_size:        vulkan.DeviceSize,
	usage_flags:           vulkan.BufferUsageFlags,
	memory_property_flags: vulkan.MemoryPropertyFlags,
}

create_buffer :: proc(
	device: ^d.Device,
	instance_size: vulkan.DeviceSize,
	instance_count: u32,
	usage_flags: vulkan.BufferUsageFlags,
	memory_property_flags: vulkan.MemoryPropertyFlags,
	buffer: ^Buffer,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
	min_offset_alignment: vulkan.DeviceSize = 1,
) {
	alignment_size := get_alignment(instance_size, min_offset_alignment)
	buffer_size := alignment_size * vulkan.DeviceSize(instance_count)
	buffer^ = {
		device                = device,
		instance_size         = instance_size,
		instance_count        = instance_count,
		usage_flags           = usage_flags,
		memory_property_flags = memory_property_flags,
		alignment_size        = alignment_size,
		buffer_size           = buffer_size,
		vk_allocator          = vk_allocator,
	}

	d.create_buffer(
		device,
		buffer_size,
		usage_flags,
		memory_property_flags,
		&buffer.vk_buffer,
		&buffer.memory,
	)
}

descriptor_info :: proc(
	buffer: ^Buffer,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) -> vulkan.DescriptorBufferInfo {
	return vulkan.DescriptorBufferInfo{buffer = buffer.vk_buffer, offset = offset, range = size}
}

descriptor_info_for_index :: proc(buffer: ^Buffer, index: int) -> vulkan.DescriptorBufferInfo {
	return descriptor_info(
		buffer,
		buffer.alignment_size,
		vulkan.DeviceSize(index) * buffer.alignment_size,
	)
}

destroy_buffer :: proc(buffer: ^Buffer) {
	unmap_buffer(buffer)
	vulkan.DestroyBuffer(buffer.device.logical_device, buffer.vk_buffer, buffer.vk_allocator)
	vulkan.FreeMemory(buffer.device.logical_device, buffer.memory, buffer.vk_allocator)
}

flush :: proc(
	buffer: ^Buffer,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) -> vulkan.Result {
	mapped_range := vulkan.MappedMemoryRange {
		sType  = .MAPPED_MEMORY_RANGE,
		memory = buffer.memory,
		offset = offset,
		size   = size,
	}

	return vulkan.FlushMappedMemoryRanges(buffer.device.logical_device, 1, &mapped_range)
}

flush_index :: proc(buffer: ^Buffer, index: i32) -> vulkan.Result {
	return flush(buffer, buffer.alignment_size, vulkan.DeviceSize(index) * buffer.alignment_size)
}

invalidate :: proc(
	buffer: ^Buffer,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) -> vulkan.Result {
	mapped_range := vulkan.MappedMemoryRange {
		sType  = .MAPPED_MEMORY_RANGE,
		memory = buffer.memory,
		offset = offset,
		size   = size,
	}

	return vulkan.InvalidateMappedMemoryRanges(buffer.device.logical_device, 1, &mapped_range)
}

invalidate_index :: proc(buffer: ^Buffer, index: i32) -> vulkan.Result {
	return invalidate(
		buffer,
		buffer.alignment_size,
		vulkan.DeviceSize(index) * buffer.alignment_size,
	)
}

map_buffer :: proc(
	buffer: ^Buffer,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) -> vulkan.Result {
	assert(
		buffer.memory != 0 && buffer.vk_buffer != vulkan.Buffer{},
		"Must call map on buffer before create",
	)

	return vulkan.MapMemory(
		buffer.device.logical_device,
		buffer.memory,
		offset,
		size,
		{},
		&buffer.mapped,
	)
}

@(private)
get_alignment :: proc(
	instance_size: vulkan.DeviceSize,
	min_offset_alignment: vulkan.DeviceSize,
) -> vulkan.DeviceSize {
	if min_offset_alignment > 0 {
		return (instance_size + min_offset_alignment - 1) & ~(min_offset_alignment - 1)
	}

	return instance_size
}
unmap_buffer :: proc(buffer: ^Buffer) {
	if buffer.mapped == nil {
		return
	}
	vulkan.UnmapMemory(buffer.device.logical_device, buffer.memory)
	buffer.mapped = nil
}

write_to_buffer :: proc(
	buffer: ^Buffer,
	data: rawptr,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) {
	assert(buffer.mapped != nil, "Cannot copy to unmapped buffer")

	if size == vulkan.DeviceSize(vulkan.WHOLE_SIZE) {
		mem.copy(buffer.mapped, data, int(buffer.buffer_size))
	} else {
		mem_offset := mem.ptr_offset(cast(^byte)buffer.mapped, offset)
		mem.copy(mem_offset, data, int(size))
	}
}

write_to_index :: proc(buffer: ^Buffer, data: rawptr, index: i32) {
	write_to_buffer(
		buffer,
		data,
		buffer.instance_size,
		vulkan.DeviceSize(index) * buffer.alignment_size,
	)
}

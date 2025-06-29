package renderer_vulkan_buffer

import d "../device"
import "core:fmt"
import "core:mem"
import "vendor:vulkan"

Buffer :: struct {
	instance_count:        u32,
	mapped:                rawptr,
	device:                ^d.Device,
	vk_allocator:          ^vulkan.AllocationCallbacks,
	vk_buffer:             vulkan.Buffer,
	memory:                vulkan.DeviceMemory,
	buffer_size:           vulkan.DeviceSize,
	instance_size:         vulkan.DeviceSize,
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
	using buffer: ^Buffer,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) -> vulkan.DescriptorBufferInfo {
	return vulkan.DescriptorBufferInfo{buffer = vk_buffer, offset = offset, range = size}
}

descriptor_info_for_index :: proc(
	using buffer: ^Buffer,
	index: int,
) -> vulkan.DescriptorBufferInfo {
	return descriptor_info(buffer, alignment_size, vulkan.DeviceSize(index) * alignment_size)
}

destroy_buffer :: proc(using buffer: ^Buffer) {
	unmap_buffer(buffer)
	vulkan.DestroyBuffer(device.vk_device, vk_buffer, vk_allocator)
	vulkan.FreeMemory(device.vk_device, memory, vk_allocator)
}

flush :: proc(
	using buffer: ^Buffer,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) -> vulkan.Result {
	mapped_range := vulkan.MappedMemoryRange {
		sType  = .MAPPED_MEMORY_RANGE,
		memory = memory,
		offset = offset,
		size   = size,
	}

	return vulkan.FlushMappedMemoryRanges(device.vk_device, 1, &mapped_range)
}

flush_index :: proc(using buffer: ^Buffer, index: i32) -> vulkan.Result {
	return flush(buffer, alignment_size, vulkan.DeviceSize(index) * alignment_size)
}

invalidate :: proc(
	using buffer: ^Buffer,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) -> vulkan.Result {
	mapped_range := vulkan.MappedMemoryRange {
		sType  = .MAPPED_MEMORY_RANGE,
		memory = memory,
		offset = offset,
		size   = size,
	}

	return vulkan.InvalidateMappedMemoryRanges(device.vk_device, 1, &mapped_range)
}

invalidate_index :: proc(using buffer: ^Buffer, index: i32) -> vulkan.Result {
	return invalidate(buffer, alignment_size, vulkan.DeviceSize(index) * alignment_size)
}

map_buffer :: proc(
	using buffer: ^Buffer,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) -> vulkan.Result {
	assert(memory != 0 && vk_buffer != vulkan.Buffer{}, "Must call map on buffer before create")

	if size == vulkan.DeviceSize(vulkan.WHOLE_SIZE) {
		return vulkan.MapMemory(device.vk_device, memory, 0, buffer_size, {}, &mapped)
	}

	return vulkan.MapMemory(device.vk_device, memory, offset, size, {}, &mapped)
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
unmap_buffer :: proc(using buffer: ^Buffer) {
	if mapped == nil {
		return
	}
	vulkan.UnmapMemory(device.vk_device, memory)
	mapped = nil
}

write_to_buffer :: proc(
	using buffer: ^Buffer,
	data: rawptr,
	size: vulkan.DeviceSize = vulkan.DeviceSize(vulkan.WHOLE_SIZE),
	offset: vulkan.DeviceSize = 0,
) {
	assert(mapped != nil, "Cannot copy to unmapped buffer")

	if size == vulkan.DeviceSize(vulkan.WHOLE_SIZE) {
		mem.copy(mapped, data, int(buffer_size))
	} else {
		mem_offset := mem.ptr_offset(cast(^byte)mapped, offset)
		mem.copy(mem_offset, data, int(size))
	}
}

write_to_index :: proc(using buffer: ^Buffer, data: rawptr, index: i32) {
	write_to_buffer(buffer, data, instance_size, vulkan.DeviceSize(index) * alignment_size)
}

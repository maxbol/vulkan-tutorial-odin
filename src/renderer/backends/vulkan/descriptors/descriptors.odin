package renderer_vulkan_descriptor

import d "../device/"

import "core:fmt"
import "vendor:vulkan"

DescriptorSetLayout :: struct {
	device:                   ^d.Device,
	vk_descriptor_set_layout: vulkan.DescriptorSetLayout,
	bindings:                 map[u32]vulkan.DescriptorSetLayoutBinding,
	vk_allocator:             ^vulkan.AllocationCallbacks,
}

DescriptorPool :: struct {
	device:             ^d.Device,
	vk_descriptor_pool: vulkan.DescriptorPool,
	vk_allocator:       ^vulkan.AllocationCallbacks,
}

DescriptorWriter :: struct {
	set_layout: ^DescriptorSetLayout,
	pool:       ^DescriptorPool,
	writes:     [dynamic]vulkan.WriteDescriptorSet,
}

bind_descriptor_set_layout :: proc(
	bindings: ^map[u32]vulkan.DescriptorSetLayoutBinding,
	binding: u32,
	descriptor_type: vulkan.DescriptorType,
	stage_flags: vulkan.ShaderStageFlags,
	count: u32 = 1,
) {
	_, bound := bindings[binding]
	assert(!bound, "Binding already in use")

	layout_binding := vulkan.DescriptorSetLayoutBinding {
		binding         = binding,
		descriptorType  = descriptor_type,
		descriptorCount = count,
		stageFlags      = stage_flags,
	}

	bindings[binding] = layout_binding
}

descriptor_set_layout_create :: proc(
	device: ^d.Device,
	bindings: map[u32]vulkan.DescriptorSetLayoutBinding,
	dsl: ^DescriptorSetLayout,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> bool {
	dsl^ = {
		device       = device,
		bindings     = bindings,
		vk_allocator = vk_allocator,
	}

	set_layout_bindings := make([]vulkan.DescriptorSetLayoutBinding, len(bindings))
	defer delete(set_layout_bindings)
	index := 0
	for _, v in bindings {
		set_layout_bindings[index] = v
		index += 1
	}

	descriptor_set_layout_info := vulkan.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(set_layout_bindings)),
		pBindings    = &set_layout_bindings[0],
	}

	if vulkan.CreateDescriptorSetLayout(
		   device.vk_device,
		   &descriptor_set_layout_info,
		   vk_allocator,
		   &dsl.vk_descriptor_set_layout,
	   ) !=
	   .SUCCESS {
		fmt.println("Failed to create descriptor set layout")
		return false
	}

	return true
}

descriptor_set_layout_destroy :: proc(using dsl: ^DescriptorSetLayout) {
	vulkan.DestroyDescriptorSetLayout(device.vk_device, vk_descriptor_set_layout, vk_allocator)
}

descriptor_pool_create :: proc(
	device: ^d.Device,
	max_sets: u32,
	pool_flags: vulkan.DescriptorPoolCreateFlags,
	pool_sizes: []vulkan.DescriptorPoolSize,
	dp: ^DescriptorPool,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> bool {
	dp^ = {
		device       = device,
		vk_allocator = vk_allocator,
	}

	descriptor_pool_info := vulkan.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = &pool_sizes[0],
		maxSets       = max_sets,
		flags         = pool_flags,
	}

	if vulkan.CreateDescriptorPool(
		   device.vk_device,
		   &descriptor_pool_info,
		   vk_allocator,
		   &dp.vk_descriptor_pool,
	   ) !=
	   .SUCCESS {
		fmt.println("Failed to create descriptor pool")
		return false
	}

	return true
}

descriptor_pool_destroy :: proc(using dp: ^DescriptorPool) {
	vulkan.DestroyDescriptorPool(device.vk_device, vk_descriptor_pool, vk_allocator)
}

descriptor_pool_allocate_descriptor :: proc(
	using dp: ^DescriptorPool,
	descriptor_set_layout: ^vulkan.DescriptorSetLayout,
	descriptor: ^vulkan.DescriptorSet,
) -> bool {
	alloc_info := vulkan.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = vk_descriptor_pool,
		pSetLayouts        = descriptor_set_layout,
		descriptorSetCount = 1,
	}

	if vulkan.AllocateDescriptorSets(device.vk_device, &alloc_info, descriptor) != .SUCCESS {
		return false
	}

	return true
}

descriptor_pool_free_descriptors :: proc(
	using dp: ^DescriptorPool,
	descriptors: []vulkan.DescriptorSet,
) {
	vulkan.FreeDescriptorSets(
		device.vk_device,
		vk_descriptor_pool,
		u32(len(descriptors)),
		&descriptors[0],
	)
}

descriptor_pool_reset_pool :: proc(using dp: ^DescriptorPool) {
	vulkan.ResetDescriptorPool(device.vk_device, vk_descriptor_pool, {})
}

descriptor_writer_create :: proc(
	dsl: ^DescriptorSetLayout,
	dp: ^DescriptorPool,
	dw: ^DescriptorWriter,
) {
	dw^ = {
		set_layout = dsl,
		pool       = dp,
	}
}

descriptor_writer_write_buffer :: proc(
	using dw: ^DescriptorWriter,
	binding: u32,
	buffer_info: ^vulkan.DescriptorBufferInfo,
) {
	_, bound := set_layout.bindings[binding]
	assert(bound, "Layout does not contain specified binding")

	binding_description := set_layout.bindings[binding]

	assert(
		binding_description.descriptorCount == 1,
		"Binding single descriptor info, but binding expects multiple",
	)

	write := vulkan.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		descriptorType  = binding_description.descriptorType,
		dstBinding      = binding,
		pBufferInfo     = buffer_info,
		descriptorCount = 1,
	}

	append(&writes, write)
}

descriptor_writer_write_image :: proc(
	using dw: ^DescriptorWriter,
	binding: u32,
	image_info: ^vulkan.DescriptorImageInfo,
) {
	_, bound := set_layout.bindings[binding]
	assert(bound, "Layout does not contain specified binding")

	binding_description := set_layout.bindings[binding]

	assert(
		binding_description.descriptorCount == 1,
		"Binding single descriptor info, but binding expects multiple",
	)

	write := vulkan.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		descriptorType  = binding_description.descriptorType,
		dstBinding      = binding,
		pImageInfo      = image_info,
		descriptorCount = 1,
	}

	append(&writes, write)
}

descriptor_writer_end :: proc(using dw: ^DescriptorWriter, set: ^vulkan.DescriptorSet) -> bool {
	success := descriptor_pool_allocate_descriptor(pool, &set_layout.vk_descriptor_set_layout, set)
	if !success {
		return false
	}

	overwrite(dw, set^)

	return true
}

@(private)
overwrite :: proc(using dw: ^DescriptorWriter, set: vulkan.DescriptorSet) {
	for &write in writes {
		write.dstSet = set
	}
	vulkan.UpdateDescriptorSets(pool.device.vk_device, u32(len(writes)), &writes[0], 0, nil)
}

package main

import vb "renderer/backends/vulkan"
import d "renderer/backends/vulkan/device"
import p "renderer/backends/vulkan/pipeline"

import "core:fmt"
import "vendor:vulkan"

SimpleRenderSystem :: struct {
	pipeline:        ^p.Pipeline,
	pipeline_layout: vulkan.PipelineLayout,
	device:          ^d.Device,
	vk_allocator:    ^vulkan.AllocationCallbacks,
}

SimplePushConstantData :: struct {
	model_matrix:  vb.mat4,
	normal_matrix: vb.mat4,
}

create_simple_render_system :: proc(
	device: ^d.Device,
	render_pass: vulkan.RenderPass,
	global_set_layout: vulkan.DescriptorSetLayout,
	srs: ^SimpleRenderSystem,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> bool {
	srs^ = {
		device       = device,
		vk_allocator = vk_allocator,
	}

	if !create_pipeline_layout(srs, global_set_layout) {
		return false
	}

	if !create_pipeline(srs, render_pass) {
		return false
	}

	return true
}

destroy_simple_render_system :: proc(srs: ^SimpleRenderSystem) {
	vulkan.DestroyPipelineLayout(srs.device.logical_device, srs.pipeline_layout, srs.vk_allocator)
}

@(private = "file")
create_pipeline_layout :: proc(
	srs: ^SimpleRenderSystem,
	global_set_layout: vulkan.DescriptorSetLayout,
) -> bool {
	push_constant_range := vulkan.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = size_of(SimplePushConstantData),
	}

	descriptor_set_layouts := []vulkan.DescriptorSetLayout{global_set_layout}

	pipeline_layout_info := vulkan.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(descriptor_set_layouts)),
		pSetLayouts            = &descriptor_set_layouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_constant_range,
	}

	if vulkan.CreatePipelineLayout(
		   srs.device.logical_device,
		   &pipeline_layout_info,
		   srs.vk_allocator,
		   &srs.pipeline_layout,
	   ) !=
	   .SUCCESS {
		fmt.println("Failed to create pipeline layout!")
		return false
	}

	return true
}

@(private = "file")
create_pipeline :: proc(srs: ^SimpleRenderSystem, render_pass: vulkan.RenderPass) -> bool {
	assert(srs.pipeline_layout != 0, "Cannot create pipeline before pipeline layout")

	pipeline_config: p.PipelineConfigInfo
	p.default_pipeline_config_info(&pipeline_config)

	pipeline_config.render_pass = render_pass
	pipeline_config.pipeline_layout = srs.pipeline_layout

	err := p.create_pipeline(
		srs.device,
		"./shaders/simple_shader.vert.spv",
		"./shaders/simple_shader.frag.spv",
		pipeline_config,
		srs.pipeline,
		srs.vk_allocator,
	)

	if err != nil {
		fmt.println("Error creating pipeline:", err)
		return false
	}
	return true
}

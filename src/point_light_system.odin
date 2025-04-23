package main

import "core:fmt"
import "vendor:vulkan"

import vr "renderer/backends/vulkan"
import d "renderer/backends/vulkan/device"
import p "renderer/backends/vulkan/pipeline"

PointLightSystem :: struct {
	device:          ^d.Device,
	pipeline:        ^p.Pipeline,
	pipeline_layout: vulkan.PipelineLayout,
	vk_allocator:    ^vulkan.AllocationCallbacks,
}

PointLightPushConstants :: struct {
	position: vr.vec4,
	color:    vr.vec4,
	radius:   f32,
}

create_point_light_system :: proc(
	device: ^d.Device,
	render_pass: vulkan.RenderPass,
	global_set_layout: vulkan.DescriptorSetLayout,
	pls: ^PointLightSystem,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> bool {
	pls^ = {
		device       = device,
		vk_allocator = vk_allocator,
	}

	if !create_pipeline_layout(pls, global_set_layout) {
		return false
	}

	if !create_pipeline(pls, render_pass) {
		return false
	}

	return true
}

destroy_point_light_system :: proc(pls: ^PointLightSystem) {
	vulkan.DestroyPipelineLayout(pls.device.logical_device, pls.pipeline_layout, pls.vk_allocator)
}

@(private = "file")
create_pipeline_layout :: proc(
	pls: ^PointLightSystem,
	global_set_layout: vulkan.DescriptorSetLayout,
) -> bool {
	push_constant_range := vulkan.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = size_of(PointLightPushConstants),
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
		   pls.device.logical_device,
		   &pipeline_layout_info,
		   pls.vk_allocator,
		   &pls.pipeline_layout,
	   ) !=
	   .SUCCESS {
		fmt.println("Failed to create pipeline layout")
		return false
	}

	return true
}

@(private = "file")
create_pipeline :: proc(pls: ^PointLightSystem, render_pass: vulkan.RenderPass) -> bool {
	assert(pls.pipeline_layout != 0, "Cannot create pipeline before pipeline layout")

	pipeline_config: p.PipelineConfigInfo
	p.default_pipeline_config_info(&pipeline_config)
	p.enable_alpha_blending(&pipeline_config)
	p.clear_binding_descriptions(&pipeline_config)
	p.clear_attribute_descriptions(&pipeline_config)

	pipeline_config.render_pass = render_pass
	pipeline_config.pipeline_layout = pls.pipeline_layout

	err := p.create_pipeline(
		pls.device,
		"./shaders/point_light.vert.spv",
		"./shaders/point_light.frag.spv",
		pipeline_config,
		pls.pipeline,
	)

	if err != nil {
		fmt.println("Error creating pipeline", err)
		return false
	}

	return true
}

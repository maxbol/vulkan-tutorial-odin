package main

import d "renderer/backends/vulkan/device"
import m "renderer/backends/vulkan/model"
import p "renderer/backends/vulkan/pipeline"
import um "unitmath"

import "core:fmt"
import l "core:math/linalg"
import "vendor:vulkan"

SimpleRenderSystem :: struct {
	pipeline:        p.Pipeline,
	pipeline_layout: vulkan.PipelineLayout,
	device:          ^d.Device,
	vk_allocator:    ^vulkan.AllocationCallbacks,
}

SimplePushConstantData :: struct {
	model_matrix:  um.Mat4,
	normal_matrix: um.Mat4,
}

create_simple_push_constant_data :: proc() -> SimplePushConstantData {
	return SimplePushConstantData {
		model_matrix = um.Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		normal_matrix = um.Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
	}
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
		   srs.device.vk_device,
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
create_pipeline :: proc(using srs: ^SimpleRenderSystem, render_pass: vulkan.RenderPass) -> bool {
	assert(pipeline_layout != 0, "Cannot create pipeline before pipeline layout")

	pipeline_config: p.PipelineConfigInfo
	p.default_pipeline_config_info(&pipeline_config)

	pipeline_config.render_pass = render_pass
	pipeline_config.pipeline_layout = pipeline_layout

	fmt.println("pipeline_config", pipeline_config)

	err := p.create_pipeline(
		device,
		"./shaders/simple_shader.vert.spv",
		"./shaders/simple_shader.frag.spv",
		pipeline_config,
		&pipeline,
		vk_allocator,
	)

	if err != nil {
		fmt.println("Error creating pipeline:", err)
		return false
	}
	return true
}

srs_create :: proc(
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

srs_destroy :: proc(using srs: ^SimpleRenderSystem) {
	p.destroy_pipeline(&pipeline)
	pipeline = p.Pipeline{}
	vulkan.DestroyPipelineLayout(device.vk_device, pipeline_layout, vk_allocator)
}

srs_render_game_objects :: proc(using srs: ^SimpleRenderSystem, frame_info: ^FrameInfo) {
	p.bind(&pipeline, frame_info.command_buffer)

	vulkan.CmdBindDescriptorSets(
		frame_info.command_buffer,
		.GRAPHICS,
		pipeline_layout,
		0,
		1,
		&frame_info.global_descriptor_set,
		0,
		nil,
	)

	for key, obj in frame_info.game_objects {
		if !obj.model.present {
			continue
		}
		push := create_simple_push_constant_data()

		push.model_matrix = transform_to_mat4(obj.transform)
		push.normal_matrix = l.matrix4_from_matrix3(transform_to_normal_mat(obj.transform))

		vulkan.CmdPushConstants(
			frame_info.command_buffer,
			pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(SimplePushConstantData),
			&push,
		)

		m.bind(obj.model.value, frame_info.command_buffer)
		m.draw(obj.model.value, frame_info.command_buffer)
	}


}

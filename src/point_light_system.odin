package main

import rbt "core:container/rbtree"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "vendor:vulkan"

import gs "game_state"
import c "renderer/backends/vulkan/camera"
import d "renderer/backends/vulkan/device"
import p "renderer/backends/vulkan/pipeline"
import um "unitmath"

PointLight :: struct {
	position: um.Vec4,
	color:    um.Vec4,
}

PointLightSystem :: struct {
	device:          ^d.Device,
	pipeline:        p.Pipeline,
	pipeline_layout: vulkan.PipelineLayout,
	vk_allocator:    ^vulkan.AllocationCallbacks,
}

PointLightPushConstants :: struct {
	position: um.Vec4,
	color:    um.Vec4,
	radius:   f32,
}

PointLightSortedGameObject :: struct {
	order: f32,
	id:    gs.GameObjectId,
}

pls_create :: proc(
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

pls_destroy :: proc(using pls: ^PointLightSystem) {
	p.destroy_pipeline(&pipeline)
	pipeline = {}
	vulkan.DestroyPipelineLayout(device.vk_device, pipeline_layout, vk_allocator)
}

@(private = "file")
create_pipeline_layout :: proc(
	using pls: ^PointLightSystem,
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
		   device.vk_device,
		   &pipeline_layout_info,
		   vk_allocator,
		   &pipeline_layout,
	   ) !=
	   .SUCCESS {
		fmt.println("Failed to create pipeline layout")
		return false
	}

	return true
}

@(private = "file")
create_pipeline :: proc(using pls: ^PointLightSystem, render_pass: vulkan.RenderPass) -> bool {
	assert(pipeline_layout != 0, "Cannot create pipeline before pipeline layout")

	pipeline_config: p.PipelineConfigInfo
	p.default_pipeline_config_info(&pipeline_config)
	p.enable_alpha_blending(&pipeline_config)
	p.clear_binding_descriptions(&pipeline_config)
	p.clear_attribute_descriptions(&pipeline_config)

	pipeline_config.render_pass = render_pass
	pipeline_config.pipeline_layout = pipeline_layout

	err := p.create_pipeline(
		device,
		"./shaders/point_light.vert.spv",
		"./shaders/point_light.frag.spv",
		pipeline_config,
		&pipeline,
	)

	if err != nil {
		fmt.println("Error creating pipeline", err)
		return false
	}

	return true
}

pls_update :: proc(frame_info: ^gs.FrameInfo, ubo: ^GlobalUbo) {
	using um, linalg
	rotate_light := Mat4(1) * matrix4_rotate_f32(0.5 * frame_info.frame_time, {0., -1., 0.})
	light_index: int = 0

	for id, &obj in frame_info.game_objects {
		if !obj.point_light.present {
			continue
		}

		assert(light_index < MAX_LIGHTS, "Point lights exceed maximum specified")

		obj.transform.translation = (rotate_light * vec4(obj.transform.translation, 1)).xyz

		ubo.pointLights[light_index].position = vec4(obj.transform.translation, 1)
		ubo.pointLights[light_index].color = vec4(obj.color, obj.point_light.value.light_intensity)

		light_index += 1
	}

	ubo.numLights = light_index
}

pls_render :: proc(using pls: ^PointLightSystem, frame_info: ^gs.FrameInfo) {
	using linalg

	sorted := make(
		[dynamic]PointLightSortedGameObject,
		0,
		len(frame_info.game_objects),
		context.temp_allocator,
	)

	for id, obj in frame_info.game_objects {
		if obj.point_light.present == false {
			continue
		}
		offset := c.camera_get_position(frame_info.camera) - obj.transform.translation
		dist_squared := dot(offset, offset)
		append(&sorted, PointLightSortedGameObject{id = id, order = dist_squared})
	}

	slice.sort_by(
		sorted[:],
		proc(i: PointLightSortedGameObject, j: PointLightSortedGameObject) -> bool {
			return i.order > j.order
		},
	)

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

	for sorted_go in sorted {
		using um
		obj := frame_info.game_objects[sorted_go.id]

		push := PointLightPushConstants {
			position = vec4(obj.transform.translation, 1),
			color    = vec4(obj.color, obj.point_light.value.light_intensity),
			radius   = obj.transform.scale.x,
		}

		vulkan.CmdPushConstants(
			frame_info.command_buffer,
			pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(PointLightPushConstants),
			&push,
		)

		vulkan.CmdDraw(frame_info.command_buffer, 6, 1, 0, 0)
	}
}

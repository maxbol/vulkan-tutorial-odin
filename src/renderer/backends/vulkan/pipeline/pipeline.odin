package renderer_vulkan_pipeline

import d "../device"
import m "../model"

import "core:fmt"
import "core:os"
import "vendor:vulkan"


PipelineConfigInfo :: struct {
	attribute_descriptions:       [m.ATTRIBUTE_DESCRIPTIONS_MAX_COUNT]vulkan.VertexInputAttributeDescription,
	attribute_descriptions_count: u32,
	binding_descriptions:         [m.BINDING_DESCRIPTIONS_MAX_COUNT]vulkan.VertexInputBindingDescription,
	binding_descriptions_count:   u32,
	viewport_info:                vulkan.PipelineViewportStateCreateInfo,
	input_assembly_info:          vulkan.PipelineInputAssemblyStateCreateInfo,
	rasterization_info:           vulkan.PipelineRasterizationStateCreateInfo,
	multisample_info:             vulkan.PipelineMultisampleStateCreateInfo,
	color_blend_attachment:       vulkan.PipelineColorBlendAttachmentState,
	color_blend_info:             vulkan.PipelineColorBlendStateCreateInfo,
	depth_stencil_info:           vulkan.PipelineDepthStencilStateCreateInfo,
	dynamic_state_enables:        []vulkan.DynamicState,
	dynamic_state_info:           vulkan.PipelineDynamicStateCreateInfo,
	pipeline_layout:              vulkan.PipelineLayout,
	render_pass:                  vulkan.RenderPass,
	subpass:                      u32,
}

Pipeline :: struct {
	device:             ^d.Device,
	graphics_pipeline:  vulkan.Pipeline,
	vert_shader_module: vulkan.ShaderModule,
	frag_shader_module: vulkan.ShaderModule,
	vk_allocator:       ^vulkan.AllocationCallbacks,
}

CreatePipelineError :: enum {
	None,
	VertShaderReadFailed,
	FragShaderReadFailed,
	VertShaderLoadFailed,
	FragShaderLoadFailed,
	GraphicsPipelinesCreationFailed,
}

bind :: proc(pipeline: ^Pipeline, command_buffer: vulkan.CommandBuffer) {
	vulkan.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline.graphics_pipeline)
}

create_pipeline :: proc(
	device: ^d.Device,
	vert_file_path: string,
	frag_file_path: string,
	config_info: PipelineConfigInfo,
	pipeline: ^Pipeline,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> CreatePipelineError {
	pipeline^ = {
		device       = device,
		vk_allocator = vk_allocator,
	}

	assert(
		config_info.pipeline_layout != 0,
		"Cannot create graphics pipeline: no pipeline_layout provided in config_info",
	)

	assert(
		config_info.render_pass != 0,
		"Cannot create graphics pipeline: no render_pass provided in config_info",
	)

	ok: bool
	vert_code, frag_code: []u8

	ok, vert_code = read_bytecode_file(vert_file_path)
	if !ok {
		return .VertShaderReadFailed
	}

	ok, frag_code = read_bytecode_file(frag_file_path)
	if !ok {
		return .FragShaderReadFailed
	}

	if !create_shader_module(pipeline, vert_code, &pipeline.vert_shader_module) {
		return .VertShaderLoadFailed
	}

	if !create_shader_module(pipeline, frag_code, &pipeline.frag_shader_module) {
		return .FragShaderLoadFailed
	}

	shader_stages: [2]vulkan.PipelineShaderStageCreateInfo

	shader_stages[0] = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage               = {.VERTEX},
		module              = pipeline.vert_shader_module,
		pName               = "main",
		flags               = {},
		pNext               = nil,
		pSpecializationInfo = nil,
	}

	shader_stages[1] = {
		sType               = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage               = {.FRAGMENT},
		module              = pipeline.frag_shader_module,
		pName               = "main",
		flags               = {},
		pNext               = nil,
		pSpecializationInfo = nil,
	}

	cfg_info := config_info

	vertex_input_info := vulkan.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexAttributeDescriptionCount = cfg_info.attribute_descriptions_count,
		vertexBindingDescriptionCount   = cfg_info.binding_descriptions_count,
		pVertexAttributeDescriptions    = &cfg_info.attribute_descriptions[0],
		pVertexBindingDescriptions      = &cfg_info.binding_descriptions[0],
	}

	pipeline_info := vulkan.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = &shader_stages[0],
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &cfg_info.input_assembly_info,
		pViewportState      = &cfg_info.viewport_info,
		pRasterizationState = &cfg_info.rasterization_info,
		pMultisampleState   = &cfg_info.multisample_info,
		pColorBlendState    = &cfg_info.color_blend_info,
		pDepthStencilState  = &cfg_info.depth_stencil_info,
		pDynamicState       = &cfg_info.dynamic_state_info,
		layout              = cfg_info.pipeline_layout,
		renderPass          = cfg_info.render_pass,
		subpass             = cfg_info.subpass,
		basePipelineIndex   = 1,
		basePipelineHandle  = 0,
	}

	if vulkan.CreateGraphicsPipelines(
		   device.logical_device,
		   0,
		   1,
		   &pipeline_info,
		   vk_allocator,
		   &pipeline.graphics_pipeline,
	   ) !=
	   .SUCCESS {
		fmt.println("failed to create graphics pipeline!")
		return .GraphicsPipelinesCreationFailed
	}

	return .None
}

default_pipeline_config_info :: proc(config_info: ^PipelineConfigInfo) {
	config_info.input_assembly_info.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	config_info.input_assembly_info.topology = .TRIANGLE_LIST
	config_info.input_assembly_info.primitiveRestartEnable = false

	config_info.viewport_info.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
	config_info.viewport_info.viewportCount = 1
	config_info.viewport_info.pViewports = nil
	config_info.viewport_info.scissorCount = 1
	config_info.viewport_info.pScissors = nil

	config_info.rasterization_info.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
	config_info.rasterization_info.depthClampEnable = false
	config_info.rasterization_info.rasterizerDiscardEnable = false
	config_info.rasterization_info.polygonMode = .FILL
	config_info.rasterization_info.lineWidth = 1
	config_info.rasterization_info.cullMode = {}
	config_info.rasterization_info.frontFace = .CLOCKWISE
	config_info.rasterization_info.depthClampEnable = false
	config_info.rasterization_info.depthBiasConstantFactor = 0
	config_info.rasterization_info.depthBiasClamp = 0
	config_info.rasterization_info.depthBiasSlopeFactor = 0

	config_info.multisample_info.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	config_info.multisample_info.sampleShadingEnable = false
	config_info.multisample_info.rasterizationSamples = {._1}
	config_info.multisample_info.minSampleShading = 1
	config_info.multisample_info.pSampleMask = nil
	config_info.multisample_info.alphaToCoverageEnable = false
	config_info.multisample_info.alphaToOneEnable = false

	config_info.color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	config_info.color_blend_attachment.blendEnable = false
	config_info.color_blend_attachment.srcColorBlendFactor = .ONE
	config_info.color_blend_attachment.dstColorBlendFactor = .ZERO
	config_info.color_blend_attachment.colorBlendOp = .ADD
	config_info.color_blend_attachment.srcAlphaBlendFactor = .ONE
	config_info.color_blend_attachment.dstAlphaBlendFactor = .ZERO
	config_info.color_blend_attachment.alphaBlendOp = .ADD

	config_info.color_blend_info.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	config_info.color_blend_info.logicOpEnable = false
	config_info.color_blend_info.logicOp = .COPY
	config_info.color_blend_info.attachmentCount = 1
	config_info.color_blend_info.pAttachments = &config_info.color_blend_attachment
	config_info.color_blend_info.blendConstants = {0, 0, 0, 0}

	config_info.depth_stencil_info.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
	config_info.depth_stencil_info.depthTestEnable = true
	config_info.depth_stencil_info.depthWriteEnable = true
	config_info.depth_stencil_info.depthCompareOp = .LESS
	config_info.depth_stencil_info.depthBoundsTestEnable = false
	config_info.depth_stencil_info.minDepthBounds = 0
	config_info.depth_stencil_info.maxDepthBounds = 1
	config_info.depth_stencil_info.stencilTestEnable = false
	config_info.depth_stencil_info.front = {}
	config_info.depth_stencil_info.back = {}

	config_info.dynamic_state_enables = {.VIEWPORT, .SCISSOR}
	config_info.dynamic_state_info.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
	config_info.dynamic_state_info.pDynamicStates = &config_info.dynamic_state_enables[0]
	config_info.dynamic_state_info.dynamicStateCount = u32(len(config_info.dynamic_state_enables))
	config_info.dynamic_state_info.flags = {}

	m.get_binding_descriptions(
		&config_info.binding_descriptions,
		&config_info.binding_descriptions_count,
	)

	m.get_attribute_descriptions(
		&config_info.attribute_descriptions,
		&config_info.attribute_descriptions_count,
	)
}

destroy_pipeline :: proc(pipeline: ^Pipeline) {
	vulkan.DestroyShaderModule(
		pipeline.device.logical_device,
		pipeline.vert_shader_module,
		pipeline.vk_allocator,
	)

	vulkan.DestroyShaderModule(
		pipeline.device.logical_device,
		pipeline.frag_shader_module,
		pipeline.vk_allocator,
	)

	vulkan.DestroyPipeline(
		pipeline.device.logical_device,
		pipeline.graphics_pipeline,
		pipeline.vk_allocator,
	)
}

clear_attribute_descriptions :: proc(config_info: ^PipelineConfigInfo) {
	for i in 0 ..< m.ATTRIBUTE_DESCRIPTIONS_MAX_COUNT {
		config_info.attribute_descriptions[i] = {}
	}
}
clear_binding_descriptions :: proc(config_info: ^PipelineConfigInfo) {
	for i in 0 ..< m.BINDING_DESCRIPTIONS_MAX_COUNT {
		config_info.binding_descriptions[i] = {}
	}
}


enable_alpha_blending :: proc(config_info: ^PipelineConfigInfo) {
	config_info.color_blend_attachment.blendEnable = true
	config_info.color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	config_info.color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
	config_info.color_blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
	config_info.color_blend_attachment.colorBlendOp = .ADD
	config_info.color_blend_attachment.srcAlphaBlendFactor = .ONE
	config_info.color_blend_attachment.dstAlphaBlendFactor = .ZERO
	config_info.color_blend_attachment.alphaBlendOp = .ADD
}

@(private)
create_shader_module :: proc(
	pipeline: ^Pipeline,
	code: []u8,
	shader_module: ^vulkan.ShaderModule,
) -> bool {
	create_info := vulkan.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)&code[0],
	}

	result := vulkan.CreateShaderModule(
		pipeline.device.logical_device,
		&create_info,
		pipeline.vk_allocator,
		shader_module,
	)

	if result != .SUCCESS {
		fmt.println("failed to create shader module:", result)
		return false
	}

	return true
}
read_bytecode_file :: proc(filepath: string) -> (bool, []u8) {
	data, err := os.read_entire_file_from_filename_or_err(filepath)
	if err != nil {
		fmt.println("Error reading bytecode from file:", err)
		return false, nil
	}
	return true, data
}

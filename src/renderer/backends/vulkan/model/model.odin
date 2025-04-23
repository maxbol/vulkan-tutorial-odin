package renderer_vulkan_model

import v "../"
import wavefront "../../../utils/wavefront"
import buffer "../buffer"
import device "../device"
import "core:fmt"
import "core:os"
import "vendor:vulkan"

BINDING_DESCRIPTIONS_MAX_COUNT :: 1
ATTRIBUTE_DESCRIPTIONS_MAX_COUNT :: 4

Vertex :: struct {
	position: v.vec3,
	color:    v.vec3,
	normal:   v.vec3,
	uv:       v.vec2,
}

Builder :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
}

Model :: struct {
	device:           ^device.Device,
	vertex_buffer:    buffer.Buffer,
	vertex_count:     u32,
	has_index_buffer: bool,
	index_buffer:     buffer.Buffer,
	index_count:      u32,
}

bind :: proc(model: ^Model, command_buffer: vulkan.CommandBuffer) {
	buffers := []vulkan.Buffer{model.vertex_buffer.vk_buffer}
	offsets := []vulkan.DeviceSize{0}

	vulkan.CmdBindVertexBuffers(command_buffer, 0, 1, &buffers[0], &offsets[0])

	if model.has_index_buffer {
		vulkan.CmdBindIndexBuffer(command_buffer, model.index_buffer.vk_buffer, 0, .UINT32)
	}
}

@(private)
create_index_buffers :: proc(model: ^Model, indices: []u32) {
	model.index_count = u32(len(indices))
	model.has_index_buffer = model.index_count > 0

	if !model.has_index_buffer {
		return
	}

	buffer_size := size_of(indices[0]) * vulkan.DeviceSize(model.index_count)
	index_size := vulkan.DeviceSize(size_of(indices[0]))

	staging_buffer: buffer.Buffer
	buffer.create_buffer(
		model.device,
		index_size,
		model.index_count,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
	)

	buffer.map_buffer(&staging_buffer)
	buffer.write_to_buffer(&staging_buffer, &indices[0])

	buffer.create_buffer(
		model.device,
		index_size,
		model.index_count,
		{.INDEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
		&model.index_buffer,
	)

	device.copy_buffer(
		model.device,
		staging_buffer.vk_buffer,
		model.index_buffer.vk_buffer,
		buffer_size,
	)
}
create_model :: proc(device: ^device.Device, builder: Builder, model: ^Model) {
	create_vertex_buffers(model, builder.vertices[:])
	create_index_buffers(model, builder.indices[:])
}

create_model_from_file :: proc(device: ^device.Device, filepath: string, model: ^Model) {
	ENGINE_DIR :: "./"
	builder: Builder
	load_model(
		&builder,
		/* ENGINE_DIR +  */
		filepath,
	)
	create_model(device, builder, model)
}

@(private)
create_vertex_buffers :: proc(model: ^Model, vertices: []Vertex) {
	vertex_count := u32(len(vertices))
	assert(vertex_count >= 3, "Vertex count must be at least 3")
	buffer_size := size_of(vertices[0]) * vertex_count
	vertex_size := size_of(vertices[0])

	staging_buffer: buffer.Buffer

	buffer.create_buffer(
		model.device,
		vulkan.DeviceSize(vertex_size),
		vertex_count,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
	)

	buffer.map_buffer(&staging_buffer)
	buffer.write_to_buffer(&staging_buffer, &vertices[0])

	buffer.create_buffer(
		model.device,
		vulkan.DeviceSize(vertex_size),
		vertex_count,
		{.VERTEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
		&model.vertex_buffer,
	)

	device.copy_buffer(
		model.device,
		staging_buffer.vk_buffer,
		model.vertex_buffer.vk_buffer,
		vulkan.DeviceSize(buffer_size),
	)
}

destroy_model :: proc(model: ^Model) {
}

draw :: proc(model: ^Model, command_buffer: vulkan.CommandBuffer) {
	if model.has_index_buffer {
		vulkan.CmdDrawIndexed(command_buffer, model.index_count, 1, 0, 0, 0)
	} else {
		vulkan.CmdDraw(command_buffer, model.vertex_count, 1, 0, 0)
	}
}

get_attribute_descriptions :: proc(
	attribute_descriptions: ^[ATTRIBUTE_DESCRIPTIONS_MAX_COUNT]vulkan.VertexInputAttributeDescription,
	attribute_descriptions_count: ^u32,
) {
	attribute_descriptions[0] = {0, 0, .R32G32B32_SFLOAT, u32(offset_of(Vertex, position))}
	attribute_descriptions[1] = {1, 0, .R32G32B32_SFLOAT, u32(offset_of(Vertex, color))}
	attribute_descriptions[2] = {2, 0, .R32G32B32_SFLOAT, u32(offset_of(Vertex, normal))}
	attribute_descriptions[3] = {3, 0, .R32G32_SFLOAT, u32(offset_of(Vertex, uv))}

	attribute_descriptions_count^ = 4
}

get_binding_descriptions :: proc(
	binding_descriptions: ^[BINDING_DESCRIPTIONS_MAX_COUNT]vulkan.VertexInputBindingDescription,
	binding_descriptions_count: ^u32,
) {
	binding_descriptions[0] = {
		binding   = 0,
		stride    = size_of(Vertex),
		inputRate = .VERTEX,
	}
	binding_descriptions_count^ = 1
}

load_model :: proc(builder: ^Builder, filepath: string) -> bool {
	file_data, err := os.read_entire_file_from_filename_or_err(filepath)
	if err != nil {
		fmt.println("Error loading model:", err)
		return false
	}
	data, ok := wavefront.wavefront_load(transmute(string)file_data, false)

	for index in data.index_buffer {
		append(&builder.indices, index)
	}

	for vertex_data in data.vertex_buffer {
		vertex := Vertex {
			position = v.vec3(vertex_data.position),
			normal   = v.vec3(vertex_data.normal),
			uv       = v.vec2(vertex_data.tex_coord),
			// the wavefront loader currently doesn't support loading colors
			color    = {0.6, 0.6, 0.6},
		}
		append(&builder.vertices, vertex)
	}

	return true
}

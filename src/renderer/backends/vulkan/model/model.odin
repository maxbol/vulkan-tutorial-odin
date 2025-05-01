package renderer_vulkan_model

import um "../../../../unitmath"
import wavefront "../../../utils/wavefront"
import b "../buffer"
import d "../device"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "vendor:vulkan"

BINDING_DESCRIPTIONS_MAX_COUNT :: 1
ATTRIBUTE_DESCRIPTIONS_MAX_COUNT :: 4

Vertex :: struct {
	position: um.Vec3,
	color:    um.Vec3,
	normal:   um.Vec3,
	uv:       um.Vec2,
}

Builder :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
}

Model :: struct {
	device:           ^d.Device,
	vertex_buffer:    b.Buffer,
	vertex_count:     u32,
	has_index_buffer: bool,
	index_buffer:     b.Buffer,
	index_count:      u32,
}

bind :: proc(using model: Model, command_buffer: vulkan.CommandBuffer) {
	buffers := []vulkan.Buffer{vertex_buffer.vk_buffer}
	offsets := []vulkan.DeviceSize{0}

	vulkan.CmdBindVertexBuffers(command_buffer, 0, 1, &buffers[0], &offsets[0])

	if has_index_buffer {
		vulkan.CmdBindIndexBuffer(command_buffer, index_buffer.vk_buffer, 0, .UINT32)
	}
}

@(private)
create_index_buffers :: proc(using model: ^Model, indices: []u32) {
	index_count = u32(len(indices))
	has_index_buffer = index_count > 0

	if !has_index_buffer {
		return
	}

	buffer_size := size_of(indices[0]) * vulkan.DeviceSize(index_count)
	index_size := vulkan.DeviceSize(size_of(indices[0]))

	staging_buffer: b.Buffer
	b.create_buffer(
		device,
		index_size,
		index_count,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
	)
	defer b.destroy_buffer(&staging_buffer)

	b.map_buffer(&staging_buffer)
	b.write_to_buffer(&staging_buffer, &indices[0])

	b.create_buffer(
		device,
		index_size,
		index_count,
		{.INDEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
		&index_buffer,
	)

	d.copy_buffer(device, staging_buffer.vk_buffer, index_buffer.vk_buffer, buffer_size)
}

create_model :: proc(device: ^d.Device, builder: Builder, model: ^Model) {
	model^ = {
		device = device,
	}
	create_vertex_buffers(model, builder.vertices[:])
	create_index_buffers(model, builder.indices[:])
}

create_model_from_file :: proc(device: ^d.Device, file: string, model: ^Model) -> bool {
	ENGINE_DIR :: "./"
	builder: Builder
	p, ok := filepath.abs(strings.concatenate({ENGINE_DIR, file}))
	if !ok {
		fmt.eprintfln("Couldn't resolve model path", file)
		return false
	}
	fmt.println("Loading model from", p)
	if !load_model(&builder, p) {
		return false
	}
	create_model(device, builder, model)
	return true
}

@(private)
create_vertex_buffers :: proc(using model: ^Model, vertices: []Vertex) {
	vertex_count = u32(len(vertices))
	assert(vertex_count >= 3, "Vertex count must be at least 3")
	buffer_size := size_of(vertices[0]) * vertex_count
	vertex_size := size_of(vertices[0])

	staging_buffer: b.Buffer

	b.create_buffer(
		device,
		vulkan.DeviceSize(vertex_size),
		vertex_count,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
	)
	defer b.destroy_buffer(&staging_buffer)

	b.map_buffer(&staging_buffer)
	b.write_to_buffer(&staging_buffer, &vertices[0])

	b.create_buffer(
		device,
		vulkan.DeviceSize(vertex_size),
		vertex_count,
		{.VERTEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
		&vertex_buffer,
	)

	d.copy_buffer(
		device,
		staging_buffer.vk_buffer,
		vertex_buffer.vk_buffer,
		vulkan.DeviceSize(buffer_size),
	)
}

destroy_model :: proc(using model: ^Model) {
	b.destroy_buffer(&vertex_buffer)
	b.destroy_buffer(&index_buffer)
}

draw :: proc(using model: Model, command_buffer: vulkan.CommandBuffer) {
	if has_index_buffer {
		vulkan.CmdDrawIndexed(command_buffer, index_count, 1, 0, 0, 0)
	} else {
		vulkan.CmdDraw(command_buffer, vertex_count, 1, 0, 0)
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

load_model :: proc(using builder: ^Builder, filepath: string) -> bool {
	file_data, err := os.read_entire_file_from_filename_or_err(filepath)
	if err != nil {
		fmt.println("Error loading model:", err)
		return false
	}
	data, ok := wavefront.wavefront_load(transmute(string)file_data, false)

	for index in data.index_buffer {
		append(&indices, index)
	}

	for vertex_data in data.vertex_buffer {
		vertex := Vertex {
			position = um.Vec3(vertex_data.position),
			normal   = um.Vec3(vertex_data.normal),
			uv       = um.Vec2(vertex_data.tex_coord),
			// the wavefront loader currently doesn't support loading colors
			color    = {0.6, 0.6, 0.6},
		}
		append(&vertices, vertex)
	}

	return true
}

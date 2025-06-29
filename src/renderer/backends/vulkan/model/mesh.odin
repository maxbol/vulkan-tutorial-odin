package renderer_vulkan_model

import um "../../../../unitmath"
import wavefront "../../../utils/wavefront"
import b "../buffer"
import d "../device"
import "core:fmt"
import "core:image"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "vendor:cgltf"
import "vendor:vulkan"

BINDING_DESCRIPTIONS_MAX_COUNT :: 1
ATTRIBUTE_DESCRIPTIONS_MAX_COUNT :: 4

Vertex :: struct {
	position: um.Vec3,
	color:    um.Vec3,
	normal:   um.Vec3,
	uv:       um.Vec2,
}

MeshBuilder :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
}

Mesh :: struct {
	has_index_buffer: bool,
	index_count:      u32,
	vertex_count:     u32,
	device:           ^d.Device,
	index_buffer:     b.Buffer,
	vertex_buffer:    b.Buffer,
}

// attach_texture_to_model :: proc(
// 	using model: ^Model,
// 	texture_file_path: string,
// 	options: image.Options = {},
// 	allocator := context.allocator,
// ) -> CreateImageError {
// 	return create_texture_image(model.texture, model.device, texture_file_path, options, allocator)
// }

bind :: proc(using mesh: Mesh, command_buffer: vulkan.CommandBuffer) {
	buffers := []vulkan.Buffer{vertex_buffer.vk_buffer}
	offsets := []vulkan.DeviceSize{0}

	vulkan.CmdBindVertexBuffers(command_buffer, 0, 1, &buffers[0], &offsets[0])

	if has_index_buffer {
		vulkan.CmdBindIndexBuffer(command_buffer, index_buffer.vk_buffer, 0, .UINT32)
	}
}

@(private)
create_index_buffers :: proc(using mesh: ^Mesh, indices: []u32) {
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

create_mesh :: proc(device: ^d.Device, builder: MeshBuilder, mesh: ^Mesh) {
	mesh^ = {
		device = device,
	}
	create_vertex_buffers(mesh, builder.vertices[:])
	create_index_buffers(mesh, builder.indices[:])
}

@(private)
create_vertex_buffers :: proc(using mesh: ^Mesh, vertices: []Vertex) {
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

destroy_mesh :: proc(using mesh: ^Mesh) {
	b.destroy_buffer(&vertex_buffer)
	b.destroy_buffer(&index_buffer)
}

draw :: proc(using mesh: Mesh, command_buffer: vulkan.CommandBuffer) {
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

load_mesh_wavefront :: proc(using builder: ^MeshBuilder, filepath: string) -> bool {
	file_data, err := os.read_entire_file_from_filename_or_err(filepath)
	if err != nil {
		fmt.println("Error loading mesh:", err)
		return false
	}
	data, ok := wavefront.wavefront_load(transmute(string)file_data, false)
	defer wavefront.wavefront_destroy(&data)

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

load_model_glb :: proc(filepath: string, options: cgltf.options = {}) -> bool {
	fmt.println("Loading model from glTF file", filepath)
	file_data, err := os.read_entire_file_from_filename_or_err(filepath)
	if err != nil {
		fmt.println("Error loading model:", err)
		return false
	}
	data, result := cgltf.parse_file(options, strings.clone_to_cstring(filepath))

	if result != .success {
		fmt.println("Error loading GLTF model: ", filepath)
		return false
	}

	fmt.println("glTF file loaded", data)

	for mesh, i in data.meshes {
		fmt.println("Mesh #", i, ":")
		for primitive, j in mesh.primitives {
			fmt.println("  Primitive #", j)
			fmt.println("    Indices:")
			fmt.println(primitive.indices)
			fmt.println(primitive.indices.buffer_view)
			for attribute, k in primitive.attributes {
				fmt.println("    Attribute ", attribute.name, attribute.type, ":")
				accessor := attribute.data
				fmt.println("      Accessor:")
				fmt.println(accessor)
				fmt.println("      Buffer view:")
				fmt.println(accessor.buffer_view)
				fmt.println("      Buffer:")
				fmt.println(accessor.buffer_view.buffer)
			}
		}
	}

	return true
}

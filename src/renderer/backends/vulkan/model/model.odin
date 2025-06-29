package renderer_vulkan_model

import d "../device"

import "core:fmt"
import "core:path/filepath"
import "core:strings"

ENGINE_DIR :: "./"

Model :: struct {
	meshes: []Mesh,
}

create_simple_model_from_wavefront_file :: proc(
	device: ^d.Device,
	file: string,
	model: ^Model,
) -> bool {
	builder: MeshBuilder
	p, ok := filepath.abs(strings.concatenate({ENGINE_DIR, file}))
	if !ok {
		fmt.eprintfln("Couldn't resolve model path", file)
		return false
	}
	fmt.println("Loading model from", p)
	if !load_mesh_wavefront(&builder, p) {
		return false
	}

	model^ = {}
	model.meshes = make([]Mesh, 1)
	create_mesh(device, builder, &model.meshes[0])

	return true
}

destroy_model :: proc(using model: ^Model) {
	for &mesh in meshes {
		destroy_mesh(&mesh)
	}

	free(&meshes)
}

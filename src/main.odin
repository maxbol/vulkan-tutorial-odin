package main

import vulkan_backend "renderer/backends/vulkan"
import b "renderer/backends/vulkan/buffer"
import ds "renderer/backends/vulkan/descriptors"
import d "renderer/backends/vulkan/device"
import r "renderer/backends/vulkan/renderer"
import s "renderer/backends/vulkan/swapchain"
import w "renderer/backends/vulkan/window"

import "core:fmt"
import "vendor:vulkan"

WIDTH :: 800
HEIGHT :: 600

run_game :: proc(
	device: ^d.Device,
	renderer: ^r.Renderer,
	global_pool: ^ds.DescriptorPool,
) -> bool {
	ubo_buffers := make([]b.Buffer, s.MAX_FRAMES_IN_FLIGHT)
	defer delete(ubo_buffers)

	for i in 0 ..< len(ubo_buffers) {
		b.create_buffer(
			device,
			size_of(vulkan_backend.GlobalUbo),
			1,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE},
			&ubo_buffers[i],
		)
	}

	bindings := make(map[u32]vulkan.DescriptorSetLayoutBinding)
	defer delete(bindings)

	ds.bind_descriptor_set_layout(
		&bindings,
		0,
		.UNIFORM_BUFFER,
		vulkan.ShaderStageFlags_ALL_GRAPHICS,
	)

	global_set_layout: ds.DescriptorSetLayout

	ok := ds.descriptor_set_layout_create(device, bindings, &global_set_layout)
	if !ok {
		fmt.println("Failed to create DescriptorSetLayout")
		return false
	}
	defer ds.descriptor_set_layout_destroy(&global_set_layout)

	global_descriptor_sets: [s.MAX_FRAMES_IN_FLIGHT]vulkan.DescriptorSet
	for i in 0 ..< s.MAX_FRAMES_IN_FLIGHT {
		buffer_info := b.descriptor_info(&ubo_buffers[i])
		dw: ds.DescriptorWriter
		ds.descriptor_writer_create(&global_set_layout, global_pool, &dw)
		ds.descriptor_writer_write_buffer(&dw, 0, &buffer_info)
		ds.descriptor_writer_end(&dw, &global_descriptor_sets[i])
	}

	simple_render_system: SimpleRenderSystem
	if !create_simple_render_system(
		device,
		r.get_swapchain_render_pass(renderer),
		global_set_layout.vk_descriptor_set_layout,
		&simple_render_system,
	) {
		return false
	}

	point_light_system: PointLightSystem
	if !create_point_light_system(
		device,
		r.get_swapchain_render_pass(renderer),
		global_set_layout.vk_descriptor_set_layout,
		&point_light_system,
	) {
		return false
	}


	return true
}

main :: proc() {
	err, window := w.create_window(WIDTH, HEIGHT, "Tutorial")
	if err != nil {
		fmt.println("Error creating GLFW window", err)
		return
	}
	defer w.destroy_window(&window)

	device: d.Device
	renderer: r.Renderer
	global_pool: ds.DescriptorPool

	d.create_device(&window, &device)
	defer d.destroy_device(&device)

	r.create_renderer(&window, &device, &renderer)
	defer r.destroy_renderer(&renderer)

	ds.descriptor_pool_create(
		&device,
		s.MAX_FRAMES_IN_FLIGHT,
		{},
		{{descriptorCount = s.MAX_FRAMES_IN_FLIGHT, type = .UNIFORM_BUFFER}},
		&global_pool,
	)
	defer ds.descriptor_pool_destroy(&global_pool)

	load_game_objects()

	if !run_game(&device, &renderer, &global_pool) {
		fmt.println("Exited with non-ok result")
	}

}

load_game_objects :: proc() {}

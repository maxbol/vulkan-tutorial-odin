package main

import b "renderer/backends/vulkan/buffer"
import c "renderer/backends/vulkan/camera"
import ds "renderer/backends/vulkan/descriptors"
import d "renderer/backends/vulkan/device"
import m "renderer/backends/vulkan/model"
import r "renderer/backends/vulkan/renderer"
import s "renderer/backends/vulkan/swapchain"
import w "renderer/backends/vulkan/window"
import um "unitmath"

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:time"
import "vendor:glfw"
import "vendor:vulkan"

WIDTH :: 800
HEIGHT :: 600

run_game :: proc(
	device: ^d.Device,
	window: ^w.Window,
	renderer: ^r.Renderer,
	global_pool: ^ds.DescriptorPool,
	game_objects: ^GameObjectMap,
) -> bool {
	ubo_buffers := make([]b.Buffer, s.MAX_FRAMES_IN_FLIGHT)
	defer delete(ubo_buffers)

	for i in 0 ..< len(ubo_buffers) {
		b.create_buffer(
			device,
			size_of(GlobalUbo),
			1,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE},
			&ubo_buffers[i],
		)

		b.map_buffer(&ubo_buffers[i])
	}
	defer {
		for &buffer, i in ubo_buffers {
			b.destroy_buffer(&buffer)
		}
	}

	bindings := make(map[u32]vulkan.DescriptorSetLayoutBinding)

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
	if !srs_create(
		device,
		r.get_swapchain_render_pass(renderer),
		global_set_layout.vk_descriptor_set_layout,
		&simple_render_system,
	) {
		return false
	}
	defer srs_destroy(&simple_render_system)

	point_light_system: PointLightSystem
	if !pls_create(
		device,
		r.get_swapchain_render_pass(renderer),
		global_set_layout.vk_descriptor_set_layout,
		&point_light_system,
	) {
		return false
	}
	defer pls_destroy(&point_light_system)

	camera: c.Camera

	viewer_object := create_game_object()
	viewer_object.transform.translation.z = -2.5

	current_time := time.tick_now()
	for !w.should_close(window) {
		using math

		glfw.PollEvents()

		new_time := time.tick_now()
		frame_time := f32(time.tick_diff(current_time, new_time)) / 1_000_000_000
		current_time = new_time

		mouse_lookaround(window, frame_time, &viewer_object)
		move_in_plane_xyz(window.handle, frame_time, &viewer_object)

		(&game_objects[0]).transform.translation.x += 0.1 * frame_time

		c.camera_set_view_xyz(
			&camera,
			viewer_object.transform.translation,
			viewer_object.transform.rotation,
		)

		aspect := r.get_aspect_ratio(renderer)
		c.camera_set_perspective_projection(&camera, to_radians_f32(50), aspect, 0.1, 100)

		ok, command_buffer := r.begin_frame(renderer)
		if !ok {
			fmt.eprintfln("Begin frame failed")
			return false
		}

		if command_buffer == nil {
			continue
		}

		frame_index := r.get_frame_index(renderer)

		frame_info := FrameInfo {
			frame_index,
			frame_time,
			command_buffer,
			&camera,
			global_descriptor_sets[frame_index],
			game_objects,
		}

		ubo := global_ubo(camera.projection_matrix, camera.view_matrix, camera.inverse_view_matrix)

		pls_update(&frame_info, &ubo)

		b.write_to_buffer(&ubo_buffers[frame_index], &ubo)
		b.flush(&ubo_buffers[frame_index])

		r.begin_swapchain_render_pass(renderer, command_buffer)

		srs_render_game_objects(&simple_render_system, &frame_info)
		pls_render(&point_light_system, &frame_info)

		r.end_swapchain_render_pass(renderer, command_buffer)
		r.end_frame(renderer)
	}

	vulkan.DeviceWaitIdle(device.vk_device)

	return true
}

main :: proc() {
	err, window := w.create_window(WIDTH, HEIGHT, "Tutorial")
	if err != nil {
		fmt.println("Error creating GLFW window", err)
		return
	}
	defer w.destroy_window(window)

	device: d.Device
	renderer: r.Renderer
	instance: vulkan.Instance
	global_pool: ds.DescriptorPool

	if !glfw.VulkanSupported() {
		fmt.eprintln("Vulkan not supported by GLFW")
		return
	}

	vulkan.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	d.create_instance(&instance)
	vulkan.load_proc_addresses(instance)

	d.create_device(window, &instance, &device)
	defer d.destroy_device(&device)

	vulkan.load_proc_addresses_device(device.vk_device)

	r.create_renderer(window, &device, &renderer)
	defer r.destroy_renderer(&renderer)

	ds.descriptor_pool_create(
		&device,
		s.MAX_FRAMES_IN_FLIGHT,
		{},
		{{descriptorCount = s.MAX_FRAMES_IN_FLIGHT, type = .UNIFORM_BUFFER}},
		&global_pool,
	)
	defer ds.descriptor_pool_destroy(&global_pool)

	ok, game_objects := load_game_objects(&device)
	if !ok {
		fmt.eprintln("Error loading game objects, crashing out")
		return
	}
	defer unload_game_objects(game_objects)

	if !run_game(&device, window, &renderer, &global_pool, &game_objects) {
		fmt.println("Exited with non-ok result")
	}
}

unload_game_objects :: proc(game_objects: GameObjectMap) {
	for id, &obj in game_objects {
		if obj.model.present {
			m.destroy_model(&obj.model.value)
		}
	}
}

load_game_objects :: proc(device: ^d.Device) -> (bool, GameObjectMap) {
	using um

	game_objects := make(GameObjectMap)

	model: m.Model


	if !m.create_model_from_file(device, "models/flat_vase.obj", &model) {
		return false, nil
	}
	flat_vase := create_game_object()
	flat_vase.model = {
		value   = model,
		present = true,
	}
	flat_vase.transform.translation = {.5, .5, 0}
	flat_vase.transform.scale = {3, 1.5, 3}
	game_objects[flat_vase.id] = flat_vase

	if !m.create_model_from_file(device, "models/smooth_vase.obj", &model) {
		return false, nil
	}
	smooth_vase := create_game_object()
	smooth_vase.model = {
		value   = model,
		present = true,
	}
	smooth_vase.transform.translation = {-.5, .5, 0}
	smooth_vase.transform.scale = {3, 1.5, 3}
	game_objects[smooth_vase.id] = smooth_vase

	if !m.create_model_from_file(device, "models/quad.obj", &model) {
		return false, nil
	}
	floor := create_game_object()
	floor.model = {
		value   = model,
		present = true,
	}
	floor.transform.translation = {0, .5, 0}
	floor.transform.scale = {3, 1, 3}
	game_objects[floor.id] = floor

	light_colors := []Vec3 {
		{1., .1, .1},
		{.1, .1, 1.},
		{.1, 1., .1},
		{1., 1., .1},
		{.1, 1., 1.},
		{1., 1., 1.},
	}

	for light_color, i in light_colors {
		point_light := make_point_light(0.2)
		point_light.color = light_colors[i]
		rotate_light :=
			um.Mat4(1) *
			linalg.matrix4_rotate_f32((f32(i) * math.TAU) / f32(len(light_colors)), {0, -1, 0})
		point_light.transform.translation = (rotate_light * Vec4{-1, -1, -1, 1}).xyz
		game_objects[point_light.id] = point_light
	}

	return true, game_objects
}

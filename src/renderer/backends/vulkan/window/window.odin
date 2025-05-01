package renderer_vulkan_window

import "base:runtime"
import "core:fmt"
import "core:strings"
import glfw "vendor:glfw"
import "vendor:vulkan"

Window :: struct {
	width:               i32,
	height:              i32,
	framebuffer_resized: bool,
	window_name:         string,
	handle:              glfw.WindowHandle,
}

CreateWindowError :: enum {
	None,
	GLFWInitFailed,
	GLFWCreateWindowFailed,
}

CreateWindowSurfaceError :: enum {
	None,
	GLFWCreateWindowSurfaceFailed,
}

create_window :: proc(w: i32, h: i32, name: string) -> (CreateWindowError, Window) {
	ok := glfw.Init()
	if !ok {
		fmt.println("Error initializing GLFW")
		return .GLFWInitFailed, Window{}
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, true)

	handle := glfw.CreateWindow(w, h, strings.clone_to_cstring(name), nil, nil)

	if handle == nil {
		return .GLFWCreateWindowFailed, Window{}
	}


	window := Window {
		height      = h,
		width       = w,
		window_name = name,
		handle      = handle,
	}

	glfw.SetWindowUserPointer(handle, &window)
	glfw.SetFramebufferSizeCallback(handle, framebuffer_resize_callback)

	return .None, window
}

create_window_surface :: proc(
	using window: ^Window,
	instance: vulkan.Instance,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> (
	CreateWindowSurfaceError,
	vulkan.SurfaceKHR,
) {
	surface: vulkan.SurfaceKHR
	result := glfw.CreateWindowSurface(instance, handle, vk_allocator, &surface)

	if result != .SUCCESS {
		return .GLFWCreateWindowSurfaceFailed, vulkan.SurfaceKHR{}
	}

	return .None, surface
}

destroy_window :: proc(using window: ^Window) {
	glfw.DestroyWindow(handle)
	glfw.Terminate()
}

@(private)
framebuffer_resize_callback :: proc "c" (handle: glfw.WindowHandle, width: i32, height: i32) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	window.framebuffer_resized = true
	window.width = width
	window.height = height
}

get_extent :: proc(using window: ^Window) -> vulkan.Extent2D {
	return {u32(width), u32(height)}
}

get_glfw_window :: proc(using window: ^Window) -> glfw.WindowHandle {
	return handle
}

reset_window_resize_flag :: proc(using window: ^Window) {
	framebuffer_resized = false
}

should_close :: proc(using window: ^Window) -> bool {
	return cast(bool)glfw.WindowShouldClose(handle)
}

was_window_resized :: proc(using window: ^Window) -> bool {
	return framebuffer_resized
}

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
	window: ^Window,
	instance: vulkan.Instance,
	vk_allocator: ^vulkan.AllocationCallbacks = nil,
) -> (
	CreateWindowSurfaceError,
	vulkan.SurfaceKHR,
) {
	surface: vulkan.SurfaceKHR
	result := glfw.CreateWindowSurface(instance, window.handle, vk_allocator, &surface)

	if result != .SUCCESS {
		return .GLFWCreateWindowSurfaceFailed, vulkan.SurfaceKHR{}
	}

	return .None, surface
}

destroy_window :: proc(window: ^Window) {
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

@(private)
framebuffer_resize_callback :: proc "c" (handle: glfw.WindowHandle, width: i32, height: i32) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(handle)
	window.width = width
	window.height = height
}
get_extent :: proc(window: ^Window) -> vulkan.Extent2D {
	return {u32(window.width), u32(window.height)}
}

get_glfw_window :: proc(window: ^Window) -> glfw.WindowHandle {
	return window.handle
}

reset_window_resize_flag :: proc(window: ^Window) {
	window.framebuffer_resized = false
}

should_close :: proc(window: ^Window) -> bool {
	return cast(bool)glfw.WindowShouldClose(window.handle)
}

was_window_resized :: proc(window: ^Window) -> bool {
	return window.framebuffer_resized
}

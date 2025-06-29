package gui

import imgui "../../odin-imgui/"
import imglfw "../../odin-imgui/impl/glfw"
import imvk "../../odin-imgui/impl/vulkan/"
import gs "../game_state/"
import d "../renderer/backends/vulkan/device/"
import r "../renderer/backends/vulkan/renderer/"
import s "../renderer/backends/vulkan/swapchain/"
import w "../renderer/backends/vulkan/window/"
import "base:runtime"
import "core:fmt"
import "core:strings"
import "vendor:vulkan"

GuiState :: struct {
	vk_state:   imvk.Vulkan_State,
	font_atlas: imgui.Font_Atlas,
}

init :: proc(using gui: ^GuiState, renderer: ^r.Renderer) {
	vk_state = {}
	font_atlas = {}

	fmt.println("-> 1")
	queue_families := d.find_physical_queue_families(renderer.device)
	fmt.println("-> 2", queue_families)
	ctx := imgui.create_context(&font_atlas)
	imgui.set_current_context(ctx)
	io := imgui.get_io()
	fmt.println("io", io)
	fmt.println("-> 3")
	imglfw.setup_state(renderer.window.handle, true)
	fmt.println("-> 4")
	imvk.setup_state(
		&vk_state,
		{
			device = renderer.device.vk_device,
			physical_device = renderer.device.physical_device,
			queue = renderer.device.graphics_queue,
			queue_family = queue_families.graphics_family.value,
			compatible_renderpass = renderer.swapchain.render_pass,
			max_frames_in_flight = s.MAX_FRAMES_IN_FLIGHT,
			use_srgb = true,
		},
	)
	fmt.println("-> 5")

}

destroy :: proc(using gui: ^GuiState) {
	imvk.cleanup_state(&vk_state)
}

begin_frame :: proc(gui: ^GuiState) {
	imglfw.update_display_size()
	imglfw.update_mouse()
	imglfw.update_dt()

	imgui.new_frame()
}

draw :: proc(gui: ^GuiState) {
	info_overlay()
	text_test_window()
	input_text_test_window()
	misc_test_window()
	combo_test_window()
}

end_frame :: proc(gui: ^GuiState, frame_info: ^gs.FrameInfo) {
	imgui.render()
	imvk.imgui_render(
		frame_info.command_buffer,
		imgui.get_draw_data(),
		&gui.vk_state,
		frame_info.frame_index,
	)
}

info_overlay :: proc() {
	imgui.set_next_window_pos(imgui.Vec2{10, 10})
	imgui.set_next_window_bg_alpha(0.2)
	overlay_flags: imgui.Window_Flags =
		.NoDecoration |
		.AlwaysAutoResize |
		.NoSavedSettings |
		.NoFocusOnAppearing |
		.NoNav |
		.NoMove
	imgui.begin("Info", nil, overlay_flags)
	imgui.text_unformatted("Press Esc to close the application")
	imgui.text_unformatted("Press Tab to show demo window")
	imgui.end()
}

text_test_window :: proc() {
	imgui.begin("Text test")
	imgui.text("NORMAL TEXT: {}", 1)
	imgui.text_colored(imgui.Vec4{1, 0, 0, 1}, "COLORED TEXT: {}", 2)
	imgui.text_disabled("DISABLED TEXT: {}", 3)
	imgui.text_unformatted("UNFORMATTED TEXT")
	imgui.text_wrapped("WRAPPED TEXT: {}", 4)
	imgui.end()
}

input_text_test_window :: proc() {
	imgui.begin("Input text test")
	@(static) buf: [256]u8
	@(static) ok := false
	imgui.input_text("Test input", buf[:])
	imgui.input_text("Test password input", buf[:], .Password)
	if imgui.input_text("Test returns true input", buf[:], .EnterReturnsTrue) {
		ok = !ok
	}
	imgui.checkbox("OK?", &ok)
	imgui.text_wrapped("Buf content: %s", string(buf[:]))
	imgui.end()
}

misc_test_window :: proc() {
	imgui.begin("Misc tests")
	pos := imgui.get_window_pos()
	size := imgui.get_window_size()
	imgui.text("pos: {}", pos)
	imgui.text("size: {}", size)
	imgui.end()
}

combo_test_window :: proc() {
	imgui.begin("Combo tests")
	@(static) items := []string{"1", "2", "3"}
	@(static) curr_1 := i32(0)
	@(static) curr_2 := i32(1)
	@(static) curr_3 := i32(2)
	if imgui.begin_combo("begin combo", items[curr_1]) {
		for item, idx in items {
			is_selected := idx == int(curr_1)
			if imgui.selectable(item, is_selected) {
				curr_1 = i32(idx)
			}

			if is_selected {
				imgui.set_item_default_focus()
			}
		}
		defer imgui.end_combo()
	}

	imgui.combo_str_arr("combo str arr", &curr_2, items)

	item_getter: imgui.Items_Getter_Proc : proc "c" (
		data: rawptr,
		idx: i32,
		out_text: ^cstring,
	) -> bool {
		context = runtime.default_context()
		items := (cast(^[]string)data)
		out_text^ = strings.clone_to_cstring(items[idx], context.temp_allocator)
		return true
	}

	imgui.combo_fn_bool_ptr("combo fn ptr", &curr_3, item_getter, &items, i32(len(items)))

	imgui.end()
}

package windows

import "../common"
import "../render/vk"
import "core:log"
import "core:math"
import "vendor:sdl3"

main :: proc() {
	context.logger = log.create_console_logger()
	log.info("Start of Windows Chaos ")
	state: VulkanPlatformApp

	if !init_windows(&state) do return
	defer finish_windows(&state)

	for state.running {
		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			game.GameUpdateAndRender()
			if (event.type == sdl3.EventType.QUIT) {
				log.debug("checkEvents QUIT")
				state.running = false
			}
			if (event.type == sdl3.EventType.WINDOW_RESIZED) {
				log.debug("checkEvents WINDOW_RESIZED")
				state.rend.w = event.window.data1
				state.rend.h = event.window.data2
			}
		}

		if !vk.draw_frame(&state.rend, vertices[:], indices[:]) do return
	}

	log.info("End of Windows Chaos ")
}


//windows using sdl vulkan 
init_windows :: proc(state: ^VulkanPlatformApp) -> bool {
	using state


	if !sdl3.SetAppMetadata(APP_NAME, APP_VERSION, APP_VERSION) {
		log.error("Init AppState SDL SetMetadata failed:", sdl3.GetError())
		return false
	}

	if !sdl3.Init(sdl3.INIT_VIDEO) {
		log.error("Init AppState SDL Init failed:", sdl3.GetError())
		return false
	}

	flags := sdl3.WindowFlags{sdl3.WindowFlag.RESIZABLE, sdl3.WindowFlag.VULKAN}

	rend.window = sdl3.CreateWindow(title, rend.w, rend.h, flags)

	if rend.window == nil {
		log.error("Init AppState SDL CreateWindow failed:", sdl3.GetError())
		return false
	}

	vk.init_vulkan(&rend, vertices[:], indices[:]) or_return
	return true
}

//cleanup render and vulkan
finish_windows :: proc(state: ^VulkanPlatformApp) {
	vk.clean_vulkan(&state.rend)
	sdl3.DestroyWindow(state.rend.window)
	sdl3.Quit() // Ensure sdl3 is quit when the program exits 
	log.debug("cleanup SUCCESFULL")
}


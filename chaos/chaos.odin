package chaos

import "core:fmt"
import "core:math"
import "vendor:sdl3"
import "vendor:vulkan"



AppState :: struct {
  title:   cstring,
	w:       i32,
	h:       i32,
	window:  ^sdl3.Window,
	render:  ^sdl3.Renderer,
	running: bool,
}


init :: proc(state: ^AppState) -> bool {
	if !sdl3.SetAppMetadata("SDL APP", "1.0", "com.raz.chaos") {
		fmt.println("SDL Metadata failed:", sdl3.GetError())
		return false
	}

	if !sdl3.Init(sdl3.INIT_VIDEO) {
		fmt.println("SDL initialization failed:", sdl3.GetError())
		return false
	}

	flags := sdl3.WindowFlags{
    sdl3.WindowFlag.RESIZABLE,
    sdl3.WindowFlag.VULKAN
  }

	window := sdl3.CreateWindow(state.title, state.w, state.h, flags)
	if window == nil {
		fmt.println("Window creation failed:", sdl3.GetError())
		return false
	}
  
  vulkan.CreateInstance();

	state.running = true
	fmt.println("\n# INIT SUCCESFULL")
	return true
}

cleanup :: proc(state: ^AppState) {
	sdl3.DestroyRenderer(state.render)
	sdl3.DestroyWindow(state.window) // Destroy window when finished
	sdl3.Quit() // Ensure sdl3 is quit when the program exits 
}

checkEvents :: proc(state: ^AppState) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		if (event.type == sdl3.EventType.QUIT) {
			fmt.println("Quir Event")
			state.running = false
		}
	}
}

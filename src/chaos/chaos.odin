package chaos


import "core:fmt"
import "core:math"
import "vendor:sdl3"
import "vendor:vulkan"
import "core:log"
import "gpu"

AppState :: struct {
	title:   cstring,
	rend:    ^gpu.Context,
	running: bool,
}


APP_NAME: cstring = "SDL APP"
APP_VERSION: cstring = "1.0"
APP_IDENTIFIER: cstring = "com.chaos.dev"

vertices := [?]gpu.Vertex {
	{{-0.5, -0.5, -0.5}, {0.0, 0.0, 1.0}, {0.5, 0}},
	{{0.5, 0, -0.5}, {1.0, 0.0, 0.0}, {0, 0}},
	{{0.5, 0, 0.5}, {0.0, 1.0, 0.0}, {0, 0}},
	{{-0.5, 0, 0.5}, {1.0, 0.0, 0.0}, {0, 0}},
}

indices := [?]u16{0, 1, 2, 2, 3, 0}


default_render :: proc(w: i32, h: i32) -> (render: ^gpu.Context) {
	render.h = h
	render.w = w
	return render
}


init :: proc(using state: ^AppState) -> (ok: bool) {
	log.debug("Init AppState START")
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

	gpu.init_vulkan(rend, vertices[:], indices[:]) or_return

	running = true
	log.debug("Init AppState  SUCCESFULL")
	return true
}

cleanup :: proc(state: ^AppState) {
	log.debug("cleanup START")
	gpu.clean_vulkan(state.rend)
	sdl3.DestroyWindow(state.rend.window)
	sdl3.Quit() // Ensure sdl3 is quit when the program exits 
	log.debug("cleanup SUCCESFULL")
}

checkEvents :: proc(state: ^AppState) {
  log.debug("checkEvents START")
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
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

  log.debug("checkEvents SUCCESFULL")
}

iterate :: proc(state: ^AppState) -> bool {
  log.debug("iterate START")
	gpu.draw_frame(state.rend, vertices[:], indices[:]) or_return
	checkEvents(state)
  log.debug("iterate SUCCESFULL")
	return true
}

package main

import "core:fmt"
import "core:math"
import "vendor:sdl3"

AppState :: struct {
	w:       int,
	h:       int,
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

	flags := sdl3.WindowFlags{sdl3.WindowFlag.RESIZABLE}

	w_r := sdl3.CreateWindowAndRenderer("Chaos", 640, 480, flags, &state.window, &state.render)
	if !w_r {
		fmt.println("Window and Render creation failed:", sdl3.GetError())
		return false
	}

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

iterate :: proc(state: ^AppState) {
	now: f64 = f64(sdl3.GetTicks()) / 1000.0 /* convert from milliseconds to seconds. */
	/* choose the color for the frame we will draw. The sine wave trick makes it fade between colors smoothly. */
	red: f32 = (0.5 + 0.5 * f32(sdl3.sin(now)))
	green: f32 = (0.5 + 0.5 * f32(sdl3.sin(now + math.PI * 2 / 3)))
	blue: f32 = (0.5 + 0.5 * f32(sdl3.sin(now + math.PI * 4 / 3)))
	sdl3.SetRenderDrawColorFloat(state.render, red, green, blue, 1.0)
	sdl3.RenderClear(state.render)
	sdl3.RenderPresent(state.render)
}


main :: proc() {
	state := AppState{}
	state.w = 640
	state.h = 480
	if (!init(&state)) {
		return
	}
	defer cleanup(&state)

	// Iterate and create events
	for state.running {
		checkEvents(&state)
		iterate(&state)
	}

	fmt.println("END of Chaos App")
}

package main

import "core:fmt"
import "core:math"
import "vendor:sdl3"
import "chaos"

main :: proc() {
  using state := chaos.AppState{}
	title = "Chaos"
	gpu.w = 640
	gpu.h = 480

	if (!chaos.init(&state)) {return}
	defer chaos.cleanup(&state)

	// Iterate and create events
	for state.running {
		chaos.checkEvents(&state)
		iterate(&state)
	}

	fmt.println("END of Chaos App")
}

iterate :: proc(state: ^chaos.AppState) {
	now: f64 = f64(sdl3.GetTicks()) / 1000.0 /* convert from milliseconds to seconds. */
	/* choose the color for the frame we will draw. The sine wave trick makes it fade between colors smoothly. */
	red: f32 = (0.5 + 0.5 * f32(sdl3.sin(now)))
	green: f32 = (0.5 + 0.5 * f32(sdl3.sin(now + math.PI * 2 / 3)))
	blue: f32 = (0.5 + 0.5 * f32(sdl3.sin(now + math.PI * 4 / 3)))
	
}



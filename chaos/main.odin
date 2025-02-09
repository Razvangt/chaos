package chaos

import "core:fmt"
import "core:math"
import "vendor:sdl3"

main :: proc() {
	state := AppState{}
	state.title = "Chaos"
	state.w = 640
	state.h = 480

	if (!init(&state)) {return}
	defer cleanup(&state)

	// Iterate and create events
	for state.running {
		checkEvents(&state)
		iterate(&state)
	}

	fmt.println("END of Chaos App")
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



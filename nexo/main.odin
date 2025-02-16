package main

import "core:fmt"
import "core:math"
import "vendor:sdl3"
import "chaos"


main :: proc() {
	fmt.println("Start of Chaos App")
  using state := chaos.AppState{}
	title = "Chaos" 
  render := chaos.default_render(640,480);
  rend = &render

	if (!chaos.init(&state)) do return
	defer chaos.cleanup(&state)

	// Iterate and create events
	for state.running {
		chaos.checkEvents(&state)
		iterate(&state)
	}

	fmt.println("END of Chaos App")
}

iterate :: proc(state: ^chaos.AppState) {
  // ?
}



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



	if (!chaos.init(&state)) {
    fmt.eprintf("App faild to initialize")
    return
  }
	defer chaos.cleanup(&state)
  
	for state.running {
      if !chaos.iterate(&state) {return}
      game_loop(&state)
  }
	fmt.println("END of Chaos App")
}

game_loop:: proc(state: ^chaos.AppState) {
  // ?
  
}



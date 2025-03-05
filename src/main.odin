package main

import "chaos"
import "core:fmt"
import "core:math"
import "vendor:sdl3"
import "core:log"

main :: proc() {
  context.logger = log.create_console_logger()
  log.info("Start of Chaos App")

  state := chaos.AppState{
	  title = "Chaos",
	  rend = chaos.default_render(640, 480)
  }


	if (!chaos.init(&state)) {
		log.error("App faild to initialize")
		return
	}
	defer chaos.cleanup(&state)

	for state.running {
		if !chaos.iterate(&state) do return
		game_loop(&state)
	}
  log.info("End of Chaos App")
}

game_loop :: proc(state: ^chaos.AppState) {
	// ?

}

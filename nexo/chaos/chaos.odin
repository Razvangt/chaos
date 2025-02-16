package chaos


import "core:fmt"
import "core:math"
import "vendor:sdl3"
import "vendor:vulkan"

import "gpu"

AppState :: struct {
  title:   cstring,
  rend: ^gpu.Context,
	running: bool,
}


APP_NAME       :cstring = "SDL APP";
APP_VERSION    :cstring = "1.0";
APP_IDENTIFIER :cstring = "com.chaos.dev";

vertices := [?]gpu.Vertex{
		{{-0.5, -0.5}, {0.0, 0.0, 1.0}},
		{{ 0.5, -0.5}, {1.0, 0.0, 0.0}},
		{{ 0.5,  0.5}, {0.0, 1.0, 0.0}},
		{{-0.5,  0.5}, {1.0, 0.0, 0.0}},
	};

indices := [?]u16{
		0, 1, 2,
		2, 3, 0,
	};


default_render::proc(w: i32,h : i32) -> (render : gpu.Context){
  render.h = w
  render.w = w
  return render
}


init :: proc(using state: ^AppState) -> (ok:bool) {
	fmt.println("Start Init SDL");
	if !sdl3.SetAppMetadata(APP_NAME, APP_VERSION, APP_VERSION) {
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

	rend.window = sdl3.CreateWindow(title, rend.w, rend.h, flags)
	if rend.window == nil {
		fmt.println("Window creation failed:", sdl3.GetError())
		return false;
	}
  

  gpu.init_vulkan(rend,vertices[:],indices[:]);

	running = true;
	fmt.println("\n# INIT SUCCESFULL");
	return true;
}

cleanup :: proc(state: ^AppState) {
  gpu.clean_vulkan(state.rend);
  sdl3.DestroyWindow(state.rend.window);
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

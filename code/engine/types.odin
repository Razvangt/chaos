package engine

// should handle common utilities between diferent platforms that can interface with the game

GAME_TITLE: cstring = "Chaos engine game"
init_width: i32 = 500
init_heigth: i32 = 500


PlatformApp :: struct {
	title:  cstring,
	width:  i32,
	height: i32,
}

vertices := [?]vk.Vertex {
	{{-0.5, -0.5, -0.5}, {0.0, 0.0, 1.0}, {0.5, 0}},
	{{0.5, 0, -0.5}, {1.0, 0.0, 0.0}, {0, 0}},
	{{0.5, 0, 0.5}, {0.0, 1.0, 0.0}, {0, 0}},
	{{-0.5, 0, 0.5}, {1.0, 0.0, 0.0}, {0, 0}},
}

indices := [?]u16{0, 1, 2, 2, 3, 0}

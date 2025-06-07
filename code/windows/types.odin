package windows
import "../render/vk"


APP_NAME :: "SDL APP"
APP_VERSION :: "1.0"
APP_IDENTIFIER :: "com.chaos.dev"


vertices := [?]vk.Vertex {
	{{-0.5, -0.5, -0.5}, {0.0, 0.0, 1.0}, {0.5, 0}},
	{{0.5, 0, -0.5}, {1.0, 0.0, 0.0}, {0, 0}},
	{{0.5, 0, 0.5}, {0.0, 1.0, 0.0}, {0, 0}},
	{{-0.5, 0, 0.5}, {1.0, 0.0, 0.0}, {0, 0}},
}

indices := [?]u16{0, 1, 2, 2, 3, 0}


VulkanPlatformApp :: struct {
	rend: vk.Context,
}



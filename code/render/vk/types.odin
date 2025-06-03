package vk


import "core:fmt"
import "vendor:sdl3"
import vk "vendor:vulkan"


MAX_FRAMES_IN_FLIGHT :: 2

Context :: struct {
	instance:            vk.Instance,
	device:              vk.Device,
	physical_device:     vk.PhysicalDevice,
	swap_chain:          Swapchain,
	pipeline:            Pipeline,
	queue_indices:       [QueueFamily]int,
	queues:              [QueueFamily]vk.Queue,
	surface:             vk.SurfaceKHR,
	command_pool:        vk.CommandPool,
	command_buffers:     [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	vertex_buffer:       Buffer,
	index_buffer:        Buffer,
	image_available:     [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished:     [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight:           [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	curr_frame:          u32,
	framebuffer_resized: bool,
	window:              ^sdl3.Window,

	// Added 
	w:                   i32,
	h:                   i32,
  texture_sampler:     vk.Sampler,
	mssa_samples:        vk.SampleCountFlags,
  mip_leveles :        u32,
	color_resource:      ImageResource,
	depth_resource:      ImageResource,
  texture_resource:    ImageResource,
}

Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	length: int,
	size:   vk.DeviceSize,
}

Pipeline :: struct {
	handle:                vk.Pipeline,
	render_pass:           vk.RenderPass,
	layout:                vk.PipelineLayout,
	descriptor_set_layout: vk.DescriptorSetLayout,
}

QueueFamily :: enum {
	Graphics,
	Present,
}

Swapchain :: struct {
	handle:       vk.SwapchainKHR,
	images:       []vk.Image,
	image_views:  []vk.ImageView,
	format:       vk.SurfaceFormatKHR,
	extent:       vk.Extent2D,
	present_mode: vk.PresentModeKHR,
	image_count:  u32,
	support:      SwapChainDetails,
	framebuffers: []vk.Framebuffer,
}

ImageResource :: struct {
	image:  vk.Image,
	memory: vk.DeviceMemory,
	view:   vk.ImageView,
}


SwapChainDetails :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

Vertex :: struct {
	pos:      [3]f32,
	color:    [3]f32,
	texCoord: [2]f32,
}


DEVICE_EXTENSIONS := [?]cstring{"VK_KHR_swapchain"}

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

VERTEX_BINDING := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}


VERTEX_ATTRIBUTES := [?]vk.VertexInputAttributeDescription {
	{binding = 0, location = 0, format = .R32G32_SFLOAT, offset = cast(u32)offset_of(Vertex, pos)},
	{binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = cast(u32)offset_of(Vertex, color)},
	{binding = 0, location = 2, format = .R32G32B32_SFLOAT, offset = cast(u32)offset_of(Vertex, texCoord)},
}

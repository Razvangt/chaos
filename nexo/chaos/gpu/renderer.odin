package gpu

import "vendor:sdl3"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 2

Context :: struct
{
	instance: vk.Instance,
  device:   vk.Device,
	physical_device: vk.PhysicalDevice,
	swap_chain: Swapchain,
	pipeline: Pipeline,
	queue_indices:   [QueueFamily]int,
	queues:   [QueueFamily]vk.Queue,
	surface:  vk.SurfaceKHR,
  
	command_pool: vk.CommandPool,
	command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	vertex_buffer: Buffer,
	index_buffer: Buffer,
	
	image_available: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight: [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	
	curr_frame: u32,
	framebuffer_resized: bool,
  
  window: ^sdl3.Window,
  w : i32,
  h : i32,

  
}

Buffer :: struct
{
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	length: int,
	size:   vk.DeviceSize,
}

Pipeline :: struct
{
	handle: vk.Pipeline,
	render_pass: vk.RenderPass,
	layout: vk.PipelineLayout,
}

QueueFamily :: enum
{
	Graphics,
	Present,
}

Swapchain :: struct
{
	handle: vk.SwapchainKHR,
	images: []vk.Image,
	image_views: []vk.ImageView,
	format: vk.SurfaceFormatKHR,
	extent: vk.Extent2D,
	present_mode: vk.PresentModeKHR,
	image_count: u32,
	support: SwapChainDetails,
	framebuffers: []vk.Framebuffer,
}

SwapChainDetails :: struct
{
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats: []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

Vertex :: struct
{
	pos: [2]f32,
	color: [3]f32,
}

DEVICE_EXTENSIONS := [?]cstring{
	"VK_KHR_swapchain",
};
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"};

init_vulkan:: proc(using ctx: ^Context, vertices: []Vertex, indices: []u16){
  context.user_ptr = &instance;
  create_instance(ctx);
}



create_instance :: proc(using ctx: ^Context) -> bool {
	appInfo : vk.ApplicationInfo;
	appInfo.sType = vk.StructureType.APPLICATION_INFO
	appInfo.pApplicationName = "ChaosRenderer"
	appInfo.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.pEngineName = "ChaosEngine"
	appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.apiVersion = vk.API_VERSION_1_3

	createinfo := vk.InstanceCreateInfo{}
	createinfo.sType = vk.StructureType.INSTANCE_CREATE_INFO
	createinfo.pApplicationInfo = &appInfo


	count: u32
	extensions := sdl3.Vulkan_GetInstanceExtensions(&count)
	createinfo.ppEnabledExtensionNames = extensions
	createinfo.enabledExtensionCount = count

	when ODIN_DEBUG {
		layer_count: u32
		vk.EnumerateInstanceLayerProperties(&layer_count, nil)
		layers := make([]vk.LayerProperties, layer_count)
		vk.EnumerateInstanceLayerProperties(&layer_count, &layers)

		outer: for name in VALIDATION_LAYERS {
			for layer in &layers {
				if name == cstring(&layer.layerName[0]) do continue outer
			}
			fmt.eprintf("ERROR: validation layer %q no available\n", name)
			return false
		}
	} else {
		validationLayers :: 0
	}
  
  return true;
}



package vk

import "../../utils"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "shared:shaderc"
import "vendor:sdl3"
import vk "vendor:vulkan"

init_vulkan :: proc(ctx: ^Context, vertices: []Vertex, indices: []u16) -> (ok: bool) {
	log.debug("vulkan init_vulkan START")

	// this is for the vtable bindings 
	getInstanceProcAddr := sdl3.Vulkan_GetVkGetInstanceProcAddr()

	if getInstanceProcAddr == nil {
		log.panicf("init_vulkan getInstanceProcAddr nil")
	}


	vk.load_proc_addresses_global(rawptr(getInstanceProcAddr))
	create_instance(ctx) or_return
	vk.load_proc_addresses_instance(ctx.instance)


	extensions := get_extensions()
	log.debug("--------------------------")
	log.debug("extensions")
	for ext in &extensions do log.debug(byte_to_cstring(ext.extensionName))
	log.debug("--------------------------")


	create_surface(ctx) or_return
	get_suitable_device(ctx) or_return
	get_mssa_samples(ctx) // maybe i should put it inside the get sutaible device Whatever 
	find_queue_families(ctx)

	log.debug("--------------------------")
	log.debug("Queue Indices:")
	for q, f in ctx.queue_indices do log.debug("  %v: %d\n", f, q)
	log.debug("--------------------------")

	create_device(ctx)
	vk.load_proc_addresses_device(ctx.device)
	for &q, f in ctx.queues {
		vk.GetDeviceQueue(ctx.device, u32(ctx.queue_indices[f]), 0, &q)
	}

	create_swap_chain(ctx) or_return
	create_image_views(ctx) or_return

	create_graphics_pipeline(ctx, "shader.vert", "shader.frag") or_return


	create_command_pool(ctx) or_return
	create_color_resources(ctx) or_return
	create_depth_resources(ctx) or_return
	create_framebuffers(ctx) or_return


	//texture resources 
	// TODO: add texture path
	img := utils.load_texture_from_file("res/textures/viking_room.png") or_return
	create_texture_image(ctx, &img) or_return
	// no need of image after texture creation on vulkan  buffers 
	utils.free_image(&img)
	create_texture_imageview(ctx)
	create_texture_sampler(ctx)
	// texture sampler 

	// load model ??? 
	load_model(ctx, " models/")

	create_vertex_buffer(ctx, vertices) or_return
	create_index_buffer(ctx, indices) or_return

	// uniform bffer
	// Descriptor pool 
	// Descriptor sets 

	create_command_buffers(ctx) or_return
	create_sync_objects(ctx) or_return


	log.debug("vulkan init_vulkan SUCCESSFULL")
	return true
}

clean_vulkan :: proc(using ctx: ^Context) {
	vk.DestroyDevice(device, nil)
	vk.DestroySurfaceKHR(instance, surface, nil)
	vk.DestroyInstance(instance, nil)
}

debug_callback :: proc "system" (
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_type: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = runtime.default_context()
	fmt.fprintf(os.stderr, "Validation Layer (%d, %d): ", message_severity, message_type)
	fmt.fprintf(os.stderr, "%s\n", callback_data.pMessage)

	return false
}


create_instance :: proc(using ctx: ^Context) -> (ok: bool) {
	log.debug("vulkan create_instance START")

	when ODIN_DEBUG {
		log.info("Validation layers enabled")
		if (!is_validation_layer_support_on()) {
			log.panic("validation layers requested but not available")
		}
	}

	appInfo := vk.ApplicationInfo {
		sType              = vk.StructureType.APPLICATION_INFO,
		pApplicationName   = "ChaosRenderer",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "ChaosEngine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_3,
	}

	createinfo := vk.InstanceCreateInfo {
		sType            = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo = &appInfo,
	}

	when ODIN_DEBUG {
		validation_layers := VALIDATION_LAYERS

		log.info("Enabling validation layers:")
		log.info(" Layer: ", validation_layers[0])

		createinfo.ppEnabledLayerNames = &validation_layers[0]
		createinfo.enabledLayerCount = len(validation_layers)

		debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .INFO, .ERROR, .WARNING},
			// TODO: do I want to enable the address binding messages?
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = debug_callback,
		}


		createinfo.pNext = &debug_create_info
	}

	count: u32
	extensions := sdl3.Vulkan_GetInstanceExtensions(&count)
	createinfo.ppEnabledExtensionNames = extensions
	createinfo.enabledExtensionCount = count


	if (vk.CreateInstance(&createinfo, nil, &instance) != vk.Result.SUCCESS) {
		log.error("vulkan creating_instance failed create_instance")
		return false
	}

	log.debug("vulkan creating_instance SUCCESSFULL")
	return true
}


create_surface :: proc(using ctx: ^Context) -> (ok: bool) {
	log.debug("vulkan create_surface START")
	if !sdl3.Vulkan_CreateSurface(window, instance, nil, &surface) {
		log.error("vulkan create_surface Failed to to create window surface")
		return false
	}
	log.debug("vulkan create_surface SUCCESSFULL")
	return true
}

query_swap_chain_details :: proc(using ctx: ^Context, dev: vk.PhysicalDevice) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &swap_chain.support.capabilities)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_count, nil)
	if format_count > 0 {
		swap_chain.support.formats = make([]vk.SurfaceFormatKHR, format_count)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_count, raw_data(swap_chain.support.formats))
	}

	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_count, nil)
	if present_mode_count > 0 {
		swap_chain.support.present_modes = make([]vk.PresentModeKHR, present_mode_count)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_count, raw_data(swap_chain.support.present_modes))
	}
}


check_device_extension_support :: proc(physical_device: vk.PhysicalDevice) -> bool {
	ext_count: u32
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &ext_count, nil)

	available_extensions := make([]vk.ExtensionProperties, ext_count)
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &ext_count, raw_data(available_extensions))

	for ext in DEVICE_EXTENSIONS {
		found: b32
		for available in &available_extensions {
			if byte_to_cstring(available.extensionName) == ext {
				found = true
				break
			}
		}
		if !found do return false
	}
	return true
}

find_queue_families :: proc(using ctx: ^Context) {
	queue_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_count, nil)
	available_queues := make([]vk.QueueFamilyProperties, queue_count)
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_count, raw_data(available_queues))

	for v, i in available_queues {
		if .GRAPHICS in v.queueFlags && queue_indices[.Graphics] == -1 do queue_indices[.Graphics] = i

		present_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(i), surface, &present_support)
		if present_support && queue_indices[.Present] == -1 do queue_indices[.Present] = i

		for q in queue_indices do if q == -1 do continue
		break
	}
}


create_device :: proc(using ctx: ^Context) -> (ok: bool) {
	log.debug("vulkan create_device START")
	unique_indices: map[int]b8
	defer delete(unique_indices)
	for i in queue_indices do unique_indices[i] = true

	queue_priority := f32(1.0)

	queue_create_infos: [dynamic]vk.DeviceQueueCreateInfo
	defer delete(queue_create_infos)
	for k, _ in unique_indices {
		queue_create_info: vk.DeviceQueueCreateInfo
		queue_create_info.sType = .DEVICE_QUEUE_CREATE_INFO
		queue_create_info.queueFamilyIndex = u32(queue_indices[.Graphics])
		queue_create_info.queueCount = 1
		queue_create_info.pQueuePriorities = &queue_priority
		append(&queue_create_infos, queue_create_info)
	}

	device_features: vk.PhysicalDeviceFeatures
	device_features.samplerAnisotropy = true
	device_features.sampleRateShading = true

	device_create_info: vk.DeviceCreateInfo
	device_create_info.sType = .DEVICE_CREATE_INFO
	device_create_info.enabledExtensionCount = u32(len(DEVICE_EXTENSIONS))
	device_create_info.ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0]
	device_create_info.pQueueCreateInfos = raw_data(queue_create_infos)
	device_create_info.queueCreateInfoCount = u32(len(queue_create_infos))
	device_create_info.pEnabledFeatures = &device_features
	// i can add here the validation layers to debug better 
	//
	//
	when ODIN_DEBUG {
		device_create_info.enabledLayerCount = len(VALIDATION_LAYERS)
		device_create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
	} else {
		device_create_info.enabledLayerCount = 0
	}

	if vk.CreateDevice(physical_device, &device_create_info, nil, &device) != .SUCCESS {
		log.error("vulkan create_device Failed to create logical device\n")
		return false
	}

	log.debug("vulkan create_device SUCCESSFULL")
	return true
}

create_swap_chain :: proc(using ctx: ^Context) -> (ok: bool) {
	log.debug("vulkan create_swap_chain START")

	using ctx.swap_chain.support
	swap_chain.format = choose_surface_format(ctx)
	swap_chain.present_mode = choose_present_mode(ctx)

	res, extent := choose_swap_extent(ctx)
	res or_return
	swap_chain.extent = extent
	swap_chain.image_count = capabilities.minImageCount + 1

	if capabilities.maxImageCount > 0 && swap_chain.image_count > capabilities.maxImageCount {
		swap_chain.image_count = capabilities.maxImageCount
	}

	create_info: vk.SwapchainCreateInfoKHR
	create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR
	create_info.surface = surface
	create_info.minImageCount = swap_chain.image_count
	create_info.imageFormat = swap_chain.format.format
	create_info.imageColorSpace = swap_chain.format.colorSpace
	create_info.imageExtent = swap_chain.extent
	create_info.imageArrayLayers = 1
	create_info.imageUsage = {.COLOR_ATTACHMENT}

	queue_family_indices := [len(QueueFamily)]u32{u32(queue_indices[.Graphics]), u32(queue_indices[.Present])}

	if queue_indices[.Graphics] != queue_indices[.Present] {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = &queue_family_indices[0]
	} else {
		create_info.imageSharingMode = .EXCLUSIVE
		create_info.queueFamilyIndexCount = 0
		create_info.pQueueFamilyIndices = nil
	}

	create_info.preTransform = capabilities.currentTransform
	create_info.compositeAlpha = {.OPAQUE}
	create_info.presentMode = swap_chain.present_mode
	create_info.clipped = true
	create_info.oldSwapchain = vk.SwapchainKHR{}

	if res := vk.CreateSwapchainKHR(device, &create_info, nil, &swap_chain.handle); res != .SUCCESS {
		log.debug("vulkan create_swap_chain failed to create swap chain")
		return false
	}

	vk.GetSwapchainImagesKHR(device, swap_chain.handle, &swap_chain.image_count, nil)
	swap_chain.images = make([]vk.Image, swap_chain.image_count)
	vk.GetSwapchainImagesKHR(device, swap_chain.handle, &swap_chain.image_count, raw_data(swap_chain.images))
	log.debug("vulkan create_swap_chain SUCCESSFULL")
	return true
}


choose_surface_format :: proc(using ctx: ^Context) -> vk.SurfaceFormatKHR {
	for v in swap_chain.support.formats {
		if v.format == .B8G8R8A8_SRGB && v.colorSpace == .SRGB_NONLINEAR do return v
	}

	return swap_chain.support.formats[0]
}

choose_present_mode :: proc(using ctx: ^Context) -> vk.PresentModeKHR {
	for v in swap_chain.support.present_modes {
		if v == .MAILBOX do return v
	}

	return .FIFO
}

choose_swap_extent :: proc(using ctx: ^Context) -> (ok: bool, extent: vk.Extent2D) {
	if (swap_chain.support.capabilities.currentExtent.width != max(u32)) {
		return true, swap_chain.support.capabilities.currentExtent
	} else {
		width, height: c.int
		if !sdl3.GetWindowSizeInPixels(window, &width, &height) do return false, extent

		extent := vk.Extent2D{u32(width), u32(height)}

		extent.width = clamp(
			extent.width,
			swap_chain.support.capabilities.minImageExtent.width,
			swap_chain.support.capabilities.maxImageExtent.width,
		)
		extent.height = clamp(
			extent.height,
			swap_chain.support.capabilities.minImageExtent.height,
			swap_chain.support.capabilities.maxImageExtent.height,
		)

		return true, extent
	}
}


create_image_views :: proc(using ctx: ^Context) -> bool {
	log.debug("vulkan create_image_views START")
	using ctx.swap_chain

	image_views = make([]vk.ImageView, len(images))

	for _, i in images {
		// I may have to export this latter 
		create_info: vk.ImageViewCreateInfo
		create_info.sType = .IMAGE_VIEW_CREATE_INFO
		create_info.image = images[i]
		create_info.viewType = .D2
		create_info.format = format.format
		create_info.components.r = .IDENTITY
		create_info.components.g = .IDENTITY
		create_info.components.b = .IDENTITY
		create_info.components.a = .IDENTITY
		create_info.subresourceRange.aspectMask = {.COLOR}
		create_info.subresourceRange.baseMipLevel = 0
		create_info.subresourceRange.levelCount = 1
		create_info.subresourceRange.baseArrayLayer = 0
		create_info.subresourceRange.layerCount = 1

		if res := vk.CreateImageView(device, &create_info, nil, &image_views[i]); res != .SUCCESS {
			log.error("vulkan create_image_views failed to create image view")
			return false
		}
	}

	log.debug("vulkan create_image_views SUCCESSFULL")
	return true
}

create_framebuffers :: proc(using ctx: ^Context) -> (ok: bool) {
	swap_chain.framebuffers = make([]vk.Framebuffer, len(swap_chain.image_views))
	for v, i in swap_chain.image_views {
		attachments := [?]vk.ImageView{v}

		framebuffer_info: vk.FramebufferCreateInfo
		framebuffer_info.sType = .FRAMEBUFFER_CREATE_INFO
		framebuffer_info.renderPass = pipeline.render_pass
		framebuffer_info.attachmentCount = 1
		framebuffer_info.pAttachments = &attachments[0]
		framebuffer_info.width = swap_chain.extent.width
		framebuffer_info.height = swap_chain.extent.height
		framebuffer_info.layers = 1

		if res := vk.CreateFramebuffer(device, &framebuffer_info, nil, &swap_chain.framebuffers[i]); res != .SUCCESS {
			fmt.eprintf("Error: Failed to create framebuffer #%d!\n", i)
			return false
		}
	}
	return true
}

create_command_pool :: proc(using ctx: ^Context) -> (ok: bool) {
	log.debug("vulkan create_command_pool: START")
	pool_info: vk.CommandPoolCreateInfo
	pool_info.sType = .COMMAND_POOL_CREATE_INFO
	pool_info.flags = {.RESET_COMMAND_BUFFER}
	pool_info.queueFamilyIndex = u32(queue_indices[.Graphics])

	if res := vk.CreateCommandPool(device, &pool_info, nil, &command_pool); res != .SUCCESS {
		log.error("vulkan create_command_pool: failed to create command pool")
		return false
	}
	log.debug("vulkan create_command_pool: SUCCESSFULL")
	return true
}

create_command_buffers :: proc(using ctx: ^Context) -> (ok: bool) {
	// resize commandBuffers ? max frames in  flight
	alloc_info: vk.CommandBufferAllocateInfo
	alloc_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
	alloc_info.commandPool = command_pool
	alloc_info.level = .PRIMARY
	alloc_info.commandBufferCount = len(command_buffers)

	if res := vk.AllocateCommandBuffers(device, &alloc_info, &command_buffers[0]); res != .SUCCESS {
		fmt.eprintf("Error: Failed to allocate command buffers!\n")
		return false
	}

	return true
}

create_vertex_buffer :: proc(using ctx: ^Context, vertices: []Vertex) -> (ok: bool) {
	vertex_buffer.length = len(vertices)
	vertex_buffer.size = cast(vk.DeviceSize)(len(vertices) * size_of(Vertex))

	staging: Buffer
	create_buffer(ctx, size_of(Vertex), len(vertices), {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging) or_return

	data: rawptr
	vk.MapMemory(device, staging.memory, 0, vertex_buffer.size, {}, &data)
	if data == nil {
		fmt.eprintf("Error: vk.MapMemory Failed")
		return false
	}

	mem.copy(data, raw_data(vertices), cast(int)vertex_buffer.size)


	vk.UnmapMemory(device, staging.memory)

	create_buffer(ctx, size_of(Vertex), len(vertices), {.VERTEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL}, &vertex_buffer) or_return
	copy_buffer(ctx, staging, vertex_buffer, vertex_buffer.size)

	vk.FreeMemory(device, staging.memory, nil)
	vk.DestroyBuffer(device, staging.buffer, nil)
	return true
}

create_index_buffer :: proc(using ctx: ^Context, indices: []u16) -> (ok: bool) {
	index_buffer.length = len(indices)
	index_buffer.size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0]))

	staging: Buffer
	create_buffer(ctx, size_of(indices[0]), len(indices), {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging) or_return

	data: rawptr
	vk.MapMemory(device, staging.memory, 0, index_buffer.size, {}, &data)
	mem.copy(data, raw_data(indices), cast(int)index_buffer.size)
	vk.UnmapMemory(device, staging.memory)

	create_buffer(ctx, size_of(Vertex), len(indices), {.INDEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL}, &index_buffer) or_return
	copy_buffer(ctx, staging, index_buffer, index_buffer.size)

	vk.FreeMemory(device, staging.memory, nil)
	vk.DestroyBuffer(device, staging.buffer, nil)
	return true
}


create_sync_objects :: proc(using ctx: ^Context) -> (ok: bool) {
	semaphore_info: vk.SemaphoreCreateInfo
	semaphore_info.sType = .SEMAPHORE_CREATE_INFO

	fence_info: vk.FenceCreateInfo
	fence_info.sType = .FENCE_CREATE_INFO
	fence_info.flags = {.SIGNALED}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		res := vk.CreateSemaphore(device, &semaphore_info, nil, &image_available[i])
		if res != .SUCCESS {
			fmt.eprintf("Error: Failed to create \"image_available\" semaphore\n")
			return false
		}
		res = vk.CreateSemaphore(device, &semaphore_info, nil, &render_finished[i])
		if res != .SUCCESS {
			fmt.eprintf("Error: Failed to create \"render_finished\" semaphore\n")
			return false
		}
		res = vk.CreateFence(device, &fence_info, nil, &in_flight[i])
		if res != .SUCCESS {
			fmt.eprintf("Error: Failed to create \"in_flight\" fence\n")
			return false
		}
	}

	return true
}

cleanup_swap_chain :: proc(using ctx: ^Context) {
	for f in swap_chain.framebuffers {
		vk.DestroyFramebuffer(device, f, nil)
	}
	for view in swap_chain.image_views {
		vk.DestroyImageView(device, view, nil)
	}
	vk.DestroySwapchainKHR(device, swap_chain.handle, nil)
}


recreate_swap_chain :: proc(using ctx: ^Context) -> (ok: bool) {
	vk.DeviceWaitIdle(device)

	cleanup_swap_chain(ctx)
	create_swap_chain(ctx) or_return
	create_image_views(ctx) or_return
	create_framebuffers(ctx) or_return
	return true
}

draw_frame :: proc(using ctx: ^Context, vertices: []Vertex, indices: []u16) -> (ok: bool) {
	vk.WaitForFences(device, 1, &in_flight[curr_frame], true, max(u64))
	image_index: u32

	res := vk.AcquireNextImageKHR(device, swap_chain.handle, max(u64), image_available[curr_frame], {}, &image_index)
	if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR || framebuffer_resized {
		framebuffer_resized = false
		recreate_swap_chain(ctx) or_return
		return true
	} else if res != .SUCCESS {
		fmt.eprintf("Error: Failed tp acquire swap chain image!\n")
		return false
	}

	vk.ResetFences(device, 1, &in_flight[curr_frame])
	vk.ResetCommandBuffer(command_buffers[curr_frame], {})
	record_command_buffer(ctx, command_buffers[curr_frame], image_index) or_return

	submit_info: vk.SubmitInfo
	submit_info.sType = .SUBMIT_INFO

	wait_semaphores := [?]vk.Semaphore{image_available[curr_frame]}
	wait_stages := [?]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	submit_info.waitSemaphoreCount = 1
	submit_info.pWaitSemaphores = &wait_semaphores[0]
	submit_info.pWaitDstStageMask = &wait_stages[0]
	submit_info.commandBufferCount = 1
	submit_info.pCommandBuffers = &command_buffers[curr_frame]

	signal_semaphores := [?]vk.Semaphore{render_finished[curr_frame]}
	submit_info.signalSemaphoreCount = 1
	submit_info.pSignalSemaphores = &signal_semaphores[0]

	if res := vk.QueueSubmit(queues[.Graphics], 1, &submit_info, in_flight[curr_frame]); res != .SUCCESS {
		fmt.eprintf("Error: Failed to submit draw command buffer!\n")
		return false
	}

	present_info: vk.PresentInfoKHR
	present_info.sType = .PRESENT_INFO_KHR
	present_info.waitSemaphoreCount = 1
	present_info.pWaitSemaphores = &signal_semaphores[0]

	swap_chains := [?]vk.SwapchainKHR{swap_chain.handle}
	present_info.swapchainCount = 1
	present_info.pSwapchains = &swap_chains[0]
	present_info.pImageIndices = &image_index
	present_info.pResults = nil

	vk.QueuePresentKHR(queues[.Present], &present_info)
	curr_frame = (curr_frame + 1) % MAX_FRAMES_IN_FLIGHT
	return true
}


record_command_buffer :: proc(using ctx: ^Context, buffer: vk.CommandBuffer, image_index: u32) -> (ok: bool) {
	begin_info: vk.CommandBufferBeginInfo
	begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO
	begin_info.flags = {}
	begin_info.pInheritanceInfo = nil

	if res := vk.BeginCommandBuffer(buffer, &begin_info); res != .SUCCESS {
		fmt.eprintf("Error: Failed to begin recording command buffer!\n")
		return false
	}

	render_pass_info: vk.RenderPassBeginInfo
	render_pass_info.sType = .RENDER_PASS_BEGIN_INFO
	render_pass_info.renderPass = pipeline.render_pass
	render_pass_info.framebuffer = swap_chain.framebuffers[image_index]
	render_pass_info.renderArea.offset = {0, 0}
	render_pass_info.renderArea.extent = swap_chain.extent

	clear_color: vk.ClearValue
	clear_color.color.float32 = [4]f32{0.0, 0.0, 0.0, 1.0}
	render_pass_info.clearValueCount = 1
	render_pass_info.pClearValues = &clear_color

	vk.CmdBeginRenderPass(buffer, &render_pass_info, .INLINE)

	vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline.handle)

	vertex_buffers := [?]vk.Buffer{vertex_buffer.buffer}
	offsets := [?]vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(buffer, 0, 1, &vertex_buffers[0], &offsets[0])
	vk.CmdBindIndexBuffer(buffer, index_buffer.buffer, 0, .UINT16)

	viewport: vk.Viewport
	viewport.x = 0.0
	viewport.y = 0.0
	viewport.width = f32(swap_chain.extent.width)
	viewport.height = f32(swap_chain.extent.height)
	viewport.minDepth = 0.0
	viewport.maxDepth = 1.0
	vk.CmdSetViewport(buffer, 0, 1, &viewport)

	scissor: vk.Rect2D
	scissor.offset = {0, 0}
	scissor.extent = swap_chain.extent
	vk.CmdSetScissor(buffer, 0, 1, &scissor)

	vk.CmdDrawIndexed(buffer, cast(u32)index_buffer.length, 1, 0, 0, 0)

	vk.CmdEndRenderPass(buffer)

	if res := vk.EndCommandBuffer(buffer); res != .SUCCESS {
		fmt.eprintf("Error: Failed to record command buffer!\n")
		return false
	}
	return true
}

create_image :: proc(
	using ctx: ^Context,
	image: ^vk.Image,
	image_memory: ^vk.DeviceMemory,
	width, height, mip_levels: u32,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	properties: vk.MemoryPropertyFlags,
	num_samples: vk.SampleCountFlags,
) -> bool {
	log.debug("vulkan create_image: START")
	imageInfo: vk.ImageCreateInfo
	imageInfo.sType = .IMAGE_COMPRESSION_PROPERTIES_EXT
	imageInfo.imageType = .D2
	imageInfo.extent.width = width
	imageInfo.extent.height = height
	imageInfo.extent.depth = 1
	imageInfo.mipLevels = mip_levels
	imageInfo.arrayLayers = 1
	imageInfo.format = format
	imageInfo.tiling = tiling
	imageInfo.initialLayout = .UNDEFINED
	imageInfo.usage = usage
	imageInfo.samples = num_samples
	imageInfo.sharingMode = .EXCLUSIVE


	if vk.CreateImage(ctx.device, &imageInfo, nil, image) != .SUCCESS {
		log.error("vulkan create_image: failed CreateImage")
		return false
	}

	memRequiremens: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(ctx.device, image^, &memRequiremens)
	mem_type: u32 = find_memory_type(ctx, memRequiremens.memoryTypeBits, properties) or_return
	allocInfo: vk.MemoryAllocateInfo
	allocInfo.sType = .MEMORY_ALLOCATE_INFO
	allocInfo.allocationSize = memRequiremens.size
	allocInfo.memoryTypeIndex = mem_type

	if res := vk.AllocateMemory(device, &allocInfo, nil, image_memory); res != .SUCCESS {
		log.error("vulkan create_image: failed AllocateMemory")
		return false
	}

	log.debug("vulkan create_image: SUCCESSFULL")
	return true
}

create_image_view_info :: proc(
	image: vk.Image,
	format: vk.Format,
	aspectFlags: vk.ImageAspectFlags,
	mipLevels: u32,
) -> (
	viewInfo: vk.ImageViewCreateInfo,
) {
	viewInfo.sType = .IMAGE_VIEW_CREATE_INFO
	viewInfo.image = image
	viewInfo.viewType = .D2
	viewInfo.format = format
	viewInfo.subresourceRange.aspectMask = aspectFlags
	viewInfo.subresourceRange.baseMipLevel = 0
	viewInfo.subresourceRange.baseArrayLayer = 0
	viewInfo.subresourceRange.layerCount = 1
	viewInfo.subresourceRange.levelCount = mipLevels
	return
}


create_color_resources :: proc(using ctx: ^Context) -> bool {
	log.debug("vulkan create_color_resources: START")
	color_format: vk.Format = ctx.swap_chain.format.format
	create_image(
		ctx,
		&color_resource.image,
		&color_resource.memory,
		swap_chain.extent.width,
		swap_chain.extent.height,
		1,
		color_format,
		vk.ImageTiling.OPTIMAL,
		{vk.ImageUsageFlag.TRANSIENT_ATTACHMENT, vk.ImageUsageFlag.COLOR_ATTACHMENT},
		{vk.MemoryPropertyFlag.DEVICE_LOCAL},
		mssa_samples,
	) or_return
	image_view_info := create_image_view_info(color_resource.image, color_format, {vk.ImageAspectFlag.COLOR}, 1)
	if res := vk.CreateImageView(device, &image_view_info, nil, &color_resource.view); res != .SUCCESS {
		log.error("vulkan create_color_resources: failed CreateImageView")
		return false
	}
	log.debug("vulkan create_color_resources: SUCCESSFULL")
	return true
}

create_depth_resources :: proc(using ctx: ^Context) -> bool {
	log.debug("vulkan create_depth_resources: START")
	depth_format := find_supported_format(
		ctx,
		{vk.Format.D32_SFLOAT, vk.Format.D32_SFLOAT_S8_UINT, vk.Format.D24_UNORM_S8_UINT},
		.OPTIMAL,
		{vk.FormatFeatureFlag.DEPTH_STENCIL_ATTACHMENT},
	)

	create_image(
		ctx,
		&depth_resource.image,
		&depth_resource.memory,
		swap_chain.extent.width,
		swap_chain.extent.height,
		1,
		depth_format,
		vk.ImageTiling.OPTIMAL,
		{vk.ImageUsageFlag.DEPTH_STENCIL_ATTACHMENT},
		{vk.MemoryPropertyFlag.DEVICE_LOCAL},
		mssa_samples,
	) or_return

	image_view_info := create_image_view_info(depth_resource.image, depth_format, {vk.ImageAspectFlag.DEPTH}, 1)

	if res := vk.CreateImageView(device, &image_view_info, nil, &depth_resource.view); res != .SUCCESS {
		fmt.eprintln("vulkan create_depth_resources: failed CreateImageView")
		return false
	}

	log.debug("vulkan create_depth_resources: SUCCESSFULL")
	return true
}

// Explota seguro 
create_texture_image :: proc(ctx: ^Context, img: ^utils.ImageInfo) -> bool {
	log.debug("vulkan create_texture_image: START")

	device_size: vk.DeviceSize = vk.DeviceSize(img.width * img.height * 4)
	staging_buffer: Buffer
	staging_buffer_memory: vk.DeviceMemory
	ctx.mip_leveles = u32(math.floor_f32(math.logb_f32(f32(max(img.width, img.height))))) + 1

	create_buffer(
		ctx,
		size_of(u8),
		len(img.data),
		{vk.BufferUsageFlag.TRANSFER_SRC},
		{vk.MemoryPropertyFlag.HOST_VISIBLE, vk.MemoryPropertyFlag.HOST_COHERENT},
		&staging_buffer,
	) or_return


	data: ^rawptr
	vk.MapMemory(ctx.device, staging_buffer_memory, 0, device_size, {}, data)
	mem.copy(data, rawptr(&img.data), int(device_size))
	vk.UnmapMemory(ctx.device, staging_buffer_memory)

	create_image(
		ctx,
		&ctx.texture_resource.image,
		&ctx.texture_resource.memory,
		u32(img.width),
		u32(img.height),
		ctx.mip_leveles,
		vk.Format.R8G8B8A8_SRGB,
		.OPTIMAL,
		{vk.ImageUsageFlag.TRANSFER_SRC, vk.ImageUsageFlag.TRANSFER_DST, vk.ImageUsageFlag.SAMPLED},
		{vk.MemoryPropertyFlag.DEVICE_LOCAL},
		{vk.SampleCountFlag._1},
	)

	transition_image_layout(
		ctx,
		ctx.texture_resource.image,
		vk.Format.R8G8B8A8_SRGB,
		vk.ImageLayout.UNDEFINED,
		vk.ImageLayout.TRANSFER_DST_OPTIMAL,
	) or_return

	copy_buffer_to_image(ctx, &staging_buffer, ctx.texture_resource.image, img.width, img.height) or_return

	vk.DestroyBuffer(ctx.device, staging_buffer.buffer, nil)
	vk.FreeMemory(ctx.device, staging_buffer.memory, nil)


	generate_mipmaps(ctx, ctx.texture_resource.image, vk.Format.R8G8B8A8_SRGB, i32(img.width), i32(img.height), ctx.mip_leveles) or_return
	log.debug("vulkan create_texture_image: SUCCESSFULL")
	return true
}

generate_mipmaps :: proc(ctx: ^Context, image: vk.Image, imageFormat: vk.Format, width, height: i32, mip_leveles: u32) -> bool {
	log.debug("vulkan generate_mipmaps: START")
	format_properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(ctx.physical_device, imageFormat, &format_properties)

	// not sure why or how would this happen,I hope to never find out :(
	if (!(vk.FormatFeatureFlag.SAMPLED_IMAGE_FILTER_LINEAR in format_properties.optimalTilingFeatures)) {
		log.debug("vulkan generate_mipmaps: texture image format does not support linear blitting")
		return false
	}

	command_buffer := begin_single_time_commands(ctx) or_return

	barrier: vk.ImageMemoryBarrier
	barrier.sType = .IMAGE_MEMORY_BARRIER
	barrier.image = image
	barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
	barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
	barrier.subresourceRange.aspectMask = {vk.ImageAspectFlag.COLOR}
	barrier.subresourceRange.baseArrayLayer = 0
	barrier.subresourceRange.layerCount = 1
	barrier.subresourceRange.levelCount = 1


	mip_width := width
	mip_height := height

	for i in 1 ..< mip_leveles {
		barrier.subresourceRange.baseArrayLayer = i - 1
		barrier.oldLayout = vk.ImageLayout.TRANSFER_DST_OPTIMAL
		barrier.newLayout = vk.ImageLayout.TRANSFER_SRC_OPTIMAL
		barrier.srcAccessMask = {vk.AccessFlag.TRANSFER_WRITE}
		barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_READ}

		vk.CmdPipelineBarrier(
			command_buffer,
			{vk.PipelineStageFlag.TRANSFER},
			{vk.PipelineStageFlag.TRANSFER},
			{},
			0,
			nil,
			0,
			nil,
			1,
			&barrier,
		)

		blit: vk.ImageBlit
		blit.srcOffsets[0] = {0, 0, 0}
		blit.srcOffsets[1] = {width, height, 1}
		blit.srcSubresource.aspectMask = {vk.ImageAspectFlag.COLOR}
		blit.srcSubresource.mipLevel = i - 1
		blit.srcSubresource.baseArrayLayer = 0
		blit.srcSubresource.layerCount = 1

		blit.dstOffsets[0] = {0, 0, 0}
		blit.dstOffsets[1] = {mip_width > 1 ? mip_width / 2 : 1, mip_height > 1 ? mip_height / 2 : 1, 1}
		blit.dstSubresource.aspectMask = {vk.ImageAspectFlag.COLOR}
		blit.dstSubresource.mipLevel = 1
		blit.dstSubresource.baseArrayLayer = 0
		blit.dstSubresource.layerCount = 1

		vk.CmdBlitImage(
			command_buffer,
			image,
			vk.ImageLayout.TRANSFER_SRC_OPTIMAL,
			image,
			vk.ImageLayout.TRANSFER_DST_OPTIMAL,
			1,
			&blit,
			vk.Filter.LINEAR,
		)

		barrier.oldLayout = vk.ImageLayout.TRANSFER_SRC_OPTIMAL
		barrier.newLayout = vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
		barrier.srcAccessMask = {vk.AccessFlags.TRANSFER_READ}
		barrier.dstAccessMask = {vk.AccessFlags.SHADER_READ}

		vk.CmdPipelineBarrier(
			command_buffer,
			{vk.PipelineStageFlag.TRANSFER},
			{vk.PipelineStageFlag.FRAGMENT_SHADER},
			{},
			0,
			nil,
			0,
			nil,
			1,
			&barrier,
		)
		if mip_width > 1 {
			mip_width /= 2
		}
		if mip_height > 1 {
			mip_height /= 2
		}
	}

	barrier.subresourceRange.baseMipLevel = mip_leveles - 1
	barrier.oldLayout = vk.ImageLayout.TRANSFER_DST_OPTIMAL
	barrier.newLayout = vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = {vk.AccessFlag.TRANSFER_WRITE}
	barrier.dstAccessMask = {vk.AccessFlag.SHADER_READ}

	vk.CmdPipelineBarrier(
		command_buffer,
		{vk.PipelineStageFlag.TRANSFER},
		{vk.PipelineStageFlag.FRAGMENT_SHADER},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)

	end_single_time_commands(ctx, &command_buffer) or_return
	log.debug("vulkan generate_mipmaps: SUCCESSFULL")
	return true
}

transition_image_layout :: proc(ctx: ^Context, image: vk.Image, format: vk.Format, oldLayout, newLayout: vk.ImageLayout) -> bool {
	log.debug("vulkan transition_image_layout: START")
	command_buffer: vk.CommandBuffer = begin_single_time_commands(ctx) or_return
	barrier: vk.ImageMemoryBarrier
	barrier.sType = .IMAGE_MEMORY_BARRIER
	barrier.oldLayout = oldLayout
	barrier.newLayout = newLayout
	barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
	barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
	barrier.image = image
	barrier.subresourceRange.baseMipLevel = 0
	barrier.subresourceRange.levelCount = ctx.mip_leveles
	barrier.subresourceRange.baseArrayLayer = 0
	barrier.subresourceRange.layerCount = 1

	if (newLayout == vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
		barrier.subresourceRange.aspectMask = {vk.ImageAspectFlag.DEPTH}
		if format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT {
			barrier.subresourceRange.aspectMask = barrier.subresourceRange.aspectMask | {vk.ImageAspectFlag.STENCIL}
		}
	} else {
		barrier.subresourceRange.aspectMask = {vk.ImageAspectFlag.COLOR}
	}
	sourceStage: vk.PipelineStageFlags
	destinationStage: vk.PipelineStageFlags

	if oldLayout == .UNDEFINED && newLayout == .TRANSFER_DST_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_WRITE}

		sourceStage = {.TOP_OF_PIPE}
		destinationStage = {.TRANSFER}
	} else if oldLayout == .TRANSFER_DST_OPTIMAL && newLayout == .READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		sourceStage = {.TRANSFER}
		destinationStage = {.FRAGMENT_SHADER}
	} else if oldLayout == .UNDEFINED && newLayout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_READ} | {.DEPTH_STENCIL_ATTACHMENT_WRITE}

		sourceStage = {.TOP_OF_PIPE}
		destinationStage = {.EARLY_FRAGMENT_TESTS}
	} else {
		log.error("vulkan transition_image_layout: unsupported layout transition")
		return false
	}

	vk.CmdPipelineBarrier(command_buffer, sourceStage, destinationStage, {}, 0, nil, 0, nil, 1, &barrier)
	end_single_time_commands(ctx, &command_buffer) or_return
	log.debug("vulkan transition_image_layout: SUCCESSFULL")
	return true
}

create_texture_imageview :: proc(ctx: ^Context) -> bool {
	log.debug("vulkan create_texture_imageview: START")
	view_info := create_image_view_info(ctx.texture_resource.image, vk.Format.R8G8B8A8_SRGB, {vk.ImageAspectFlag.COLOR}, ctx.mip_leveles)

	if res := vk.CreateImageView(ctx.device, &view_info, nil, &ctx.texture_resource.view); res != .SUCCESS {
		log.error("vulkan create_texture_imageview: failed to create texture image view")
		return false
	}
	log.debug("vulkan create_texture_imageview: SUCCESSFULL")
	return true
}

create_texture_sampler :: proc(ctx: ^Context) -> bool {
	log.debug("vulkan create_texture_sampler: START")
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(ctx.physical_device, &properties)
	sampler_info: vk.SamplerCreateInfo
	sampler_info.sType = .SAMPLER_CREATE_INFO
	sampler_info.magFilter = .LINEAR
	sampler_info.minFilter = .LINEAR
	sampler_info.addressModeU = .REPEAT
	sampler_info.addressModeV = .REPEAT
	sampler_info.addressModeW = .REPEAT
	sampler_info.anisotropyEnable = true
	sampler_info.maxAnisotropy = properties.limits.maxSamplerAnisotropy
	sampler_info.borderColor = .INT_OPAQUE_BLACK
	sampler_info.unnormalizedCoordinates = false
	sampler_info.compareEnable = false
	sampler_info.compareOp = .ALWAYS
	sampler_info.mipmapMode = .LINEAR
	sampler_info.minLod = 0.0
	sampler_info.maxLod = f32(ctx.mip_leveles)
	sampler_info.mipLodBias = 0.0

	if res := vk.CreateSampler(ctx.device, &sampler_info, nil, &ctx.texture_sampler); res != .SUCCESS {
		log.error("vulkan create_texture_sampler: failed  CreateSampler")
		return false
	}

	log.debug("vulkan create_texture_sampler: SUCCESSFULL")
	return true
}

package gpu

import "core:c"
import "core:os"
import "core:fmt"
import "core:strings"
import "vendor:sdl3"
import "shared:shaderc"
import vk "vendor:vulkan"


init_vulkan :: proc(using ctx: ^Context, vertices: []Vertex, indices: []u16) -> (ok: bool) {
	fmt.println("Creating vulkan context")
	context.user_ptr = &instance

	vk.load_proc_addresses(rawptr(sdl3.Vulkan_GetVkGetInstanceProcAddr()))
	create_instance(ctx) or_return
	extensions := get_extensions()

	for ext in &extensions do fmt.println("ExtensionName:  ", byte_to_cstring(ext.extensionName[0]))

	create_surface(ctx) or_return

	get_suitable_device(ctx) or_return
	find_queue_families(ctx)

	fmt.println("Queue Indices:")
	for q, f in queue_indices do fmt.printf("  %v: %d\n", f, q)

	create_device(ctx)

	for queue, f in queues {
		q := queue
		vk.GetDeviceQueue(device, u32(queue_indices[f]), 0, &q)
	}

	create_swap_chain(ctx) or_return
	create_image_views(ctx)
	create_graphics_pipeline(ctx, "shader.vert", "shader.frag")
	create_framebuffers(ctx)
	create_command_pool(ctx)
	create_vertex_buffer(ctx, vertices)
	create_index_buffer(ctx, indices)
	create_command_buffers(ctx)
	create_sync_objects(ctx)


	fmt.println("Vulkan context created")
	return true
}

clean_vulkan :: proc(using ctx: ^Context) {
	vk.DestroyDevice(device, nil)
	vk.DestroySurfaceKHR(instance, surface, nil)
	vk.DestroyInstance(instance, nil)
}

create_instance :: proc(using ctx: ^Context) -> (ok: bool) {
	fmt.println("Creating instance")

	if (enableValidationLayers && !check_ValidationLayerSupport()) {
		fmt.eprintf("validation layers requested but not available\n")
	}

	appInfo: vk.ApplicationInfo
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


	if (vk.CreateInstance(&createinfo, nil, &instance) != vk.Result.SUCCESS) {
		fmt.eprintf("ERROR: Failed to CreateInstance\n")
		return false
	}

	fmt.println("Instance created")
	return true
}


create_surface :: proc(using ctx: ^Context) -> (ok: bool) {
	if !sdl3.Vulkan_CreateSurface(window, instance, nil, &surface) {
		fmt.eprintf("ERROR: Failed to create window surface\n")
		return false
	}
	return true
}

get_suitable_device :: proc(using ctx: ^Context) -> (ok: bool) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 {
		fmt.eprintf("ERROR: Failed to create window surface\n")
		return false
	}
	devices := make([]vk.PhysicalDevice, device_count)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))

	suitability :: proc(using ctx: ^Context, dev: vk.PhysicalDevice) -> int {
		props: vk.PhysicalDeviceProperties
		features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceProperties(dev, &props)
		vk.GetPhysicalDeviceFeatures(dev, &features)

		score := 0
		if props.deviceType == .DISCRETE_GPU do score += 1000
		score += cast(int)props.limits.maxImageDimension2D

		if !features.geometryShader do return 0
		if !check_device_extension_support(dev) do return 0

		query_swap_chain_details(ctx, dev)
		if len(swap_chain.support.formats) == 0 || len(swap_chain.support.present_modes) == 0 do return 0

		return score
	}

	hiscore := 0
	for dev in devices {
		score := suitability(ctx, dev)
		if score > hiscore {
			physical_device = dev
			hiscore = score
		}
	}

	if (hiscore == 0) {
		fmt.eprintf("ERROR: Failed to find a suitable GPU\n")
		return false
	}

	return true
}

get_extensions :: proc() -> []vk.ExtensionProperties {
	n_ext: u32
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil)
	extensions := make([]vk.ExtensionProperties, n_ext)
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extensions))
	return extensions
}


check_ValidationLayerSupport :: proc() -> b32 {
	layerCount: u32
	vk.EnumerateInstanceLayerProperties(&layerCount, nil)
	availableLayers := make([]vk.LayerProperties, layerCount)
	vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(availableLayers))
	for layerName in VALIDATION_LAYERS {
		for layerProperties in availableLayers {
			if byte_to_cstring(layerProperties.layerName) == layerName do return true
		}
	}
	return false
}

query_swap_chain_details :: proc(using ctx: ^Context, dev: vk.PhysicalDevice) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &swap_chain.support.capabilities)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_count, nil)
	if format_count > 0 {
		swap_chain.support.formats = make([]vk.SurfaceFormatKHR, format_count)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			dev,
			surface,
			&format_count,
			raw_data(swap_chain.support.formats),
		)
	}

	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_count, nil)
	if present_mode_count > 0 {
		swap_chain.support.present_modes = make([]vk.PresentModeKHR, present_mode_count)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			dev,
			surface,
			&present_mode_count,
			raw_data(swap_chain.support.present_modes),
		)
	}
}


check_device_extension_support :: proc(physical_device: vk.PhysicalDevice) -> bool {
	ext_count: u32
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &ext_count, nil)

	available_extensions := make([]vk.ExtensionProperties, ext_count)
	vk.EnumerateDeviceExtensionProperties(
		physical_device,
		nil,
		&ext_count,
		raw_data(available_extensions),
	)

	for ext in DEVICE_EXTENSIONS {
		found: b32
		for available in &available_extensions {
			if byte_to_cstring(available.extensionName[0]) == ext {
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
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&queue_count,
		raw_data(available_queues),
	)

	for v, i in available_queues {
		if .GRAPHICS in v.queueFlags && queue_indices[.Graphics] == -1 do queue_indices[.Graphics] = i

		present_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(i), surface, &present_support)
		if present_support && queue_indices[.Present] == -1 do queue_indices[.Present] = i

		for q in queue_indices do if q == -1 do continue
		break
	}
}


byte_to_cstring :: proc(name: [256]u8) -> cstring {
	bytes := name
	builder := strings.clone_from_bytes(bytes[:])
	return strings.clone_to_cstring(builder)
}


create_device :: proc(using ctx: ^Context) -> (ok: bool) {
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
	device_create_info: vk.DeviceCreateInfo
	device_create_info.sType = .DEVICE_CREATE_INFO
	device_create_info.enabledExtensionCount = u32(len(DEVICE_EXTENSIONS))
	device_create_info.ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0]
	device_create_info.pQueueCreateInfos = raw_data(queue_create_infos)
	device_create_info.queueCreateInfoCount = u32(len(queue_create_infos))
	device_create_info.pEnabledFeatures = &device_features
	device_create_info.enabledLayerCount = 0

	if vk.CreateDevice(physical_device, &device_create_info, nil, &device) != .SUCCESS {
		fmt.eprintf("ERROR: Failed to create logical device\n")
		return false
	}
	return true
}

create_swap_chain :: proc(using ctx: ^Context) -> (ok: bool) {
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

	queue_family_indices := [len(QueueFamily)]u32 {
		u32(queue_indices[.Graphics]),
		u32(queue_indices[.Present]),
	}

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

	if res := vk.CreateSwapchainKHR(device, &create_info, nil, &swap_chain.handle);
	   res != .SUCCESS {
		fmt.eprintf("Error: failed to create swap chain!\n")
		return false
	}

	vk.GetSwapchainImagesKHR(device, swap_chain.handle, &swap_chain.image_count, nil)
	swap_chain.images = make([]vk.Image, swap_chain.image_count)
	vk.GetSwapchainImagesKHR(
		device,
		swap_chain.handle,
		&swap_chain.image_count,
		raw_data(swap_chain.images),
	)
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
	using ctx.swap_chain

	image_views = make([]vk.ImageView, len(images))

	for _, i in images {
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
			fmt.eprintf("Error: failed to create image view!")
			return false
		}
	}

	return true
}

create_graphics_pipeline :: proc(using ctx: ^Context, vs_name: string, fs_name: string) -> bool {
	vs_code := compile_shader(vs_name, .vertex_shader)
	fs_code := compile_shader(fs_name, .fragment_shader)
	/*
		vs_code, vs_ok := os.read_entire_file(vs_path);
		fs_code, fs_ok := os.read_entire_file(fs_path);
		if !vs_ok
		{
			fmt.eprintf("Error: could not load vertex shader %q\n", vs_path);
			os.exit(1);
		}
		
		if !fs_ok
		{
			fmt.eprintf("Error: could not load fragment shader %q\n", fs_path);
			os.exit(1);
		}
	*/

	defer {
		delete(vs_code)
		delete(fs_code)
	}

	vs_shader := create_shader_module(ctx, vs_code)
	fs_shader := create_shader_module(ctx, fs_code)
	defer 
	{
		vk.DestroyShaderModule(device, vs_shader, nil)
		vk.DestroyShaderModule(device, fs_shader, nil)
	}

	vs_info: vk.PipelineShaderStageCreateInfo
	vs_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	vs_info.stage = {.VERTEX}
	vs_info.module = vs_shader
	vs_info.pName = "main"

	fs_info: vk.PipelineShaderStageCreateInfo
	fs_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	fs_info.stage = {.FRAGMENT}
	fs_info.module = fs_shader
	fs_info.pName = "main"

	shader_stages := [?]vk.PipelineShaderStageCreateInfo{vs_info, fs_info}

	dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state: vk.PipelineDynamicStateCreateInfo
	dynamic_state.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
	dynamic_state.dynamicStateCount = len(dynamic_states)
	dynamic_state.pDynamicStates = &dynamic_states[0]

	vertex_input: vk.PipelineVertexInputStateCreateInfo
	vertex_input.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
	vertex_input.vertexBindingDescriptionCount = 1
	vertex_input.pVertexBindingDescriptions = &VERTEX_BINDING
	vertex_input.vertexAttributeDescriptionCount = len(VERTEX_ATTRIBUTES)
	vertex_input.pVertexAttributeDescriptions = &VERTEX_ATTRIBUTES[0]

	input_assembly: vk.PipelineInputAssemblyStateCreateInfo
	input_assembly.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	input_assembly.topology = .TRIANGLE_LIST
	input_assembly.primitiveRestartEnable = false

	viewport: vk.Viewport
	viewport.x = 0.0
	viewport.y = 0.0
	viewport.width = cast(f32)swap_chain.extent.width
	viewport.height = cast(f32)swap_chain.extent.height
	viewport.minDepth = 0.0
	viewport.maxDepth = 1.0

	scissor: vk.Rect2D
	scissor.offset = {0, 0}
	scissor.extent = swap_chain.extent

	viewport_state: vk.PipelineViewportStateCreateInfo
	viewport_state.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
	viewport_state.viewportCount = 1
	viewport_state.scissorCount = 1

	rasterizer: vk.PipelineRasterizationStateCreateInfo
	rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
	rasterizer.depthClampEnable = false
	rasterizer.rasterizerDiscardEnable = false
	rasterizer.polygonMode = .FILL
	rasterizer.lineWidth = 1.0
	rasterizer.cullMode = {.BACK}
	rasterizer.frontFace = .CLOCKWISE
	rasterizer.depthBiasEnable = false
	rasterizer.depthBiasConstantFactor = 0.0
	rasterizer.depthBiasClamp = 0.0
	rasterizer.depthBiasSlopeFactor = 0.0

	multisampling: vk.PipelineMultisampleStateCreateInfo
	multisampling.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	multisampling.sampleShadingEnable = false
	multisampling.rasterizationSamples = {._1}
	multisampling.minSampleShading = 1.0
	multisampling.pSampleMask = nil
	multisampling.alphaToCoverageEnable = false
	multisampling.alphaToOneEnable = false

	color_blend_attachment: vk.PipelineColorBlendAttachmentState
	color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	color_blend_attachment.blendEnable = true
	color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
	color_blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
	color_blend_attachment.colorBlendOp = .ADD
	color_blend_attachment.srcAlphaBlendFactor = .ONE
	color_blend_attachment.dstAlphaBlendFactor = .ZERO
	color_blend_attachment.alphaBlendOp = .ADD

	color_blending: vk.PipelineColorBlendStateCreateInfo
	color_blending.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	color_blending.logicOpEnable = false
	color_blending.logicOp = .COPY
	color_blending.attachmentCount = 1
	color_blending.pAttachments = &color_blend_attachment
	color_blending.blendConstants[0] = 0.0
	color_blending.blendConstants[1] = 0.0
	color_blending.blendConstants[2] = 0.0
	color_blending.blendConstants[3] = 0.0

	pipeline_layout_info: vk.PipelineLayoutCreateInfo
	pipeline_layout_info.sType = .PIPELINE_LAYOUT_CREATE_INFO
	pipeline_layout_info.setLayoutCount = 0
	pipeline_layout_info.pSetLayouts = nil
	pipeline_layout_info.pushConstantRangeCount = 0
	pipeline_layout_info.pPushConstantRanges = nil

	if res := vk.CreatePipelineLayout(device, &pipeline_layout_info, nil, &pipeline.layout);
	   res != .SUCCESS {
		fmt.eprintf("Error: Failed to create pipeline layout!\n")
		return false
	}

	create_render_pass(ctx)

	pipeline_info: vk.GraphicsPipelineCreateInfo
	pipeline_info.sType = .GRAPHICS_PIPELINE_CREATE_INFO
	pipeline_info.stageCount = 2
	pipeline_info.pStages = &shader_stages[0]
	pipeline_info.pVertexInputState = &vertex_input
	pipeline_info.pInputAssemblyState = &input_assembly
	pipeline_info.pViewportState = &viewport_state
	pipeline_info.pRasterizationState = &rasterizer
	pipeline_info.pMultisampleState = &multisampling
	pipeline_info.pDepthStencilState = nil
	pipeline_info.pColorBlendState = &color_blending
	pipeline_info.pDynamicState = &dynamic_state
	pipeline_info.layout = pipeline.layout
	pipeline_info.renderPass = pipeline.render_pass
	pipeline_info.subpass = 0
	pipeline_info.basePipelineHandle = vk.Pipeline{}
	pipeline_info.basePipelineIndex = -1

	if res := vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_info, nil, &pipeline.handle);
	   res != .SUCCESS {
		fmt.eprintf("Error: Failed to create graphics pipeline!\n")
		return false
	}
	return true
}


compile_shader :: proc(name: string, kind: shaderc.shaderKind) -> []u8
{
	src_path := fmt.tprintf("./shaders/%s", name);
	cmp_path := fmt.tprintf("./shaders/compiled/%s.spv", name);
	src_time, src_err := os.last_write_time_by_name(src_path);
	if (src_err != os.ERROR_NONE)
	{
		fmt.eprintf("Failed to open shader %q\n", src_path);
		return nil;
	}
	
	cmp_time, cmp_err := os.last_write_time_by_name(cmp_path);
	if cmp_err == os.ERROR_NONE && cmp_time >= src_time
	{
		code, _ := os.read_entire_file(cmp_path);
		return code;
	}
	
	
	comp := shaderc.compiler_initialize();
	options := shaderc.compile_options_initialize();
	defer 
	{
		shaderc.compiler_release(comp);
		shaderc.compile_options_release(options);
	}
	
	shaderc.compile_options_set_optimization_level(options, .Performance);
	
	code, _ := os.read_entire_file(src_path);
	c_path := strings.clone_to_cstring(src_path, context.temp_allocator);
	res := shaderc.compile_into_spv(comp, cstring(raw_data(code)), len(code), kind, c_path, cstring("main"), options);
	defer shaderc.result_release(res);
	
	status := shaderc.result_get_compilation_status(res);
	if status != .Success
	{
		fmt.printf("%s: Error: %s\n", name, shaderc.result_get_error_message(res));
		return nil;
	}
	
	length := shaderc.result_get_length(res);
	out := make([]u8, length);
	c_out := shaderc.result_get_bytes(res);

  copy(raw_data(out), c_out);
	os.write_entire_file(cmp_path, out);
	
	return out;
}


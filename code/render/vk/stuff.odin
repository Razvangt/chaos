package vk

import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "shared:shaderc"
import "vendor:cgltf" 
import "vendor:sdl3"
import vk "vendor:vulkan"

copy_buffer :: proc(using ctx: ^Context, src, dst: Buffer, size: vk.DeviceSize) -> bool {
	log.debug("vulkan copy_buffer: START")
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = command_pool,
		commandBufferCount = 1,
	}

	cmd_buffer: vk.CommandBuffer
	if res := vk.AllocateCommandBuffers(device, &alloc_info, &cmd_buffer); res != .SUCCESS {
		log.error("vulkan copy_buffer: failed to AllocateMemory")
		return false
	}

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	if res := vk.BeginCommandBuffer(cmd_buffer, &begin_info); res != .SUCCESS {
		log.error("vulkan copy_buffer: failed to BeginCommandBuffer")
		return false
	}

	copy_region := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = size,
	}
	vk.CmdCopyBuffer(cmd_buffer, src.buffer, dst.buffer, 1, &copy_region)
	if res := vk.EndCommandBuffer(cmd_buffer); res != .SUCCESS {
		log.error("vulkan copy_buffer: failed to EndCommandBuffer")
		return false
	}

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd_buffer,
	}

	if res := vk.QueueSubmit(queues[.Graphics], 1, &submit_info, {}); res != .SUCCESS {
		log.error("vulkan copy_buffer: failed to QueueSubmit")
		return false
	}

	if res := vk.QueueWaitIdle(queues[.Graphics]); res != .SUCCESS {
		log.error("vulkan copy_buffer: failed to QueueWaitIdle")
		return false
	}
	vk.FreeCommandBuffers(device, command_pool, 1, &cmd_buffer)

	log.debug("vulkan copy_buffer: SUCCESSFULL")
	return true
}

create_buffer :: proc(
	using ctx: ^Context,
	member_size: int,
	count: int,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	buffer: ^Buffer,
) -> (
	ok: bool,
) {
	log.debug("vulkan create_buffer: START")
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = cast(vk.DeviceSize)(member_size * count),
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	if res := vk.CreateBuffer(device, &buffer_info, nil, &buffer.buffer); res != .SUCCESS {
		log.debug("vulkan create_buffer: failed create_buffer")
		return false
	}

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer.buffer, &mem_requirements)

	mty := find_memory_type(ctx, mem_requirements.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT}) or_return

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = mty,
	}

	if res := vk.AllocateMemory(device, &alloc_info, nil, &buffer.memory); res != .SUCCESS {
		log.debug("vulkan create_buffer: failed AllocateMemory")
		return false
	}

	if res := vk.BindBufferMemory(device, buffer.buffer, buffer.memory, 0); res != .SUCCESS {
		log.debug("vulkan create_buffer: failed to BindBufferMemory")
		return false
	}

	log.debug("vulkan create_buffer: SUCCESSFULL")
	return true
}


byte_to_cstring :: proc(name: [256]u8) -> cstring {
	bytes := name
	builder := strings.clone_from_bytes(bytes[:])
	return strings.clone_to_cstring(builder)
}


get_suitable_device :: proc(using ctx: ^Context) -> (ok: bool) {
	log.debug("vulkan get_suitable_device: START")
	device_count: u32

	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 {
		log.error("vulkan get_suitable_device: failed to find GPU with vulkan support")
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
		log.error("vulkan get_suitable_device: failed to find a suitable GPU")
		return false
	}

	log.debug("vulkan get_suitable_device: SUCCESSFULL")
	return true
}

get_extensions :: proc() -> []vk.ExtensionProperties {
	n_ext: u32
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil)
	extensions := make([]vk.ExtensionProperties, n_ext)
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extensions))
	return extensions
}


is_validation_layer_support_on :: proc() -> b32 {
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


find_memory_type :: proc(using ctx: ^Context, type_filter: u32, properties: vk.MemoryPropertyFlags) -> (content: u32, ok: bool) {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_properties)
	for i in 0 ..< mem_properties.memoryTypeCount {
		if (type_filter & (1 << i) != 0) && (mem_properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i, true
		}
	}


	log.error("vulkan find_memory_type: Failed to find suitable memory type!\n")
	return 0, false
}

find_supported_format :: proc(
	using ctx: ^Context,
	candidates: []vk.Format,
	tiling: vk.ImageTiling,
	features: vk.FormatFeatureFlags,
) -> vk.Format {
	for format in candidates {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &props)
		if (tiling == .LINEAR && (props.linearTilingFeatures & features) == features) {
			return format
		} else if (tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features) {
			return format
		}
	}
	return nil
}

find_dept_format :: proc(using ctx: ^Context) -> vk.Format {
	return find_supported_format(ctx, {.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
}


get_mssa_samples :: proc(using ctx: ^Context) {
	physical_properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &physical_properties)
	counts := physical_properties.limits.framebufferColorSampleCounts & physical_properties.limits.framebufferDepthSampleCounts
	switch {
	case ._64 in counts:
		ctx.mssa_samples = {._64}
	case ._32 in counts:
		ctx.mssa_samples = {._32}
	case ._16 in counts:
		ctx.mssa_samples = {._16}
	case ._8 in counts:
		ctx.mssa_samples = {._8}
	case ._4 in counts:
		ctx.mssa_samples = {._4}
	case ._2 in counts:
		ctx.mssa_samples = {._2}
	case:
		ctx.mssa_samples = {._1}
	}
}


begin_single_time_commands :: proc(using ctx: ^Context) -> (commandBuffer: vk.CommandBuffer, ok: bool) {
	log.debug("vulkan begin_single_time_commands: START")
	allocInfo: vk.CommandBufferAllocateInfo
	allocInfo.sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO
	allocInfo.level = vk.CommandBufferLevel.PRIMARY
	allocInfo.commandPool = command_pool
	allocInfo.commandBufferCount = 1

	if res := vk.AllocateCommandBuffers(device, &allocInfo, &commandBuffer); res != .SUCCESS {
		log.error("vulkan begin_single_time_commands: failed to AllocateCommandBuffers")
		return commandBuffer, false
	}

	beginInfo: vk.CommandBufferBeginInfo
	beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
	beginInfo.flags = {.ONE_TIME_SUBMIT}

	if res := vk.BeginCommandBuffer(commandBuffer, &beginInfo); res != .SUCCESS {
		log.error("vulkan begin_single_time_commands: failed  BeginCommandBuffer")
		return commandBuffer, false
	}

	log.debug("vulkan begin_single_time_commands: SUCCESSFULL")
	return commandBuffer, true
}


end_single_time_commands :: proc(ctx: ^Context, command_buffer: ^vk.CommandBuffer) -> bool {
	log.debug("vulkan end_single_time_commands: START")
	if res := vk.EndCommandBuffer(command_buffer^); res != .SUCCESS {
		log.error("vulkan end_single_time_commands: failed on EndCommandBuffer")
		return false
	}

	submit_info: vk.SubmitInfo
	submit_info.sType = .SUBMIT_INFO
	submit_info.commandBufferCount = 1
	submit_info.pCommandBuffers = command_buffer

	// so a VK_NULL_HANDLE is  a  initialized  struct with no value  LOL 
	if res := vk.QueueSubmit(ctx.queues[QueueFamily.Graphics], 1, &submit_info, vk.Fence{}); res != .SUCCESS {
		log.error("vulkan end_single_time_commands: failed on QueueSubmit")
		return false
	}
	if res := vk.QueueWaitIdle(ctx.queues[QueueFamily.Graphics]); res != .SUCCESS {
		log.error("vulkan end_single_time_commands: failed on QueueWaitIdle")
		return false
	}

	vk.FreeCommandBuffers(ctx.device, ctx.command_pool, 1, command_buffer)

	log.debug("vulkan end_single_time_commands: SUCCESSFULL")
	return true
}


copy_buffer_to_image :: proc(ctx: ^Context, buffer: ^Buffer, image: vk.Image, width, height: u32) -> bool {
	log.debug("vulkan copy_buffer_to_image: START")
	command_buffer: vk.CommandBuffer = begin_single_time_commands(ctx) or_return
	region: vk.BufferImageCopy
	region.bufferOffset = 0
	region.bufferRowLength = 0
	region.bufferImageHeight = 0

	region.imageSubresource.aspectMask = {.COLOR}
	region.imageSubresource.mipLevel = 0
	region.imageSubresource.baseArrayLayer = 0
	region.imageSubresource.layerCount = 1

	region.imageOffset = {0, 0, 0}
	region.imageExtent = {width, height, 1}

	vk.CmdCopyBufferToImage(command_buffer, buffer.buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)
	end_single_time_commands(ctx, &command_buffer) or_return
	log.debug("vulkan copy_buffer_to_image: SUCCESSFULL")
	return true
}


load_model :: proc(ctx: ^Context, path: cstring) -> bool {
	log.debug("vulkan load_model: START")
	options: cgltf.options = {}
	data, res := cgltf.parse_file(options, path)
	if (res != .success) {
		log.error("vulkan load_model: failed to parse file")
		return false
	}
	defer cgltf.free(data)
  

	log.info("Loaded gltf file: %s\n", path)
	log.info("Number of meshes : %s\n", path)

	for mesh_index in 0 ..< int(len(data.meshes)) {
		mesh := &data.meshes[mesh_index]
		log.debug("Mesh: %s", mesh.primitives)
	}

	log.debug("vulkan load_model: SUCCESSFULL")
	return true
}

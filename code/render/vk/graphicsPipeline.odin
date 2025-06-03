package vk

import "core:c"
import "core:log"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "shared:shaderc"
import "vendor:sdl3"
import vk "vendor:vulkan"


create_graphics_pipeline :: proc(using ctx: ^Context, vs_name: string, fs_name: string) -> bool {
  log.debug("vulkan create_graphics_pipeline: START")
	vs_code := compile_shader(vs_name, .VertexShader) or_return
	defer delete(vs_code)

	fs_code := compile_shader(fs_name, .FragmentShader) or_return
	defer delete(fs_code)


	vs_shader := create_shader_module(ctx, vs_code) or_return
	defer vk.DestroyShaderModule(device, vs_shader, nil)

	fs_shader := create_shader_module(ctx, fs_code) or_return
	defer vk.DestroyShaderModule(device, fs_shader, nil)


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

	// Not used 
	viewport: vk.Viewport
	viewport.x = 0.0
	viewport.y = 0.0
	viewport.width = cast(f32)swap_chain.extent.width
	viewport.height = cast(f32)swap_chain.extent.height
	viewport.minDepth = 0.0
	viewport.maxDepth = 1.0

	// Not USED ???
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
	multisampling.rasterizationSamples = mssa_samples
	multisampling.sampleShadingEnable = true
	multisampling.minSampleShading = .2
	multisampling.pSampleMask = nil
	multisampling.alphaToCoverageEnable = false
	multisampling.alphaToOneEnable = false

	color_blend_attachment: vk.PipelineColorBlendAttachmentState
	color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	color_blend_attachment.blendEnable = false
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


	create_descriptor_layout(ctx) or_return

	pipeline_layout_info: vk.PipelineLayoutCreateInfo
	pipeline_layout_info.sType = .PIPELINE_LAYOUT_CREATE_INFO
	pipeline_layout_info.setLayoutCount = 1
	pipeline_layout_info.pSetLayouts = &pipeline.descriptor_set_layout
	pipeline_layout_info.pushConstantRangeCount = 0
	pipeline_layout_info.pPushConstantRanges = nil

	if res := vk.CreatePipelineLayout(device, &pipeline_layout_info, nil, &pipeline.layout); res != .SUCCESS {
		log.error("vulkan create_graphics_pipeline: Failed CreatePipelineLayout")
		return false
	}

	create_render_pass(ctx) or_return

	depth_stencil: vk.PipelineDepthStencilStateCreateInfo
	depth_stencil.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
	depth_stencil.depthTestEnable = true
	depth_stencil.depthWriteEnable = true
	depth_stencil.depthCompareOp = .LESS
	depth_stencil.depthBoundsTestEnable = false
	depth_stencil.minDepthBounds = 0
	depth_stencil.maxDepthBounds = 1
	depth_stencil.stencilTestEnable = false
	depth_stencil.front = {}
	depth_stencil.back = {}

	pipeline_info: vk.GraphicsPipelineCreateInfo
	pipeline_info.sType = .GRAPHICS_PIPELINE_CREATE_INFO
	pipeline_info.stageCount = 2
	pipeline_info.pStages = &shader_stages[0]
	pipeline_info.pVertexInputState = &vertex_input
	pipeline_info.pInputAssemblyState = &input_assembly
	pipeline_info.pViewportState = &viewport_state
	pipeline_info.pRasterizationState = &rasterizer
	pipeline_info.pMultisampleState = &multisampling
	pipeline_info.pDepthStencilState = &depth_stencil
	pipeline_info.pColorBlendState = &color_blending
	pipeline_info.pDynamicState = &dynamic_state
	pipeline_info.layout = pipeline.layout
	pipeline_info.renderPass = pipeline.render_pass
	pipeline_info.subpass = 0
	pipeline_info.basePipelineHandle = vk.Pipeline{}
	pipeline_info.basePipelineIndex = -1

	if res := vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_info, nil, &pipeline.handle); res != .SUCCESS {
		fmt.eprintf("vulkan create_graphics_pipeline:Failed CreateGraphicsPipelines")
		return false
	}

  log.debug("vulkan create_graphics_pipeline: SUCCESSFULL")
	return true
}

compile_shader :: proc(name: string, kind: shaderc.shaderKind) -> (content: []u8, ok: bool) {
  log.debugf("vulkan compile_shader START :",name)
	src_path := fmt.tprintf("./res/shaders/%s", name)
	cmp_path := fmt.tprintf("./res/shaders/compiled/%s.spv", name)
	src_time, src_err := os.last_write_time_by_name(src_path)
	if (src_err != os.ERROR_NONE) {
		log.errorf("Failed to open shader %q\n", src_path)
		return nil, false
	}

	cmp_time, cmp_err := os.last_write_time_by_name(cmp_path)
	if cmp_err == os.ERROR_NONE && cmp_time >= src_time {
		code, _ := os.read_entire_file(cmp_path)
		return code, true
	}


	comp := shaderc.compiler_initialize()
	options := shaderc.compile_options_initialize()
	defer 
	{
		shaderc.compiler_release(comp)
		shaderc.compile_options_release(options)
	}

	shaderc.compile_options_set_optimization_level(options, .Performance)

	code, _ := os.read_entire_file(src_path)
	c_path := strings.clone_to_cstring(src_path, context.temp_allocator)

	res := shaderc.compile_into_spv(comp, cstring(raw_data(code)), len(code), kind, c_path, cstring("main"), options)
	defer shaderc.result_release(res)

	status := shaderc.result_get_compilation_status(res)
	if status != .Success {
		log.errorf("%s: Error: %s\n", name, shaderc.result_get_error_message(res))
		return nil, false
	}

	length := shaderc.result_get_length(res)
	out := make([]u8, length)
	c_out := shaderc.result_get_bytes(res)
	mem.copy(raw_data(out), c_out, int(length))
	os.write_entire_file(cmp_path, out)

  log.debugf("vulkan compile_shader SUCCESSFULL :",name)
	return out, true
}

create_descriptor_layout :: proc(using ctx: ^Context) -> (ok: bool) {
  log.debug("vulkan create_descriptor_layout: START")
	ubo_layout: vk.DescriptorSetLayoutBinding
	ubo_layout.binding = 0
	ubo_layout.descriptorCount = 1
	ubo_layout.descriptorType = vk.DescriptorType.UNIFORM_BUFFER
	ubo_layout.pImmutableSamplers = nil
	/// was it just this ???? DEBUG for sure 
	ubo_layout.stageFlags = {.VERTEX}

	sampler_layout: vk.DescriptorSetLayoutBinding
	sampler_layout.binding = 1
	sampler_layout.descriptorCount = 1
	sampler_layout.descriptorType = .COMBINED_IMAGE_SAMPLER
	sampler_layout.pImmutableSamplers = nil
	sampler_layout.stageFlags = {.FRAGMENT}

	bindings := [?]vk.DescriptorSetLayoutBinding{ubo_layout, sampler_layout}

	layout_info: vk.DescriptorSetLayoutCreateInfo
	layout_info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
	layout_info.bindingCount = len(bindings)
	layout_info.pBindings = &bindings[0]
	if res := vk.CreateDescriptorSetLayout(device, &layout_info, nil, &pipeline.descriptor_set_layout); res != .SUCCESS {
    log.error("vulkan create_descriptor_layout: failed CreateDescriptorSetLayout")
		return false
	}
  log.debug("vulkan create_descriptor_layout: SUCCESSFULL")
	return true
}


create_render_pass :: proc(using ctx: ^Context) -> (ok: bool) {
  log.debug("vulkan create_render_pass: START")

	// COLOR ATTACHMENT
	color_attachment: vk.AttachmentDescription
	color_attachment.format = swap_chain.format.format
	color_attachment.samples = mssa_samples
	color_attachment.loadOp = .CLEAR
	color_attachment.storeOp = .STORE
	color_attachment.stencilLoadOp = .DONT_CARE
	color_attachment.stencilStoreOp = .DONT_CARE
	color_attachment.initialLayout = .UNDEFINED
	color_attachment.finalLayout = .COLOR_ATTACHMENT_OPTIMAL

	// DEPTH ATTACHMENT 
	format := find_dept_format(ctx)
	if format == nil {
    log.error("vulkan create_render_pass: failed to find depth format")
		return false
	}

	depth_attachment: vk.AttachmentDescription
	depth_attachment.format = format
	depth_attachment.samples = mssa_samples
	depth_attachment.loadOp = .CLEAR
	depth_attachment.storeOp = .DONT_CARE
	depth_attachment.stencilLoadOp = .DONT_CARE
	depth_attachment.stencilStoreOp = .DONT_CARE
	depth_attachment.initialLayout = .UNDEFINED
	depth_attachment.finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL

	//COLOR ATTACHMENT RESOLVE 

	color_attachment_resolve: vk.AttachmentDescription
	color_attachment_resolve.format = swap_chain.format.format
	color_attachment_resolve.samples = {._1}
	color_attachment_resolve.loadOp = .DONT_CARE
	color_attachment_resolve.storeOp = .STORE
	color_attachment_resolve.stencilLoadOp = .DONT_CARE
	color_attachment_resolve.stencilStoreOp = .DONT_CARE
	color_attachment_resolve.initialLayout = .UNDEFINED
	color_attachment_resolve.finalLayout = .PRESENT_SRC_KHR

	attachments := [?]vk.AttachmentDescription{color_attachment, depth_attachment, color_attachment_resolve}

	// COLOR ATTACHMENT REF 
	color_attachment_ref: vk.AttachmentReference
	color_attachment_ref.attachment = 0
	color_attachment_ref.layout = .COLOR_ATTACHMENT_OPTIMAL
	// depth Attachment Ref
	depth_attachment_ref: vk.AttachmentReference
	depth_attachment_ref.attachment = 1
	depth_attachment_ref.layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
	// color attachment resolve ref 
	color_attachment_resolve_ref: vk.AttachmentReference
	color_attachment_resolve_ref.attachment = 2
	color_attachment_resolve_ref.layout = .COLOR_ATTACHMENT_OPTIMAL

	//Subpass
	subpass: vk.SubpassDescription
	subpass.pipelineBindPoint = .GRAPHICS
	subpass.colorAttachmentCount = 1
	subpass.pColorAttachments = &color_attachment_ref
	subpass.pDepthStencilAttachment = &depth_attachment_ref
	subpass.pResolveAttachments = &color_attachment_resolve_ref


	dependency: vk.SubpassDependency
	dependency.srcSubpass = vk.SUBPASS_EXTERNAL
	dependency.dstSubpass = 0
	dependency.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS}
	dependency.srcAccessMask = {}
	dependency.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS}
	dependency.dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE}

	render_pass_info: vk.RenderPassCreateInfo
	render_pass_info.sType = .RENDER_PASS_CREATE_INFO
	render_pass_info.attachmentCount = len(attachments)
	render_pass_info.pAttachments = &attachments[0]
	render_pass_info.subpassCount = 1
	render_pass_info.pSubpasses = &subpass
	render_pass_info.dependencyCount = 1
	render_pass_info.pDependencies = &dependency

	if res := vk.CreateRenderPass(device, &render_pass_info, nil, &pipeline.render_pass); res != .SUCCESS {
    log.error("vulkan create_render_pass: failed CreateRenderPass")
		return false
	}
  log.debug("vulkan create_render_pass: SUCCESSFULL")
	return true
}


create_shader_module :: proc(using ctx: ^Context, code: []u8) -> (content: vk.ShaderModule, ok: bool) {
  log.debug("vulkan create_shader_module: START")
	create_info: vk.ShaderModuleCreateInfo
	create_info.sType = .SHADER_MODULE_CREATE_INFO
	create_info.codeSize = len(code)
	create_info.pCode = cast(^u32)raw_data(code)

	if res := vk.CreateShaderModule(device, &create_info, nil, &content); res != .SUCCESS {
    log.debug("vulkan create_shader_module: failed CreateShaderModule")
		return content, false
	}

  log.debug("vulkan create_shader_module: SUCCESSFULL")
	return content, true
}

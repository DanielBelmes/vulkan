{.experimental: "codeReordering".}
import std/options
import glfw
import sets
import bitops
import vulkan
from errors import RuntimeException
import types
from utils import cStringToString

const
    validationLayers = ["VK_LAYER_KHRONOS_validation"]
    vkInstanceExtensions = [VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME]
    deviceExtensions = [VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME,VK_KHR_SWAPCHAIN_EXTENSION_NAME]
    WIDTH* = 800
    HEIGHT* = 600
    MAX_FRAMES_IN_FLIGHT: uint32 = 2

when not defined(release):
    const enableValidationLayers = true
else:
    const enableValidationLayers = false

type
    VulkanTriangleApp* = ref object
        instance: VkInstance
        window: GLFWWindow
        surface: VkSurfaceKHR
        physicalDevice: VkPhysicalDevice
        graphicsQueue: VkQueue
        presentQueue: VkQueue
        device: VkDevice
        swapChain: VkSwapchainKHR
        swapChainImages: seq[VkImage]
        swapChainImageFormat: VkFormat
        swapChainExtent: VkExtent2D
        swapChainImageViews: seq[VkImageView]
        pipelineLayout: VkPipelineLayout
        renderPass: VkRenderPass
        graphicsPipeline: VkPipeline
        swapChainFramebuffers: seq[VkFramebuffer]
        commandPool: VkCommandPool
        commandBuffers: seq[VkCommandBuffer]
        imageAvailableSemaphores: seq[VkSemaphore]
        renderFinishedSemaphores: seq[VkSemaphore]
        inFlightFences: seq[VkFence]
        currentFrame: uint32
        framebufferResized: bool

proc initWindow(self: VulkanTriangleApp) =
    doAssert glfwInit()
    doAssert glfwVulkanSupported()

    glfwWindowHint(GLFWClientApi, GLFWNoApi)

    self.window = glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", nil, nil, icon = false)
    if self.window == nil:
        quit(-1)
    setWindowUserPointer(self.window, unsafeAddr self);
    discard setFramebufferSizeCallback(self.window, cast[GLFWFramebuffersizeFun](framebufferResizeCallback))

proc framebufferResizeCallback(window: GLFWWindow, width: int, height: int) {.cdecl.} =
    let app = cast[ptr VulkanTriangleApp](getWindowUserPointer(window))
    app.framebufferResized = true

proc checkValidationLayerSupport(): bool =
    var layerCount: uint32
    discard vkEnumerateInstanceLayerProperties(addr layerCount, nil)

    var availableLayers = newSeq[VkLayerProperties](layerCount)
    discard vkEnumerateInstanceLayerProperties(addr layerCount, addr availableLayers[0])

    for layerName in validationLayers:
        var layerFound: bool = false
        for layerProperties in availableLayers:
            if cmp(layerName, cStringToString(layerProperties.layerName)) == 0:
                layerFound = true
                break

        if not layerFound:
            return false

    return true

proc createInstance(self: VulkanTriangleApp) =
    var appInfo = newVkApplicationInfo(
        pApplicationName = "NimGL Vulkan Example",
        applicationVersion = vkMakeVersion(1, 0, 0),
        pEngineName = "No Engine",
        engineVersion = vkMakeVersion(1, 0, 0),
        apiVersion = VK_API_VERSION_1_1
    )

    var glfwExtensionCount: uint32 = 0
    var glfwExtensions: cstringArray

    glfwExtensions = glfwGetRequiredInstanceExtensions(addr glfwExtensionCount)
    var extensions: seq[string]
    for ext in cstringArrayToSeq(glfwExtensions, glfwExtensionCount):
        extensions.add(ext)
    for ext in vkInstanceExtensions:
        extensions.add(ext)
    var allExtensions = allocCStringArray(extensions)


    var layerCount: uint32 = 0
    var enabledLayers: cstringArray = nil

    if enableValidationLayers:
        layerCount = uint32(validationLayers.len)
        enabledLayers = allocCStringArray(validationLayers)

    var createInfo = newVkInstanceCreateInfo(
        flags = VkInstanceCreateFlags(0x0000001),
        pApplicationInfo = addr appInfo,
        enabledExtensionCount = glfwExtensionCount + uint32(vkInstanceExtensions.len),
        ppEnabledExtensionNames = allExtensions,
        enabledLayerCount = layerCount,
        ppEnabledLayerNames = enabledLayers,
    )

    if enableValidationLayers and not checkValidationLayerSupport():
        raise newException(RuntimeException, "validation layers requested, but not available!")

    if vkCreateInstance(addr createInfo, nil, addr self.instance) != VKSuccess:
        quit("failed to create instance")

    if enableValidationLayers and not enabledLayers.isNil:
        deallocCStringArray(enabledLayers)

    if not allExtensions.isNil:
        deallocCStringArray(allExtensions)

proc createSurface(self: VulkanTriangleApp) =
    if glfwCreateWindowSurface(self.instance, self.window, nil, addr self.surface) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to create window surface")

proc checkDeviceExtensionSupport(self: VulkanTriangleApp, pDevice: VkPhysicalDevice): bool =
    var extensionCount: uint32
    discard vkEnumerateDeviceExtensionProperties(pDevice, nil, addr extensionCount, nil)
    var availableExtensions: seq[VkExtensionProperties] = newSeq[VkExtensionProperties](extensionCount)
    discard vkEnumerateDeviceExtensionProperties(pDevice, nil, addr extensionCount, addr availableExtensions[0])
    var requiredExtensions: HashSet[string] = deviceExtensions.toHashSet

    for extension in availableExtensions.mitems:
        requiredExtensions.excl(extension.extensionName.cStringToString)
    return requiredExtensions.len == 0

proc querySwapChainSupport(self: VulkanTriangleApp, pDevice: VkPhysicalDevice): SwapChainSupportDetails =
    discard vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pDevice,self.surface,addr result.capabilities)
    var formatCount: uint32
    discard vkGetPhysicalDeviceSurfaceFormatsKHR(pDevice, self.surface, addr formatCount, nil)

    if formatCount != 0:
        result.formats.setLen(formatCount)
        discard vkGetPhysicalDeviceSurfaceFormatsKHR(pDevice, self.surface, formatCount.addr, result.formats[0].addr)
    var presentModeCount: uint32
    discard vkGetPhysicalDeviceSurfacePresentModesKHR(pDevice, self.surface, presentModeCount.addr, nil)
    if presentModeCount != 0:
        result.presentModes.setLen(presentModeCount)
        discard vkGetPhysicalDeviceSurfacePresentModesKHR(pDevice, self.surface, presentModeCount.addr, result.presentModes[0].addr)

proc chooseSwapSurfaceFormat(self: VulkanTriangleApp, availableFormats: seq[VkSurfaceFormatKHR]): VkSurfaceFormatKHR =
    for format in availableFormats:
        if format.format == VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
            return format
    return availableFormats[0]

proc chooseSwapPresnetMode(self: VulkanTriangleApp, availablePresentModes: seq[VkPresentModeKHR]): VkPresentModeKHR =
    for presentMode in availablePresentModes:
        if presentMode == VK_PRESENT_MODE_MAILBOX_KHR:
            return presentMode
    return VK_PRESENT_MODE_FIFO_KHR

proc chooseSwapExtent(self: VulkanTriangleApp, capabilities: VkSurfaceCapabilitiesKHR): VkExtent2D =
    if capabilities.currentExtent.width != uint32.high:
        return capabilities.currentExtent
    else:
        var width: int32
        var height: int32
        getFramebufferSize(self.window, addr width, addr height)
        result.width = clamp(cast[uint32](width),
                                capabilities.minImageExtent.width,
                                capabilities.maxImageExtent.width)
        result.height = clamp(cast[uint32](height),
                                capabilities.minImageExtent.height,
                                capabilities.maxImageExtent.height)

proc findQueueFamilies(self: VulkanTriangleApp, pDevice: VkPhysicalDevice): QueueFamilyIndices =
    var queueFamilyCount: uint32 = 0
    vkGetPhysicalDeviceQueueFamilyProperties(pDevice, addr queueFamilyCount, nil)
    var queueFamilies: seq[VkQueueFamilyProperties] = newSeq[VkQueueFamilyProperties](queueFamilyCount) # [TODO] this pattern can be templated
    vkGetPhysicalDeviceQueueFamilyProperties(pDevice, addr queueFamilyCount, addr queueFamilies[0])
    var index: uint32 = 0
    for queueFamily in queueFamilies:
        if (queueFamily.queueFlags.uint32 and VkQueueGraphicsBit.uint32) > 0'u32:
            result.graphicsFamily = some(index)
        var presentSupport: VkBool32 = VkBool32(VK_FALSE)
        discard vkGetPhysicalDeviceSurfaceSupportKHR(pDevice, index, self.surface, addr presentSupport)
        if presentSupport.ord == 1:
            result.presentFamily = some(index)

        if(result.isComplete()):
            break
        index.inc

proc isDeviceSuitable(self: VulkanTriangleApp, pDevice: VkPhysicalDevice): bool =
    var deviceProperties: VkPhysicalDeviceProperties
    vkGetPhysicalDeviceProperties(pDevice, deviceProperties.addr)
    var indicies: QueueFamilyIndices = self.findQueueFamilies(pDevice)
    var extensionsSupported = self.checkDeviceExtensionSupport(pDevice)
    var swapChainAdequate = false
    if extensionsSupported:
        var swapChainSupport: SwapChainSupportDetails = self.querySwapChainSupport(pDevice)
        swapChainAdequate = swapChainSupport.formats.len != 0 and swapChainSupport.presentModes.len != 0
    return indicies.isComplete and extensionsSupported and swapChainAdequate

proc pickPhysicalDevice(self: VulkanTriangleApp) =
    var deviceCount: uint32 = 0
    discard vkEnumeratePhysicalDevices(self.instance, addr deviceCount, nil)
    if(deviceCount == 0):
        raise newException(RuntimeException, "failed to find GPUs with Vulkan support!")
    var pDevices: seq[VkPhysicalDevice] = newSeq[VkPhysicalDevice](deviceCount)
    discard vkEnumeratePhysicalDevices(self.instance, addr deviceCount, addr pDevices[0])
    for pDevice in pDevices:
        if self.isDeviceSuitable(pDevice):
            self.physicalDevice = pDevice
            return

    raise newException(RuntimeException, "failed to find a suitable GPU!")

proc createLogicalDevice(self: VulkanTriangleApp) =
    let
        indices = self.findQueueFamilies(self.physicalDevice)
        uniqueQueueFamilies = [indices.graphicsFamily.get, indices.presentFamily.get].toHashSet
    var
        queuePriority = 1f
        queueCreateInfos = newSeq[VkDeviceQueueCreateInfo]()

    for queueFamily in uniqueQueueFamilies:
        let deviceQueueCreateInfo: VkDeviceQueueCreateInfo = newVkDeviceQueueCreateInfo(
            queueFamilyIndex = queueFamily,
            queueCount = 1,
            pQueuePriorities = queuePriority.addr
        )
        queueCreateInfos.add(deviceQueueCreateInfo)

    var
        deviceFeatures = newSeq[VkPhysicalDeviceFeatures](1)
        deviceExts = allocCStringArray(deviceExtensions)
        deviceCreateInfo = newVkDeviceCreateInfo(
            pQueueCreateInfos = queueCreateInfos[0].addr,
            queueCreateInfoCount = queueCreateInfos.len.uint32,
            pEnabledFeatures = deviceFeatures[0].addr,
            enabledExtensionCount = deviceExtensions.len.uint32,
            enabledLayerCount = 0,
            ppEnabledLayerNames = nil,
            ppEnabledExtensionNames = deviceExts
        )

    if vkCreateDevice(self.physicalDevice, deviceCreateInfo.addr, nil, self.device.addr) != VKSuccess:
        echo "failed to create logical device"

    if not deviceExts.isNil:
        deallocCStringArray(deviceExts)

    vkGetDeviceQueue(self.device, indices.graphicsFamily.get, 0, addr self.graphicsQueue)
    vkGetDeviceQueue(self.device, indices.presentFamily.get, 0, addr self.presentQueue)


proc createSwapChain(self: VulkanTriangleApp) =
    let swapChainSupport: SwapChainSupportDetails = self.querySwapChainSupport(self.physicalDevice)

    let surfaceFormat: VkSurfaceFormatKHR = self.chooseSwapSurfaceFormat(swapChainSupport.formats)
    let presentMode: VkPresentModeKHR = self.chooseSwapPresnetMode(swapChainSupport.presentModes)
    let extent: VkExtent2D = self.chooseSwapExtent(swapChainSupport.capabilities)

    var imageCount: uint32 = swapChainSupport.capabilities.minImageCount + 1 # request one extra per recommended settings

    if swapChainSupport.capabilities.maxImageCount > 0 and imageCount > swapChainSupport.capabilities.maxImageCount:
        imageCount = swapChainSupport.capabilities.maxImageCount

    var createInfo = VkSwapchainCreateInfoKHR(
        sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        surface: self.surface,
        minImageCount: imageCount,
        imageFormat: surfaceFormat.format,
        imageColorSpace: surfaceFormat.colorSpace,
        imageExtent: extent,
        imageArrayLayers: 1,
        imageUsage: VkImageUsageFlags(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT),
        preTransform: swapChainSupport.capabilities.currentTransform,
        compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        presentMode: presentMode,
        clipped: VKBool32(VK_TRUE),
        oldSwapchain: VkSwapchainKHR(VK_NULL_HANDLE)
    )
    let indices = self.findQueueFamilies(self.physicalDevice)
    var queueFamilyIndicies = [indices.graphicsFamily.get, indices.presentFamily.get]

    if indices.graphicsFamily.get != indices.presentFamily.get:
        createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT
        createInfo.queueFamilyIndexCount = 2
        createInfo.pQueueFamilyIndices = queueFamilyIndicies[0].addr
    else:
        createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE
        createInfo.queueFamilyIndexCount = 0
        createInfo.pQueueFamilyIndices = nil

    if vkCreateSwapchainKHR(self.device, addr createInfo, nil, addr self.swapChain) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to create swap chain!")
    discard vkGetSwapchainImagesKHR(self.device, self.swapChain, addr imageCount, nil)
    self.swapChainImages.setLen(imageCount)
    discard vkGetSwapchainImagesKHR(self.device, self.swapChain, addr imageCount, addr self.swapChainImages[0])
    self.swapChainImageFormat = surfaceFormat.format
    self.swapChainExtent = extent

proc createImageViews(self: VulkanTriangleApp) =
    self.swapChainImageViews.setLen(self.swapChainImages.len)
    for index, swapChainImage in self.swapChainImages:
        var createInfo = newVkImageViewCreateInfo(
            image = swapChainImage,
            viewType = VK_IMAGE_VIEW_TYPE_2D,
            format = self.swapChainImageFormat,
            components = newVkComponentMapping(VK_COMPONENT_SWIZZLE_IDENTITY,VK_COMPONENT_SWIZZLE_IDENTITY,VK_COMPONENT_SWIZZLE_IDENTITY,VK_COMPONENT_SWIZZLE_IDENTITY),
            subresourceRange = newVkImageSubresourceRange(aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT), 0.uint32, 1.uint32, 0.uint32, 1.uint32)
        )
        if vkCreateImageView(self.device, addr createInfo, nil, addr self.swapChainImageViews[index]) != VK_SUCCESS:
            raise newException(RuntimeException, "failed to create image views")

proc createShaderModule(self: VulkanTriangleApp, code: string) : VkShaderModule =
    var createInfo = newVkShaderModuleCreateInfo(
        codeSize = code.len.uint32,
        pCode = cast[ptr uint32](code[0].unsafeAddr) #Hopefully reading bytecode as string is alright
    )
    if vkCreateShaderModule(self.device, addr createInfo, nil, addr result) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to create shader module")

proc createRenderPass(self: VulkanTriangleApp) =
    var
        colorAttachment: VkAttachmentDescription = newVkAttachmentDescription(
            format = self.swapChainImageFormat,
            samples = VK_SAMPLE_COUNT_1_BIT,
            loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
            storeOp = VK_ATTACHMENT_STORE_OP_STORE,
            stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        )
        colorAttachmentRef: VkAttachmentReference = newVkAttachmentReference(
            attachment = 0,
            layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        )
        subpass = VkSubpassDescription(
            pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
            colorAttachmentCount: 1,
            pColorAttachments: addr colorAttachmentRef,
        )
        dependency: VkSubpassDependency = VkSubpassDependency(
            srcSubpass: VK_SUBPASS_EXTERNAL,
            dstSubpass: 0,
            srcStageMask: VkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            srcAccessMask: VkAccessFlags(0),
            dstStageMask: VkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            dstAccessMask: VkAccessFlags(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT),
        )
        renderPassInfo: VkRenderPassCreateInfo = newVkRenderPassCreateInfo(
            attachmentCount = 1,
            pAttachments = addr colorAttachment,
            subpassCount = 1,
            pSubpasses = addr subpass,
            dependencyCount = 1,
            pDependencies = addr dependency,
        )
    if vkCreateRenderPass(self.device, addr renderPassInfo, nil, addr self.renderPass) != VK_SUCCESS:
        quit("failed to create render pass")

proc createGraphicsPipeline(self: VulkanTriangleApp) =
    const
        vertShaderCode: string = staticRead("./shaders/vert.spv")
        fragShaderCode: string = staticRead("./shaders/frag.spv")
    var
        vertShaderModule: VkShaderModule = self.createShaderModule(vertShaderCode)
        fragShaderModule: VkShaderModule = self.createShaderModule(fragShaderCode)
        vertShaderStageInfo: VkPipelineShaderStageCreateInfo = newVkPipelineShaderStageCreateInfo(
            stage = VK_SHADER_STAGE_VERTEX_BIT,
            module = vertShaderModule,
            pName = "main",
            pSpecializationInfo = nil
        )
        fragShaderStageInfo: VkPipelineShaderStageCreateInfo = newVkPipelineShaderStageCreateInfo(
            stage = VK_SHADER_STAGE_FRAGMENT_BIT,
            module = fragShaderModule,
            pName = "main",
            pSpecializationInfo = nil
        )
        shaderStages: array[2, VkPipelineShaderStageCreateInfo] = [vertShaderStageInfo, fragShaderStageInfo]
        dynamicStates: array[2, VkDynamicState] = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR]
        dynamicState: VkPipelineDynamicStateCreateInfo = newVkPipelineDynamicStateCreateInfo(
            dynamicStateCount = dynamicStates.len.uint32,
            pDynamicStates = addr dynamicStates[0]
        )
        vertexInputInfo: VkPipelineVertexInputStateCreateInfo = newVkPipelineVertexInputStateCreateInfo(
            vertexBindingDescriptionCount = 0,
            pVertexBindingDescriptions = nil,
            vertexAttributeDescriptionCount = 0,
            pVertexAttributeDescriptions = nil
        )
        inputAssembly: VkPipelineInputAssemblyStateCreateInfo = newVkPipelineInputAssemblyStateCreateInfo(
            topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable = VkBool32(VK_FALSE)
        )
        viewport: VkViewPort = newVkViewport(
            x = 0.float,
            y = 0.float,
            width = self.swapChainExtent.width.float32,
            height = self.swapChainExtent.height.float32,
            minDepth = 0.float,
            maxDepth = 1.float
        )
        scissor: VkRect2D = newVkRect2D(
            offset = newVkOffset2D(0,0),
            extent = self.swapChainExtent
        )
        viewportState: VkPipelineViewportStateCreateInfo = newVkPipelineViewportStateCreateInfo(
            viewportCount = 1,
            pViewports = addr viewport,
            scissorCount = 1,
            pScissors = addr scissor
        )
        rasterizer: VkPipelineRasterizationStateCreateInfo = newVkPipelineRasterizationStateCreateInfo(
            depthClampEnable = VkBool32(VK_FALSE),
            rasterizerDiscardEnable = VkBool32(VK_FALSE),
            polygonMode = VK_POLYGON_MODE_FILL,
            lineWidth = 1.float,
            cullMode = VkCullModeFlags(VK_CULL_MODE_BACK_BIT),
            frontface = VK_FRONT_FACE_CLOCKWISE,
            depthBiasEnable = VKBool32(VK_FALSE),
            depthBiasConstantFactor = 0.float,
            depthBiasClamp = 0.float,
            depthBiasSlopeFactor = 0.float,
        )
        multisampling: VkPipelineMultisampleStateCreateInfo = newVkPipelineMultisampleStateCreateInfo(
            sampleShadingEnable = VkBool32(VK_FALSE),
            rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
            minSampleShading = 1.float,
            pSampleMask = nil,
            alphaToCoverageEnable = VkBool32(VK_FALSE),
            alphaToOneEnable = VkBool32(VK_FALSE)
        )
        # [NOTE] Not doing VkPipelineDepthStencilStateCreateInfo because we don't have a depth or stencil buffer yet
        colorBlendAttachment: VkPipelineColorBlendAttachmentState = newVkPipelineColorBlendAttachmentState(
            colorWriteMask = VkColorComponentFlags(bitor(VK_COLOR_COMPONENT_R_BIT.int32, bitor(VK_COLOR_COMPONENT_G_BIT.int32, bitor(VK_COLOR_COMPONENT_B_BIT.int32, VK_COLOR_COMPONENT_A_BIT.int32)))),
            blendEnable = VkBool32(VK_FALSE),
            srcColorBlendFactor = VK_BLEND_FACTOR_ONE, # optional
            dstColorBlendFactor = VK_BLEND_FACTOR_ZERO, # optional
            colorBlendOp = VK_BLEND_OP_ADD, # optional
            srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE, # optional
            dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO, # optional
            alphaBlendOp = VK_BLEND_OP_ADD, # optional
        )
        colorBlending: VkPipelineColorBlendStateCreateInfo = newVkPipelineColorBlendStateCreateInfo(
            logicOpEnable = VkBool32(VK_FALSE),
            logicOp = VK_LOGIC_OP_COPY, # optional
            attachmentCount = 1,
            pAttachments = colorBlendAttachment.addr,
            blendConstants = [0f, 0f, 0f, 0f], # optional
        )
        pipelineLayoutInfo: VkPipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
            setLayoutCount = 0, # optional
            pSetLayouts = nil, # optional
            pushConstantRangeCount = 0, # optional
            pPushConstantRanges = nil, # optional
        )
    if vkCreatePipelineLayout(self.device, pipelineLayoutInfo.addr, nil, addr self.pipelineLayout) != VK_SUCCESS:
        quit("failed to create pipeline layout")
    var
        pipelineInfo: VkGraphicsPipelineCreateInfo = newVkGraphicsPipelineCreateInfo(
            stageCount = shaderStages.len.uint32,
            pStages = shaderStages[0].addr,
            pVertexInputState = vertexInputInfo.addr,
            pInputAssemblyState = inputAssembly.addr,
            pViewportState = viewportState.addr,
            pRasterizationState = rasterizer.addr,
            pMultisampleState = multisampling.addr,
            pDepthStencilState = nil, # optional
            pColorBlendState = colorBlending.addr,
            pDynamicState = dynamicState.addr, # optional
            pTessellationState = nil,
            layout = self.pipelineLayout,
            renderPass = self.renderPass,
            subpass = 0,
            basePipelineHandle = VkPipeline(0), # optional
            basePipelineIndex = -1, # optional
        )
    if vkCreateGraphicsPipelines(self.device, VkPipelineCache(0), 1, pipelineInfo.addr, nil, addr self.graphicsPipeline) != VK_SUCCESS:
        quit("fialed to create graphics pipeline")
    vkDestroyShaderModule(self.device, vertShaderModule, nil)
    vkDestroyShaderModule(self.device, fragShaderModule, nil)

proc createFrameBuffers(self: VulkanTriangleApp) =
    self.swapChainFramebuffers.setLen(self.swapChainImageViews.len)

    for index, view in self.swapChainImageViews:
        var
            attachments = [self.swapChainImageViews[index]]
            framebufferInfo = newVkFramebufferCreateInfo(
                sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                renderPass = self.renderPass,
                attachmentCount = attachments.len.uint32,
                pAttachments = attachments[0].addr,
                width = self.swapChainExtent.width,
                height = self.swapChainExtent.height,
                layers = 1,
            )
        if vkCreateFramebuffer(self.device, framebufferInfo.addr, nil, addr self.swapChainFramebuffers[index]) != VK_SUCCESS:
            quit("failed to create framebuffer")

proc cleanupSwapChain(self: VulkanTriangleApp) =
    for framebuffer in self.swapChainFramebuffers:
        vkDestroyFramebuffer(self.device, framebuffer, nil)
    for imageView in self.swapChainImageViews:
        vkDestroyImageView(self.device, imageView, nil)
    vkDestroySwapchainKHR(self.device, self.swapChain, nil)

proc recreateSwapChain(self: VulkanTriangleApp) =
    var
        width: int32 = 0
        height: int32 = 0
    getFramebufferSize(self.window, addr width, addr height)
    while width == 0 or height == 0:
        getFramebufferSize(self.window, addr width, addr height)
        glfwWaitEvents()
    discard vkDeviceWaitIdle(self.device)

    self.cleanupSwapChain()

    self.createSwapChain()
    self.createImageViews()
    self.createFramebuffers()

proc createCommandPool(self: VulkanTriangleApp) =
    var
        indicies: QueueFamilyIndices = self.findQueueFamilies(self.physicalDevice) # I should just save this info. Does it change?
        poolInfo: VkCommandPoolCreateInfo = newVkCommandPoolCreateInfo(
            flags = VkCommandPoolCreateFlags(VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT),
            queueFamilyIndex = indicies.graphicsFamily.get
        )
    if vkCreateCommandPool(self.device, addr poolInfo, nil, addr self.commandPool) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to create command pool!")

proc createCommandBuffers(self: VulkanTriangleApp) =
    self.commandBuffers.setLen(MAX_FRAMES_IN_FLIGHT)
    var allocInfo: VkCommandBufferAllocateInfo = newVkCommandBufferAllocateInfo(
        commandPool = self.commandPool,
        level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        commandBufferCount = cast[uint32](self.commandBuffers.len)
    )
    if vkAllocateCommandBuffers(self.device, addr allocInfo, addr self.commandBuffers[0]) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to allocate command buffers!")

proc recordCommandBuffer(self: VulkanTriangleApp, commandBuffer: VkCommandBuffer, imageIndex: uint32) =
    var beginInfo: VkCommandBufferBeginInfo = newVkCommandBufferBeginInfo(
        flags = VkCommandBufferUsageFlags(0),
        pInheritanceInfo = nil
    )
    if vkBeginCOmmandBuffer(commandBuffer, addr beginInfo) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to begin recording command buffer!")

    var
        clearColor: VkClearValue = VkClearValue(color: VkClearColorValue(float32: [0f, 0f, 0f, 1f]))
        renderPassInfo: VkRenderPassBeginInfo = newVkRenderPassBeginInfo(
            renderPass = self.renderPass,
            framebuffer = self.swapChainFrameBuffers[imageIndex],
            renderArea = VkRect2D(
                offset: VkOffset2d(x: 0,y: 0),
                extent: self.swapChainExtent
            ),
            clearValueCount = 1,
            pClearValues = addr clearColor
        )
    vkCmdBeginRenderPass(commandBuffer, renderPassInfo.addr, VK_SUBPASS_CONTENTS_INLINE)
    vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphicsPipeline)
    var
        viewport: VkViewport = newVkViewport(
            x = 0f,
            y = 0f,
            width = self.swapChainExtent.width.float32,
            height = self.swapChainExtent.height.float32,
            minDepth = 0f,
            maxDepth = 1f
        )
        scissor: VkRect2D = newVkRect2D(
            offset = VkOffset2D(x: 0, y: 0),
            extent = self.swapChainExtent
        )
    vkCmdSetViewport(commandBuffer, 0, 1, addr viewport)
    vkCmdSetScissor(commandBuffer, 0, 1, addr scissor)
    vkCmdDraw(commandBuffer, 3, 1, 0, 0)
    vkCmdEndRenderPass(commandBuffer)
    if vkEndCommandBuffer(commandBuffer) != VK_SUCCESS:
        quit("failed to record command buffer")

proc createSyncObjects(self: VulkanTriangleApp) =
    self.imageAvailableSemaphores.setLen(MAX_FRAMES_IN_FLIGHT)
    self.renderFinishedSemaphores.setLen(MAX_FRAMES_IN_FLIGHT)
    self.inFlightFences.setLen(MAX_FRAMES_IN_FLIGHT)
    var
        semaphoreInfo: VkSemaphoreCreateInfo = newVkSemaphoreCreateInfo()
        fenceInfo: VkFenceCreateInfo = newVkFenceCreateInfo(
            flags = VkFenceCreateFlags(VK_FENCE_CREATE_SIGNALED_BIT)
        )
    for i in countup(0,cast[int](MAX_FRAMES_IN_FLIGHT-1)):
        if  (vkCreateSemaphore(self.device, addr semaphoreInfo, nil, addr self.imageAvailableSemaphores[i]) != VK_SUCCESS) or 
            (vkCreateSemaphore(self.device, addr semaphoreInfo, nil, addr self.renderFinishedSemaphores[i]) != VK_SUCCESS) or 
            (vkCreateFence(self.device, addr fenceInfo, nil, addr self.inFlightFences[i]) != VK_SUCCESS):
                raise newException(RuntimeException, "failed to create sync Objects!")

proc drawFrame(self: VulkanTriangleApp) =
    discard vkWaitForFences(self.device, 1, addr self.inFlightFences[self.currentFrame], VkBool32(VK_TRUE), uint64.high)
    var imageIndex: uint32
    let imageResult: VkResult = vkAcquireNextImageKHR(self.device, self.swapChain, uint64.high, self.imageAvailableSemaphores[self.currentFrame], VkFence(0), addr imageIndex)
    if imageResult == VK_ERROR_OUT_OF_DATE_KHR:
        self.recreateSwapChain();
        return
    elif (imageResult != VK_SUCCESS and imageResult != VK_SUBOPTIMAL_KHR):
        raise newException(RuntimeException, "failed to acquire swap chain image!")

    # Only reset the fence if we are submitting work
    discard vkResetFences(self.device, 1 , addr self.inFlightFences[self.currentFrame])

    discard vkResetCommandBuffer(self.commandBuffers[self.currentFrame], VkCommandBufferResetFlags(0))
    self.recordCommandBuffer(self.commandBuffers[self.currentFrame], imageIndex)
    var
        waitSemaphores: array[1, VkSemaphore] = [self.imageAvailableSemaphores[self.currentFrame]]
        waitStages: array[1, VkPipelineStageFlags] = [VkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)]
        signalSemaphores: array[1, VkSemaphore] = [self.renderFinishedSemaphores[self.currentFrame]]
        submitInfo: VkSubmitInfo = newVkSubmitInfo(
            waitSemaphoreCount = waitSemaphores.len.uint32,
            pWaitSemaphores = addr waitSemaphores[0],
            pWaitDstStageMask = addr waitStages[0],
            commandBufferCount = 1,
            pCommandBuffers = addr self.commandBuffers[self.currentFrame],
            signalSemaphoreCount = 1,
            pSignalSemaphores = addr signalSemaphores[0]
        )
    if vkQueueSubmit(self.graphicsQueue, 1, addr submitInfo, self.inFlightFences[self.currentFrame]) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to submit draw command buffer")
    var
        swapChains: array[1, VkSwapchainKHR] = [self.swapChain]
        presentInfo: VkPresentInfoKHR = newVkPresentInfoKHR(
            waitSemaphoreCount = 1,
            pWaitSemaphores = addr signalSemaphores[0],
            swapchainCount = 1,
            pSwapchains = addr swapChains[0],
            pImageIndices = addr imageIndex,
            pResults = nil
        )
    let queueResult = vkQueuePresentKHR(self.presentQueue, addr presentInfo)
    if queueResult == VK_ERROR_OUT_OF_DATE_KHR or queueResult == VK_SUBOPTIMAL_KHR or self.framebufferResized:
        self.framebufferResized = false
        self.recreateSwapChain();
    elif queueResult != VK_SUCCESS:
        raise newException(RuntimeException, "failed to present swap chain image!")
    self.currentFrame = (self.currentFrame + 1).mod(MAX_FRAMES_IN_FLIGHT)


proc initVulkan(self: VulkanTriangleApp) =
    self.createInstance()
    self.createSurface()
    self.pickPhysicalDevice()
    self.createLogicalDevice()
    self.createSwapChain()
    self.createImageViews()
    self.createRenderPass()
    self.createGraphicsPipeline()
    self.createFrameBuffers()
    self.createCommandPool()
    self.createCommandBuffers()
    self.createSyncObjects()
    self.framebufferResized = false
    self.currentFrame = 0

proc mainLoop(self: VulkanTriangleApp) =
    while not windowShouldClose(self.window):
        glfwPollEvents()
        self.drawFrame()
    discard vkDeviceWaitIdle(self.device);

proc cleanup(self: VulkanTriangleApp) =
    for i in countup(0,cast[int](MAX_FRAMES_IN_FLIGHT-1)):
        vkDestroySemaphore(self.device, self.imageAvailableSemaphores[i], nil)
        vkDestroySemaphore(self.device, self.renderFinishedSemaphores[i], nil)
        vkDestroyFence(self.device, self.inFlightFences[i], nil)
    vkDestroyCommandPool(self.device, self.commandPool, nil)
    vkDestroyPipeline(self.device, self.graphicsPipeline, nil)
    vkDestroyPipelineLayout(self.device, self.pipelineLayout, nil)
    vkDestroyRenderPass(self.device, self.renderPass, nil)
    self.cleanupSwapChain()
    vkDestroyDevice(self.device, nil) #destroy device before instance
    vkDestroySurfaceKHR(self.instance, self.surface, nil)
    vkDestroyInstance(self.instance, nil)
    self.window.destroyWindow()
    glfwTerminate()

proc run*(self: VulkanTriangleApp) =
    self.initWindow()
    self.initVulkan()
    self.mainLoop()
    self.cleanup()
import std/options
import vulkan

type QueueFamilyIndices* = object
    graphicsFamily*: Option[uint32]
    presentFamily*: Option[uint32]

proc isComplete*(self: QueueFamilyIndices): bool =
    return self.graphicsFamily.isSome and self.presentFamily.isSome

type SwapChainSupportDetails* = object
    capabilities*: VkSurfaceCapabilitiesKHR
    formats*: seq[VkSurfaceFormatKHR]
    presentModes*: seq[VkPresentModeKHR]

# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

const srcHeader* = """
{.experimental: "codeReordering".}
# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

## Vulkan Bindings
## ====
## WARNING: This is a generated file. Do not edit
## Any edits will be overwritten by the generator.


when not defined(vkCustomLoader):
  import dynlib

  when defined(windows):
    const vkDLL = "vulkan-1.dll"
  elif defined(macosx):
    when defined(libMoltenVK):
      const vkDLL = "libMoltenVK.dylib"
    else:
      const vkDLL = "libvulkan.1.dylib"
  else:
    const vkDLL = "libvulkan.so.1"

  let vkHandleDLL = loadLib(vkDLL)
  if isNil(vkHandleDLL):
    quit("could not load: " & vkDLL)

type
  VkHandle* = int64
  VkNonDispatchableHandle* = int64
  ANativeWindow = ptr object
  CAMetalLayer = ptr object
  AHardwareBuffer = ptr object
  MTLDevice_id = ptr object
  MTLCommandQueue_id = ptr object
  MTLBuffer_id = ptr object
  MTLTexture_id = ptr object
  MTLSharedEvent_id = ptr object
  IOSurfaceRef = ptr object
"""

let keywords* = ["addr", "and", "as", "asm", "bind", "block", "break", "case", "cast", "concept",
                 "const", "continue", "converter", "defer", "discard", "distinct", "div", "do",
                 "elif", "else", "end", "enum", "except", "export", "finally", "for", "from", "func",
                 "if", "import", "in", "include", "interface", "is", "isnot", "iterator", "let",
                 "macro", "method", "mixin", "mod", "nil", "not", "notin", "object", "of", "or",
                 "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr", "static", "template",
                 "try", "tuple", "type", "using", "var", "when", "while", "xor", "yield"]

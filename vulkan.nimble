# Package

version     = "1.2.2"
author      = "Leonardo Mariscal"
description = "Vulkan bindings for Nim"
license     = "MIT"
srcDir      = "src"
skipDirs    = @["tests"]

# Dependencies

requires "nim >= 1.0.0"
requires "https://github.com/DanielBelmes/glfw#head"

task gen, "Generate bindings from source":
  exec("nim c -d:ssl -r tools/generator.nim")

task test, "Create basic triangle with Vulkan and GLFW":
  requires "nimgl@#1.0" # Please https://github.com/nim-lang/nimble/issues/482
  exec("nim c -r -d:release tests/test.nim")

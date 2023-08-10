import application
import unittest

test "can launch app":
  if isMainModule:
    var app: VulkanTriangleApp = new VulkanTriangleApp

    try:
      app.run()
      check true
    except CatchableError:
      echo getCurrentExceptionMsg()
      quit(-1)
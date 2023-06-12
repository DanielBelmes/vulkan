import application

if isMainModule:
  var app: VulkanTriangleApp = new VulkanTriangleApp

  try:
    app.run()
  except CatchableError:
    echo getCurrentExceptionMsg()
    quit(-1)
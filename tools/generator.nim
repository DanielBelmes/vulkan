# Written by Leonardo Mariscal <leo@ldmd.mx>, 2019

import strutils, ./utils, httpClient, os, xmlparser, xmltree, streams, strformat, math, tables, algorithm, bitops, std/strtabs, re

type
  VkProc = object
    name: string
    rVal: string
    args: seq[VkArg]
  VkArg = object
    name: string
    argType: string
  VkStruct = object
    name: string
    members: seq[VkArg]

var vkProcs: seq[VkProc]
var vkStructs: seq[VkStruct]
var vkStructureTypes: seq[string]

proc translateType(s: string): string =
  result = s
  result = result.replace("int64_t", "int64")
  result = result.replace("int32_t", "int32")
  result = result.replace("int16_t", "int16")
  result = result.replace("int8_t", "int8")
  result = result.replace("size_t", "uint") # uint matches pointer size just like size_t
  result = result.replace("float", "float32")
  result = result.replace("double", "float64")
  result = result.replace("VK_DEFINE_HANDLE", "VkHandle")
  result = result.replace("VK_DEFINE_NON_DISPATCHABLE_HANDLE", "VkNonDispatchableHandle")
  result = result.replace("const ", "")
  result = result.replace(" const", "")
  result = result.replace("unsigned ", "u")
  result = result.replace("signed ", "")
  result = result.replace("struct ", "")

  if result.contains('*'):
    let levels = result.count('*')
    result = result.replace("*", "")
    for i in 0..<levels:
      result = "ptr " & result

  result = result.replace("ptr void", "pointer")
  result = result.replace("ptr ptr char", "cstringArray")
  result = result.replace("ptr char", "cstring")

proc getVkPrefixSuffix(name: string): tuple[prefix: string, suffix: string] =
  var
    expandName = name.replacef(re"([0-9]+|[a-z_])([A-Z0-9])", "$1_$2").toUpper()
    expandPrefix = expandName
    expandSuffix = ""
    expandSuffixMatch = expandName.findAll(re"[A-Z][A-Z]+$")
  if expandSuffixMatch.len > 0:
      expandSuffix = '_' & expandSuffixMatch.join()
      # Strip off the suffix from the prefix
      expandPrefix = expandName.rsplit(expandSuffix, 1)[0]
  return (expandPrefix, expandSuffix)

proc genBaseTypes(basetype: XmlNode, output: var string) =
  let name = basetype.child("name").innerText
  if basetype.child("type") != nil:
    var bType = basetype.child("type").innerText
    bType = bType.translateType()

    output.add("type {name}* = distinct {bType}\n".fmt)

proc genConsts(constNode: XmlNode, output: var string) =
  let constName = constNode.attr("name")
  var constValue = constNode.attr("value")
  var constType = constNode.attr("type")
  if constType != "":
    constType = ": " & constType.translateType()
  case constValue:
    of "(~0U)":
      constValue = "(not 0'u32)"
    of "(~1U)":
      constValue = "(not 1'u32)"
    of "(~2U)":
      constValue = "(not 1'u32)"
    of "(~0U-1)":
      constValue = "(not 0'u32) - 1"
    of "(~0U-2)":
      constValue = "(not 0'u32) - 2"
    of "(~0ULL)":
      constValue = "(not 0'u64)"

  if constName == "VK_LUID_SIZE_KHR":
    constValue = "VK_LUID_SIZE"
  elif constName == "VK_QUEUE_FAMILY_EXTERNAL_KHR":
    constValue = "VK_QUEUE_FAMILY_EXTERNAL"
  elif constName == "VK_MAX_DEVICE_GROUP_SIZE_KHR":
    constValue = "VK_MAX_DEVICE_GROUP_SIZE"

  output.add("const {constName}*{constType} = {constValue}\n".fmt)

proc genDefines(define: XmlNode, output: var string) =
  if define.child("name") == nil or define.child("name").innerText == "VK_API_VERSION" or define.attr("api") == "vulkansc" or define.child("name").innerText == "VK_DEFINE_HANDLE": #VK_API_VERSION deprecated and VK_DEFINE_HANDLE not needed
    return
  let name = define.child("name").innerText
  if  name == "VK_MAKE_VERSION":
    output.add("\ntemplate vkMakeVersion*(major, minor, patch: untyped): untyped =\n")
    output.add("  (((major) shl 22) or ((minor) shl 12) or (patch))\n")
  elif name == "VK_VERSION_MAJOR":
    output.add("\ntemplate vkVersionMajor*(version: untyped): untyped =\n")
    output.add("  ((uint32)(version) shr 22)\n")
  elif name == "VK_VERSION_MINOR":
    output.add("\ntemplate vkVersionMinor*(version: untyped): untyped =\n")
    output.add("  (((uint32)(version) shr 12) and 0x000003FF)\n")
  elif name == "VK_VERSION_PATCH":
    output.add("\ntemplate vkVersionPatch*(version: untyped): untyped =\n")
    output.add("  ((uint32)(version) and 0x00000FFF)\n")
  elif name == "VK_API_VERSION_1_0":
    output.add("const VK_API_VERSION_1_0* = vkMakeVersion(1, 0, 0)\n")
  elif name == "VK_API_VERSION_1_1":
    output.add("const VK_API_VERSION_1_1* = vkMakeVersion(1, 1, 0)\n")
  elif name == "VK_API_VERSION_1_2":
    output.add("const VK_API_VERSION_1_2* = vkMakeVersion(1, 2, 0)\n")
  elif name == "VK_HEADER_VERSION":
    output.add("const VK_HEADER_VERSION* = 152\n")
  elif name == "VK_HEADER_VERSION_COMPLETE":
    output.add("const VK_HEADER_VERSION_COMPLETE* = vkMakeVersion(1, 2, VK_HEADER_VERSION)\n")
  elif name == "VK_NULL_HANDLE":
    output.add("const VK_NULL_HANDLE* = 0\n")
  elif name == "VK_MAKE_API_VERSION":
    output.add("\ntemplate vkMakeApiVersion*(variant, major, minor, patch: untyped): untyped =\n")
    output.add("  (((variant) shl 29) or ((major) shl 22) or ((minor) shl 12) or (patch))\n")
  elif name == "VK_API_VERSION_VARIANT":
    output.add("\ntemplate vkApiVersionVariant*(version: untyped): untyped =\n")
    output.add("  ((uint32)(version) shr 29)\n")
  elif name == "VK_API_VERSION_MAJOR":
    output.add("\ntemplate vkApiVersionMajor*(version: untyped): untyped =\n")
    output.add("  (((uint32)(version) shr 22) and 0x000007FU)\n")
  elif name == "VK_API_VERSION_MINOR":
    output.add("\ntemplate vkApiVersionMinor*(version: untyped): untyped =\n")
    output.add("  (((uint32)(version) shr 12) and 0x000003FF)\n")
  elif name == "VK_API_VERSION_PATCH":
    output.add("\ntemplate vkApiVersionPatch*(version: untyped): untyped =\n")
    output.add("  ((uint32)(version) and 0x00000FFF)\n")
  elif name == "VKSC_API_VARIANT":
    output.add("\nconst VKSC_API_VARIANT* = 1\n")
  elif name == "VK_API_VERSION_1_3":
    output.add("const VK_API_VERSION_1_3* = vkMakeApiVersion(0, 1, 3, 0)\n")
  elif name == "VKSC_API_VERSION_1_0":
    output.add("const VKSC_API_VERSION_1_0* = vkMakeApiVersion(VKSC_API_VARIANT, 1, 0, 0)\n")
  else:
    echo "category:define not found {name}".fmt

proc getEnumValue(node: XmlNode): int64 =
  if node.attr("value") != "":
    var enumValueStr = node.attr("value")
    enumValueStr = enumValueStr.translateType()

    if enumValueStr.contains('x'):
      result = fromHex[int](enumValueStr)
    else:
      result = enumValueStr.parseInt()
  if node.attr("bitpos") != "":
    let bitpos = node.attr("bitpos").parseInt()
    result.setBit(bitpos)
  if node.attr("offset") != "":
    const base_value = 1000000000
    const range_size = 1000
    let offset = node.attr("offset").parseInt()
    let extnumberAttr = node.attr("extnumber")
    var extnumber = if extnumberAttr != "": extnumberAttr.parseInt() else: node.attr("extIndex").parseInt()
    let enumNegative = node.attr("dir") != "" #Direction
    var num = base_value + (extnumber - 1) * range_size + offset
    if enumNegative:
      num *= -1
    result = num

proc sortEnum(x, y: XmlNode): int =
  result = cmp(x.attr("extends"), y.attr("extends"))
  result += (getEnumValue(x) > getEnumValue(y)).ord

proc genEnumMembers(node: XmlNode, output: var string) =
  if node.len > 0:
    output.add("const\n")
    for enumNode in node.items:
      let extends = node.attr("name")
      if enumNode.attr("value") != "":
        output.add("  {enumNode.attr(\"name\")}*: {extends} = {extends}({enumNode.attr(\"value\")})\n".fmt)
      elif enumNode.attr("offset") != "":
        output.add("  {enumNode.attr(\"name\")}*: {extends} = {extends}({getEnumValue(enumNode)})\n".fmt)
      elif enumNode.attr("bitpos") != "":
        output.add("  {enumNode.attr(\"name\")}*: {extends} = {extends}({getEnumValue(enumNode)})\n".fmt)

proc genEnums(enums: XmlNode, output: var string) =
  let enumsName = enums.attr("name")
  let enumstype = enums.attr("type")
  output.add("type {enumsName}* = cint\n".fmt)

proc genConstructors(s: XmlNode, output: var string) =
  #TODO implement optional members
  var sname = s.attr("name")
  if s.len == 0:
    return
  output.add("proc new{sname}*(".fmt)
  for member in s.findAll("member"):
    if member.attr("api") == "vulkansc":
        continue
    var name = member.child("name").innerText
    if keywords.contains(name):
      name = "`{name}`".fmt
    var argType = member.child("type").innerText
    argType = argType.translateType()
    var optional = member.attr("optional")
    if not output.endsWith('('):
      output.add(", ")

    var isArray = false
    var arraySize = "0"
    if member.innerText.contains('['):
      arraySize = member.innerText[member.innerText.find('[') + 1 ..< member.innerText.find(']')]
      if arraySize != "":
        isArray = true
      if arraySize == "_DYNAMIC":
        argType = "ptr " & argType
        isArray = false

    var depth = member.innerText.count('*')
    if argType == "pointer":
      depth.dec
    for i in 0 ..< depth:
      argType = "ptr " & argType

    argType = argType.replace("ptr void", "pointer")
    argType = argType.replace("ptr ptr char", "cstringArray")
    argType = argType.replace("ptr char", "cstring")

    if not isArray:
      output.add("{name}: {argType}".fmt)
    else:
      output.add("{name}: array[{arraySize}, {argType}]".fmt)

    if name.contains("flags"):
      output.add(" = 0.{argType}".fmt)
    if name == "sType":
      if member.attr("values") != "":
        output.add(" = {member.attr(\"values\")}".fmt)
    if argType == "pointer":
      output.add(" = nil")

  output.add("): {sname} =\n".fmt)

  for member in s.findAll("member"):
    if member.attr("api") == "vulkansc":
        continue
    var name = member.child("name").innerText
    if keywords.contains(name):
      name = "`{name}`".fmt
    output.add("  result.{name} = {name}\n".fmt)
  output.add("\n")

proc genStructsOrUnion(node: XmlNode, output: var string) =
  let name = node.attr("name")

  if node.attr("category") == "struct":
    output.add("type {name}* = object\n".fmt)
  else:
    output.add("type {name}*  {{.union.}} = object\n".fmt)

  for member in node.findAll("member"):
    if member.attr("api") == "vulkansc":
      continue
    var memberName = member.child("name").innerText
    if keywords.contains(memberName):
      memberName = "`{memberName}`".fmt
    var memberType = member.child("type").innerText
    memberType = memberType.translateType()

    var isArray = false
    var arraySize = "0"
    if member.innerText.contains('['):
      arraySize = member.innerText[member.innerText.find('[') + 1 ..< member.innerText.find(']')]
      if arraySize != "":
        isArray = true
      if arraySize == "_DYNAMIC":
        memberType = "ptr " & memberType
        isArray = false

    var depth = member.innerText.count('*')
    if memberType == "pointer":
      depth.dec
    for i in 0 ..< depth:
      memberType = "ptr " & memberType

    memberType = memberType.replace("ptr void", "pointer")
    memberType = memberType.replace("ptr ptr char", "cstringArray")
    memberType = memberType.replace("ptr char", "cstring")

    var vkArg: VkArg
    vkArg.name = memberName
    if not isArray:
      vkArg.argType = memberType
    else:
      vkArg.argType = "array[{arraySize}, {memberType}]".fmt

    if not isArray:
      output.add("  {memberName}*: {memberType}\n".fmt)
    else:
      output.add("  {memberName}*: array[{arraySize}, {memberType}]\n".fmt)
  output.add("\n")
  node.genConstructors(output)

proc genFuncPointer(funcpointer: XmlNode, output: var string) =
  let name = funcpointer.child("name").innerText
  if name == "PFN_vkInternalAllocationNotification":
    output.add("type PFN_vkInternalAllocationNotification* = proc(pUserData: pointer; size: csize_t; allocationType: VkInternalAllocationType; allocationScope: VkSystemAllocationScope) {.cdecl.}\n")
  elif name == "PFN_vkInternalFreeNotification":
    output.add("type PFN_vkInternalFreeNotification* = proc(pUserData: pointer; size: csize_t; allocationType: VkInternalAllocationType; allocationScope: VkSystemAllocationScope) {.cdecl.}\n")
  elif name == "PFN_vkReallocationFunction":
    output.add("type PFN_vkReallocationFunction* = proc(pUserData: pointer; pOriginal: pointer; size: csize_t; alignment: csize_t; allocationScope: VkSystemAllocationScope): pointer {.cdecl.}\n")
  elif name == "PFN_vkAllocationFunction":
    output.add("type PFN_vkAllocationFunction* = proc(pUserData: pointer; size: csize_t; alignment: csize_t; allocationScope: VkSystemAllocationScope): pointer {.cdecl.}\n")
  elif name == "PFN_vkFreeFunction":
    output.add("type PFN_vkFreeFunction* = proc(pUserData: pointer; pMemory: pointer) {.cdecl.}\n")
  elif name == "PFN_vkVoidFunction":
    output.add("type PFN_vkVoidFunction* = proc() {.cdecl.}\n")
  elif name == "PFN_vkDebugReportCallbackEXT":
    output.add("type PFN_vkDebugReportCallbackEXT* = proc(flags: VkDebugReportFlagsEXT; objectType: VkDebugReportObjectTypeEXT; cbObject: uint64; location: csize_t; messageCode:  int32; pLayerPrefix: cstring; pMessage: cstring; pUserData: pointer): VkBool32 {.cdecl.}\n")
  elif name == "PFN_vkDebugUtilsMessengerCallbackEXT":
    output.add("type PFN_vkDebugUtilsMessengerCallbackEXT* = proc(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT, messageTypes: VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: VkDebugUtilsMessengerCallbackDataEXT, userData: pointer): VkBool32 {.cdecl.}\n"):
  elif name == "PFN_vkFaultCallbackFunction":
    output.add("type PFN_vkFaultCallbackFunction* = proc(unrecordedFaults: VkBool32, faultCount: uint32, pFaults: pointer) {.cdecl.}\n"):
  elif name == "PFN_vkDeviceMemoryReportCallbackEXT":
    output.add("type PFN_vkDeviceMemoryReportCallbackEXT* = proc(pCallbackData: VkDeviceMemoryReportCallbackDataEXT, pUserData: pointer) {.cdecl.}\n"):
  elif name == "PFN_vkGetInstanceProcAddrLUNARG":
    output.add("type PFN_vkGetInstanceProcAddrLUNARG* = proc(instance: VkInstance, pName: cstring) {.cdecl.}\n")
  else:
    echo "category:funcpointer not found {name}".fmt

proc genFlags(flag: XmlNode, output: var string) =
  if flag.attr("api") == "vulkansc":
      return
  var name = flag.child("name").innerText
  var nodeType = flag.child("type").innerText.translateType()
  output.add("type {name}* = distinct {nodeType}\n".fmt)

proc genHandles(handle: XmlNode, output: var string) =
  var name = handle.child("name").innerText
  var nodeType = handle.child("type").innerText.translateType()
  output.add("type {name}* = distinct {nodeType}\n".fmt)

proc genProcs(function: XmlNode, output: var string) =
  var vkProc: VkProc
  if function.child("proto") == nil or function.attr("api") == "vulkansc":
    return
  vkProc.name = function.child("proto").child("name").innerText
  vkProc.rVal = function.child("proto").innerText
  vkProc.rVal = vkProc.rVal[0 ..< vkProc.rval.len - vkProc.name.len]
  while vkProc.rVal.endsWith(" "):
    vkProc.rVal = vkProc.rVal[0 ..< vkProc.rVal.len - 1]
  vkProc.rVal = vkProc.rVal.translateType()

  for param in function.findAll("param"):
    var vkArg: VkArg
    if param.child("name") == nil or param.attr("api") == "vulkansc":
      continue
    vkArg.name = param.child("name").innerText
    vkArg.argType = param.innerText

    if vkArg.argType.contains('['):
      let openBracket = vkArg.argType.find('[')
      let arraySize = vkArg.argType[openBracket + 1 ..< vkArg.argType.find(']')]
      var typeName = vkArg.argType[0..<openBracket].translateType()
      typeName = typeName[0 ..< typeName.len - vkArg.name.len]
      vkArg.argType = "array[{arraySize}, {typeName}]".fmt
    else:
      vkArg.argType = vkArg.argType[0 ..< vkArg.argType.len - vkArg.name.len]
      vkArg.argType = vkArg.argType.translateType()

    for part in vkArg.name.split(" "):
      if keywords.contains(part):
        vkArg.name = "`{vkArg.name}`".fmt

    vkProc.args.add(vkArg)

  vkProcs.add(vkProc)
  output.add("proc {vkProc.name}*(".fmt)
  for arg in vkProc.args:
    if not output.endsWith('('):
      output.add(", ")
    output.add("{arg.name}: {arg.argType}".fmt)
  output.add("): {vkProc.rval} {{.cdecl, importc, dynlib: vkDLL.}}\n".fmt)

proc genAliases(alias: XmlNode, output: var string) =
  var
    name = alias.attr("name")
    aliasVal = alias.attr("alias")
  if alias.tag == "type":
    output.add("type {name}* = {aliasVal}\n".fmt)
  else:
    output.add("template {name}* =\n  {aliasVal}\n".fmt)

proc genObjPointers(objpointer: XmlNode, output: var string) =
  var name = objpointer.attr("name")
  var requires = objpointer.attr("requires")
  if requires == "vk_platform" or requires == "":
    return
  if name[0..0] == "_":
    name = name[1..^1]

  output.add("type {name}* = ptr object\n".fmt)

proc genExtensionOrFeature(extensionOrFeature: XmlNode, output: var string) =
  output.add("# Extension: {extensionOrFeature.attr(\"name\")}\n".fmt)
  for require in extensionOrFeature.findAll("require"):
    for enumNode in require.findAll("enum"):
      if enumNode.attr("api") == "vulkansc":
        continue
      if enumNode.attr("alias") != "":
        enumNode.genAliases(output)
      elif enumNode.attr("extends") != "":
        var attrs = StringTableRef(enumNode.attrs)
        attrs["extIndex"] = extensionOrFeature.attr("number")
        let extends = enumNode.attr("extends")
        if enumNode.attr("value") != "":
          output.add("const {enumNode.attr(\"name\")}*: {extends} = {extends}({enumNode.attr(\"value\")})\n".fmt)
        elif enumNode.attr("offset") != "":
          output.add("const {enumNode.attr(\"name\")}*: {extends} = {extends}({getEnumValue(enumNode)})\n".fmt)
        elif enumNode.attr("bitpos") != "":
          output.add("const {enumNode.attr(\"name\")}*: {extends} = {extends}({getEnumValue(enumNode)})\n".fmt)
      elif enumNode.attr("value") != "":
        enumNode.genConsts(output)
  output.add("\n")

proc parseRegistery(node: XmlNode, registery: TableRef[string, seq[XmlNode]], output: var string) =
  var kind = node.kind
  case kind:
    of xnText, xnVerbatimText, xnCData, xnEntity, xnComment:
      discard
    of xnElement:
      case node.tag:
        of "type":
          case node.attr("category"):
            of "basetype":
              node.genBaseTypes(output)
            of "struct":
              node.genStructsOrUnion(output)
            of "define":
              node.genDefines(output)
            of "bitmask":
              if node.attr("alias") != "":
                node.genAliases(output)
              else:
                node.genFlags(output)
            of "handle":
              if node.attr("alias") != "":
                node.genAliases(output)
              else:
                node.genHandles(output)
            of "funcpointer":
              node.genFuncPointer(output)
            of "union":
              node.genStructsOrUnion(output)
            of "enum":
              if node.attr("alias") != "":
                node.genAliases(output)
              else:
                node.genEnums(output)
            of "include":
              discard
            else:
              node.genObjPointers(output)
        of "enums":
          if node.attr("name") == "API Constants":
            for constItem in node.items:
              if constItem.attr("alias") != "":
                constItem.genAliases(output)
              else:
                constItem.genConsts(output)
          else: #All Enums get a max enum entry
            if node.attr("type") != "bitmask":
              var prefixSuffixTuple = getVkPrefixSuffix(node.attr("name"))
              var maxEnumNode: XmlNode = newElement("enum")
              var attrs = {"name": "{prefixSuffixTuple.prefix}_MAX_ENUM{prefixSuffixTuple.suffix}".fmt, "value": "0x7FFFFFFF", "extends": node.attr("name")}.toXmlAttributes
              maxEnumNode.attrs = attrs
              node.add(maxEnumNode)

            node.genEnumMembers(output)
        of "extension":
          node.genExtensionOrFeature(output)
        of "feature":
          node.genExtensionOrFeature(output)
        of "command":
          node.genProcs(output)
        else:
          for n in node.items:
            parseRegistery(n, registery, output)

proc main() =
  if not os.fileExists("vk.xml"):
    let client = newHttpClient()
    let glUrl = "https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/main/xml/vk.xml"
    client.downloadFile(glUrl, "vk.xml")

  var output = srcHeader & "\n"

  let file = newFileStream("vk.xml", fmRead)
  let xml = file.parseXml()
  var registery: TableRef[string, seq[XmlNode]] = newTable[string, seq[XmlNode]]()

  registery["basetypes"] = newSeq[XmlNode]()
  registery["consts"] = newSeq[XmlNode]()
  registery["enums"] = newSeq[XmlNode]()
  registery["flags"] = newSeq[XmlNode]()
  registery["objpointer"] = newSeq[XmlNode]()
  registery["funcpointer"] = newSeq[XmlNode]()
  registery["structs"] = newSeq[XmlNode]()
  registery["handles"] = newSeq[XmlNode]()
  registery["defines"] = newSeq[XmlNode]()
  registery["aliases"] = newSeq[XmlNode]()
  registery["unions"] = newSeq[XmlNode]()
  registery["includes"] = newSeq[XmlNode]()
  registery["Procs"] = newSeq[XmlNode]()
  registery["enumExtensions"] = newSeq[XmlNode]()
  registery["extensions"] = newSeq[XmlNode]()

  echo "Parsing XML File..."
  xml.parseRegistery(registery, output)
  echo "Parsing Done and Registery filled"
  # registery.genDefines(output)
  # registery.genBaseTypes(output)
  # registery.genConsts(output)
  # registery.genFlags(output)
  # registery.genHandles(output)
  # registery.genEnums(output)
  # registery.genEnumMembers(output)
  # registery.genFuncPointer(output)
  # registery.genStructsOrUnion(output)
  # registery.genUnions(output)
  # registery.genObjPointers(output)
  # registery.genProcs(output)
  # registery.genAliases(output)
  # registery.genConstructors(output)

  #xml.genEnums(output)
  #xml.genTypes(output)
  #xml.genConstructors(output)
  #xml.genProcs(output)
  #xml.genFeatures(output)
  #xml.genExtensions(output)

  #output.add("\n" & vkInit)

  writeFile("src/vulkan.nim", output)

if isMainModule:
  main()

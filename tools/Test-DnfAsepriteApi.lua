local outputDirectory = app.params["outputDirectory"]
local minimumApiVersion = 30

if not outputDirectory or outputDirectory == "" then
  error("Missing required script parameter: outputDirectory")
end
if not app.fs.isDirectory(outputDirectory) then
  error("Probe output directory does not exist: " .. outputDirectory)
end
if not app.apiVersion or app.apiVersion < minimumApiVersion then
  error(string.format(
    "Aseprite API %s is too old; API %d or newer is required.",
    tostring(app.apiVersion), minimumApiVersion))
end

local jsonProbe = json.decode('{"status":"passed","values":[1,2,3]}')
if not jsonProbe or jsonProbe.status ~= "passed" or
    not jsonProbe.values or #jsonProbe.values ~= 3 or jsonProbe.values[3] ~= 3 then
  error("json.decode is unavailable or returned invalid data.")
end

local requiredBlendModes = {
  NORMAL = BlendMode.NORMAL,
  SCREEN = BlendMode.SCREEN,
  MULTIPLY = BlendMode.MULTIPLY,
  OVERLAY = BlendMode.OVERLAY,
  HSL_LUMINOSITY = BlendMode.HSL_LUMINOSITY
}
for name, value in pairs(requiredBlendModes) do
  if value == nil then
    error("Required blend mode is unavailable: " .. name)
  end
end
local resizeMethod = "bilinear"
if ResizeMethod and ResizeMethod.BILINEAR ~= nil then
  resizeMethod = ResizeMethod.BILINEAR
end

local projectFile = app.fs.joinPath(outputDirectory, "aseprite-api-probe.aseprite")
local pngFile = app.fs.joinPath(outputDirectory, "aseprite-api-probe.png")
if app.fs.isFile(projectFile) or app.fs.isFile(pngFile) then
  error("Refusing to overwrite an existing API probe output.")
end

local source = Image(8, 8, ColorMode.RGB)
source:clear()
local context = source.context
if not context then
  error("Image.context is unavailable.")
end
context.antialias = true
context.color = Color { r = 32, g = 184, b = 255, a = 255 }
context.opacity = 224
context.blendMode = BlendMode.NORMAL
context:beginPath()
context:moveTo(1, 6)
context:lineTo(4, 1)
context:lineTo(7, 6)
context:closePath()
context:fill()

local cropped = Image(source, Rectangle(0, 0, 8, 8))
cropped:resize { width = 16, height = 16, method = resizeMethod }
local canvas = Image(16, 16, ColorMode.RGB)
canvas:clear()
canvas:drawImage(cropped, Point(0, 0))

local sprite = Sprite(16, 16, ColorMode.RGB)
local ok, failure = pcall(function()
  local baseLayer = sprite.layers[1]
  baseLayer.name = "api probe base"
  local baseCel = baseLayer:cel(1)
  if baseCel then
    baseCel.image = canvas
  else
    sprite:newCel(baseLayer, 1, canvas, Point(0, 0))
  end

  for name, blendMode in pairs(requiredBlendModes) do
    local layer = sprite:newLayer()
    layer.name = "blend " .. name
    layer.blendMode = blendMode
    layer.opacity = 0
    local layerImage = Image(16, 16, ColorMode.RGB)
    layerImage:clear()
    sprite:newCel(layer, 1, layerImage, Point(0, 0))
  end

  sprite:saveAs(projectFile)
  sprite:saveCopyAs(pngFile)
end)
sprite:close()
if not ok then
  error(failure)
end
if not app.fs.isFile(projectFile) or not app.fs.isFile(pngFile) or
    app.fs.fileSize(projectFile) <= 0 or app.fs.fileSize(pngFile) <= 0 then
  error("Aseprite did not create non-empty API probe outputs.")
end

local reopened = app.open(projectFile)
if not reopened then
  error("Aseprite could not reopen the layered API probe project.")
end
local reopenOk, reopenFailure = pcall(function()
  if reopened.width ~= 16 or reopened.height ~= 16 or
      reopened.colorMode ~= ColorMode.RGB then
    error("Reopened API probe project geometry or color mode changed.")
  end
  local png = Image { fromFile = pngFile }
  if not png or png.width ~= 16 or png.height ~= 16 or
      png.colorMode ~= ColorMode.RGB then
    error("Reopened API probe PNG geometry or color mode changed.")
  end
  local flattened = Image(reopened)
  if flattened.bytes ~= png.bytes then
    error("API probe PNG pixels differ from the reopened layered project.")
  end
end)
reopened:close()
if not reopenOk then
  error(reopenFailure)
end

print("AsepriteApiProbe=passed")
print("AsepriteApiVersion=" .. tostring(app.apiVersion))
print("AsepriteMinimumApiVersion=" .. tostring(minimumApiVersion))
print("AsepriteProbeFeatures=json.decode,Image.context,path-fill,crop,resize,drawImage,layers,blend-modes,project-save,png-save,reopen,pixel-equality")
local mode = app.params["mode"] or "render"
local frameStart = tonumber(app.params["frameStart"] or "3")
local frameEnd = tonumber(app.params["frameEnd"] or "26")
local canvasWidth = tonumber(app.params["canvasWidth"] or "1068")
local canvasHeight = tonumber(app.params["canvasHeight"] or "600")
local sourceWidth = tonumber(app.params["sourceWidth"] or "1067")
local sourceHeight = tonumber(app.params["sourceHeight"] or "600")
local sourceDirectory = app.params["sourceDirectory"]
local bodyReference = app.params["bodyReference"]
local cinemaReference = app.params["cinemaReference"]
local projectDirectory = app.params["projectDirectory"]
local runtimeDirectory = app.params["runtimeDirectory"]

local function requireValue(value, label)
  if not value or value == "" then
    error("Missing required script parameter: " .. label)
  end
end

local function requireDirectory(path, label)
  requireValue(path, label)
  if not app.fs.isDirectory(path) then
    error(label .. " directory does not exist: " .. path)
  end
end

local function requireFile(path, label)
  requireValue(path, label)
  if not app.fs.isFile(path) then
    error(label .. " does not exist: " .. path)
  end
end

local function pad3(value)
  return string.format("%03d", value)
end

local function percent(value)
  return math.max(0, math.min(255, math.floor(value * 2.55 + 0.5)))
end

local function rgba(hex, alpha)
  local clean = string.gsub(hex, "#", "")
  return Color {
    r = tonumber(string.sub(clean, 1, 2), 16),
    g = tonumber(string.sub(clean, 3, 4), 16),
    b = tonumber(string.sub(clean, 5, 6), 16),
    a = alpha or 255
  }
end

local function transparentImage()
  local image = Image(canvasWidth, canvasHeight, ColorMode.RGB)
  image:clear()
  return image
end

local function fillImage(hex)
  local image = transparentImage()
  image:clear(image.bounds, rgba(hex, 255))
  return image
end

local function addLayer(sprite, name, image, opacity, blendMode)
  local layer = sprite:newLayer()
  layer.name = name
  layer.opacity = opacity or 255
  layer.blendMode = blendMode or BlendMode.NORMAL
  sprite:newCel(layer, 1, image, Point(0, 0))
  return layer
end

local function initializeBackground(sprite, image)
  local layer = sprite.layers[1]
  layer.name = "cobalt black spatial background"
  layer.opacity = 255
  layer.blendMode = BlendMode.NORMAL
  local cel = layer:cel(1)
  if cel then
    cel.image = image
  else
    sprite:newCel(layer, 1, image, Point(0, 0))
  end
end

local function drawPolygon(image, points, hex, opacity)
  local context = image.context
  if not context then
    error("This renderer requires the Aseprite Image GraphicsContext API.")
  end
  context.antialias = true
  context.color = rgba(hex, 255)
  context.opacity = opacity or 255
  context.blendMode = BlendMode.NORMAL
  context:beginPath()
  context:moveTo(points[1][1], points[1][2])
  for index = 2, #points do
    context:lineTo(points[index][1], points[index][2])
  end
  context:closePath()
  context:fill()
end

local function bladePolygon(x1, y1, x2, y2, width)
  local dx = x2 - x1
  local dy = y2 - y1
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 1 then
    return nil
  end
  local nx = -dy / length * width / 2
  local ny = dx / length * width / 2
  return {
    { x1 + nx, y1 + ny },
    { x2 + nx, y2 + ny },
    { x2 - nx, y2 - ny },
    { x1 - nx, y1 - ny }
  }
end

local function drawSoftBlade(image, x1, y1, x2, y2, width, blur, hex)
  if blur and blur > 0 then
    local bands = {
      { width + blur * 2.0, 28 },
      { width + blur * 1.25, 48 },
      { width + blur * 0.6, 82 }
    }
    for _, band in ipairs(bands) do
      local glow = bladePolygon(x1, y1, x2, y2, band[1])
      if glow then
        drawPolygon(image, glow, hex, band[2])
      end
    end
  end
  local core = bladePolygon(x1, y1, x2, y2, width)
  if core then
    drawPolygon(image, core, hex, 255)
  end
end

local function addPolygonLayer(sprite, name, points, hex, opacity, blendMode)
  local image = transparentImage()
  drawPolygon(image, points, hex, 255)
  addLayer(sprite, name, image, percent(opacity), blendMode)
end

local function addBladeLayer(sprite, name, x1, y1, x2, y2, width, hex, opacity, blur)
  local image = transparentImage()
  drawSoftBlade(image, x1, y1, x2, y2, width, blur, hex)
  addLayer(sprite, name, image, percent(opacity), BlendMode.SCREEN)
end

local function addPolyline(image, points, hex, width, blur)
  for index = 1, #points - 1 do
    drawSoftBlade(
      image,
      points[index][1], points[index][2],
      points[index + 1][1], points[index + 1][2],
      width, blur, hex)
  end
end

local function addDiamond(image, x, y, size, hex)
  drawPolygon(image, {
    { x, y - size * 1.4 },
    { x + size, y },
    { x, y + size * 1.4 },
    { x - size, y }
  }, hex, 255)
end

local function croppedReference(path, crop)
  local source = Image { fromFile = path }
  if not source then
    error("Aseprite could not load reference: " .. path)
  end
  local x = crop[1]
  local y = crop[2]
  local width = crop[3] - crop[1]
  local height = crop[4] - crop[2]
  if x < 0 or y < 0 or width <= 0 or height <= 0 or
      x + width > source.width or y + height > source.height then
    error("Reference crop is outside image bounds: " .. path)
  end
  local result = Image(source, Rectangle(x, y, width, height))
  result:resize { width = canvasWidth, height = canvasHeight, method = ResizeMethod.BILINEAR }
  return result
end

local function addReference(sprite, path, crop, name, opacity, blendMode)
  addLayer(sprite, name, croppedReference(path, crop), percent(opacity), blendMode)
end

local function addReferences(sprite, frame)
  if frame >= 24 then
    addReference(sprite, cinemaReference, { 260, 170, 1585, 916 },
      "rear spectral portrait crop", 46, BlendMode.NORMAL)
    addReference(sprite, bodyReference, { 270, 95, 1595, 841 },
      "foreground silver hair crop", 82, BlendMode.NORMAL)
  elseif frame <= 4 then
    addReference(sprite, bodyReference, { 160, 130, 1620, 951 },
      "opening face and blade crop", 76, BlendMode.NORMAL)
    addReference(sprite, cinemaReference, { 0, 140, 1728, 1112 },
      "opening dark phantom crop", 38, BlendMode.SCREEN)
  elseif frame >= 22 then
    addReference(sprite, cinemaReference, { 0, 215, 1728, 1187 },
      "release double figure crop", 72, BlendMode.NORMAL)
    addReference(sprite, bodyReference, { 0, 250, 1728, 1222 },
      "release armor and blade crop", 54, BlendMode.SCREEN)
  else
    addReference(sprite, cinemaReference, { 0, 205, 1728, 1177 },
      "cinematic double figure crop", 58, BlendMode.NORMAL)
    addReference(sprite, bodyReference, { 0, 275, 1728, 1247 },
      "blue black armor and icy slash crop", 68, BlendMode.SCREEN)
  end
end

local function addColdVignette(sprite, frame)
  local upperOpacity = (frame >= 19 and frame <= 23) and 72 or 56
  addPolygonLayer(sprite, "deep cobalt upper shadow",
    { { 0, 0 }, { canvasWidth, 0 }, { canvasWidth, 125 }, { 0, 72 } },
    "#02040D", upperOpacity, BlendMode.MULTIPLY)
  addPolygonLayer(sprite, "cyan lower wake",
    { { 0, 575 }, { canvasWidth, 500 }, { canvasWidth, 600 }, { 0, 600 } },
    "#0A3C78", 36, BlendMode.SCREEN)
end

local function addRifts(sprite, frame)
  local boost = (frame >= 19 and frame <= 23) and 1.25 or 1.0
  local image = transparentImage()
  addPolyline(image, { { 720, 42 }, { 835, 74 }, { 930, 48 }, { 1040, 88 } },
    "#7E48FF", 5 * boost, 2.2)
  addPolyline(image, { { 34, 428 }, { 116, 390 }, { 162, 420 }, { 240, 374 } },
    "#00D4FF", 4 * boost, 1.8)
  addPolyline(image, { { 910, 495 }, { 980, 438 }, { 1066, 460 } },
    "#8E4DFF", 6 * boost, 3.0)
  if frame >= 19 and frame <= 23 then
    addPolyline(image, { { 260, 96 }, { 368, 72 }, { 502, 92 }, { 638, 64 } },
      "#00D4FF", 5, 2.0)
    addPolyline(image, { { 180, 520 }, { 275, 485 }, { 350, 508 }, { 454, 470 } },
      "#8E4DFF", 6, 2.5)
  end
  addLayer(sprite, "cyan and violet spatial fractures", image, percent(55), BlendMode.SCREEN)
end

local function addBladeEnergy(sprite, frame)
  if frame <= 4 then
    addBladeLayer(sprite, "opening cyan blade glow", 620, 80, 1060, 430, 46,
      "#1A8FFF", 62, 18)
    addBladeLayer(sprite, "opening white blade core", 655, 105, 1050, 392, 10,
      "#FFFFFF", 86, 1.4)
    return
  end
  if frame >= 19 and frame <= 21 then
    addBladeLayer(sprite, "peak cyan blade bloom", 85, 590, 955, 18, 72,
      "#00D4FF", 82, 24)
    addBladeLayer(sprite, "peak white blade core", 120, 584, 925, 35, 13,
      "#FFFFFF", 94, 1.1)
    addBladeLayer(sprite, "secondary violet rift edge", 175, 575, 1030, 90, 18,
      "#6D5CFF", 48, 6)
    return
  end
  if frame >= 22 and frame <= 23 then
    addBladeLayer(sprite, "release horizontal icy wake", -30, 410, 1120, 170, 82,
      "#00D4FF", 78, 26)
    addBladeLayer(sprite, "release white slash core", -10, 384, 1100, 196, 14,
      "#FFFFFF", 93, 1.2)
    return
  end
  if frame >= 24 then
    addBladeLayer(sprite, "face closeup right icy edge", 790, 0, 1045, 600, 58,
      "#00D4FF", 70, 22)
    addBladeLayer(sprite, "face closeup white edge", 842, 0, 1015, 600, 11,
      "#FFFFFF", 88, 1.2)
    return
  end

  local offset = (frame - 5) * 3
  addBladeLayer(sprite, "main diagonal icy glow", 150 + offset, 590, 935 + offset, 44, 54,
    "#1A8FFF", 66, 18)
  addBladeLayer(sprite, "main diagonal white core", 185 + offset, 580, 905 + offset, 65, 9,
    "#FFFFFF", 88, 1.1)
end

local function addCrystals(sprite, frame)
  local image = transparentImage()
  local seed = frame * 37
  for index = 0, 8 do
    local x = 70 + ((seed + index * 109) % 930)
    local y = 50 + ((seed * 3 + index * 67) % 470)
    local size = 4 + ((seed + index * 13) % 12)
    local color = (index % 3 == 0) and "#FFFFFF" or
      ((index % 3 == 1) and "#00D4FF" or "#7E48FF")
    addDiamond(image, x, y, size, color)
  end
  addLayer(sprite, "cold glass fragments", image, percent(46), BlendMode.SCREEN)
end

local function addSourceFrame(sprite, frame)
  local sourcePath = app.fs.joinPath(sourceDirectory, "frame-" .. pad3(frame) .. ".png")
  requireFile(sourcePath, "source frame")
  local source = Image { fromFile = sourcePath }
  if source.width ~= sourceWidth or source.height ~= sourceHeight then
    error(string.format(
      "Source frame geometry mismatch for #%03d: %dx%d expected %dx%d",
      frame, source.width, source.height, sourceWidth, sourceHeight))
  end
  local padded = transparentImage()
  padded:drawImage(source, Point(0, 0))
  local opacity = (frame >= 24) and 52 or 38
  addLayer(sprite, "source cut-in timing and linework #" .. pad3(frame), padded,
    percent(opacity), BlendMode.HSL_LUMINOSITY)
end

local function addFinalGrade(sprite, frame)
  local opacity = (frame >= 19 and frame <= 23) and 20 or 14
  addLayer(sprite, "final cold blue grade", fillImage("#0A1633"),
    percent(opacity), BlendMode.OVERLAY)
end

local function renderFrame(frame)
  local frameName = "frame-" .. pad3(frame)
  local projectPath = app.fs.joinPath(projectDirectory, frameName .. ".aseprite")
  local runtimePath = app.fs.joinPath(runtimeDirectory, frameName .. ".png")
  if app.fs.isFile(projectPath) or app.fs.isFile(runtimePath) then
    error("Refusing to overwrite frame output: " .. frameName)
  end

  local sprite = Sprite(canvasWidth, canvasHeight, ColorMode.RGB)
  local ok, failure = pcall(function()
    sprite.data = string.format(
      "resource=cutin_weaponmaster_neo; frame=%03d; logicalCanvas=1067x600; runtimeTexture=1068x600",
      frame)
    initializeBackground(sprite, fillImage("#030713"))
    addReferences(sprite, frame)
    addColdVignette(sprite, frame)
    addRifts(sprite, frame)
    addBladeEnergy(sprite, frame)
    addCrystals(sprite, frame)
    addSourceFrame(sprite, frame)
    addFinalGrade(sprite, frame)
    sprite:saveAs(projectPath)
    sprite:saveCopyAs(runtimePath)
  end)
  sprite:close()
  if not ok then
    error(failure)
  end
  if not app.fs.isFile(projectPath) or not app.fs.isFile(runtimePath) then
    error("Aseprite did not create both frame outputs: " .. frameName)
  end
  print("RenderedFrame=" .. pad3(frame))
end

local function findLayer(sprite, name)
  for _, layer in ipairs(sprite.layers) do
    if layer.name == name then
      return layer
    end
  end
  return nil
end

local function validateFrame(frame)
  local frameName = "frame-" .. pad3(frame)
  local projectPath = app.fs.joinPath(projectDirectory, frameName .. ".aseprite")
  local runtimePath = app.fs.joinPath(runtimeDirectory, frameName .. ".png")
  requireFile(projectPath, "layered project")
  requireFile(runtimePath, "runtime PNG")

  local sprite = app.open(projectPath)
  if not sprite then
    error("Aseprite could not reopen layered project: " .. projectPath)
  end
  local ok, failure = pcall(function()
    if sprite.width ~= canvasWidth or sprite.height ~= canvasHeight or
        sprite.colorMode ~= ColorMode.RGB then
      error("Layered project geometry or color mode changed: " .. frameName)
    end
    if #sprite.layers < 10 then
      error("Layered project has too few auditable layers: " .. frameName)
    end
    if not findLayer(sprite, "cobalt black spatial background") or
        not findLayer(sprite, "source cut-in timing and linework #" .. pad3(frame)) or
        not findLayer(sprite, "final cold blue grade") then
      error("Layered project is missing required audit layers: " .. frameName)
    end
    for _, layer in ipairs(sprite.layers) do
      if not layer.isVisible then
        error("Layered project contains a hidden render layer: " .. frameName .. "/" .. layer.name)
      end
    end

    local runtime = Image { fromFile = runtimePath }
    if not runtime or runtime.width ~= canvasWidth or runtime.height ~= canvasHeight or
        runtime.colorMode ~= ColorMode.RGB then
      error("Runtime PNG geometry or color mode changed: " .. frameName)
    end
    local flattened = Image(sprite)
    if flattened.bytes ~= runtime.bytes then
      error("Runtime PNG does not match reopened layered project: " .. frameName)
    end
  end)
  sprite:close()
  if not ok then
    error(failure)
  end
  print("ValidatedFrame=" .. pad3(frame))
end

if frameStart ~= 3 or frameEnd ~= 26 or canvasWidth ~= 1068 or canvasHeight ~= 600 or
    sourceWidth ~= 1067 or sourceHeight ~= 600 then
  error("This verified Cut-in route requires frames 3-26, source 1067x600, and runtime 1068x600.")
end
requireDirectory(projectDirectory, "projectDirectory")
requireDirectory(runtimeDirectory, "runtimeDirectory")

if mode == "render" then
  requireDirectory(sourceDirectory, "sourceDirectory")
  requireFile(bodyReference, "bodyReference")
  requireFile(cinemaReference, "cinemaReference")
  for frame = frameStart, frameEnd do
    renderFrame(frame)
  end
  print("CutinAsepriteRender=passed")
elseif mode == "validate" then
  for frame = frameStart, frameEnd do
    validateFrame(frame)
  end
  print("CutinAsepriteValidation=passed")
else
  error("Unsupported mode: " .. tostring(mode))
end
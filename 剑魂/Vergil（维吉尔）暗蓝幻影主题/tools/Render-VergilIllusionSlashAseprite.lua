local mode = app.params["mode"] or "render"
local renderPlan = app.params["renderPlan"]
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

local function splitTab(line)
  local result = {}
  local start = 1
  while true do
    local index = string.find(line, "\t", start, true)
    if not index then
      table.insert(result, string.sub(line, start))
      break
    end
    table.insert(result, string.sub(line, start, index - 1))
    start = index + 1
  end
  return result
end

local function normalizeFieldName(value)
  value = string.gsub(value or "", "\r$", "")
  return string.gsub(value, "^" .. string.char(239, 187, 191), "")
end

local function normalizeFieldValue(value)
  return string.gsub(value or "", "\r$", "")
end

local function readPlan(path)
  requireFile(path, "render plan")
  local file = io.open(path, "r")
  if not file then
    error("Could not open render plan: " .. path)
  end
  local rows = {}
  local header = nil
  for line in file:lines() do
    if line ~= "" then
      local values = splitTab(line)
      if not header then
        header = {}
        for _, name in ipairs(values) do
          header[#header + 1] = normalizeFieldName(name)
        end
      else
        local row = {}
        for index, name in ipairs(header) do
          row[name] = normalizeFieldValue(values[index])
        end
        row.frameIndexNumber = tonumber(row.frameIndex)
        row.textureWidthNumber = tonumber(row.textureWidth)
        row.textureHeightNumber = tonumber(row.textureHeight)
        if not row.frameIndexNumber or not row.textureWidthNumber or not row.textureHeightNumber then
          error("Render plan has invalid numeric fields for " .. tostring(row.frameKey))
        end
        table.insert(rows, row)
      end
    end
  end
  file:close()
  if not header or #rows == 0 then
    error("Render plan is empty: " .. path)
  end
  return rows
end

local function clampByte(value)
  if value < 0 then return 0 end
  if value > 255 then return 255 end
  return math.floor(value + 0.5)
end

local function mapVergilPixel(red, green, blue, alpha, frameIndex, x, y)
  if alpha == 0 then
    return 0, 0, 0, 0
  end
  local maxChannel = math.max(red, math.max(green, blue))
  local minChannel = math.min(red, math.min(green, blue))
  local intensity = maxChannel / 255.0
  local edge = (maxChannel - minChannel) / 255.0
  local phase = ((frameIndex * 37 + x * 3 + y * 5) % 29) / 28.0
  local core = math.max(0.0, intensity - 0.62) / 0.38
  local rim = math.max(0.0, edge - 0.10) / 0.90
  local crack = ((x + y + frameIndex * 11) % 23 == 0) and 0.18 or 0.0
  local cold = math.min(1.0, 0.34 + intensity * 0.66 + rim * 0.16 + crack)
  local r = 10 + 20 * intensity + 225 * core
  local g = 22 + 110 * intensity + 140 * core + 38 * phase
  local b = 51 + 188 * cold + 18 * rim
  if core > 0.75 then
    r = 235 + 20 * core
    g = 246 + 9 * core
    b = 255
  end
  return clampByte(r), clampByte(g), clampByte(b), alpha
end

local function recolorImage(source, row)
  if source.width ~= row.textureWidthNumber or source.height ~= row.textureHeightNumber then
    error(string.format(
      "Source PNG geometry mismatch for %s: %dx%d expected %dx%d",
      row.frameKey, source.width, source.height, row.textureWidthNumber, row.textureHeightNumber))
  end
  local output = Image(source.width, source.height, ColorMode.RGB)
  output:clear()
  for y = 0, source.height - 1 do
    for x = 0, source.width - 1 do
      local pixel = source:getPixel(x, y)
      local red = app.pixelColor.rgbaR(pixel)
      local green = app.pixelColor.rgbaG(pixel)
      local blue = app.pixelColor.rgbaB(pixel)
      local alpha = app.pixelColor.rgbaA(pixel)
      local nr, ng, nb, na = mapVergilPixel(red, green, blue, alpha, row.frameIndexNumber, x, y)
      output:putPixel(x, y, app.pixelColor.rgba(nr, ng, nb, na))
    end
  end
  return output
end

local function ensureFrameDirectories(row)
  local projectAlbum = app.fs.joinPath(projectDirectory, row.albumSlug)
  local runtimeAlbum = app.fs.joinPath(runtimeDirectory, row.albumSlug)
  requireDirectory(projectAlbum, "project album")
  requireDirectory(runtimeAlbum, "runtime album")
  return projectAlbum, runtimeAlbum
end

local function renderRow(row)
  requireFile(row.sourcePng, "source PNG")
  local projectAlbum, runtimeAlbum = ensureFrameDirectories(row)
  local baseName = "frame-" .. string.format("%03d", row.frameIndexNumber)
  local projectPath = app.fs.joinPath(projectAlbum, baseName .. ".aseprite")
  local runtimePath = app.fs.joinPath(runtimeAlbum, baseName .. ".png")
  if app.fs.isFile(projectPath) or app.fs.isFile(runtimePath) then
    error("Refusing to overwrite frame output: " .. row.frameKey)
  end

  local source = Image { fromFile = row.sourcePng }
  if not source then
    error("Aseprite could not open source PNG: " .. row.sourcePng)
  end
  local final = recolorImage(source, row)
  local sprite = Sprite(source.width, source.height, ColorMode.RGB)
  local sourceLayer = sprite.layers[1]
  sourceLayer.name = "hidden source alpha reference"
  sourceLayer.isVisible = false
  sprite:newCel(sourceLayer, 1, source, Point(0, 0))
  local finalLayer = sprite:newLayer()
  finalLayer.name = "runtime final alpha-preserving vergil recolor"
  finalLayer.isVisible = true
  finalLayer.opacity = 255
  finalLayer.blendMode = BlendMode.NORMAL
  sprite:newCel(finalLayer, 1, final, Point(0, 0))
  local auditLayer = sprite:newLayer()
  auditLayer.name = "hidden prompt style audit marker"
  auditLayer.isVisible = false
  auditLayer.opacity = 0
  sprite:saveCopyAs(projectPath)
  sprite:saveCopyAs(runtimePath)
  sprite:close()
  print("RenderedFrame=" .. row.frameKey)
end

local function findLayer(sprite, name)
  for _, layer in ipairs(sprite.layers) do
    if layer.name == name then
      return layer
    end
  end
  return nil
end

local function validateRow(row)
  local projectAlbum, runtimeAlbum = ensureFrameDirectories(row)
  local baseName = "frame-" .. string.format("%03d", row.frameIndexNumber)
  local projectPath = app.fs.joinPath(projectAlbum, baseName .. ".aseprite")
  local runtimePath = app.fs.joinPath(runtimeAlbum, baseName .. ".png")
  requireFile(row.sourcePng, "source PNG")
  requireFile(projectPath, "layered project")
  requireFile(runtimePath, "runtime PNG")

  local source = Image { fromFile = row.sourcePng }
  local runtime = Image { fromFile = runtimePath }
  local sprite = app.open(projectPath)
  if not source or not runtime or not sprite then
    error("Could not reopen render outputs for " .. row.frameKey)
  end
  local ok, failure = pcall(function()
    if source.width ~= row.textureWidthNumber or source.height ~= row.textureHeightNumber then
      error("Source PNG geometry changed: " .. row.frameKey)
    end
    if runtime.width ~= row.textureWidthNumber or runtime.height ~= row.textureHeightNumber then
      error("Runtime PNG geometry changed: " .. row.frameKey)
    end
    if sprite.width ~= row.textureWidthNumber or sprite.height ~= row.textureHeightNumber then
      error("Layered project geometry changed: " .. row.frameKey)
    end
    local sourceLayer = findLayer(sprite, "hidden source alpha reference")
    local finalLayer = findLayer(sprite, "runtime final alpha-preserving vergil recolor")
    if not sourceLayer or sourceLayer.isVisible then
      error("Source audit layer is missing or visible: " .. row.frameKey)
    end
    if not finalLayer or not finalLayer.isVisible then
      error("Final runtime layer is missing or hidden: " .. row.frameKey)
    end
    local flattened = Image(sprite)
    if flattened.width ~= runtime.width or flattened.height ~= runtime.height or flattened.bytes ~= runtime.bytes then
      error("Layered project does not flatten to runtime PNG: " .. row.frameKey)
    end

    local visible = 0
    local changed = 0
    for y = 0, source.height - 1 do
      for x = 0, source.width - 1 do
        local sp = source:getPixel(x, y)
        local rp = runtime:getPixel(x, y)
        local sa = app.pixelColor.rgbaA(sp)
        local ra = app.pixelColor.rgbaA(rp)
        if sa ~= ra then
          error("Runtime alpha changed: " .. row.frameKey)
        end
        if sa ~= 0 then
          visible = visible + 1
          if app.pixelColor.rgbaR(sp) ~= app.pixelColor.rgbaR(rp) or
             app.pixelColor.rgbaG(sp) ~= app.pixelColor.rgbaG(rp) or
             app.pixelColor.rgbaB(sp) ~= app.pixelColor.rgbaB(rp) then
            changed = changed + 1
          end
        end
      end
    end
    if visible > 0 and changed == 0 then
      error("Runtime RGB did not change visible pixels: " .. row.frameKey)
    end
  end)
  sprite:close()
  if not ok then
    error(failure)
  end
  print("ValidatedFrame=" .. row.frameKey)
end

requireFile(renderPlan, "render plan")
requireDirectory(projectDirectory, "project")
requireDirectory(runtimeDirectory, "runtime")
local rows = readPlan(renderPlan)

if mode == "render" then
  for _, row in ipairs(rows) do
    renderRow(row)
  end
  print("IllusionSlashAsepriteRender=passed")
  print("FrameCount=" .. tostring(#rows))
elseif mode == "validate" then
  for _, row in ipairs(rows) do
    validateRow(row)
  end
  print("IllusionSlashAsepriteValidation=passed")
  print("FrameCount=" .. tostring(#rows))
else
  error("Unsupported mode: " .. tostring(mode))
end

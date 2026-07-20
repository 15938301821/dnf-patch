local mode = app.params["mode"] or "render"
local renderPlan = app.params["renderPlan"]
local stylePlanPath = app.params["stylePlan"]
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

local function readAllText(path, label)
  requireFile(path, label)
  local file = io.open(path, "rb")
  if not file then
    error("Could not open " .. label .. ": " .. path)
  end
  local text = file:read("*all")
  file:close()
  if string.sub(text, 1, 3) == string.char(239, 187, 191) then
    text = string.sub(text, 4)
  end
  return text
end

local function requireNumber(value, minimum, maximum, label)
  if type(value) ~= "number" or value < minimum or value > maximum then
    error(string.format("%s must be a number in [%s, %s].", label, tostring(minimum), tostring(maximum)))
  end
end

local function requireRgb(value, label)
  if type(value) ~= "table" or #value ~= 3 then
    error(label .. " must contain exactly three RGB bytes.")
  end
  for index = 1, 3 do
    requireNumber(value[index], 0, 255, label .. "[" .. tostring(index) .. "]")
  end
end

local function readStylePlan(path)
  local decoded = json.decode(readAllText(path, "style plan"))
  if type(decoded) ~= "table" or decoded.schemaVersion ~= 1 or
      decoded.kind ~= "dnf-aseprite-pixel-style-plan-v1" then
    error("Style plan identity is invalid.")
  end
  if type(decoded.source) ~= "table" or decoded.source.provider ~= "openai" or
      decoded.source.modelEvidenceEligible ~= true then
    error("Style plan is not backed by eligible OpenAI model evidence.")
  end
  if decoded.geometryPolicy ~= "strict-preserve-source-frame-position-size" or
      decoded.alphaPolicy ~= "preserve-source-alpha-byte-exact" then
    error("Style plan geometry or alpha policy is invalid.")
  end
  if type(decoded.safety) ~= "table" or
      decoded.safety.arbitraryCodeAccepted ~= false or
      decoded.safety.resourceFactsFromModel ~= false or
      decoded.safety.runtimeImageFromImageModel ~= false or
      decoded.safety.fullSkillCoverageProven ~= false or
      decoded.safety.deploymentAuthorized ~= false then
    error("Style plan safety policy is invalid.")
  end
  if type(decoded.palette) ~= "table" then
    error("Style plan palette is missing.")
  end
  requireRgb(decoded.palette.shadow, "palette.shadow")
  requireRgb(decoded.palette.midtone, "palette.midtone")
  requireRgb(decoded.palette.rim, "palette.rim")
  requireRgb(decoded.palette.core, "palette.core")
  if type(decoded.parameters) ~= "table" then
    error("Style plan parameters are missing.")
  end
  requireNumber(decoded.parameters.sourceColorMix, 0, 1, "parameters.sourceColorMix")
  requireNumber(decoded.parameters.coreThreshold, 0.5, 0.95, "parameters.coreThreshold")
  requireNumber(decoded.parameters.coreIntensity, 0, 1, "parameters.coreIntensity")
  requireNumber(decoded.parameters.rimThreshold, 0, 0.8, "parameters.rimThreshold")
  requireNumber(decoded.parameters.rimIntensity, 0, 1, "parameters.rimIntensity")
  requireNumber(decoded.parameters.phaseAmount, 0, 1, "parameters.phaseAmount")
  requireNumber(decoded.parameters.crackDensity, 0, 0.25, "parameters.crackDensity")
  requireNumber(decoded.parameters.crackIntensity, 0, 1, "parameters.crackIntensity")
  if type(decoded.enabledOperations) ~= "table" or #decoded.enabledOperations == 0 then
    error("Style plan enabledOperations is empty.")
  end
  local allowedOperations = {
    ["palette-map"] = true,
    ["rim-light"] = true,
    ["particle-trail"] = true,
    ["spatial-crack"] = true,
    ["blade-core"] = true,
    ["alpha-preserve"] = true
  }
  local enabled = {}
  for _, operation in ipairs(decoded.enabledOperations) do
    if not allowedOperations[operation] then
      error("Unsupported style operation: " .. tostring(operation))
    end
    enabled[operation] = true
  end
  if not enabled["palette-map"] or not enabled["alpha-preserve"] then
    error("Style plan must enable palette-map and alpha-preserve.")
  end
  decoded.enabled = enabled
  return decoded
end

local function clampByte(value)
  if value < 0 then return 0 end
  if value > 255 then return 255 end
  return math.floor(value + 0.5)
end

local function clampUnit(value)
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local function mix(left, right, amount)
  return left + (right - left) * clampUnit(amount)
end

local function mapStylePixel(red, green, blue, alpha, frameIndex, x, y, plan)
  if alpha == 0 then
    return 0, 0, 0, 0, false, false, false
  end
  local maxChannel = math.max(red, math.max(green, blue))
  local minChannel = math.min(red, math.min(green, blue))
  local intensity = maxChannel / 255.0
  local edge = (maxChannel - minChannel) / 255.0
  local phase = ((frameIndex * 37 + x * 3 + y * 5) % 29) / 28.0
  local parameters = plan.parameters
  local palette = plan.palette
  local baseR = mix(palette.shadow[1], palette.midtone[1], intensity)
  local baseG = mix(palette.shadow[2], palette.midtone[2], intensity)
  local baseB = mix(palette.shadow[3], palette.midtone[3], intensity)
  local core = clampUnit((intensity - parameters.coreThreshold) / (1.0 - parameters.coreThreshold))
  local rim = clampUnit((edge - parameters.rimThreshold) / (1.0 - parameters.rimThreshold))
  local coreAmount = plan.enabled["blade-core"] and core * parameters.coreIntensity or 0
  local rimAmount = plan.enabled["rim-light"] and rim * parameters.rimIntensity or 0
  local phaseAmount = plan.enabled["particle-trail"] and phase * parameters.phaseAmount or 0
  local crackBucket = (x * 17 + y * 31 + frameIndex * 11) % 10000
  local crackActive = plan.enabled["spatial-crack"] and
      crackBucket < math.floor(parameters.crackDensity * 10000 + 0.5)
  local crackAmount = crackActive and parameters.crackIntensity or 0
  local r = mix(baseR, red, parameters.sourceColorMix)
  local g = mix(baseG, green, parameters.sourceColorMix)
  local b = mix(baseB, blue, parameters.sourceColorMix)
  r = mix(r, palette.rim[1], clampUnit(rimAmount + phaseAmount + crackAmount))
  g = mix(g, palette.rim[2], clampUnit(rimAmount + phaseAmount + crackAmount))
  b = mix(b, palette.rim[3], clampUnit(rimAmount + phaseAmount + crackAmount))
  r = mix(r, palette.core[1], coreAmount)
  g = mix(g, palette.core[2], coreAmount)
  b = mix(b, palette.core[3], coreAmount)
  return clampByte(r), clampByte(g), clampByte(b), alpha,
      coreAmount > 0, rimAmount > 0, crackActive
end

local function recolorImage(source, row, plan)
  if source.width ~= row.textureWidthNumber or source.height ~= row.textureHeightNumber then
    error(string.format(
      "Source PNG geometry mismatch for %s: %dx%d expected %dx%d",
      row.frameKey, source.width, source.height, row.textureWidthNumber, row.textureHeightNumber))
  end
  local output = Image(source.width, source.height, ColorMode.RGB)
  output:clear()
  local stats = { visible = 0, changed = 0, core = 0, rim = 0, crack = 0 }
  for y = 0, source.height - 1 do
    for x = 0, source.width - 1 do
      local pixel = source:getPixel(x, y)
      local red = app.pixelColor.rgbaR(pixel)
      local green = app.pixelColor.rgbaG(pixel)
      local blue = app.pixelColor.rgbaB(pixel)
      local alpha = app.pixelColor.rgbaA(pixel)
      local nr, ng, nb, na, core, rim, crack =
          mapStylePixel(red, green, blue, alpha, row.frameIndexNumber, x, y, plan)
      output:putPixel(x, y, app.pixelColor.rgba(nr, ng, nb, na))
      if alpha ~= 0 then
        stats.visible = stats.visible + 1
        if nr ~= red or ng ~= green or nb ~= blue then stats.changed = stats.changed + 1 end
        if core then stats.core = stats.core + 1 end
        if rim then stats.rim = stats.rim + 1 end
        if crack then stats.crack = stats.crack + 1 end
      end
    end
  end
  return output, stats
end

local function ensureFrameDirectories(row)
  local projectAlbum = app.fs.joinPath(projectDirectory, row.albumSlug)
  local runtimeAlbum = app.fs.joinPath(runtimeDirectory, row.albumSlug)
  requireDirectory(projectAlbum, "project album")
  requireDirectory(runtimeAlbum, "runtime album")
  return projectAlbum, runtimeAlbum
end

local function renderRow(row, plan)
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
  local final, stats = recolorImage(source, row, plan)
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
  auditLayer.name = "hidden compiled model style audit marker"
  auditLayer.isVisible = false
  auditLayer.opacity = 0
  sprite:saveCopyAs(projectPath)
  sprite:saveCopyAs(runtimePath)
  sprite:close()
  print("RenderedFrame=" .. row.frameKey)
  print(string.format("StyleAppliedFrame=%s;visible=%d;changed=%d;core=%d;rim=%d;crack=%d",
    row.frameKey, stats.visible, stats.changed, stats.core, stats.rim, stats.crack))
end

local function findLayer(sprite, name)
  for _, layer in ipairs(sprite.layers) do
    if layer.name == name then
      return layer
    end
  end
  return nil
end

local function validateRow(row, plan)
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
          local expectedRed, expectedGreen, expectedBlue, expectedAlpha = mapStylePixel(
            app.pixelColor.rgbaR(sp),
            app.pixelColor.rgbaG(sp),
            app.pixelColor.rgbaB(sp),
            sa,
            row.frameIndexNumber,
            x,
            y,
            plan)
          if expectedAlpha ~= ra or expectedRed ~= app.pixelColor.rgbaR(rp) or
             expectedGreen ~= app.pixelColor.rgbaG(rp) or
             expectedBlue ~= app.pixelColor.rgbaB(rp) then
            error("Runtime pixel does not match compiled style plan: " .. row.frameKey)
          end
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
  print("StyleRecomputedFrame=" .. row.frameKey)
end

requireFile(renderPlan, "render plan")
requireFile(stylePlanPath, "style plan")
requireDirectory(projectDirectory, "project")
requireDirectory(runtimeDirectory, "runtime")
local rows = readPlan(renderPlan)
local stylePlan = readStylePlan(stylePlanPath)

if mode == "render" then
  for _, row in ipairs(rows) do
    renderRow(row, stylePlan)
  end
  print("IllusionSlashAsepriteRender=passed")
  print("FrameCount=" .. tostring(#rows))
  print("StylePlanAppliedFrames=" .. tostring(#rows))
elseif mode == "validate" then
  for _, row in ipairs(rows) do
    validateRow(row, stylePlan)
  end
  print("IllusionSlashAsepriteValidation=passed")
  print("FrameCount=" .. tostring(#rows))
  print("StylePlanRecomputedFrames=" .. tostring(#rows))
else
  error("Unsupported mode: " .. tostring(mode))
end

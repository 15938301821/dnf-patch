local sourceFile = app.params["source"]
local outputFile = app.params["output"]

if not sourceFile or sourceFile == "" then
  error("Missing required script parameter: source")
end
if not outputFile or outputFile == "" then
  error("Missing required script parameter: output")
end
if not app.fs.isFile(sourceFile) then
  error("Source preview does not exist: " .. sourceFile)
end
if app.fs.isFile(outputFile) then
  error("Refusing to overwrite preview output: " .. outputFile)
end

local outputDirectory = app.fs.filePath(outputFile)
if not app.fs.isDirectory(outputDirectory) then
  error("Preview output directory does not exist: " .. outputDirectory)
end

local sprite = app.open(sourceFile)
if not sprite then
  error("Aseprite could not open source preview: " .. sourceFile)
end

local ok, failure = pcall(function()
  if sprite.colorMode ~= ColorMode.RGB then
    error("Source preview must use RGB/RGBA color mode: " .. sourceFile)
  end
  sprite:saveCopyAs(outputFile)
end)

sprite:close()
if not ok then
  error(failure)
end
if not app.fs.isFile(outputFile) or app.fs.fileSize(outputFile) <= 0 then
  error("Aseprite did not create a non-empty preview: " .. outputFile)
end

print("SakuraPreviewExport=passed")
print("Source=" .. sourceFile)
print("Output=" .. outputFile)
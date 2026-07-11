#target photoshop

(function () {
    var scriptFile = new File($.fileName);
    var toolsDirectory = scriptFile.parent;
    var projectDirectory = toolsDirectory.parent;
    var outputDirectory = new Folder(projectDirectory.fsName + "/\u6c14\u529f\u5e08\uff08\u5973\uff09/\u6a31\u82b1\u4e3b\u9898");
    var sourceFile = new File(outputDirectory.fsName + "/frames/preview/\u5168\u6280\u80fd\u8054\u7cfb\u8868.png");
    var outputFile = new File(outputDirectory.fsName + "/\u6a31\u82b1\u7c89\u9884\u89c8.photoshop.png");

    if (!sourceFile.exists)
        throw new Error("Candidate preview does not exist: " + sourceFile.fsName);
    if (!outputDirectory.exists)
        throw new Error("Preview output directory does not exist: " + outputDirectory.fsName);
    if (outputFile.exists && !outputFile.remove())
        throw new Error("Could not remove stale Photoshop preview: " + outputFile.fsName);

    var previousDialogs = app.displayDialogs;
    var document = null;
    try {
        app.displayDialogs = DialogModes.NO;
        document = app.open(sourceFile);

        var options = new PNGSaveOptions();
        options.compression = 9;
        options.interlaced = false;
        document.saveAs(outputFile, options, true, Extension.LOWERCASE);
    } finally {
        if (document != null)
            document.close(SaveOptions.DONOTSAVECHANGES);
        app.displayDialogs = previousDialogs;
    }

    outputFile.fsName;
})();

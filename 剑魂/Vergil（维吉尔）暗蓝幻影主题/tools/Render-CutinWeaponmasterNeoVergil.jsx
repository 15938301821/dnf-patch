#target photoshop

app.displayDialogs = DialogModes.NO;
app.preferences.rulerUnits = Units.PIXELS;

var themeRoot = "E:/My Project/dnf-patch/剑魂/Vergil（维吉尔）暗蓝幻影主题";
var sourceDir = themeRoot + "/frames/source/cutin_weaponmaster_neo";
var outputRoot = themeRoot + "/frames/edited/cutin_weaponmaster_neo_v1";
var pngDir = outputRoot + "/png";
var psdDir = outputRoot + "/psd";
var refBody = themeRoot + "/referencediagram/DNF剑魂3觉立绘改维吉尔.png";
var refCinema = themeRoot + "/referencediagram/DNF剑魂3觉立绘改维吉尔 (1).png";

var canvasW = 1068;
var canvasH = 600;

try {
    createFolder(outputRoot);
    createFolder(pngDir);
    createFolder(psdDir);
    logMessage("render start");

    for (var frame = 3; frame <= 26; frame++) {
        renderFrame(frame);
    }

    logMessage("render complete");
}
catch (error) {
    logMessage("ERROR " + error.toString() + " line=" + error.line);
    closeOpenDocuments();
}

function renderFrame(frame) {
    logMessage("frame " + pad3(frame) + " begin");
    var doc = app.documents.add(
        canvasW,
        canvasH,
        72,
        "cutin_weaponmaster_neo_vergil_" + pad3(frame),
        NewDocumentMode.RGB,
        DocumentFill.TRANSPARENT,
        1,
        BitsPerChannelType.EIGHT);

    app.activeDocument = doc;
    fillBackground(doc, "#030713");

    if (frame >= 24) {
        pasteCropped(refCinema, doc, [260, 170, 1585, 916], "rear spectral portrait crop", 46, BlendMode.NORMAL);
        pasteCropped(refBody, doc, [270, 95, 1595, 841], "foreground silver hair crop", 82, BlendMode.NORMAL);
    }
    else if (frame <= 4) {
        pasteCropped(refBody, doc, [160, 130, 1620, 951], "opening face and blade crop", 76, BlendMode.NORMAL);
        pasteCropped(refCinema, doc, [0, 140, 1728, 1112], "opening dark phantom crop", 38, BlendMode.SCREEN);
    }
    else if (frame >= 22) {
        pasteCropped(refCinema, doc, [0, 215, 1728, 1187], "release double figure crop", 72, BlendMode.NORMAL);
        pasteCropped(refBody, doc, [0, 250, 1728, 1222], "release armor and blade crop", 54, BlendMode.SCREEN);
    }
    else {
        pasteCropped(refCinema, doc, [0, 205, 1728, 1177], "cinematic double figure crop", 58, BlendMode.NORMAL);
        pasteCropped(refBody, doc, [0, 275, 1728, 1247], "blue black armor and icy slash crop", 68, BlendMode.SCREEN);
    }

    addColdVignette(doc, frame);
    addRifts(doc, frame);
    addBladeEnergy(doc, frame);
    addCrystals(doc, frame);
    pasteSourceFrame(doc, frame);
    addFinalColdGrade(doc, frame);

    if (frame == 12) {
        logMessage("frame " + pad3(frame) + " save layered psd");
        var psdFile = new File(psdDir + "/frame-012-layered.psd");
        var psdOptions = new PhotoshopSaveOptions();
        psdOptions.layers = true;
        doc.saveAs(psdFile, psdOptions, true, Extension.LOWERCASE);
    }

    logMessage("frame " + pad3(frame) + " export png");
    var pngFile = new File(pngDir + "/frame-" + pad3(frame) + ".png");
    var exportOptions = new ExportOptionsSaveForWeb();
    exportOptions.format = SaveDocumentType.PNG;
    exportOptions.PNG8 = false;
    exportOptions.transparency = true;
    exportOptions.interlaced = false;
    doc.exportDocument(pngFile, ExportType.SAVEFORWEB, exportOptions);
    doc.close(SaveOptions.DONOTSAVECHANGES);
    logMessage("frame " + pad3(frame) + " done");
}

function pasteSourceFrame(targetDoc, frame) {
    var file = new File(sourceDir + "/frame-" + pad3(frame) + ".png");
    var src = app.open(file);
    app.activeDocument = src;
    src.resizeCanvas(UnitValue(canvasW, "px"), UnitValue(canvasH, "px"), AnchorPosition.MIDDLELEFT);
    src.selection.selectAll();
    src.selection.copy();
    src.close(SaveOptions.DONOTSAVECHANGES);

    app.activeDocument = targetDoc;
    targetDoc.paste();
    var layer = targetDoc.activeLayer;
    layer.name = "source cut-in timing and linework #" + pad3(frame);
    layer.opacity = frame >= 24 ? 52 : 38;
    try {
        layer.blendMode = BlendMode.LUMINOSITY;
    }
    catch (e) {
        layer.blendMode = BlendMode.OVERLAY;
    }
}

function pasteCropped(fileName, targetDoc, crop, layerName, opacity, blendMode) {
    var doc = app.open(new File(fileName));
    app.activeDocument = doc;
    doc.crop([
        UnitValue(crop[0], "px"),
        UnitValue(crop[1], "px"),
        UnitValue(crop[2], "px"),
        UnitValue(crop[3], "px")
    ]);
    doc.resizeImage(UnitValue(canvasW, "px"), UnitValue(canvasH, "px"), 72, ResampleMethod.BICUBICSHARPER);
    doc.selection.selectAll();
    doc.selection.copy();
    doc.close(SaveOptions.DONOTSAVECHANGES);

    app.activeDocument = targetDoc;
    targetDoc.paste();
    var layer = targetDoc.activeLayer;
    layer.name = layerName;
    layer.opacity = opacity;
    layer.blendMode = blendMode;
}

function fillBackground(doc, hex) {
    var layer = doc.artLayers.add();
    layer.name = "cobalt black spatial background";
    doc.activeLayer = layer;
    doc.selection.selectAll();
    doc.selection.fill(makeColor(hex), ColorBlendMode.NORMAL, 100, false);
    doc.selection.deselect();
}

function addColdVignette(doc, frame) {
    var alpha = frame >= 19 && frame <= 23 ? 72 : 56;
    addPolygon(doc, "deep cobalt upper shadow", [[0, 0], [canvasW, 0], [canvasW, 125], [0, 72]], "#02040D", alpha, BlendMode.MULTIPLY, 18);
    addPolygon(doc, "cyan lower wake", [[0, 575], [canvasW, 500], [canvasW, 600], [0, 600]], "#0A3C78", 36, BlendMode.SCREEN, 28);
}

function addBladeEnergy(doc, frame) {
    if (frame <= 4) {
        addBlade(doc, "opening cyan blade glow", 620, 80, 1060, 430, 46, "#1A8FFF", 62, 18);
        addBlade(doc, "opening white blade core", 655, 105, 1050, 392, 10, "#FFFFFF", 86, 1.4);
        return;
    }
    if (frame >= 19 && frame <= 21) {
        addBlade(doc, "peak cyan blade bloom", 85, 590, 955, 18, 72, "#00D4FF", 82, 24);
        addBlade(doc, "peak white blade core", 120, 584, 925, 35, 13, "#FFFFFF", 94, 1.1);
        addBlade(doc, "secondary violet rift edge", 175, 575, 1030, 90, 18, "#6D5CFF", 48, 6);
        return;
    }
    if (frame >= 22 && frame <= 23) {
        addBlade(doc, "release horizontal icy wake", -30, 410, 1120, 170, 82, "#00D4FF", 78, 26);
        addBlade(doc, "release white slash core", -10, 384, 1100, 196, 14, "#FFFFFF", 93, 1.2);
        return;
    }
    if (frame >= 24) {
        addBlade(doc, "face closeup right icy edge", 790, 0, 1045, 600, 58, "#00D4FF", 70, 22);
        addBlade(doc, "face closeup white edge", 842, 0, 1015, 600, 11, "#FFFFFF", 88, 1.2);
        return;
    }

    var offset = (frame - 5) * 3;
    addBlade(doc, "main diagonal icy glow", 150 + offset, 590, 935 + offset, 44, 54, "#1A8FFF", 66, 18);
    addBlade(doc, "main diagonal white core", 185 + offset, 580, 905 + offset, 65, 9, "#FFFFFF", 88, 1.1);
}

function addRifts(doc, frame) {
    var boost = frame >= 19 && frame <= 23 ? 1.25 : 1.0;
    addPolyline(doc, "upper violet space fracture", [[720, 42], [835, 74], [930, 48], [1040, 88]], "#7E48FF", 5 * boost, 52, 2.2);
    addPolyline(doc, "left cyan crack", [[34, 428], [116, 390], [162, 420], [240, 374]], "#00D4FF", 4 * boost, 46, 1.8);
    addPolyline(doc, "rear purple rift", [[910, 495], [980, 438], [1066, 460]], "#8E4DFF", 6 * boost, 45, 3.0);

    if (frame >= 19 && frame <= 23) {
        addPolyline(doc, "peak fractured ring segment", [[260, 96], [368, 72], [502, 92], [638, 64]], "#00D4FF", 5, 58, 2.0);
        addPolyline(doc, "peak violet lower crack", [[180, 520], [275, 485], [350, 508], [454, 470]], "#8E4DFF", 6, 58, 2.5);
    }
}

function addCrystals(doc, frame) {
    var seed = frame * 37;
    for (var i = 0; i < 9; i++) {
        var x = 70 + ((seed + i * 109) % 930);
        var y = 50 + ((seed * 3 + i * 67) % 470);
        var size = 4 + ((seed + i * 13) % 12);
        var color = i % 3 == 0 ? "#FFFFFF" : (i % 3 == 1 ? "#00D4FF" : "#7E48FF");
        var opacity = i % 3 == 0 ? 54 : 38;
        addDiamond(doc, "cold glass fragment " + i, x, y, size, color, opacity);
    }
}

function addFinalColdGrade(doc, frame) {
    var layer = doc.artLayers.add();
    layer.name = "final cold blue grade";
    doc.activeLayer = layer;
    doc.selection.selectAll();
    doc.selection.fill(makeColor("#0A1633"), ColorBlendMode.NORMAL, frame >= 19 && frame <= 23 ? 20 : 14, false);
    doc.selection.deselect();
    layer.blendMode = BlendMode.OVERLAY;
}

function addBlade(doc, name, x1, y1, x2, y2, width, hex, opacity, blur) {
    var dx = x2 - x1;
    var dy = y2 - y1;
    var len = Math.sqrt(dx * dx + dy * dy);
    if (len < 1) {
        return;
    }
    var nx = -dy / len * width / 2;
    var ny = dx / len * width / 2;
    addPolygon(doc, name, [
        [x1 + nx, y1 + ny],
        [x2 + nx, y2 + ny],
        [x2 - nx, y2 - ny],
        [x1 - nx, y1 - ny]
    ], hex, opacity, BlendMode.SCREEN, blur);
}

function addPolyline(doc, name, points, hex, width, opacity, blur) {
    for (var i = 0; i < points.length - 1; i++) {
        addBlade(doc, name + " segment " + i, points[i][0], points[i][1], points[i + 1][0], points[i + 1][1], width, hex, opacity, blur);
    }
}

function addDiamond(doc, name, x, y, size, hex, opacity) {
    addPolygon(doc, name, [
        [x, y - size * 1.4],
        [x + size, y],
        [x, y + size * 1.4],
        [x - size, y]
    ], hex, opacity, BlendMode.SCREEN, 0.6);
}

function addPolygon(doc, name, points, hex, opacity, blendMode, blur) {
    var layer = doc.artLayers.add();
    layer.name = name;
    doc.activeLayer = layer;
    doc.selection.select(toSelectionPoints(points));
    doc.selection.fill(makeColor(hex), ColorBlendMode.NORMAL, 100, false);
    doc.selection.deselect();
    layer.opacity = opacity;
    layer.blendMode = blendMode;
    if (blur > 0) {
        layer.applyGaussianBlur(blur);
    }
}

function toSelectionPoints(points) {
    var result = [];
    for (var i = 0; i < points.length; i++) {
        result.push([Math.round(points[i][0]), Math.round(points[i][1])]);
    }
    return result;
}

function makeColor(hex) {
    var clean = hex.replace("#", "");
    var color = new SolidColor();
    color.rgb.red = parseInt(clean.substring(0, 2), 16);
    color.rgb.green = parseInt(clean.substring(2, 4), 16);
    color.rgb.blue = parseInt(clean.substring(4, 6), 16);
    return color;
}

function pad3(value) {
    var text = String(value);
    while (text.length < 3) {
        text = "0" + text;
    }
    return text;
}

function createFolder(path) {
    var folder = new Folder(path);
    if (!folder.exists) {
        folder.create();
    }
}

function closeOpenDocuments() {
    while (app.documents.length > 0) {
        app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);
    }
}

function logMessage(message) {
    var logFile = new File(outputRoot + "/render-log.txt");
    logFile.open("a");
    logFile.writeln(new Date().toString() + " " + message);
    logFile.close();
}

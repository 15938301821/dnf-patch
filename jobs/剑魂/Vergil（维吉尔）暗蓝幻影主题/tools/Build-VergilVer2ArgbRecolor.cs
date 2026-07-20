using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using ExtractorSharp.Core.Coder;
using ExtractorSharp.Core.Lib;
using ExtractorSharp.Core.Model;

internal static class BuildVergilVer2ArgbRecolor
{
    private const string ExpectedThemeId = "weaponmaster-vergil-dark-blue";
    private const int NearBlackMaxChannel = 16;
    private const int ZlibOk = 0;
    private const string ConfigSchemaFileName = "vergil-ver2-argb-recolor.config.schema.json";
    private const string BuilderSourceFileName = "Build-VergilVer2ArgbRecolor.cs";

    [DllImport("zlib1.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "compressBound")]
    private static extern uint NativeCompressBound(uint sourceLength);

    [DllImport("zlib1.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "compress")]
    private static extern int NativeCompress(
        [In, Out] byte[] destination,
        ref uint destinationLength,
        [In] byte[] source,
        uint sourceLength);

    [DllImport("zlib1.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "uncompress")]
    private static extern int NativeDecompress(
        [In, Out] byte[] destination,
        ref uint destinationLength,
        [In] byte[] source,
        uint sourceLength);

    private static readonly PaletteStop[] VergilPalette =
    {
        new PaletteStop(0.00, Color.FromArgb(0x0A, 0x16, 0x33)),
        new PaletteStop(0.25, Color.FromArgb(0x0A, 0x16, 0x33)),
        new PaletteStop(0.58, Color.FromArgb(0x1A, 0x8F, 0xFF)),
        new PaletteStop(0.82, Color.FromArgb(0x00, 0xD4, 0xFF)),
        new PaletteStop(1.00, Color.FromArgb(0xFF, 0xFF, 0xFF))
    };

    private struct PaletteStop
    {
        public double Position;
        public Color Color;

        public PaletteStop(double position, Color color)
        {
            Position = position;
            Color = color;
        }
    }

    private sealed class BuildConfig
    {
        public int schemaVersion { get; set; }
        public string themeId { get; set; }
        public SourceConfig sourceNpk { get; set; }
        public OutputConfig output { get; set; }
        public SelectionExpectations expectations { get; set; }
        public string[] allowedImgPaths { get; set; }
        public string[] excludedImgPaths { get; set; }
        public string[] excludedFrameKeys { get; set; }
    }

    private sealed class SourceConfig
    {
        public string path { get; set; }
        public string sha256 { get; set; }
        public long length { get; set; }
    }

    private sealed class OutputConfig
    {
        public string componentNpkPath { get; set; }
        public string buildSummaryPath { get; set; }
    }

    private sealed class SelectionExpectations
    {
        public int albumCount { get; set; }
        public int frameCount { get; set; }
    }

    private sealed class FrameSnapshot
    {
        public int Index;
        public ColorBits Type;
        public CompressMode CompressMode;
        public bool Hidden;
        public int TargetIndex;
        public int Width;
        public int Height;
        public int CanvasWidth;
        public int CanvasHeight;
        public int X;
        public int Y;
        public int SourceLength;
        public byte[] SourceData;
        public byte[] SourceRaw;
        public byte[] SourceBgra;
        public int VisiblePixels;
        public bool NearBlack;
        public bool ExplicitlyExcluded;
        public bool Eligible;
        public bool Changed;
        public string SkipReason;
        public int ChangedVisiblePixels;
        public FrameResult Result;
    }

    private sealed class AlbumSnapshot
    {
        public string Path;
        public string Version;
        public int TableIndex;
        public string TableSignature;
        public List<FrameSnapshot> Frames = new List<FrameSnapshot>();
    }

    private sealed class BuildStats
    {
        public int Albums;
        public int Frames;
        public int LinkFrames;
        public int EligibleFrames;
        public int ChangedFrames;
        public int ChangedArgb1555Frames;
        public int ChangedArgb8888Frames;
        public int SkippedFrames;
        public int ExplicitlyExcludedFrames;
        public int HiddenFrames;
        public int TransparentFrames;
        public int NearBlackFrames;
        public int NoColorChangeFrames;
        public int AuthorizedAlphaVerified;
        public int AuthorizedNearBlackVerified;
        public int UnauthorizedRawVerified;
        public int UnauthorizedBgraVerified;
    }

    private sealed class FrameResult
    {
        public string imgPath { get; set; }
        public string imgVersion { get; set; }
        public int frameIndex { get; set; }
        public string type { get; set; }
        public string compressMode { get; set; }
        public bool hidden { get; set; }
        public int? linkTargetIndex { get; set; }
        public string decision { get; set; }
        public string skipReason { get; set; }
        public int width { get; set; }
        public int height { get; set; }
        public int canvasWidth { get; set; }
        public int canvasHeight { get; set; }
        public int x { get; set; }
        public int y { get; set; }
        public int? sourceLength { get; set; }
        public int? outputLength { get; set; }
        public int changedVisiblePixels { get; set; }
        public string sourceDataSha256 { get; set; }
        public string outputDataSha256 { get; set; }
        public string sourceRawSha256 { get; set; }
        public string outputRawSha256 { get; set; }
        public string sourceBgraSha256 { get; set; }
        public string outputBgraSha256 { get; set; }
        public string sourceAlphaSha256 { get; set; }
        public string outputAlphaSha256 { get; set; }
    }

    private sealed class BuildSummary
    {
        public int schemaVersion { get; set; }
        public string generatedAtUtc { get; set; }
        public string status { get; set; }
        public string themeId { get; set; }
        public SummarySource source { get; set; }
        public SummaryToolchain toolchain { get; set; }
        public SummaryOutput output { get; set; }
        public SummarySelection selection { get; set; }
        public SummaryCounts counts { get; set; }
        public SummaryValidation validation { get; set; }
        public List<AlbumResult> albums { get; set; }
        public List<FrameResult> frames { get; set; }
        public SummaryDeployment deployment { get; set; }
    }

    private sealed class SummaryToolchain
    {
        public SummaryArtifact config { get; set; }
        public SummaryArtifact configSchema { get; set; }
        public SummaryArtifact builderSource { get; set; }
        public SummaryArtifact builderExecutable { get; set; }
        public SummaryArtifact extractorSharpCore { get; set; }
        public SummaryArtifact extractorSharpJson { get; set; }
        public SummaryArtifact zlib { get; set; }
    }

    private sealed class SummaryArtifact
    {
        public string path { get; set; }
        public long length { get; set; }
        public string lastWriteTimeUtc { get; set; }
        public string sha256 { get; set; }
        public string version { get; set; }
    }

    private sealed class AlbumResult
    {
        public string imgPath { get; set; }
        public string imgVersion { get; set; }
        public int tableIndex { get; set; }
        public string tableSignatureSha256 { get; set; }
        public int frameCount { get; set; }
        public int linkFrameCount { get; set; }
    }

    private sealed class SummarySource
    {
        public string path { get; set; }
        public long length { get; set; }
        public string lastWriteTimeUtc { get; set; }
        public string sha256 { get; set; }
    }

    private sealed class SummaryOutput
    {
        public string componentNpkPath { get; set; }
        public long length { get; set; }
        public string sha256 { get; set; }
        public string buildSummaryPath { get; set; }
    }

    private sealed class SummarySelection
    {
        public int expectedAlbumCount { get; set; }
        public int expectedFrameCount { get; set; }
        public string[] allowedImgPaths { get; set; }
        public string[] explicitExcludedImgPaths { get; set; }
        public string[] explicitExcludedFrameKeys { get; set; }
        public string[] palette { get; set; }
        public string[] paletteStops { get; set; }
        public int nearBlackMaxChannel { get; set; }
    }

    private sealed class SummaryCounts
    {
        public int albums { get; set; }
        public int frames { get; set; }
        public int linkFrames { get; set; }
        public int eligibleFrames { get; set; }
        public int changedFrames { get; set; }
        public int changedArgb1555Frames { get; set; }
        public int changedArgb8888Frames { get; set; }
        public int skippedFrames { get; set; }
        public int explicitExcludedFrames { get; set; }
        public int hiddenFrames { get; set; }
        public int transparentFrames { get; set; }
        public int nearBlackFrames { get; set; }
        public int noColorChangeFrames { get; set; }
    }

    private sealed class SummaryValidation
    {
        public string sourceIdentityReverified { get; set; }
        public string reopenedFromDisk { get; set; }
        public string structureAndFrameOrder { get; set; }
        public string typeAndCompression { get; set; }
        public string geometryAndLinks { get; set; }
        public string nativeZlibStatusAndLength { get; set; }
        public string authorizedDecodedAlpha { get; set; }
        public string authorizedVisibleNearBlackRgb { get; set; }
        public string unauthorizedRawData { get; set; }
        public string unauthorizedDecodedBgra { get; set; }
        public string independentNpkIndex { get; set; }
        public string independentFullFrameDecode { get; set; }
        public int authorizedAlphaVerifiedFrames { get; set; }
        public int authorizedNearBlackVerifiedFrames { get; set; }
        public int unauthorizedRawVerifiedFrames { get; set; }
        public int unauthorizedBgraVerifiedFrames { get; set; }
    }

    private sealed class SummaryDeployment
    {
        public bool performed { get; set; }
        public string status { get; set; }
    }

    private static int Main(string[] args)
    {
        try
        {
            return Run(args);
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("ErrorType=" + exception.GetType().FullName);
            Console.Error.WriteLine("ErrorMessage=" + exception.Message);
            if (exception.InnerException != null)
            {
                Console.Error.WriteLine("InnerType=" + exception.InnerException.GetType().FullName);
                Console.Error.WriteLine("InnerMessage=" + exception.InnerException.Message);
            }
            Console.Error.WriteLine("Stack=" + exception.StackTrace);
            return 1;
        }
    }

    private static int Run(string[] args)
    {
        if (args.Length != 3)
        {
            Console.Error.WriteLine("Usage: <config.json> <source-npk> <builder-source.cs>");
            return 2;
        }

        string configFile = Path.GetFullPath(args[0]);
        string sourceFile = Path.GetFullPath(args[1]);
        string builderSourceFile = Path.GetFullPath(args[2]);
        RequireFile(configFile, "build config");
        RequireFile(sourceFile, "source NPK");
        RequireFile(builderSourceFile, "builder source");
        if (!String.Equals(Path.GetFileName(builderSourceFile), BuilderSourceFileName, StringComparison.Ordinal))
            throw new InvalidDataException("Unexpected builder source filename: " + builderSourceFile);
        string configSchemaFile = Path.Combine(Path.GetDirectoryName(builderSourceFile), ConfigSchemaFileName);
        RequireFile(configSchemaFile, "build config schema");
        string configHash = HashFile(configFile);
        BuildConfig config = LoadConfig(configFile);
        RequireUnchangedHash(configFile, configHash, "Build config changed while it was being loaded.");
        string configDirectory = Path.GetDirectoryName(configFile);
        string outputFile = ResolveConfiguredPath(configDirectory, config.output.componentNpkPath);
        string summaryFile = ResolveConfiguredPath(configDirectory, config.output.buildSummaryPath);
        ValidateResolvedPaths(sourceFile, outputFile, summaryFile);
        if (!String.Equals(
            Path.GetFileName(sourceFile),
            Path.GetFileName(config.sourceNpk.path),
            StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Source override filename differs from config sourceNpk.path.");
        if (File.Exists(outputFile))
            throw new IOException("Refusing to overwrite an existing component NPK: " + outputFile);
        if (File.Exists(summaryFile))
            throw new IOException("Refusing to overwrite an existing build summary: " + summaryFile);

        FileInfo sourceInfo = VerifySourceIdentity(
            sourceFile,
            config.sourceNpk.length,
            config.sourceNpk.sha256,
            "before loading");
        string sourceHash = config.sourceNpk.sha256.ToUpperInvariant();

        HashSet<string> allowedPaths = BuildAllowedPathSet(config.allowedImgPaths);
        HashSet<string> excludedPaths = BuildExcludedPathSet(config.excludedImgPaths, allowedPaths);
        HashSet<string> excludedFrames = BuildExcludedFrameSet(config.excludedFrameKeys, allowedPaths);
        HashSet<string> matchedExcludedFrames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        List<Album> analysisAll = NpkCoder.Load(sourceFile);
        ValidateExcludedPathsExist(analysisAll, excludedPaths);
        List<Album> analysisAlbums = SelectAllowedAlbums(analysisAll, allowedPaths);
        BuildStats stats = new BuildStats();
        List<AlbumSnapshot> snapshots = CaptureSource(
            analysisAlbums,
            excludedFrames,
            matchedExcludedFrames,
            stats);
        ValidateSelectionExpectations(config.expectations, snapshots, stats);
        ValidateExcludedFramesMatched(excludedFrames, matchedExcludedFrames);

        List<Album> buildAll = NpkCoder.Load(sourceFile);
        List<Album> buildAlbums = SelectAllowedAlbums(buildAll, allowedPaths);
        sourceInfo = VerifySourceIdentity(
            sourceFile,
            config.sourceNpk.length,
            sourceHash,
            "after both source loads");
        RequireUnchangedHash(configFile, configHash, "Build config changed after source selection.");
        ApplyRecolor(buildAlbums, snapshots, stats);
        RequireChangedFramePerAlbum(snapshots);
        EnsureBuildTreeClosed(buildAlbums);

        Directory.CreateDirectory(Path.GetDirectoryName(outputFile));
        Directory.CreateDirectory(Path.GetDirectoryName(summaryFile));
        string temporaryOutput = Path.Combine(
            Path.GetDirectoryName(outputFile),
            "." + Path.GetFileNameWithoutExtension(outputFile) + ".candidate-" + Guid.NewGuid().ToString("N") + ".NPK");
        try
        {
            NpkCoder.Save(temporaryOutput, buildAlbums);
            ValidateOutput(temporaryOutput, snapshots, stats);
            File.Move(temporaryOutput, outputFile);
        }
        finally
        {
            if (File.Exists(temporaryOutput))
                File.Delete(temporaryOutput);
        }

        sourceInfo = VerifySourceIdentity(
            sourceFile,
            config.sourceNpk.length,
            sourceHash,
            "before summary creation");
        RequireUnchangedHash(configFile, configHash, "Build config changed before summary creation.");
        BuildSummary summary = CreateSummary(
            config,
            configFile,
            configSchemaFile,
            builderSourceFile,
            sourceFile,
            sourceInfo,
            sourceHash,
            outputFile,
            summaryFile,
            snapshots,
            stats);
        WriteJsonAtomically(summaryFile, summary);

        Console.WriteLine("Source=" + sourceFile);
        Console.WriteLine("SourceSha256=" + sourceHash);
        Console.WriteLine("Output=" + outputFile);
        Console.WriteLine("OutputLength=" + new FileInfo(outputFile).Length);
        Console.WriteLine("OutputSha256=" + HashFile(outputFile));
        Console.WriteLine("BuildSummary=" + summaryFile);
        Console.WriteLine("Albums=" + stats.Albums);
        Console.WriteLine("Frames=" + stats.Frames);
        Console.WriteLine("ChangedFrames=" + stats.ChangedFrames);
        Console.WriteLine("SkippedFrames=" + stats.SkippedFrames);
        Console.WriteLine("StructureValidation=passed");
        Console.WriteLine("Deployment=not-performed");
        return 0;
    }

    private static BuildConfig LoadConfig(string configFile)
    {
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        serializer.MaxJsonLength = Int32.MaxValue;
        BuildConfig config = serializer.Deserialize<BuildConfig>(File.ReadAllText(configFile, Encoding.UTF8));
        if (config == null)
            throw new InvalidDataException("Build config is empty.");
        if (config.schemaVersion != 1)
            throw new InvalidDataException("Unsupported config schemaVersion: " + config.schemaVersion);
        if (!String.Equals(config.themeId, ExpectedThemeId, StringComparison.Ordinal))
            throw new InvalidDataException("Config themeId must be " + ExpectedThemeId + ".");
        if (config.sourceNpk == null || String.IsNullOrWhiteSpace(config.sourceNpk.path))
            throw new InvalidDataException("Config sourceNpk.path is required.");
        if (!IsSha256(config.sourceNpk.sha256))
            throw new InvalidDataException("Config sourceNpk.sha256 must contain 64 hexadecimal characters.");
        if (config.sourceNpk.length < 1)
            throw new InvalidDataException("Config sourceNpk.length must be positive.");
        if (config.output == null ||
            String.IsNullOrWhiteSpace(config.output.componentNpkPath) ||
            String.IsNullOrWhiteSpace(config.output.buildSummaryPath))
            throw new InvalidDataException("Config output paths are required.");
        if (config.expectations == null ||
            config.expectations.albumCount < 1 ||
            config.expectations.frameCount < 1)
            throw new InvalidDataException("Config expectations.albumCount and frameCount must be positive.");
        if (config.allowedImgPaths == null || config.allowedImgPaths.Length == 0)
            throw new InvalidDataException("Config allowedImgPaths must not be empty.");
        if (config.excludedImgPaths == null)
            throw new InvalidDataException("Config excludedImgPaths must be present; use an empty array when none are excluded.");
        if (config.excludedFrameKeys == null)
            throw new InvalidDataException("Config excludedFrameKeys must be present; use an empty array when none are excluded.");
        return config;
    }

    private static void ValidateResolvedPaths(string sourceFile, string outputFile, string summaryFile)
    {
        if (!String.Equals(Path.GetExtension(outputFile), ".NPK", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Component output must use the .NPK extension: " + outputFile);
        if (!String.Equals(Path.GetFileName(summaryFile), "build-summary.json", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Build summary filename must be build-summary.json: " + summaryFile);
        if (String.Equals(sourceFile, outputFile, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Source and output NPK paths must differ.");
        if (String.Equals(Path.GetFileName(sourceFile), Path.GetFileName(outputFile), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Component NPK must not impersonate the official source filename.");
    }

    private static HashSet<string> BuildAllowedPathSet(string[] values)
    {
        HashSet<string> result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string value in values)
        {
            string normalized = NormalizeImgPath(value);
            if (!normalized.EndsWith(".img", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Allowed IMG path must end in .img: " + value);
            if (!result.Add(normalized))
                throw new InvalidDataException("Duplicate allowed IMG path: " + normalized);
        }
        return result;
    }

    private static HashSet<string> BuildExcludedPathSet(
        string[] values,
        HashSet<string> allowedPaths)
    {
        HashSet<string> result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string value in values)
        {
            string normalized = NormalizeImgPath(value);
            if (!normalized.EndsWith(".img", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Excluded IMG path must end in .img: " + value);
            if (allowedPaths.Contains(normalized))
                throw new InvalidDataException("IMG path cannot be both allowed and excluded: " + normalized);
            if (!result.Add(normalized))
                throw new InvalidDataException("Duplicate excluded IMG path: " + normalized);
        }
        return result;
    }

    private static void ValidateExcludedPathsExist(
        List<Album> albums,
        HashSet<string> excludedPaths)
    {
        if (albums == null)
            throw new InvalidDataException("ExtractorSharp returned no NPK album list.");
        HashSet<string> sourcePaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (Album album in albums)
            sourcePaths.Add(NormalizeImgPath(album.Path));
        foreach (string excludedPath in excludedPaths)
        {
            if (!sourcePaths.Contains(excludedPath))
                throw new InvalidDataException("Excluded IMG path was not found in source NPK: " + excludedPath);
        }
    }

    private static HashSet<string> BuildExcludedFrameSet(string[] values, HashSet<string> allowedPaths)
    {
        HashSet<string> result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string value in values)
        {
            int separator = value == null ? -1 : value.LastIndexOf('#');
            int frameIndex;
            if (separator < 1 || separator == value.Length - 1 ||
                !Int32.TryParse(value.Substring(separator + 1), out frameIndex) || frameIndex < 0)
                throw new InvalidDataException("Invalid excluded frame key: " + value);
            string path = NormalizeImgPath(value.Substring(0, separator));
            if (!allowedPaths.Contains(path))
                throw new InvalidDataException("Excluded frame is outside allowedImgPaths: " + value);
            string key = BuildFrameKey(path, frameIndex);
            if (!result.Add(key))
                throw new InvalidDataException("Duplicate excluded frame key: " + key);
        }
        return result;
    }

    private static List<Album> SelectAllowedAlbums(List<Album> albums, HashSet<string> allowedPaths)
    {
        if (albums == null)
            throw new InvalidDataException("ExtractorSharp returned no NPK album list.");
        List<Album> result = new List<Album>();
        HashSet<string> allPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        HashSet<string> selectedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (Album album in albums)
        {
            string normalized = NormalizeImgPath(album.Path);
            if (!allPaths.Add(normalized))
                throw new InvalidDataException("Source NPK contains a duplicate IMG path: " + normalized);
            if (allowedPaths.Contains(normalized))
            {
                result.Add(album);
                selectedPaths.Add(normalized);
            }
        }
        foreach (string required in allowedPaths)
        {
            if (!selectedPaths.Contains(required))
                throw new InvalidDataException("Allowed IMG path was not found in source NPK: " + required);
        }
        if (result.Count != allowedPaths.Count)
            throw new InvalidDataException("Allowed IMG selection count is inconsistent.");
        return result;
    }

    private static List<AlbumSnapshot> CaptureSource(
        List<Album> albums,
        HashSet<string> excludedFrames,
        HashSet<string> matchedExcludedFrames,
        BuildStats stats)
    {
        List<AlbumSnapshot> result = new List<AlbumSnapshot>();
        foreach (Album album in albums)
        {
            if (!String.Equals(album.Version.ToString(), "Ver2", StringComparison.Ordinal))
                throw new InvalidDataException("Allowed IMG is not Ver2: " + album.Path);
            if (album.List == null)
                throw new InvalidDataException("Allowed IMG has no frame list: " + album.Path);

            AlbumSnapshot albumSnapshot = new AlbumSnapshot();
            albumSnapshot.Path = NormalizeImgPath(album.Path);
            albumSnapshot.Version = album.Version.ToString();
            albumSnapshot.TableIndex = album.TableIndex;
            albumSnapshot.TableSignature = GetTableSignature(album);
            HashSet<int> frameIndexes = new HashSet<int>();

            foreach (Sprite sprite in album.List)
            {
                if (!frameIndexes.Add(sprite.Index))
                    throw new InvalidDataException("Allowed IMG contains a duplicate frame index: " + album.Path + "#" + sprite.Index);
                string frameKey = BuildFrameKey(albumSnapshot.Path, sprite.Index);
                bool explicitlyExcluded = excludedFrames.Contains(frameKey);
                if (explicitlyExcluded)
                    matchedExcludedFrames.Add(frameKey);

                FrameSnapshot frame = CaptureFrame(sprite, explicitlyExcluded);
                ClassifyFrame(albumSnapshot.Path, frame, stats);
                frame.Result = CreateFrameResult(albumSnapshot.Path, albumSnapshot.Version, frame);
                albumSnapshot.Frames.Add(frame);
            }

            stats.Albums++;
            stats.Frames += albumSnapshot.Frames.Count;
            result.Add(albumSnapshot);
        }
        return result;
    }

    private static FrameSnapshot CaptureFrame(Sprite sprite, bool explicitlyExcluded)
    {
        FrameSnapshot frame = new FrameSnapshot();
        frame.Index = sprite.Index;
        frame.Type = sprite.Type;
        frame.CompressMode = sprite.CompressMode;
        frame.Hidden = sprite.Hidden;
        frame.TargetIndex = sprite.Target == null ? -1 : sprite.Target.Index;
        frame.Width = sprite.Width;
        frame.Height = sprite.Height;
        frame.CanvasWidth = sprite.CanvasWidth;
        frame.CanvasHeight = sprite.CanvasHeight;
        frame.X = sprite.X;
        frame.Y = sprite.Y;
        frame.SourceLength = sprite.Length;
        frame.SourceData = CloneBytes(sprite.Data);
        frame.ExplicitlyExcluded = explicitlyExcluded;

        if (sprite.Type == ColorBits.LINK)
            return frame;
        ValidateArgbDeclaration(sprite);
        frame.SourceRaw = DecodeRawData(sprite.Type, sprite.CompressMode, sprite.Data, sprite.Width, sprite.Height);
        frame.SourceBgra = DecodeArgbPixels(sprite.Type, frame.SourceRaw, sprite.Width, sprite.Height);
        frame.VisiblePixels = CountVisiblePixels(frame.SourceBgra);
        frame.NearBlack = IsNearBlackFrame(frame.SourceBgra);
        return frame;
    }

    private static void ValidateArgbDeclaration(Sprite sprite)
    {
        string label = "frame " + sprite.Index;
        if (sprite.Type != ColorBits.ARGB_1555 && sprite.Type != ColorBits.ARGB_8888)
            throw new InvalidDataException("Ver2 frame is not ARGB_1555 or ARGB_8888: " + label);
        if (sprite.CompressMode != CompressMode.ZLIB && sprite.CompressMode != CompressMode.NONE)
            throw new InvalidDataException("Ver2 ARGB frame is not ZLIB or NONE: " + label);
        if (sprite.Width < 1 || sprite.Height < 1)
            throw new InvalidDataException("Ver2 frame dimensions are invalid: " + label);
        if (sprite.Data == null || sprite.Data.Length != sprite.Length)
            throw new InvalidDataException("Ver2 frame Data/Length is inconsistent: " + label);
    }

    private static void ClassifyFrame(string albumPath, FrameSnapshot frame, BuildStats stats)
    {
        if (frame.Type == ColorBits.LINK)
        {
            frame.SkipReason = "link";
            stats.LinkFrames++;
        }
        else if (frame.ExplicitlyExcluded)
        {
            frame.SkipReason = "explicit-excluded";
            stats.ExplicitlyExcludedFrames++;
        }
        else if (frame.Hidden)
        {
            frame.SkipReason = "hidden";
            stats.HiddenFrames++;
        }
        else if (frame.VisiblePixels == 0)
        {
            frame.SkipReason = "fully-transparent";
            stats.TransparentFrames++;
        }
        else if (frame.NearBlack)
        {
            frame.SkipReason = "near-black";
            stats.NearBlackFrames++;
        }
        else
        {
            frame.Eligible = true;
            stats.EligibleFrames++;
            return;
        }
        stats.SkippedFrames++;
    }

    private static FrameResult CreateFrameResult(string albumPath, string albumVersion, FrameSnapshot frame)
    {
        FrameResult result = new FrameResult();
        result.imgPath = albumPath;
        result.imgVersion = albumVersion;
        result.frameIndex = frame.Index;
        result.type = frame.Type.ToString();
        result.compressMode = frame.Type == ColorBits.LINK ? null : frame.CompressMode.ToString();
        result.hidden = frame.Hidden;
        result.linkTargetIndex = frame.Type == ColorBits.LINK ? (int?)frame.TargetIndex : null;
        result.decision = frame.Eligible ? "eligible" : "skipped";
        result.skipReason = frame.SkipReason;
        result.width = frame.Width;
        result.height = frame.Height;
        result.canvasWidth = frame.CanvasWidth;
        result.canvasHeight = frame.CanvasHeight;
        result.x = frame.X;
        result.y = frame.Y;
        if (frame.Type != ColorBits.LINK)
        {
            result.sourceLength = frame.SourceLength;
            result.sourceDataSha256 = HashBytes(frame.SourceData);
            result.sourceRawSha256 = HashBytes(frame.SourceRaw);
            result.sourceBgraSha256 = HashBytes(frame.SourceBgra);
            result.sourceAlphaSha256 = HashBytes(GetAlphaBytes(frame.SourceBgra));
        }
        return result;
    }

    private static void ValidateSelectionExpectations(
        SelectionExpectations expectations,
        List<AlbumSnapshot> albums,
        BuildStats stats)
    {
        if (albums.Count != expectations.albumCount)
            throw new InvalidDataException("Selected IMG count changed: " + albums.Count + "/" + expectations.albumCount);
        if (stats.Frames != expectations.frameCount)
            throw new InvalidDataException("Selected frame count changed: " + stats.Frames + "/" + expectations.frameCount);
    }

    private static void ValidateExcludedFramesMatched(
        HashSet<string> excludedFrames,
        HashSet<string> matchedExcludedFrames)
    {
        foreach (string frameKey in excludedFrames)
        {
            if (!matchedExcludedFrames.Contains(frameKey))
                throw new InvalidDataException("Explicit excluded frame was not found: " + frameKey);
        }
    }

    private static void ApplyRecolor(
        List<Album> buildAlbums,
        List<AlbumSnapshot> sourceAlbums,
        BuildStats stats)
    {
        if (buildAlbums.Count != sourceAlbums.Count)
            throw new InvalidDataException("Build album selection changed between source loads.");
        for (int albumIndex = 0; albumIndex < buildAlbums.Count; albumIndex++)
        {
            Album buildAlbum = buildAlbums[albumIndex];
            AlbumSnapshot sourceAlbum = sourceAlbums[albumIndex];
            if (!String.Equals(NormalizeImgPath(buildAlbum.Path), sourceAlbum.Path, StringComparison.OrdinalIgnoreCase) ||
                buildAlbum.List.Count != sourceAlbum.Frames.Count)
                throw new InvalidDataException("Build album structure changed: " + buildAlbum.Path);

            for (int framePosition = 0; framePosition < buildAlbum.List.Count; framePosition++)
            {
                Sprite buildSprite = buildAlbum.List[framePosition];
                FrameSnapshot sourceFrame = sourceAlbum.Frames[framePosition];
                if (buildSprite.Index != sourceFrame.Index)
                    throw new InvalidDataException("Build frame order changed: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                if (!sourceFrame.Eligible)
                    continue;

                int changedVisiblePixels;
                byte[] recoloredRaw = RecolorRawPixels(
                    sourceFrame.Type,
                    sourceFrame.SourceRaw,
                    sourceFrame.Width,
                    sourceFrame.Height,
                    out changedVisiblePixels);
                if (changedVisiblePixels == 0)
                {
                    sourceFrame.Eligible = false;
                    sourceFrame.SkipReason = "no-visible-color-change";
                    sourceFrame.Result.decision = "skipped";
                    sourceFrame.Result.skipReason = sourceFrame.SkipReason;
                    stats.EligibleFrames--;
                    stats.SkippedFrames++;
                    stats.NoColorChangeFrames++;
                    continue;
                }

                byte[] storedData = sourceFrame.CompressMode == CompressMode.ZLIB
                    ? CompressZlibChecked(recoloredRaw)
                    : recoloredRaw;
                if (storedData == null || storedData.Length == 0)
                    throw new InvalidDataException("ARGB recolor produced an empty frame payload: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                buildSprite.Data = storedData;
                buildSprite.Length = storedData.Length;
                sourceFrame.Changed = true;
                sourceFrame.ChangedVisiblePixels = changedVisiblePixels;
                sourceFrame.Result.decision = "changed";
                sourceFrame.Result.skipReason = null;
                sourceFrame.Result.changedVisiblePixels = changedVisiblePixels;
                stats.ChangedFrames++;
                if (sourceFrame.Type == ColorBits.ARGB_1555)
                    stats.ChangedArgb1555Frames++;
                else
                    stats.ChangedArgb8888Frames++;
            }
        }
    }

    private static void RequireChangedFramePerAlbum(List<AlbumSnapshot> albums)
    {
        List<string> unchangedAlbums = new List<string>();
        foreach (AlbumSnapshot album in albums)
        {
            bool changed = false;
            foreach (FrameSnapshot frame in album.Frames)
            {
                if (frame.Changed)
                {
                    changed = true;
                    break;
                }
            }
            if (!changed)
                unchangedAlbums.Add(album.Path);
        }
        if (unchangedAlbums.Count > 0)
            throw new InvalidDataException(
                "Allowed IMGs have no changed frame and must not be copied into a component NPK: " +
                String.Join(", ", unchangedAlbums.ToArray()));
    }

    private static void ValidateOutput(
        string outputFile,
        List<AlbumSnapshot> sourceAlbums,
        BuildStats stats)
    {
        List<Album> outputAlbums = NpkCoder.Load(outputFile);
        if (outputAlbums.Count != sourceAlbums.Count)
            throw new InvalidDataException("Output component IMG count changed.");

        for (int albumIndex = 0; albumIndex < outputAlbums.Count; albumIndex++)
        {
            Album outputAlbum = outputAlbums[albumIndex];
            AlbumSnapshot sourceAlbum = sourceAlbums[albumIndex];
            ValidateAlbumMetadata(outputAlbum, sourceAlbum);
            for (int framePosition = 0; framePosition < outputAlbum.List.Count; framePosition++)
            {
                Sprite outputSprite = outputAlbum.List[framePosition];
                FrameSnapshot sourceFrame = sourceAlbum.Frames[framePosition];
                ValidateFrameMetadata(outputAlbum, outputSprite, sourceFrame);
                if (sourceFrame.Type == ColorBits.LINK)
                {
                    continue;
                }

                byte[] outputRaw = DecodeRawData(
                    outputSprite.Type,
                    outputSprite.CompressMode,
                    outputSprite.Data,
                    outputSprite.Width,
                    outputSprite.Height);
                byte[] outputBgra = DecodeArgbPixels(
                    outputSprite.Type,
                    outputRaw,
                    outputSprite.Width,
                    outputSprite.Height);
                int visibleRgbChanges = CountVisibleRgbChanges(sourceFrame.SourceBgra, outputBgra);

                if (sourceFrame.Changed)
                {
                    if (!AlphaBytesEqual(sourceFrame.SourceBgra, outputBgra))
                        throw new InvalidDataException("Authorized decoded alpha changed: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                    if (!VisibleNearBlackRgbEqual(sourceFrame.SourceBgra, outputBgra))
                        throw new InvalidDataException("Authorized visible near-black RGB changed: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                    if (visibleRgbChanges < 1)
                        throw new InvalidDataException("Authorized frame has no visible RGB change: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                    if (CountWarmVisiblePixels(outputBgra) != 0)
                        throw new InvalidDataException("Authorized frame contains warm visible pixels: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                    stats.AuthorizedAlphaVerified++;
                    stats.AuthorizedNearBlackVerified++;
                }
                else
                {
                    if (!BytesEqual(sourceFrame.SourceData, outputSprite.Data) ||
                        !BytesEqual(sourceFrame.SourceRaw, outputRaw) ||
                        !BytesEqual(sourceFrame.SourceBgra, outputBgra))
                        throw new InvalidDataException("Unauthorized frame changed: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                    stats.UnauthorizedRawVerified++;
                    stats.UnauthorizedBgraVerified++;
                }

                sourceFrame.Result.changedVisiblePixels = visibleRgbChanges;
                sourceFrame.Result.outputLength = outputSprite.Length;
                sourceFrame.Result.outputDataSha256 = HashBytes(outputSprite.Data);
                sourceFrame.Result.outputRawSha256 = HashBytes(outputRaw);
                sourceFrame.Result.outputBgraSha256 = HashBytes(outputBgra);
                sourceFrame.Result.outputAlphaSha256 = HashBytes(GetAlphaBytes(outputBgra));
            }
        }

        int nonLinkFrames = stats.Frames - stats.LinkFrames;
        if (stats.ChangedFrames + stats.SkippedFrames != stats.Frames)
            throw new InvalidDataException("Frame decision count is inconsistent.");
        if (stats.EligibleFrames != stats.ChangedFrames)
            throw new InvalidDataException("Eligible frame count is inconsistent after recoloring.");
        if (stats.AuthorizedAlphaVerified != stats.ChangedFrames)
            throw new InvalidDataException("Authorized alpha validation count is inconsistent.");
        if (stats.AuthorizedNearBlackVerified != stats.ChangedFrames)
            throw new InvalidDataException("Authorized near-black RGB validation count is inconsistent.");
        if (stats.UnauthorizedRawVerified != nonLinkFrames - stats.ChangedFrames)
            throw new InvalidDataException("Unauthorized raw validation count is inconsistent.");
        if (stats.UnauthorizedBgraVerified != nonLinkFrames - stats.ChangedFrames)
            throw new InvalidDataException("Unauthorized BGRA validation count is inconsistent.");
    }

    private static void ValidateAlbumMetadata(Album output, AlbumSnapshot source)
    {
        if (!String.Equals(NormalizeImgPath(output.Path), source.Path, StringComparison.OrdinalIgnoreCase) ||
            !String.Equals(output.Version.ToString(), source.Version, StringComparison.Ordinal) ||
            output.TableIndex != source.TableIndex ||
            !String.Equals(GetTableSignature(output), source.TableSignature, StringComparison.Ordinal) ||
            output.List == null || output.List.Count != source.Frames.Count)
            throw new InvalidDataException("Output IMG structure changed: " + source.Path);
    }

    private static void ValidateFrameMetadata(Album outputAlbum, Sprite output, FrameSnapshot source)
    {
        int targetIndex = output.Target == null ? -1 : output.Target.Index;
        if (output.Index != source.Index ||
            output.Type != source.Type ||
            output.CompressMode != source.CompressMode ||
            output.Hidden != source.Hidden ||
            targetIndex != source.TargetIndex ||
            output.Width != source.Width ||
            output.Height != source.Height ||
            output.CanvasWidth != source.CanvasWidth ||
            output.CanvasHeight != source.CanvasHeight ||
            output.X != source.X ||
            output.Y != source.Y)
            throw new InvalidDataException("Output frame metadata changed: " + BuildFrameKey(outputAlbum.Path, output.Index));

        if (source.Type == ColorBits.LINK)
            return;
        if (output.Data == null || output.Data.Length != output.Length)
            throw new InvalidDataException("Output frame Data/Length is inconsistent: " + BuildFrameKey(outputAlbum.Path, output.Index));
        if (!source.Changed || source.CompressMode == CompressMode.NONE)
        {
            if (output.Length != source.SourceLength)
                throw new InvalidDataException("Output frame Length semantics changed: " + BuildFrameKey(outputAlbum.Path, output.Index));
        }
    }

    private static byte[] CompressZlibChecked(byte[] source)
    {
        if (source == null || source.Length == 0)
            throw new InvalidDataException("Cannot zlib-compress an empty ARGB payload.");
        uint sourceLength = checked((uint)source.Length);
        uint capacity = NativeCompressBound(sourceLength);
        if (capacity == 0 || capacity > Int32.MaxValue)
            throw new InvalidDataException("zlib compressBound returned an invalid capacity: " + capacity);
        byte[] buffer = new byte[(int)capacity];
        uint outputLength = capacity;
        int status = NativeCompress(buffer, ref outputLength, source, sourceLength);
        if (status != ZlibOk)
            throw new InvalidDataException("zlib compress failed with status " + status + ".");
        if (outputLength == 0 || outputLength > capacity || outputLength > Int32.MaxValue)
            throw new InvalidDataException("zlib compress returned an invalid output length: " + outputLength);
        byte[] result = new byte[(int)outputLength];
        Buffer.BlockCopy(buffer, 0, result, 0, result.Length);
        return result;
    }

    private static byte[] DecompressZlibChecked(byte[] source, int expectedLength)
    {
        if (source == null || source.Length == 0)
            throw new InvalidDataException("Cannot zlib-decompress an empty ARGB payload.");
        if (expectedLength < 1)
            throw new InvalidDataException("Expected zlib output length must be positive.");
        byte[] result = new byte[expectedLength];
        uint outputLength = checked((uint)expectedLength);
        int status = NativeDecompress(
            result,
            ref outputLength,
            source,
            checked((uint)source.Length));
        if (status != ZlibOk)
            throw new InvalidDataException("zlib decompress failed with status " + status + ".");
        if (outputLength != (uint)expectedLength)
            throw new InvalidDataException(
                "zlib decompressed length is invalid: " + outputLength + "/" + expectedLength);
        return result;
    }

    private static byte[] DecodeRawData(
        ColorBits type,
        CompressMode compressMode,
        byte[] storedData,
        int width,
        int height)
    {
        int bytesPerPixel = BytesPerPixel(type);
        int expectedLength = checked(width * height * bytesPerPixel);
        if (storedData == null)
            throw new InvalidDataException("Stored ARGB data is null.");
        byte[] raw;
        if (compressMode == CompressMode.ZLIB)
            raw = DecompressZlibChecked(storedData, expectedLength);
        else if (compressMode == CompressMode.NONE)
            raw = CloneBytes(storedData);
        else
            throw new InvalidDataException("Unsupported ARGB compression mode: " + compressMode);
        if (raw == null || raw.Length != expectedLength)
            throw new InvalidDataException("Decoded ARGB payload length is invalid: " + (raw == null ? -1 : raw.Length) + "/" + expectedLength);
        return raw;
    }

    private static byte[] DecodeArgbPixels(ColorBits type, byte[] raw, int width, int height)
    {
        int pixelCount = checked(width * height);
        if (type == ColorBits.ARGB_8888)
        {
            if (raw.Length != checked(pixelCount * 4))
                throw new InvalidDataException("ARGB_8888 raw length is invalid.");
            return CloneBytes(raw);
        }
        if (type != ColorBits.ARGB_1555 || raw.Length != checked(pixelCount * 2))
            throw new InvalidDataException("ARGB_1555 raw length is invalid.");

        byte[] bgra = new byte[checked(pixelCount * 4)];
        for (int pixel = 0; pixel < pixelCount; pixel++)
        {
            ushort value = ReadUInt16(raw, pixel * 2);
            int target = pixel * 4;
            int blue = value & 31;
            int green = (value >> 5) & 31;
            int red = (value >> 10) & 31;
            bgra[target] = Expand5(blue);
            bgra[target + 1] = Expand5(green);
            bgra[target + 2] = Expand5(red);
            bgra[target + 3] = (value & 0x8000) == 0 ? (byte)0 : (byte)255;
        }
        return bgra;
    }

    private static byte[] RecolorRawPixels(
        ColorBits type,
        byte[] sourceRaw,
        int width,
        int height,
        out int changedVisiblePixels)
    {
        byte[] result = CloneBytes(sourceRaw);
        byte[] sourceBgra = DecodeArgbPixels(type, sourceRaw, width, height);
        int pixelCount = checked(width * height);
        changedVisiblePixels = 0;

        for (int pixel = 0; pixel < pixelCount; pixel++)
        {
            int bgraOffset = pixel * 4;
            if (sourceBgra[bgraOffset + 3] == 0)
                continue;
            if (sourceBgra[bgraOffset] <= NearBlackMaxChannel &&
                sourceBgra[bgraOffset + 1] <= NearBlackMaxChannel &&
                sourceBgra[bgraOffset + 2] <= NearBlackMaxChannel)
                continue;
            double intensity = Math.Max(
                sourceBgra[bgraOffset + 2],
                Math.Max(sourceBgra[bgraOffset + 1], sourceBgra[bgraOffset])) / 255.0;
            Color mapped = MapPalette(intensity);
            if (type == ColorBits.ARGB_8888)
            {
                int rawOffset = pixel * 4;
                if (result[rawOffset] != mapped.B ||
                    result[rawOffset + 1] != mapped.G ||
                    result[rawOffset + 2] != mapped.R)
                    changedVisiblePixels++;
                result[rawOffset] = mapped.B;
                result[rawOffset + 1] = mapped.G;
                result[rawOffset + 2] = mapped.R;
            }
            else
            {
                int rawOffset = pixel * 2;
                ushort sourceValue = ReadUInt16(sourceRaw, rawOffset);
                ushort outputValue = (ushort)(
                    (sourceValue & 0x8000) |
                    ((mapped.R >> 3) << 10) |
                    ((mapped.G >> 3) << 5) |
                    (mapped.B >> 3));
                if (sourceValue != outputValue)
                    changedVisiblePixels++;
                WriteUInt16(result, rawOffset, outputValue);
            }
        }
        return result;
    }

    private static int BytesPerPixel(ColorBits type)
    {
        if (type == ColorBits.ARGB_1555)
            return 2;
        if (type == ColorBits.ARGB_8888)
            return 4;
        throw new InvalidDataException("Unsupported ARGB type: " + type);
    }

    private static byte Expand5(int value)
    {
        return (byte)((value << 3) | (value >> 2));
    }

    private static Color MapPalette(double intensity)
    {
        for (int index = 1; index < VergilPalette.Length; index++)
        {
            PaletteStop right = VergilPalette[index];
            if (intensity <= right.Position)
            {
                PaletteStop left = VergilPalette[index - 1];
                double span = right.Position - left.Position;
                double amount = span <= 0 ? 0 : (intensity - left.Position) / span;
                return Color.FromArgb(
                    Lerp(left.Color.R, right.Color.R, amount),
                    Lerp(left.Color.G, right.Color.G, amount),
                    Lerp(left.Color.B, right.Color.B, amount));
            }
        }
        return VergilPalette[VergilPalette.Length - 1].Color;
    }

    private static int Lerp(int from, int to, double amount)
    {
        return (int)Math.Round(from + (to - from) * amount);
    }

    private static int CountVisiblePixels(byte[] bgra)
    {
        int count = 0;
        for (int offset = 3; offset < bgra.Length; offset += 4)
        {
            if (bgra[offset] != 0)
                count++;
        }
        return count;
    }

    private static bool IsNearBlackFrame(byte[] bgra)
    {
        bool hasVisiblePixel = false;
        for (int offset = 0; offset < bgra.Length; offset += 4)
        {
            if (bgra[offset + 3] == 0)
                continue;
            hasVisiblePixel = true;
            if (bgra[offset] > NearBlackMaxChannel ||
                bgra[offset + 1] > NearBlackMaxChannel ||
                bgra[offset + 2] > NearBlackMaxChannel)
                return false;
        }
        return hasVisiblePixel;
    }

    private static int CountVisibleRgbChanges(byte[] source, byte[] output)
    {
        if (source == null || output == null || source.Length != output.Length)
            throw new InvalidDataException("BGRA lengths differ during color comparison.");
        int count = 0;
        for (int offset = 0; offset < source.Length; offset += 4)
        {
            if (source[offset + 3] == 0)
                continue;
            if (source[offset] != output[offset] ||
                source[offset + 1] != output[offset + 1] ||
                source[offset + 2] != output[offset + 2])
                count++;
        }
        return count;
    }

    private static int CountWarmVisiblePixels(byte[] bgra)
    {
        int count = 0;
        for (int offset = 0; offset < bgra.Length; offset += 4)
        {
            if (bgra[offset] <= NearBlackMaxChannel &&
                bgra[offset + 1] <= NearBlackMaxChannel &&
                bgra[offset + 2] <= NearBlackMaxChannel)
                continue;
            if (bgra[offset + 3] >= 16 && bgra[offset + 2] > bgra[offset] + 12)
                count++;
        }
        return count;
    }

    private static bool AlphaBytesEqual(byte[] leftBgra, byte[] rightBgra)
    {
        if (leftBgra == null || rightBgra == null || leftBgra.Length != rightBgra.Length)
            return false;
        for (int offset = 3; offset < leftBgra.Length; offset += 4)
        {
            if (leftBgra[offset] != rightBgra[offset])
                return false;
        }
        return true;
    }

    private static bool VisibleNearBlackRgbEqual(byte[] sourceBgra, byte[] outputBgra)
    {
        if (sourceBgra == null || outputBgra == null || sourceBgra.Length != outputBgra.Length)
            return false;
        for (int offset = 0; offset < sourceBgra.Length; offset += 4)
        {
            if (sourceBgra[offset + 3] == 0 ||
                sourceBgra[offset] > NearBlackMaxChannel ||
                sourceBgra[offset + 1] > NearBlackMaxChannel ||
                sourceBgra[offset + 2] > NearBlackMaxChannel)
                continue;
            if (sourceBgra[offset] != outputBgra[offset] ||
                sourceBgra[offset + 1] != outputBgra[offset + 1] ||
                sourceBgra[offset + 2] != outputBgra[offset + 2])
                return false;
        }
        return true;
    }

    private static byte[] GetAlphaBytes(byte[] bgra)
    {
        byte[] result = new byte[bgra.Length / 4];
        int target = 0;
        for (int offset = 3; offset < bgra.Length; offset += 4)
            result[target++] = bgra[offset];
        return result;
    }

    private static BuildSummary CreateSummary(
        BuildConfig config,
        string configFile,
        string configSchemaFile,
        string builderSourceFile,
        string sourceFile,
        FileInfo sourceInfo,
        string sourceHash,
        string outputFile,
        string summaryFile,
        List<AlbumSnapshot> snapshots,
        BuildStats stats)
    {
        List<FrameResult> frames = new List<FrameResult>();
        List<AlbumResult> albums = new List<AlbumResult>();
        foreach (AlbumSnapshot album in snapshots)
        {
            int linkFrames = 0;
            foreach (FrameSnapshot frame in album.Frames)
            {
                frames.Add(frame.Result);
                if (frame.Type == ColorBits.LINK)
                    linkFrames++;
            }
            albums.Add(new AlbumResult
            {
                imgPath = album.Path,
                imgVersion = album.Version,
                tableIndex = album.TableIndex,
                tableSignatureSha256 = HashBytes(Encoding.UTF8.GetBytes(album.TableSignature)),
                frameCount = album.Frames.Count,
                linkFrameCount = linkFrames
            });
        }

        Assembly builderAssembly = Assembly.GetExecutingAssembly();
        string builderExecutable = builderAssembly.Location;
        string executableDirectory = Path.GetDirectoryName(builderExecutable);
        string extractorCore = typeof(NpkCoder).Assembly.Location;
        string extractorJson = Path.Combine(executableDirectory, "ExtractorSharp.Json.dll");
        string zlib = Path.Combine(executableDirectory, "zlib1.dll");
        RequireFile(extractorJson, "ExtractorSharp.Json dependency");
        RequireFile(zlib, "zlib dependency");

        BuildSummary summary = new BuildSummary();
        summary.schemaVersion = 1;
        summary.generatedAtUtc = DateTime.UtcNow.ToString("o");
        summary.status = "passed";
        summary.themeId = ExpectedThemeId;
        summary.source = new SummarySource
        {
            path = sourceFile,
            length = sourceInfo.Length,
            lastWriteTimeUtc = sourceInfo.LastWriteTimeUtc.ToString("o"),
            sha256 = sourceHash
        };
        summary.toolchain = new SummaryToolchain
        {
            config = CreateArtifact(configFile, null),
            configSchema = CreateArtifact(configSchemaFile, null),
            builderSource = CreateArtifact(builderSourceFile, null),
            builderExecutable = CreateArtifact(
                builderExecutable,
                builderAssembly.GetName().Version == null ? null : builderAssembly.GetName().Version.ToString()),
            extractorSharpCore = CreateArtifact(
                extractorCore,
                typeof(NpkCoder).Assembly.GetName().Version == null
                    ? null
                    : typeof(NpkCoder).Assembly.GetName().Version.ToString()),
            extractorSharpJson = CreateArtifact(extractorJson, GetFileVersion(extractorJson)),
            zlib = CreateArtifact(zlib, GetFileVersion(zlib))
        };
        FileInfo outputInfo = new FileInfo(outputFile);
        summary.output = new SummaryOutput
        {
            componentNpkPath = outputFile,
            length = outputInfo.Length,
            sha256 = HashFile(outputFile),
            buildSummaryPath = summaryFile
        };
        summary.selection = new SummarySelection
        {
            expectedAlbumCount = config.expectations.albumCount,
            expectedFrameCount = config.expectations.frameCount,
            allowedImgPaths = config.allowedImgPaths,
            explicitExcludedImgPaths = config.excludedImgPaths,
            explicitExcludedFrameKeys = config.excludedFrameKeys,
            palette = new[] { "#0A1633", "#1A8FFF", "#00D4FF", "#FFFFFF" },
            paletteStops = new[]
            {
                "0.00:#0A1633",
                "0.25:#0A1633",
                "0.58:#1A8FFF",
                "0.82:#00D4FF",
                "1.00:#FFFFFF"
            },
            nearBlackMaxChannel = NearBlackMaxChannel
        };
        summary.counts = new SummaryCounts
        {
            albums = stats.Albums,
            frames = stats.Frames,
            linkFrames = stats.LinkFrames,
            eligibleFrames = stats.EligibleFrames,
            changedFrames = stats.ChangedFrames,
            changedArgb1555Frames = stats.ChangedArgb1555Frames,
            changedArgb8888Frames = stats.ChangedArgb8888Frames,
            skippedFrames = stats.SkippedFrames,
            explicitExcludedFrames = stats.ExplicitlyExcludedFrames,
            hiddenFrames = stats.HiddenFrames,
            transparentFrames = stats.TransparentFrames,
            nearBlackFrames = stats.NearBlackFrames,
            noColorChangeFrames = stats.NoColorChangeFrames
        };
        summary.validation = new SummaryValidation
        {
            sourceIdentityReverified = "passed-before-load-after-load-and-before-summary",
            reopenedFromDisk = "passed",
            structureAndFrameOrder = "passed",
            typeAndCompression = "preserved",
            geometryAndLinks = "preserved",
            nativeZlibStatusAndLength = "passed",
            authorizedDecodedAlpha = "byte-identical",
            authorizedVisibleNearBlackRgb = "byte-identical",
            unauthorizedRawData = "byte-identical",
            unauthorizedDecodedBgra = "byte-identical",
            independentNpkIndex = "pending-external",
            independentFullFrameDecode = "pending-external",
            authorizedAlphaVerifiedFrames = stats.AuthorizedAlphaVerified,
            authorizedNearBlackVerifiedFrames = stats.AuthorizedNearBlackVerified,
            unauthorizedRawVerifiedFrames = stats.UnauthorizedRawVerified,
            unauthorizedBgraVerifiedFrames = stats.UnauthorizedBgraVerified
        };
        summary.albums = albums;
        summary.frames = frames;
        summary.deployment = new SummaryDeployment
        {
            performed = false,
            status = "not-authorized-not-performed"
        };
        return summary;
    }

    private static SummaryArtifact CreateArtifact(string path, string version)
    {
        RequireFile(path, "toolchain artifact");
        FileInfo info = new FileInfo(path);
        return new SummaryArtifact
        {
            path = info.FullName,
            length = info.Length,
            lastWriteTimeUtc = info.LastWriteTimeUtc.ToString("o"),
            sha256 = HashFile(info.FullName),
            version = version
        };
    }

    private static string GetFileVersion(string path)
    {
        FileVersionInfo info = FileVersionInfo.GetVersionInfo(path);
        return String.IsNullOrWhiteSpace(info.FileVersion) ? null : info.FileVersion;
    }

    private static void WriteJsonAtomically(string path, object value)
    {
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        serializer.MaxJsonLength = Int32.MaxValue;
        string json = serializer.Serialize(value);
        string temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(temporary, json, new UTF8Encoding(false));
            File.Move(temporary, path);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    private static void EnsureBuildTreeClosed(List<Album> albums)
    {
        foreach (Album album in albums)
        {
            foreach (Sprite sprite in album.List)
            {
                if (sprite.IsOpen)
                    throw new InvalidOperationException(
                        "A build-tree Sprite decoded through a forbidden image cache: " + BuildFrameKey(album.Path, sprite.Index));
            }
        }
    }

    private static string GetTableSignature(Album album)
    {
        if (album.Tables == null)
            return "null";
        StringBuilder builder = new StringBuilder();
        builder.Append(album.Tables.Count).Append(':');
        foreach (List<Color> table in album.Tables)
        {
            if (table == null)
            {
                builder.Append("null;");
                continue;
            }
            builder.Append(table.Count).Append('[');
            foreach (Color color in table)
                builder.Append(color.ToArgb().ToString("X8")).Append(',');
            builder.Append("];");
        }
        return builder.ToString();
    }

    private static string NormalizeImgPath(string value)
    {
        if (String.IsNullOrWhiteSpace(value))
            throw new InvalidDataException("IMG path cannot be empty.");
        string normalized = value.Trim().Replace('\\', '/');
        while (normalized.StartsWith("/", StringComparison.Ordinal))
            normalized = normalized.Substring(1);
        if (normalized.IndexOf('#') >= 0)
            throw new InvalidDataException("IMG path cannot contain '#': " + value);
        return normalized;
    }

    private static string BuildFrameKey(string imgPath, int frameIndex)
    {
        return NormalizeImgPath(imgPath) + "#" + frameIndex;
    }

    private static string ResolveConfiguredPath(string configDirectory, string value)
    {
        if (String.IsNullOrWhiteSpace(value))
            throw new InvalidDataException("Configured path cannot be empty.");
        string path = value.Replace('/', Path.DirectorySeparatorChar);
        if (!Path.IsPathRooted(path))
            path = Path.Combine(configDirectory, path);
        return Path.GetFullPath(path);
    }

    private static void RequireFile(string path, string label)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException("Missing " + label + ".", path);
    }

    private static FileInfo VerifySourceIdentity(
        string path,
        long expectedLength,
        string expectedHash,
        string phase)
    {
        RequireFile(path, "source NPK");
        FileInfo before = new FileInfo(path);
        string actualHash = HashFile(path);
        FileInfo after = new FileInfo(path);
        if (before.Length != after.Length || before.LastWriteTimeUtc != after.LastWriteTimeUtc)
            throw new IOException("Source NPK changed during identity verification " + phase + ".");
        if (expectedLength > 0 && after.Length != expectedLength)
            throw new InvalidDataException(
                "Source length changed " + phase + ": " + after.Length + "/" + expectedLength);
        if (!String.Equals(actualHash, expectedHash, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Source SHA-256 changed " + phase + ": " + actualHash);
        return after;
    }

    private static void RequireUnchangedHash(string path, string expectedHash, string message)
    {
        string actualHash = HashFile(path);
        if (!String.Equals(actualHash, expectedHash, StringComparison.OrdinalIgnoreCase))
            throw new IOException(message + " Current SHA-256: " + actualHash);
    }

    private static bool IsSha256(string value)
    {
        if (String.IsNullOrWhiteSpace(value) || value.Length != 64)
            return false;
        for (int index = 0; index < value.Length; index++)
        {
            char character = value[index];
            bool valid = (character >= '0' && character <= '9') ||
                (character >= 'a' && character <= 'f') ||
                (character >= 'A' && character <= 'F');
            if (!valid)
                return false;
        }
        return true;
    }

    private static string HashFile(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
            return ToHex(sha.ComputeHash(stream));
    }

    private static string HashBytes(byte[] bytes)
    {
        if (bytes == null)
            bytes = new byte[0];
        using (SHA256 sha = SHA256.Create())
            return ToHex(sha.ComputeHash(bytes));
    }

    private static string ToHex(byte[] bytes)
    {
        StringBuilder builder = new StringBuilder(bytes.Length * 2);
        foreach (byte value in bytes)
            builder.Append(value.ToString("X2"));
        return builder.ToString();
    }

    private static byte[] CloneBytes(byte[] value)
    {
        if (value == null)
            return null;
        byte[] result = new byte[value.Length];
        Buffer.BlockCopy(value, 0, result, 0, value.Length);
        return result;
    }

    private static bool BytesEqual(byte[] left, byte[] right)
    {
        if (Object.ReferenceEquals(left, right))
            return true;
        if (left == null || right == null || left.Length != right.Length)
            return false;
        for (int index = 0; index < left.Length; index++)
        {
            if (left[index] != right[index])
                return false;
        }
        return true;
    }

    private static ushort ReadUInt16(byte[] bytes, int offset)
    {
        return (ushort)(bytes[offset] | (bytes[offset + 1] << 8));
    }

    private static void WriteUInt16(byte[] bytes, int offset, ushort value)
    {
        bytes[offset] = (byte)value;
        bytes[offset + 1] = (byte)(value >> 8);
    }
}

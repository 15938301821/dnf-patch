using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using ExtractorSharp.Core.Coder;
using ExtractorSharp.Core.Handle;
using ExtractorSharp.Core.Lib;
using ExtractorSharp.Core.Model;

internal static class IllusionSlashVer5TextureMapAccess
{
    private static readonly FieldInfo MapField = typeof(FifthHandler).GetField(
        "_map",
        BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly);

    public static Dictionary<int, TextureInfo> Get(Handler handler, string albumPath)
    {
        if (!(handler is FifthHandler))
            throw new InvalidDataException("IMG is not using a Ver5 handler: " + albumPath);
        if (MapField == null)
            throw new InvalidDataException("Ver5 texture map field is unavailable: " + albumPath);
        Dictionary<int, TextureInfo> map = MapField.GetValue(handler) as Dictionary<int, TextureInfo>;
        if (map == null)
            throw new InvalidDataException("Ver5 texture map is unavailable: " + albumPath);
        return map;
    }
}

public sealed class IllusionSlashStableFifthHandler : FifthHandler
{
    private int _declaredTextureCount = -1;

    public IllusionSlashStableFifthHandler(Album album) : base(album)
    {
    }

    public override void CreateFromStream(Stream stream)
    {
        if (stream == null)
            throw new ArgumentNullException("stream");
        if (!stream.CanSeek || stream.Length - stream.Position < 4)
            throw new InvalidDataException("Ver5 texture table header is unavailable: " + Album.Path);

        long start = stream.Position;
        _declaredTextureCount = stream.ReadInt();
        stream.Seek(start, SeekOrigin.Begin);
        if (_declaredTextureCount < 0)
            throw new InvalidDataException("Ver5 texture count cannot be negative: " + Album.Path);

        base.CreateFromStream(stream);
    }

    public override byte[] AdjustData()
    {
        Dictionary<int, TextureInfo> map = IllusionSlashVer5TextureMapAccess.Get(this, Album.Path);
        Texture[] textures = GetTexturesInSourceIndexOrder(map);

        using (MemoryStream stream = new MemoryStream())
        {
            stream.WriteInt(Album.CurrentTable.Count);
            Colors.WritePalette(stream, Album.CurrentTable);

            foreach (Texture texture in textures)
            {
                ValidateTexturePayload(texture);
                stream.WriteInt((int)texture.Version);
                stream.WriteInt((int)texture.Type);
                stream.WriteInt(texture.Index);
                stream.WriteInt(texture.Length);
                stream.WriteInt(texture.FullLength);
                stream.WriteInt(texture.Width);
                stream.WriteInt(texture.Height);
            }

            List<Sprite> embeddedFrames = new List<Sprite>();
            long indexStart = stream.Length;
            foreach (Sprite sprite in Album.List)
            {
                stream.WriteInt((int)sprite.Type);
                if (sprite.Type == ColorBits.LINK)
                {
                    if (sprite.Target == null)
                        throw new InvalidDataException("Ver5 LINK target is missing: " + BuildFrameKey(sprite.Index));
                    stream.WriteInt(sprite.Target.Index);
                    continue;
                }

                stream.WriteInt((int)sprite.CompressMode);
                stream.WriteInt(sprite.Width);
                stream.WriteInt(sprite.Height);
                stream.WriteInt(sprite.Length);
                stream.WriteInt(sprite.X);
                stream.WriteInt(sprite.Y);
                stream.WriteInt(sprite.CanvasWidth);
                stream.WriteInt(sprite.CanvasHeight);

                if (sprite.Type < ColorBits.LINK && sprite.Length != 0)
                {
                    embeddedFrames.Add(sprite);
                    continue;
                }

                TextureInfo info;
                if (!map.TryGetValue(sprite.Index, out info) || info == null || info.Texture == null)
                    throw new InvalidDataException("Ver5 texture mapping is missing: " + BuildFrameKey(sprite.Index));
                stream.WriteInt(info.Unknown);
                stream.WriteInt(info.Texture.Index);
                stream.WriteInt(info.LeftUp.X);
                stream.WriteInt(info.LeftUp.Y);
                stream.WriteInt(info.RightDown.X);
                stream.WriteInt(info.RightDown.Y);
                stream.WriteInt(info.Top);
            }
            Album.IndexLength = stream.Length - indexStart;

            foreach (Texture texture in textures)
                stream.Write(texture.Data);
            foreach (Sprite sprite in embeddedFrames)
            {
                if (sprite.Data == null || sprite.Data.Length != sprite.Length)
                    throw new InvalidDataException("Ver5 embedded frame payload length changed: " + BuildFrameKey(sprite.Index));
                stream.Write(sprite.Data);
            }

            byte[] data = stream.ToArray();
            Album.Length = data.Length + 40;
            using (MemoryStream output = new MemoryStream())
            {
                output.WriteInt(textures.Length);
                output.WriteInt(Album.Length);
                output.Write(data);
                return output.ToArray();
            }
        }
    }

    private Texture[] GetTexturesInSourceIndexOrder(Dictionary<int, TextureInfo> map)
    {
        if (_declaredTextureCount < 0)
            throw new InvalidOperationException("Ver5 source texture count was not captured: " + Album.Path);

        Texture[] textures = new Texture[_declaredTextureCount];
        foreach (KeyValuePair<int, TextureInfo> pair in map)
        {
            TextureInfo info = pair.Value;
            if (info == null || info.Texture == null)
                throw new InvalidDataException("Ver5 texture mapping is empty: " + BuildFrameKey(pair.Key));
            Texture texture = info.Texture;
            if (texture.Index < 0 || texture.Index >= textures.Length)
                throw new InvalidDataException(
                    "Ver5 Texture indices are not dense: " + Album.Path + " texture " + texture.Index +
                    " outside 0.." + (textures.Length - 1));
            if (textures[texture.Index] == null)
                textures[texture.Index] = texture;
            else if (!Object.ReferenceEquals(textures[texture.Index], texture))
                throw new InvalidDataException(
                    "Distinct Ver5 Texture objects reuse index " + texture.Index + ": " + Album.Path);
        }

        for (int index = 0; index < textures.Length; index++)
        {
            if (textures[index] == null)
                throw new InvalidDataException(
                    "Ver5 Texture index is missing or unreferenced: " + Album.Path + " texture " + index);
        }
        return textures;
    }

    private static void ValidateTexturePayload(Texture texture)
    {
        if (texture.Data == null || texture.Data.Length != texture.Length)
            throw new InvalidDataException(
                "Ver5 Texture payload length is inconsistent at index " + texture.Index);
        if (texture.FullLength < 0 || texture.Width < 0 || texture.Height < 0)
            throw new InvalidDataException(
                "Ver5 Texture metadata is invalid at index " + texture.Index);
    }

    private string BuildFrameKey(int frameIndex)
    {
        return Album.Path + "#" + frameIndex;
    }
}

internal static class BuildVergilIllusionSlashAseprite
{
    private const string ExpectedThemeId = "weaponmaster-vergil-dark-blue";

    static BuildVergilIllusionSlashAseprite()
    {
        Handler.Regisity(ImgVersion.Ver5, typeof(IllusionSlashStableFifthHandler));
    }

    private enum BcFormat
    {
        Bc1,
        Bc3
    }

    private sealed class BuildConfig
    {
        public int schemaVersion { get; set; }
        public string themeId { get; set; }
        public SourceConfig sourceNpk { get; set; }
        public OutputConfig output { get; set; }
        public string[] allowedImgPaths { get; set; }
        public string[] excludedFrameKeys { get; set; }
        public PromptBindingConfig promptBinding { get; set; }
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

    private sealed class PromptBindingConfig
    {
        public string role { get; set; }
        public int priority { get; set; }
        public string themeAgentPath { get; set; }
        public string themePromptPath { get; set; }
        public string professionPromptPath { get; set; }
        public string uiFrameGeometryPolicy { get; set; }
        public string scope { get; set; }
    }

    private sealed class RenderSummary
    {
        public int schemaVersion { get; set; }
        public string status { get; set; }
        public string runId { get; set; }
        public bool fullSkillCoverageProven { get; set; }
        public RenderPromptBinding promptBinding { get; set; }
        public RenderAccounting accounting { get; set; }
        public RenderValidation validation { get; set; }
        public RenderStyleApplication styleApplication { get; set; }
        public RenderFrame[] frames { get; set; }
        public RenderDeployment deployment { get; set; }
    }

    private sealed class RenderPromptBinding
    {
        public int priority { get; set; }
        public string uiFrameGeometryPolicy { get; set; }
        public Snapshot themeAgent { get; set; }
        public Snapshot professionPrompt { get; set; }
        public Snapshot themePrompt { get; set; }
        public Snapshot modelRequest { get; set; }
        public Snapshot stylePlan { get; set; }
    }

    private sealed class RenderAccounting
    {
        public int expectedFrames { get; set; }
        public int layeredProjects { get; set; }
        public int runtimePngs { get; set; }
        public int missingFrames { get; set; }
        public int duplicateFrames { get; set; }
        public int geometryDrift { get; set; }
    }

    private sealed class RenderValidation
    {
        public string sourceInputsUnchanged { get; set; }
        public string runtimeGeometry { get; set; }
        public string sourceAlphaPreservedByRenderer { get; set; }
        public string layeredProjectsReopened { get; set; }
        public string layeredProjectRuntimePixelEquality { get; set; }
        public string modelStylePlanSchema { get; set; }
        public string modelStylePlanEvidenceChain { get; set; }
        public string modelStylePlanAppliedByRenderer { get; set; }
    }

    private sealed class RenderStyleApplication
    {
        public string planSha256 { get; set; }
        public string model { get; set; }
        public string provider { get; set; }
        public string[] enabledOperations { get; set; }
        public int appliedFrameCount { get; set; }
        public int byteExactRecomputeCount { get; set; }
    }

    private sealed class RenderDeployment
    {
        public bool authorized { get; set; }
        public bool performed { get; set; }
        public bool imagePacks2Write { get; set; }
        public bool processOperation { get; set; }
    }

    private sealed class RenderFrame
    {
        public string frameKey { get; set; }
        public string imgPath { get; set; }
        public string albumSlug { get; set; }
        public int frameIndex { get; set; }
        public Snapshot source { get; set; }
        public Snapshot layeredProject { get; set; }
        public RuntimeSnapshot runtime { get; set; }
        public int textureWidth { get; set; }
        public int textureHeight { get; set; }
        public long sourceAlphaPixels { get; set; }
    }

    private sealed class RuntimeSnapshot
    {
        public Snapshot snapshot { get; set; }
        public int width { get; set; }
        public int height { get; set; }
        public string pixelFormat { get; set; }
    }

    private sealed class Snapshot
    {
        public string path { get; set; }
        public long length { get; set; }
        public string lastWriteTime { get; set; }
        public string sha256 { get; set; }
    }

    private sealed class DdsInfo
    {
        public int Width;
        public int Height;
        public int DataOffset;
        public int BlockCount;
        public int BlockBytes;
        public BcFormat Format;
        public string FourCc;
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
        public int Length;
        public byte[] SpriteData;
        public bool HasTexture;
        public int TextureGroupId;
        public int TextureIndex;
        public int TextureWidth;
        public int TextureHeight;
        public int TextureFullLength;
        public ColorBits TextureType;
        public TextureVersion TextureVersion;
        public Point LeftUp;
        public Point RightDown;
        public int Rotation;
        public int Unknown;
        public bool ExplicitlyExcluded;
    }

    private sealed class TextureSnapshot
    {
        public int GroupId;
        public int Index;
        public int Width;
        public int Height;
        public int SourceLength;
        public int FullLength;
        public ColorBits Type;
        public TextureVersion Version;
        public BcFormat Format;
        public byte[] SourceCompressed;
        public byte[] SourceDds;
        public byte[] SourceBgra;
        public DdsInfo DdsInfo;
        public bool HasExcludedReference;
        public bool HasHiddenReference;
        public bool HasLinkedReference;
        public bool Eligible;
        public bool Changed;
        public string SkipReason;
        public int ChangedBlocks;
        public int VisibleRgbChanges;
        public List<string> References = new List<string>();
        public List<int> ReferenceFrameIndexes = new List<int>();
        public TextureResult Result;
    }

    private sealed class AlbumSnapshot
    {
        public string Path;
        public string Version;
        public int TableIndex;
        public string TableSignature;
        public int TextureMapCount;
        public List<FrameSnapshot> Frames = new List<FrameSnapshot>();
        public List<TextureSnapshot> Textures = new List<TextureSnapshot>();
    }

    private sealed class BuildStats
    {
        public int Albums;
        public int Frames;
        public int Textures;
        public int EligibleTextures;
        public int ChangedTextures;
        public int SkippedTextures;
        public int ChangedBc1Textures;
        public int ChangedBc3Textures;
        public int ChangedColorBlocks;
        public int ExplicitlyExcludedTextures;
        public int HiddenTextures;
        public int LinkedTextures;
        public int TransparentTextures;
        public int UnchangedTextures;
        public int AuthorizedAlphaVerified;
        public int UnauthorizedBgraVerified;
        public int TexdiagValidatedTextures;
    }

    private sealed class TextureResult
    {
        public string imgPath { get; set; }
        public int textureGroupId { get; set; }
        public int textureIndex { get; set; }
        public string format { get; set; }
        public string[] frameReferences { get; set; }
        public string decision { get; set; }
        public string skipReason { get; set; }
        public int width { get; set; }
        public int height { get; set; }
        public int changedColorBlocks { get; set; }
        public int visibleRgbChanges { get; set; }
        public string sourceCompressedSha256 { get; set; }
        public string outputCompressedSha256 { get; set; }
        public string sourceDdsSha256 { get; set; }
        public string outputDdsSha256 { get; set; }
        public string sourceBgraSha256 { get; set; }
        public string outputBgraSha256 { get; set; }
        public string sourceAlphaSha256 { get; set; }
        public string outputAlphaSha256 { get; set; }
        public string texdiag { get; set; }
    }

    private sealed class BuildSummary
    {
        public int schemaVersion { get; set; }
        public string generatedAtUtc { get; set; }
        public string status { get; set; }
        public string themeId { get; set; }
        public SummarySource source { get; set; }
        public SummaryOutput output { get; set; }
        public SummaryRenderEvidence renderEvidence { get; set; }
        public SummaryCounts counts { get; set; }
        public SummaryValidation validation { get; set; }
        public List<TextureResult> textures { get; set; }
        public SummaryDeployment deployment { get; set; }
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

    private sealed class SummaryRenderEvidence
    {
        public string renderSummaryPath { get; set; }
        public long renderSummaryLength { get; set; }
        public string renderSummarySha256 { get; set; }
        public string modelRequestSha256 { get; set; }
        public string stylePlanSha256 { get; set; }
        public string stylePlanModel { get; set; }
        public string stylePlanProvider { get; set; }
        public int stylePlanAppliedFrameCount { get; set; }
        public int stylePlanByteExactRecomputeCount { get; set; }
        public string themeAgentSha256 { get; set; }
        public string professionPromptSha256 { get; set; }
        public string themePromptSha256 { get; set; }
    }

    private sealed class SummaryCounts
    {
        public int albums { get; set; }
        public int frames { get; set; }
        public int textures { get; set; }
        public int eligibleTextures { get; set; }
        public int changedTextures { get; set; }
        public int skippedTextures { get; set; }
        public int changedBc1Textures { get; set; }
        public int changedBc3Textures { get; set; }
        public int changedColorBlocks { get; set; }
        public int explicitExcludedTextures { get; set; }
        public int hiddenTextures { get; set; }
        public int linkedTextures { get; set; }
        public int transparentTextures { get; set; }
        public int unchangedTextures { get; set; }
    }

    private sealed class SummaryValidation
    {
        public string reopenedFromDisk { get; set; }
        public string structureAndSharing { get; set; }
        public string framePositionAndSize { get; set; }
        public string frameCanvasAndOffsets { get; set; }
        public string atlasRectanglesAndRotation { get; set; }
        public string textureVersionAndIndexing { get; set; }
        public string ddsHeaders { get; set; }
        public string decodedAlpha { get; set; }
        public string unauthorizedDecodedBgra { get; set; }
        public string texdiagPerTexture { get; set; }
        public int authorizedAlphaVerifiedTextures { get; set; }
        public int unauthorizedBgraVerifiedTextures { get; set; }
        public int texdiagValidatedTextures { get; set; }
    }

    private sealed class SummaryDeployment
    {
        public bool performed { get; set; }
        public string status { get; set; }
    }

    private sealed class ReferenceComparer<T> : IEqualityComparer<T> where T : class
    {
        public static readonly ReferenceComparer<T> Instance = new ReferenceComparer<T>();

        public bool Equals(T left, T right)
        {
            return Object.ReferenceEquals(left, right);
        }

        public int GetHashCode(T value)
        {
            return RuntimeHelpers.GetHashCode(value);
        }
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
        if (args.Length != 7 && args.Length != 9)
        {
            Console.Error.WriteLine("Usage: <config.json> <source-npk> <render-summary.json> <runtime-directory> <texconv.exe> <texdiag.exe> <work-directory> [output-npk build-summary.json]");
            return 2;
        }

        string configFile = Path.GetFullPath(args[0]);
        string sourceFile = Path.GetFullPath(args[1]);
        string renderSummaryFile = Path.GetFullPath(args[2]);
        string runtimeDirectory = Path.GetFullPath(args[3]);
        string texconvFile = Path.GetFullPath(args[4]);
        string texdiagFile = Path.GetFullPath(args[5]);
        string workDirectory = Path.GetFullPath(args[6]);
        RequireFile(configFile, "build config");
        RequireFile(sourceFile, "source NPK");
        RequireFile(renderSummaryFile, "render summary");
        RequireDirectory(runtimeDirectory, "runtime PNG directory");
        RequireFile(texconvFile, "texconv");
        RequireFile(texdiagFile, "texdiag");

        BuildConfig config = LoadConfig(configFile);
        RenderSummary renderSummary = LoadRenderSummary(renderSummaryFile);
        string configDirectory = Path.GetDirectoryName(configFile);
        string outputFile = args.Length == 9
            ? Path.GetFullPath(args[7])
            : ResolveConfiguredPath(configDirectory, config.output.componentNpkPath);
        string summaryFile = args.Length == 9
            ? Path.GetFullPath(args[8])
            : ResolveConfiguredPath(configDirectory, config.output.buildSummaryPath);
        ValidateResolvedPaths(sourceFile, outputFile, summaryFile);
        if (File.Exists(outputFile))
            throw new IOException("Refusing to overwrite an existing component NPK: " + outputFile);
        if (File.Exists(summaryFile))
            throw new IOException("Refusing to overwrite an existing build summary: " + summaryFile);

        FileInfo sourceInfo = new FileInfo(sourceFile);
        if (config.sourceNpk.length > 0 && sourceInfo.Length != config.sourceNpk.length)
            throw new InvalidDataException("Source length changed: " + sourceInfo.Length + "/" + config.sourceNpk.length);
        string sourceHash = HashFile(sourceFile);
        if (!String.Equals(sourceHash, config.sourceNpk.sha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Source SHA-256 changed: " + sourceHash);

        HashSet<string> allowedPaths = BuildAllowedPathSet(config.allowedImgPaths);
        HashSet<string> excludedFrames = BuildExcludedFrameSet(config.excludedFrameKeys, allowedPaths);
        HashSet<string> matchedExcludedFrames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, RenderFrame> renderFrames = BuildRenderFrameMap(renderSummary, runtimeDirectory, allowedPaths, excludedFrames);

        Directory.CreateDirectory(Path.GetDirectoryName(outputFile));
        Directory.CreateDirectory(Path.GetDirectoryName(summaryFile));
        Directory.CreateDirectory(workDirectory);

        List<Album> analysisAll = NpkCoder.Load(sourceFile);
        List<Album> analysisAlbums = SelectAllowedAlbums(analysisAll, allowedPaths);
        BuildStats stats = new BuildStats();
        List<AlbumSnapshot> snapshots = CaptureSource(analysisAlbums, excludedFrames, matchedExcludedFrames, stats);
        ValidateExcludedFramesMatched(excludedFrames, matchedExcludedFrames);
        ValidateRenderCoverage(snapshots, renderFrames);

        List<Album> buildAll = NpkCoder.Load(sourceFile);
        List<Album> buildAlbums = SelectAllowedAlbums(buildAll, allowedPaths);
        ApplyRuntimePngs(buildAlbums, snapshots, renderFrames, runtimeDirectory, texconvFile, texdiagFile, workDirectory, stats);
        RequireChangedTexturePerAlbum(snapshots);
        EnsureBuildTreeClosed(buildAlbums);

        string temporaryOutput = Path.Combine(
            Path.GetDirectoryName(outputFile),
            "." + Path.GetFileNameWithoutExtension(outputFile) + ".candidate-" + Guid.NewGuid().ToString("N") + ".NPK");
        try
        {
            NpkCoder.Save(temporaryOutput, buildAlbums);
            ValidateOutput(temporaryOutput, snapshots, texdiagFile, workDirectory, stats);
            File.Move(temporaryOutput, outputFile);
        }
        finally
        {
            if (File.Exists(temporaryOutput))
                File.Delete(temporaryOutput);
        }

        BuildSummary summary = CreateSummary(
            config,
            sourceFile,
            sourceInfo,
            sourceHash,
            outputFile,
            summaryFile,
            renderSummaryFile,
            renderSummary,
            snapshots,
            stats);
        WriteJsonAtomically(summaryFile, summary);

        Console.WriteLine("Source=" + sourceFile);
        Console.WriteLine("SourceSha256=" + sourceHash);
        Console.WriteLine("RenderSummary=" + renderSummaryFile);
        Console.WriteLine("RuntimeDirectory=" + runtimeDirectory);
        Console.WriteLine("Output=" + outputFile);
        Console.WriteLine("OutputLength=" + new FileInfo(outputFile).Length);
        Console.WriteLine("OutputSha256=" + HashFile(outputFile));
        Console.WriteLine("BuildSummary=" + summaryFile);
        Console.WriteLine("Albums=" + stats.Albums);
        Console.WriteLine("Frames=" + stats.Frames);
        Console.WriteLine("Textures=" + stats.Textures);
        Console.WriteLine("ChangedTextures=" + stats.ChangedTextures);
        Console.WriteLine("SkippedTextures=" + stats.SkippedTextures);
        Console.WriteLine("StructureValidation=passed");
        Console.WriteLine("TexdiagValidation=passed");
        Console.WriteLine("Deployment=not-performed");
        return 0;
    }

    private static BuildConfig LoadConfig(string configFile)
    {
        JavaScriptSerializer serializer = NewSerializer();
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
        if (config.output == null || String.IsNullOrWhiteSpace(config.output.componentNpkPath) ||
            String.IsNullOrWhiteSpace(config.output.buildSummaryPath))
            throw new InvalidDataException("Config output paths are required.");
        if (config.allowedImgPaths == null || config.allowedImgPaths.Length == 0)
            throw new InvalidDataException("Config allowedImgPaths must not be empty.");
        if (config.excludedFrameKeys == null)
            throw new InvalidDataException("Config excludedFrameKeys must be present.");
        ValidatePromptBindingConfig(config.promptBinding);
        return config;
    }

    private static RenderSummary LoadRenderSummary(string renderSummaryFile)
    {
        JavaScriptSerializer serializer = NewSerializer();
        RenderSummary summary = serializer.Deserialize<RenderSummary>(File.ReadAllText(renderSummaryFile, Encoding.UTF8));
        if (summary == null)
            throw new InvalidDataException("Render summary is empty.");
        if (summary.schemaVersion != 1 || !String.Equals(summary.status, "passed", StringComparison.Ordinal))
            throw new InvalidDataException("Render summary is not a passed schema v1 summary.");
        if (summary.fullSkillCoverageProven)
            throw new InvalidDataException("Single-skill render summary must not claim full skill coverage.");
        if (summary.promptBinding == null || summary.promptBinding.priority != 1 ||
            !String.Equals(summary.promptBinding.uiFrameGeometryPolicy, "strict-preserve-source-frame-position-size", StringComparison.Ordinal) ||
            summary.promptBinding.modelRequest == null || summary.promptBinding.stylePlan == null ||
            !IsSha256(summary.promptBinding.modelRequest.sha256) || !IsSha256(summary.promptBinding.stylePlan.sha256))
            throw new InvalidDataException("Render summary prompt and model style evidence is incomplete.");
        if (summary.accounting == null || summary.accounting.expectedFrames <= 0 ||
            summary.accounting.layeredProjects != summary.accounting.expectedFrames ||
            summary.accounting.runtimePngs != summary.accounting.expectedFrames ||
            summary.accounting.missingFrames != 0 || summary.accounting.duplicateFrames != 0 ||
            summary.accounting.geometryDrift != 0)
            throw new InvalidDataException("Render summary accounting is not closed.");
        if (summary.validation == null ||
            !String.Equals(summary.validation.sourceInputsUnchanged, "passed", StringComparison.Ordinal) ||
            !String.Equals(summary.validation.sourceAlphaPreservedByRenderer, "passed", StringComparison.Ordinal) ||
            !String.Equals(summary.validation.layeredProjectsReopened, "passed", StringComparison.Ordinal) ||
            !String.Equals(summary.validation.layeredProjectRuntimePixelEquality, "passed", StringComparison.Ordinal) ||
            !String.Equals(summary.validation.modelStylePlanSchema, "passed-dnf-aseprite-pixel-style-plan-v1", StringComparison.Ordinal) ||
            !String.Equals(summary.validation.modelStylePlanEvidenceChain, "passed-context-design-call-hash-bound", StringComparison.Ordinal) ||
            !String.Equals(summary.validation.modelStylePlanAppliedByRenderer, "passed-byte-exact-recompute", StringComparison.Ordinal))
            throw new InvalidDataException("Render summary validation is incomplete.");
        if (summary.styleApplication == null || !IsSha256(summary.styleApplication.planSha256) ||
            !String.Equals(summary.styleApplication.planSha256, summary.promptBinding.stylePlan.sha256, StringComparison.OrdinalIgnoreCase) ||
            !String.Equals(summary.styleApplication.provider, "openai", StringComparison.Ordinal) ||
            String.IsNullOrWhiteSpace(summary.styleApplication.model) ||
            summary.styleApplication.enabledOperations == null || summary.styleApplication.enabledOperations.Length == 0 ||
            summary.styleApplication.appliedFrameCount != summary.accounting.expectedFrames ||
            summary.styleApplication.byteExactRecomputeCount != summary.accounting.expectedFrames)
            throw new InvalidDataException("Render summary model style application evidence is incomplete.");
        if (summary.deployment == null || summary.deployment.authorized || summary.deployment.performed ||
            summary.deployment.imagePacks2Write || summary.deployment.processOperation)
            throw new InvalidDataException("Render summary must not include deployment.");
        if (summary.frames == null || summary.frames.Length != summary.accounting.expectedFrames)
            throw new InvalidDataException("Render summary frame count is inconsistent.");
        return summary;
    }

    private static JavaScriptSerializer NewSerializer()
    {
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        serializer.MaxJsonLength = Int32.MaxValue;
        return serializer;
    }

    private static void ValidatePromptBindingConfig(PromptBindingConfig binding)
    {
        if (binding == null)
            throw new InvalidDataException("Illusionslash configs must include promptBinding.");
        if (!String.Equals(binding.role, "primary-skill-prompt", StringComparison.Ordinal) || binding.priority != 1)
            throw new InvalidDataException("promptBinding must be primary-skill-prompt with priority 1.");
        if (!String.Equals(binding.uiFrameGeometryPolicy, "strict-preserve-source-frame-position-size", StringComparison.Ordinal))
            throw new InvalidDataException("promptBinding must preserve source frame position and size.");
        if (!String.Equals(binding.scope, "illusionslash-only", StringComparison.Ordinal))
            throw new InvalidDataException("promptBinding.scope must be illusionslash-only.");
        if (String.IsNullOrWhiteSpace(binding.themeAgentPath) || String.IsNullOrWhiteSpace(binding.themePromptPath) ||
            String.IsNullOrWhiteSpace(binding.professionPromptPath))
            throw new InvalidDataException("promptBinding paths are required.");
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
            if (!result.Add(normalized))
                throw new InvalidDataException("Duplicate allowed IMG path: " + normalized);
        }
        return result;
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

    private static Dictionary<string, RenderFrame> BuildRenderFrameMap(
        RenderSummary summary,
        string runtimeDirectory,
        HashSet<string> allowedPaths,
        HashSet<string> excludedFrames)
    {
        Dictionary<string, RenderFrame> result = new Dictionary<string, RenderFrame>(StringComparer.OrdinalIgnoreCase);
        foreach (RenderFrame frame in summary.frames)
        {
            if (frame == null || String.IsNullOrWhiteSpace(frame.frameKey))
                throw new InvalidDataException("Render summary contains an empty frame record.");
            string imgPath = NormalizeImgPath(frame.imgPath);
            string frameKey = BuildFrameKey(imgPath, frame.frameIndex);
            if (!String.Equals(frameKey, frame.frameKey, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Render frame key is inconsistent: " + frame.frameKey);
            if (!allowedPaths.Contains(imgPath))
                throw new InvalidDataException("Render frame is outside allowed IMG paths: " + frameKey);
            if (excludedFrames.Contains(frameKey))
                throw new InvalidDataException("Render frame includes explicitly excluded frame: " + frameKey);
            if (!result.ContainsKey(frameKey))
                result.Add(frameKey, frame);
            else
                throw new InvalidDataException("Duplicate render frame: " + frameKey);
            if (frame.runtime == null || frame.runtime.snapshot == null || !IsSha256(frame.runtime.snapshot.sha256))
                throw new InvalidDataException("Render runtime snapshot is incomplete: " + frameKey);
            string runtimePath = Path.GetFullPath(frame.runtime.snapshot.path);
            string runtimeRoot = Path.GetFullPath(runtimeDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (!runtimePath.StartsWith(runtimeRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Runtime PNG path is outside runtime directory: " + runtimePath);
            RequireFile(runtimePath, "runtime PNG for " + frameKey);
            FileInfo item = new FileInfo(runtimePath);
            if (item.Length != frame.runtime.snapshot.length ||
                !String.Equals(HashFile(runtimePath), frame.runtime.snapshot.sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Runtime PNG snapshot changed: " + runtimePath);
            using (Bitmap bitmap = new Bitmap(runtimePath))
            {
                if (bitmap.Width != frame.textureWidth || bitmap.Height != frame.textureHeight ||
                    bitmap.Width != frame.runtime.width || bitmap.Height != frame.runtime.height)
                    throw new InvalidDataException("Runtime PNG geometry mismatch: " + runtimePath);
            }
        }
        return result;
    }

    private static void ValidateRenderCoverage(List<AlbumSnapshot> albums, Dictionary<string, RenderFrame> renderFrames)
    {
        HashSet<string> expected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (AlbumSnapshot album in albums)
        {
            foreach (FrameSnapshot frame in album.Frames)
            {
                if (!frame.HasTexture || frame.ExplicitlyExcluded || frame.Hidden || frame.TargetIndex >= 0)
                    continue;
                string key = BuildFrameKey(album.Path, frame.Index);
                TextureSnapshot texture = album.Textures[frame.TextureGroupId];
                if (!texture.Eligible)
                    continue;
                expected.Add(key);
                RenderFrame renderFrame;
                if (!renderFrames.TryGetValue(key, out renderFrame))
                    throw new InvalidDataException("Missing runtime PNG for frame: " + key);
                if (renderFrame.textureWidth != frame.TextureWidth || renderFrame.textureHeight != frame.TextureHeight)
                    throw new InvalidDataException("Runtime texture geometry differs from source frame: " + key);
            }
        }
        foreach (string key in renderFrames.Keys)
        {
            if (!expected.Contains(key))
                throw new InvalidDataException("Unexpected runtime PNG frame: " + key);
        }
    }

    private static List<Album> SelectAllowedAlbums(List<Album> albums, HashSet<string> allowedPaths)
    {
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
            if (!String.Equals(album.Version.ToString(), "Ver5", StringComparison.Ordinal))
                throw new InvalidDataException("Allowed IMG is not Ver5: " + album.Path);
            Dictionary<int, TextureInfo> map = GetTextureMap(album);
            AlbumSnapshot albumSnapshot = new AlbumSnapshot();
            albumSnapshot.Path = NormalizeImgPath(album.Path);
            albumSnapshot.Version = album.Version.ToString();
            albumSnapshot.TableIndex = album.TableIndex;
            albumSnapshot.TableSignature = GetTableSignature(album);
            albumSnapshot.TextureMapCount = map.Count;

            Dictionary<Texture, TextureSnapshot> textureGroups =
                new Dictionary<Texture, TextureSnapshot>(ReferenceComparer<Texture>.Instance);
            Dictionary<int, Texture> textureIndexes = new Dictionary<int, Texture>();
            HashSet<int> mappedFrameIndexes = new HashSet<int>();

            foreach (Sprite sprite in album.List)
            {
                string frameKey = BuildFrameKey(albumSnapshot.Path, sprite.Index);
                bool explicitlyExcluded = excludedFrames.Contains(frameKey);
                if (explicitlyExcluded)
                    matchedExcludedFrames.Add(frameKey);
                FrameSnapshot frame = CaptureFrame(sprite, explicitlyExcluded);
                TextureInfo info;
                if (map.TryGetValue(sprite.Index, out info))
                {
                    mappedFrameIndexes.Add(sprite.Index);
                    ValidateTextureDeclaration(album, sprite, info);
                    Texture texture = info.Texture;
                    Texture existingIndexTexture;
                    if (textureIndexes.TryGetValue(texture.Index, out existingIndexTexture) &&
                        !Object.ReferenceEquals(existingIndexTexture, texture))
                        throw new InvalidDataException("Distinct Ver5 Texture objects reuse one texture index: " + frameKey);
                    textureIndexes[texture.Index] = texture;

                    TextureSnapshot textureSnapshot;
                    if (!textureGroups.TryGetValue(texture, out textureSnapshot))
                    {
                        textureSnapshot = CaptureTexture(texture, textureGroups.Count);
                        textureGroups.Add(texture, textureSnapshot);
                        albumSnapshot.Textures.Add(textureSnapshot);
                    }
                    frame.HasTexture = true;
                    frame.TextureGroupId = textureSnapshot.GroupId;
                    frame.TextureIndex = texture.Index;
                    frame.TextureWidth = texture.Width;
                    frame.TextureHeight = texture.Height;
                    frame.TextureFullLength = texture.FullLength;
                    frame.TextureType = texture.Type;
                    frame.TextureVersion = texture.Version;
                    frame.LeftUp = info.LeftUp;
                    frame.RightDown = info.RightDown;
                    frame.Rotation = info.Top;
                    frame.Unknown = info.Unknown;

                    textureSnapshot.References.Add(frameKey);
                    textureSnapshot.ReferenceFrameIndexes.Add(sprite.Index);
                    textureSnapshot.HasExcludedReference |= explicitlyExcluded;
                    textureSnapshot.HasHiddenReference |= sprite.Hidden;
                    textureSnapshot.HasLinkedReference |= sprite.Target != null || sprite.Type == ColorBits.LINK;
                }
                else
                {
                    frame.HasTexture = false;
                    frame.TextureGroupId = -1;
                    if (sprite.Target == null && sprite.Type != ColorBits.LINK)
                        throw new InvalidDataException("Ver5 non-LINK frame has no texture mapping: " + frameKey);
                }
                albumSnapshot.Frames.Add(frame);
            }
            if (mappedFrameIndexes.Count != map.Count)
                throw new InvalidDataException("Ver5 texture map contains an entry not represented by a frame: " + album.Path);
            foreach (TextureSnapshot texture in albumSnapshot.Textures)
            {
                ClassifyTexture(texture, stats);
                texture.Result = CreateTextureResult(albumSnapshot.Path, texture);
            }
            stats.Albums++;
            stats.Frames += albumSnapshot.Frames.Count;
            stats.Textures += albumSnapshot.Textures.Count;
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
        frame.Length = sprite.Length;
        frame.SpriteData = CloneBytes(sprite.Data);
        frame.ExplicitlyExcluded = explicitlyExcluded;
        return frame;
    }

    private static void ValidateTextureDeclaration(Album album, Sprite sprite, TextureInfo info)
    {
        string key = BuildFrameKey(album.Path, sprite.Index);
        if (info == null || info.Texture == null)
            throw new InvalidDataException("Ver5 texture mapping is empty: " + key);
        if (sprite.Target != null || sprite.Type == ColorBits.LINK)
            return;
        if (sprite.CompressMode != CompressMode.DDS_ZLIB)
            throw new InvalidDataException("Allowed Ver5 sprite is not DDS_ZLIB: " + key);
        if (sprite.Type != ColorBits.DXT_1 && sprite.Type != ColorBits.DXT_5)
            throw new InvalidDataException("Allowed Ver5 sprite is not DXT_1 or DXT_5: " + key);
        if (info.Texture.Type != sprite.Type)
            throw new InvalidDataException("Sprite and Texture formats differ: " + key);
    }

    private static TextureSnapshot CaptureTexture(Texture texture, int groupId)
    {
        if (texture.Type != ColorBits.DXT_1 && texture.Type != ColorBits.DXT_5)
            throw new InvalidDataException("Ver5 Texture is not DXT_1 or DXT_5 at index " + texture.Index);
        if (texture.Data == null || texture.Data.Length != texture.Length)
            throw new InvalidDataException("Compressed Texture length is inconsistent at index " + texture.Index);
        byte[] dds = Zlib.Decompress(texture.Data, texture.FullLength);
        DdsInfo ddsInfo = ValidateDds(dds, texture.Width, texture.Height, FormatForColorBits(texture.Type));
        byte[] bgra = GetTextureBgra(texture, "source texture index " + texture.Index);
        TextureSnapshot snapshot = new TextureSnapshot();
        snapshot.GroupId = groupId;
        snapshot.Index = texture.Index;
        snapshot.Width = texture.Width;
        snapshot.Height = texture.Height;
        snapshot.SourceLength = texture.Length;
        snapshot.FullLength = texture.FullLength;
        snapshot.Type = texture.Type;
        snapshot.Version = texture.Version;
        snapshot.Format = ddsInfo.Format;
        snapshot.SourceCompressed = CloneBytes(texture.Data);
        snapshot.SourceDds = CloneBytes(dds);
        snapshot.SourceBgra = bgra;
        snapshot.DdsInfo = ddsInfo;
        return snapshot;
    }

    private static void ClassifyTexture(TextureSnapshot texture, BuildStats stats)
    {
        if (texture.HasExcludedReference)
        {
            texture.SkipReason = "explicit-excluded-reference";
            stats.ExplicitlyExcludedTextures++;
        }
        else if (texture.HasHiddenReference)
        {
            texture.SkipReason = "hidden-reference";
            stats.HiddenTextures++;
        }
        else if (texture.HasLinkedReference)
        {
            texture.SkipReason = "linked-reference";
            stats.LinkedTextures++;
        }
        else if (CountVisiblePixels(texture.SourceBgra) == 0)
        {
            texture.SkipReason = "fully-transparent";
            stats.TransparentTextures++;
        }
        else
        {
            texture.Eligible = true;
            stats.EligibleTextures++;
            return;
        }
        stats.SkippedTextures++;
    }

    private static TextureResult CreateTextureResult(string albumPath, TextureSnapshot texture)
    {
        TextureResult result = new TextureResult();
        result.imgPath = albumPath;
        result.textureGroupId = texture.GroupId;
        result.textureIndex = texture.Index;
        result.format = texture.Format == BcFormat.Bc1 ? "BC1/DXT1" : "BC3/DXT5";
        result.frameReferences = texture.References.ToArray();
        result.decision = texture.Eligible ? "eligible" : "skipped";
        result.skipReason = texture.SkipReason;
        result.width = texture.Width;
        result.height = texture.Height;
        result.sourceCompressedSha256 = HashBytes(texture.SourceCompressed);
        result.sourceDdsSha256 = HashBytes(texture.SourceDds);
        result.sourceBgraSha256 = HashBytes(texture.SourceBgra);
        result.sourceAlphaSha256 = HashBytes(GetAlphaBytes(texture.SourceBgra));
        return result;
    }

    private static void ValidateExcludedFramesMatched(HashSet<string> excludedFrames, HashSet<string> matchedExcludedFrames)
    {
        foreach (string frameKey in excludedFrames)
        {
            if (!matchedExcludedFrames.Contains(frameKey))
                throw new InvalidDataException("Explicit excluded frame was not found: " + frameKey);
        }
    }

    private static void ApplyRuntimePngs(
        List<Album> buildAlbums,
        List<AlbumSnapshot> snapshots,
        Dictionary<string, RenderFrame> renderFrames,
        string runtimeDirectory,
        string texconvFile,
        string texdiagFile,
        string workDirectory,
        BuildStats stats)
    {
        string encodedDirectory = Path.Combine(workDirectory, "encoded-dds");
        Directory.CreateDirectory(encodedDirectory);
        for (int albumIndex = 0; albumIndex < buildAlbums.Count; albumIndex++)
        {
            Album album = buildAlbums[albumIndex];
            AlbumSnapshot albumSnapshot = snapshots[albumIndex];
            if (!String.Equals(NormalizeImgPath(album.Path), albumSnapshot.Path, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Build album order changed: " + album.Path);
            Dictionary<int, TextureInfo> map = GetTextureMap(album);
            foreach (TextureSnapshot textureSnapshot in albumSnapshot.Textures)
            {
                if (!textureSnapshot.Eligible)
                    continue;
                string frameKey = textureSnapshot.References[0];
                RenderFrame renderFrame;
                if (!renderFrames.TryGetValue(frameKey, out renderFrame))
                    throw new InvalidDataException("Missing runtime PNG for texture: " + frameKey);
                string runtimeFile = Path.GetFullPath(renderFrame.runtime.snapshot.path);
                Texture texture = GetBuildTextureForGroup(albumSnapshot, textureSnapshot, map);
                string baseName = albumIndex.ToString("D4") + "-texture-" + textureSnapshot.GroupId.ToString("D4");
                string outputDirectory = Path.Combine(encodedDirectory, baseName);
                Directory.CreateDirectory(outputDirectory);
                using (Bitmap edited = new Bitmap(runtimeFile))
                {
                    if (edited.Width != textureSnapshot.Width || edited.Height != textureSnapshot.Height)
                        throw new InvalidDataException("Runtime PNG geometry mismatch for " + frameKey);
                }
                RunTexconv(texconvFile, runtimeFile, outputDirectory, textureSnapshot.Format);
                string ddsFile = Path.Combine(outputDirectory, Path.GetFileNameWithoutExtension(runtimeFile) + ".DDS");
                RequireFile(ddsFile, "texconv output for " + frameKey);
                RunTexdiag(texdiagFile, ddsFile, textureSnapshot.Format);
                byte[] encodedDds = File.ReadAllBytes(ddsFile);
                DdsInfo encodedInfo = ValidateDds(encodedDds, textureSnapshot.Width, textureSnapshot.Height, textureSnapshot.Format);
                PreserveSourceAlphaBlocks(textureSnapshot.SourceDds, encodedDds, encodedInfo);
                byte[] encodedBgra = DecodeDdsBgra(encodedDds, encodedInfo);
                if (encodedBgra.Length != textureSnapshot.SourceBgra.Length)
                    throw new InvalidDataException("Encoded BGRA length changed: " + frameKey);
                if (!AlphaBytesEqual(textureSnapshot.SourceBgra, encodedBgra))
                    throw new InvalidDataException("Encoded runtime alpha differs from source texture: " + frameKey);
                int changedBlocks = CountChangedColorBlocks(textureSnapshot.SourceDds, encodedDds, encodedInfo);
                int visibleRgbChanges = CountVisibleRgbChanges(textureSnapshot.SourceBgra, encodedBgra);
                if (changedBlocks == 0 || visibleRgbChanges == 0)
                    throw new InvalidDataException("Runtime PNG did not create visible texture changes: " + frameKey);

                byte[] compressed = Zlib.Compress(encodedDds);
                if (compressed == null || compressed.Length == 0)
                    throw new InvalidDataException("Zlib returned an empty payload: " + frameKey);
                texture.Data = compressed;
                texture.Length = compressed.Length;
                texture.FullLength = encodedDds.Length;
                textureSnapshot.Changed = true;
                textureSnapshot.ChangedBlocks = changedBlocks;
                textureSnapshot.VisibleRgbChanges = visibleRgbChanges;
                textureSnapshot.Result.decision = "changed";
                textureSnapshot.Result.skipReason = null;
                textureSnapshot.Result.changedColorBlocks = changedBlocks;
                textureSnapshot.Result.visibleRgbChanges = visibleRgbChanges;
                stats.ChangedTextures++;
                stats.ChangedColorBlocks += changedBlocks;
                if (textureSnapshot.Format == BcFormat.Bc1)
                    stats.ChangedBc1Textures++;
                else
                    stats.ChangedBc3Textures++;
            }
        }
    }

    private static Texture GetBuildTextureForGroup(AlbumSnapshot album, TextureSnapshot texture, Dictionary<int, TextureInfo> map)
    {
        Texture result = null;
        foreach (int frameIndex in texture.ReferenceFrameIndexes)
        {
            TextureInfo info;
            if (!map.TryGetValue(frameIndex, out info) || info == null || info.Texture == null)
                throw new InvalidDataException("Build texture mapping is missing: " + BuildFrameKey(album.Path, frameIndex));
            if (result == null)
                result = info.Texture;
            else if (!Object.ReferenceEquals(result, info.Texture))
                throw new InvalidDataException("Build shared Texture relationship changed: " + BuildFrameKey(album.Path, frameIndex));
        }
        if (result == null)
            throw new InvalidDataException("Texture group has no frame references: " + album.Path + " group " + texture.GroupId);
        return result;
    }

    private static void RequireChangedTexturePerAlbum(List<AlbumSnapshot> albums)
    {
        foreach (AlbumSnapshot album in albums)
        {
            bool changed = false;
            foreach (TextureSnapshot texture in album.Textures)
            {
                if (texture.Changed)
                {
                    changed = true;
                    break;
                }
            }
            if (!changed)
                throw new InvalidDataException("Allowed IMG has no changed Texture and must not be copied into a component NPK: " + album.Path);
        }
    }

    private static void ValidateOutput(
        string outputFile,
        List<AlbumSnapshot> sourceAlbums,
        string texdiagFile,
        string workDirectory,
        BuildStats stats)
    {
        List<Album> outputAlbums = NpkCoder.Load(outputFile);
        if (outputAlbums.Count != sourceAlbums.Count)
            throw new InvalidDataException("Output component IMG count changed.");
        string ddsDirectory = Path.Combine(workDirectory, "reopened-dds");
        Directory.CreateDirectory(ddsDirectory);
        for (int albumIndex = 0; albumIndex < outputAlbums.Count; albumIndex++)
        {
            Album outputAlbum = outputAlbums[albumIndex];
            AlbumSnapshot sourceAlbum = sourceAlbums[albumIndex];
            ValidateAlbumMetadata(outputAlbum, sourceAlbum);
            Dictionary<int, TextureInfo> map = GetTextureMap(outputAlbum);
            if (map.Count != sourceAlbum.TextureMapCount)
                throw new InvalidDataException("Output texture map count changed: " + sourceAlbum.Path);
            Dictionary<int, Texture> groupObjects = new Dictionary<int, Texture>();
            Dictionary<Texture, int> reverseGroups = new Dictionary<Texture, int>(ReferenceComparer<Texture>.Instance);
            for (int framePosition = 0; framePosition < sourceAlbum.Frames.Count; framePosition++)
            {
                FrameSnapshot sourceFrame = sourceAlbum.Frames[framePosition];
                Sprite outputSprite = outputAlbum.List[framePosition];
                ValidateFrameMetadata(outputAlbum, outputSprite, sourceFrame, map);
                if (!sourceFrame.HasTexture)
                    continue;
                Texture outputTexture = map[outputSprite.Index].Texture;
                Texture knownTexture;
                if (groupObjects.TryGetValue(sourceFrame.TextureGroupId, out knownTexture))
                {
                    if (!Object.ReferenceEquals(knownTexture, outputTexture))
                        throw new InvalidDataException("Output split a shared Texture group: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                }
                else
                {
                    int otherGroup;
                    if (reverseGroups.TryGetValue(outputTexture, out otherGroup) && otherGroup != sourceFrame.TextureGroupId)
                        throw new InvalidDataException("Output merged distinct Texture groups: " + BuildFrameKey(sourceAlbum.Path, sourceFrame.Index));
                    groupObjects.Add(sourceFrame.TextureGroupId, outputTexture);
                    reverseGroups.Add(outputTexture, sourceFrame.TextureGroupId);
                }
            }
            foreach (TextureSnapshot sourceTexture in sourceAlbum.Textures)
            {
                Texture outputTexture = groupObjects[sourceTexture.GroupId];
                ValidateTextureMetadata(outputTexture, sourceTexture);
                byte[] outputDds = Zlib.Decompress(outputTexture.Data, outputTexture.FullLength);
                DdsInfo outputInfo = ValidateDds(outputDds, sourceTexture.Width, sourceTexture.Height, sourceTexture.Format);
                byte[] outputBgra = GetTextureBgra(outputTexture, sourceAlbum.Path + " texture " + sourceTexture.Index);
                int changedBlocks = CountChangedColorBlocks(sourceTexture.SourceDds, outputDds, outputInfo);
                int visibleRgbChanges = CountVisibleRgbChanges(sourceTexture.SourceBgra, outputBgra);
                if (sourceTexture.Changed)
                {
                    if (!AlphaBytesEqual(sourceTexture.SourceBgra, outputBgra))
                        throw new InvalidDataException("Authorized decoded alpha changed: " + sourceAlbum.Path + " texture " + sourceTexture.Index);
                    if (changedBlocks < 1 || visibleRgbChanges < 1)
                        throw new InvalidDataException("Authorized Texture has no visible color change: " + sourceAlbum.Path + " texture " + sourceTexture.Index);
                    stats.AuthorizedAlphaVerified++;
                }
                else
                {
                    if (!BytesEqual(sourceTexture.SourceCompressed, outputTexture.Data) ||
                        !BytesEqual(sourceTexture.SourceDds, outputDds) ||
                        !BytesEqual(sourceTexture.SourceBgra, outputBgra))
                        throw new InvalidDataException("Unauthorized Texture changed: " + sourceAlbum.Path + " texture " + sourceTexture.Index);
                    stats.UnauthorizedBgraVerified++;
                }
                string ddsFile = Path.Combine(ddsDirectory, albumIndex.ToString("D4") + "-texture-" + sourceTexture.GroupId.ToString("D4") + ".dds");
                File.WriteAllBytes(ddsFile, outputDds);
                RunTexdiag(texdiagFile, ddsFile, sourceTexture.Format);
                stats.TexdiagValidatedTextures++;
                sourceTexture.Result.changedColorBlocks = changedBlocks;
                sourceTexture.Result.visibleRgbChanges = visibleRgbChanges;
                sourceTexture.Result.outputCompressedSha256 = HashBytes(outputTexture.Data);
                sourceTexture.Result.outputDdsSha256 = HashBytes(outputDds);
                sourceTexture.Result.outputBgraSha256 = HashBytes(outputBgra);
                sourceTexture.Result.outputAlphaSha256 = HashBytes(GetAlphaBytes(outputBgra));
                sourceTexture.Result.texdiag = sourceTexture.Format == BcFormat.Bc1 ? "passed-BC1_UNORM" : "passed-BC3_UNORM";
            }
        }
    }

    private static void ValidateAlbumMetadata(Album output, AlbumSnapshot source)
    {
        if (!String.Equals(NormalizeImgPath(output.Path), source.Path, StringComparison.OrdinalIgnoreCase) ||
            !String.Equals(output.Version.ToString(), source.Version, StringComparison.Ordinal) ||
            output.TableIndex != source.TableIndex || !String.Equals(GetTableSignature(output), source.TableSignature, StringComparison.Ordinal))
            throw new InvalidDataException("Output album metadata changed: " + source.Path);
        if (output.List.Count != source.Frames.Count)
            throw new InvalidDataException("Output frame count changed: " + source.Path);
    }

    private static void ValidateFrameMetadata(Album outputAlbum, Sprite outputSprite, FrameSnapshot sourceFrame, Dictionary<int, TextureInfo> map)
    {
        if (outputSprite.Index != sourceFrame.Index || outputSprite.Type != sourceFrame.Type ||
            outputSprite.CompressMode != sourceFrame.CompressMode || outputSprite.Hidden != sourceFrame.Hidden ||
            (outputSprite.Target == null ? -1 : outputSprite.Target.Index) != sourceFrame.TargetIndex ||
            outputSprite.Width != sourceFrame.Width || outputSprite.Height != sourceFrame.Height ||
            outputSprite.CanvasWidth != sourceFrame.CanvasWidth || outputSprite.CanvasHeight != sourceFrame.CanvasHeight ||
            outputSprite.X != sourceFrame.X || outputSprite.Y != sourceFrame.Y ||
            outputSprite.Length != sourceFrame.Length || !BytesEqual(outputSprite.Data, sourceFrame.SpriteData))
            throw new InvalidDataException("Output frame metadata changed: " + BuildFrameKey(outputAlbum.Path, sourceFrame.Index));
        if (!sourceFrame.HasTexture)
            return;
        TextureInfo outputInfo = map[outputSprite.Index];
        Texture outputTexture = outputInfo.Texture;
        if (outputTexture.Index != sourceFrame.TextureIndex || outputTexture.Width != sourceFrame.TextureWidth ||
            outputTexture.Height != sourceFrame.TextureHeight || outputTexture.FullLength != sourceFrame.TextureFullLength ||
            outputTexture.Type != sourceFrame.TextureType || outputTexture.Version != sourceFrame.TextureVersion ||
            outputInfo.LeftUp != sourceFrame.LeftUp || outputInfo.RightDown != sourceFrame.RightDown ||
            outputInfo.Top != sourceFrame.Rotation || outputInfo.Unknown != sourceFrame.Unknown)
            throw new InvalidDataException("Output texture metadata changed: " + BuildFrameKey(outputAlbum.Path, sourceFrame.Index));
    }

    private static void ValidateTextureMetadata(Texture outputTexture, TextureSnapshot source)
    {
        if (outputTexture.Index != source.Index || outputTexture.Width != source.Width || outputTexture.Height != source.Height ||
            outputTexture.FullLength != source.FullLength || outputTexture.Type != source.Type || outputTexture.Version != source.Version)
            throw new InvalidDataException("Output Texture metadata changed at texture " + source.Index);
        if (!source.Changed && outputTexture.Length != source.SourceLength)
            throw new InvalidDataException("Unauthorized Texture length changed at texture " + source.Index);
    }

    private static BuildSummary CreateSummary(
        BuildConfig config,
        string sourceFile,
        FileInfo sourceInfo,
        string sourceHash,
        string outputFile,
        string summaryFile,
        string renderSummaryFile,
        RenderSummary renderSummary,
        List<AlbumSnapshot> snapshots,
        BuildStats stats)
    {
        BuildSummary summary = new BuildSummary();
        summary.schemaVersion = 1;
        summary.generatedAtUtc = DateTime.UtcNow.ToString("o");
        summary.status = "passed";
        summary.themeId = config.themeId;
        summary.source = new SummarySource();
        summary.source.path = sourceFile;
        summary.source.length = sourceInfo.Length;
        summary.source.lastWriteTimeUtc = sourceInfo.LastWriteTimeUtc.ToString("o");
        summary.source.sha256 = sourceHash;
        summary.output = new SummaryOutput();
        summary.output.componentNpkPath = outputFile;
        summary.output.length = new FileInfo(outputFile).Length;
        summary.output.sha256 = HashFile(outputFile);
        summary.output.buildSummaryPath = summaryFile;
        summary.renderEvidence = new SummaryRenderEvidence();
        summary.renderEvidence.renderSummaryPath = renderSummaryFile;
        summary.renderEvidence.renderSummaryLength = new FileInfo(renderSummaryFile).Length;
        summary.renderEvidence.renderSummarySha256 = HashFile(renderSummaryFile);
        summary.renderEvidence.modelRequestSha256 = renderSummary.promptBinding.modelRequest.sha256;
        summary.renderEvidence.stylePlanSha256 = renderSummary.promptBinding.stylePlan.sha256;
        summary.renderEvidence.stylePlanModel = renderSummary.styleApplication.model;
        summary.renderEvidence.stylePlanProvider = renderSummary.styleApplication.provider;
        summary.renderEvidence.stylePlanAppliedFrameCount = renderSummary.styleApplication.appliedFrameCount;
        summary.renderEvidence.stylePlanByteExactRecomputeCount = renderSummary.styleApplication.byteExactRecomputeCount;
        summary.renderEvidence.themeAgentSha256 = renderSummary.promptBinding.themeAgent.sha256;
        summary.renderEvidence.professionPromptSha256 = renderSummary.promptBinding.professionPrompt.sha256;
        summary.renderEvidence.themePromptSha256 = renderSummary.promptBinding.themePrompt.sha256;
        summary.counts = new SummaryCounts();
        summary.counts.albums = stats.Albums;
        summary.counts.frames = stats.Frames;
        summary.counts.textures = stats.Textures;
        summary.counts.eligibleTextures = stats.EligibleTextures;
        summary.counts.changedTextures = stats.ChangedTextures;
        summary.counts.skippedTextures = stats.SkippedTextures;
        summary.counts.changedBc1Textures = stats.ChangedBc1Textures;
        summary.counts.changedBc3Textures = stats.ChangedBc3Textures;
        summary.counts.changedColorBlocks = stats.ChangedColorBlocks;
        summary.counts.explicitExcludedTextures = stats.ExplicitlyExcludedTextures;
        summary.counts.hiddenTextures = stats.HiddenTextures;
        summary.counts.linkedTextures = stats.LinkedTextures;
        summary.counts.transparentTextures = stats.TransparentTextures;
        summary.counts.unchangedTextures = stats.UnchangedTextures;
        summary.validation = new SummaryValidation();
        summary.validation.reopenedFromDisk = "passed";
        summary.validation.structureAndSharing = "passed";
        summary.validation.framePositionAndSize = "passed";
        summary.validation.frameCanvasAndOffsets = "passed";
        summary.validation.atlasRectanglesAndRotation = "passed";
        summary.validation.textureVersionAndIndexing = "passed";
        summary.validation.ddsHeaders = "passed";
        summary.validation.decodedAlpha = "passed";
        summary.validation.unauthorizedDecodedBgra = "passed";
        summary.validation.texdiagPerTexture = "passed";
        summary.validation.authorizedAlphaVerifiedTextures = stats.AuthorizedAlphaVerified;
        summary.validation.unauthorizedBgraVerifiedTextures = stats.UnauthorizedBgraVerified;
        summary.validation.texdiagValidatedTextures = stats.TexdiagValidatedTextures;
        summary.textures = new List<TextureResult>();
        foreach (AlbumSnapshot album in snapshots)
        {
            foreach (TextureSnapshot texture in album.Textures)
                summary.textures.Add(texture.Result);
        }
        summary.deployment = new SummaryDeployment();
        summary.deployment.performed = false;
        summary.deployment.status = "not-authorized-not-performed";
        return summary;
    }

    private static Dictionary<int, TextureInfo> GetTextureMap(Album album)
    {
        return IllusionSlashVer5TextureMapAccess.Get(album.Handler, album.Path);
    }

    private static void EnsureBuildTreeClosed(List<Album> albums)
    {
        foreach (Album album in albums)
        {
            foreach (Sprite sprite in album.List)
            {
                if (sprite.IsOpen)
                    throw new InvalidOperationException("A build-tree Sprite was opened before save: " + BuildFrameKey(album.Path, sprite.Index));
            }
        }
    }

    private static BcFormat FormatForColorBits(ColorBits value)
    {
        if (value == ColorBits.DXT_1)
            return BcFormat.Bc1;
        if (value == ColorBits.DXT_5)
            return BcFormat.Bc3;
        throw new InvalidDataException("Unsupported DXT ColorBits value: " + value);
    }

    private static DdsInfo ValidateDds(byte[] dds, int expectedWidth, int expectedHeight, BcFormat expectedFormat)
    {
        if (dds == null || dds.Length < 136)
            throw new InvalidDataException("DDS payload is too short.");
        if (BitConverter.ToInt32(dds, 0) != 0x20534444)
            throw new InvalidDataException("DDS magic is invalid.");
        int headerSize = BitConverter.ToInt32(dds, 4);
        int height = BitConverter.ToInt32(dds, 12);
        int width = BitConverter.ToInt32(dds, 16);
        int mipLevels = BitConverter.ToInt32(dds, 28);
        int pixelFormatSize = BitConverter.ToInt32(dds, 76);
        int fourCc = BitConverter.ToInt32(dds, 84);
        BcFormat actualFormat;
        string fourCcText;
        if (fourCc == 0x31545844)
        {
            actualFormat = BcFormat.Bc1;
            fourCcText = "DXT1";
        }
        else if (fourCc == 0x35545844)
        {
            actualFormat = BcFormat.Bc3;
            fourCcText = "DXT5";
        }
        else
        {
            throw new InvalidDataException("DDS FourCC is not DXT1 or DXT5.");
        }
        if (headerSize != 124 || pixelFormatSize != 32 || actualFormat != expectedFormat)
            throw new InvalidDataException("DDS legacy header or format is inconsistent.");
        if (width < 1 || height < 1 || (mipLevels != 0 && mipLevels != 1))
            throw new InvalidDataException("DDS dimensions or mip count are invalid.");
        if (expectedWidth > 0 && width != expectedWidth)
            throw new InvalidDataException("DDS width changed: " + width + "/" + expectedWidth);
        if (expectedHeight > 0 && height != expectedHeight)
            throw new InvalidDataException("DDS height changed: " + height + "/" + expectedHeight);
        int blocksWide = (width + 3) / 4;
        int blocksHigh = (height + 3) / 4;
        int blockCount = checked(blocksWide * blocksHigh);
        int blockBytes = actualFormat == BcFormat.Bc1 ? 8 : 16;
        int dataOffset = 128;
        int expectedLength = checked(dataOffset + blockCount * blockBytes);
        if (dds.Length != expectedLength)
            throw new InvalidDataException("DDS block length is invalid: " + dds.Length + "/" + expectedLength);
        DdsInfo result = new DdsInfo();
        result.Width = width;
        result.Height = height;
        result.DataOffset = dataOffset;
        result.BlockCount = blockCount;
        result.BlockBytes = blockBytes;
        result.Format = actualFormat;
        result.FourCc = fourCcText;
        return result;
    }

    private static byte[] DecodeDdsBgra(byte[] dds, DdsInfo info)
    {
        byte[] result = new byte[checked(info.Width * info.Height * 4)];
        int blocksWide = (info.Width + 3) / 4;
        int blocksHigh = (info.Height + 3) / 4;
        for (int blockY = 0; blockY < blocksHigh; blockY++)
        {
            for (int blockX = 0; blockX < blocksWide; blockX++)
            {
                int blockIndex = blockY * blocksWide + blockX;
                int offset = info.DataOffset + blockIndex * info.BlockBytes;
                byte[] alpha = info.Format == BcFormat.Bc3 ? DecodeBc3AlphaBlock(dds, offset) : null;
                int colorOffset = info.Format == BcFormat.Bc3 ? offset + 8 : offset;
                ushort color0 = ReadUInt16(dds, colorOffset);
                ushort color1 = ReadUInt16(dds, colorOffset + 2);
                bool fourColor = info.Format == BcFormat.Bc3 || color0 > color1;
                Rgb[] palette = BuildBcColorPalette(color0, color1, fourColor);
                uint selectors = ReadUInt32(dds, colorOffset + 4);
                for (int pixel = 0; pixel < 16; pixel++)
                {
                    int x = blockX * 4 + pixel % 4;
                    int y = blockY * 4 + pixel / 4;
                    if (x >= info.Width || y >= info.Height)
                        continue;
                    int selector = (int)((selectors >> (pixel * 2)) & 3);
                    int target = (y * info.Width + x) * 4;
                    result[target] = palette[selector].B;
                    result[target + 1] = palette[selector].G;
                    result[target + 2] = palette[selector].R;
                    result[target + 3] = info.Format == BcFormat.Bc3 ? alpha[pixel] : (byte)(!fourColor && selector == 3 ? 0 : 255);
                }
            }
        }
        return result;
    }

    private struct Rgb
    {
        public byte R;
        public byte G;
        public byte B;
        public Rgb(byte red, byte green, byte blue)
        {
            R = red;
            G = green;
            B = blue;
        }
    }

    private static byte[] DecodeBc3AlphaBlock(byte[] data, int offset)
    {
        byte alpha0 = data[offset];
        byte alpha1 = data[offset + 1];
        byte[] table = new byte[8];
        table[0] = alpha0;
        table[1] = alpha1;
        if (alpha0 > alpha1)
        {
            for (int index = 1; index <= 6; index++)
                table[index + 1] = (byte)(((7 - index) * alpha0 + index * alpha1) / 7);
        }
        else
        {
            for (int index = 1; index <= 4; index++)
                table[index + 1] = (byte)(((5 - index) * alpha0 + index * alpha1) / 5);
            table[6] = 0;
            table[7] = 255;
        }
        ulong selectors = 0;
        for (int index = 0; index < 6; index++)
            selectors |= ((ulong)data[offset + 2 + index]) << (8 * index);
        byte[] result = new byte[16];
        for (int pixel = 0; pixel < 16; pixel++)
        {
            result[pixel] = table[selectors & 7];
            selectors >>= 3;
        }
        return result;
    }

    private static Rgb[] BuildBcColorPalette(ushort color0, ushort color1, bool fourColor)
    {
        Rgb[] palette = new Rgb[4];
        palette[0] = DecodeRgb565(color0);
        palette[1] = DecodeRgb565(color1);
        if (fourColor)
        {
            palette[2] = Interpolate(palette[0], palette[1], 2, 1, 3);
            palette[3] = Interpolate(palette[0], palette[1], 1, 2, 3);
        }
        else
        {
            palette[2] = Interpolate(palette[0], palette[1], 1, 1, 2);
            palette[3] = new Rgb(0, 0, 0);
        }
        return palette;
    }

    private static Rgb DecodeRgb565(ushort value)
    {
        return new Rgb(
            (byte)((((value >> 11) & 31) * 255) / 31),
            (byte)((((value >> 5) & 63) * 255) / 63),
            (byte)(((value & 31) * 255) / 31));
    }

    private static Rgb Interpolate(Rgb left, Rgb right, int leftWeight, int rightWeight, int divisor)
    {
        return new Rgb(
            (byte)((left.R * leftWeight + right.R * rightWeight) / divisor),
            (byte)((left.G * leftWeight + right.G * rightWeight) / divisor),
            (byte)((left.B * leftWeight + right.B * rightWeight) / divisor));
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

    private static int CountChangedColorBlocks(byte[] source, byte[] output, DdsInfo info)
    {
        int changed = 0;
        for (int block = 0; block < info.BlockCount; block++)
        {
            int offset = info.DataOffset + block * info.BlockBytes;
            int colorOffset = info.Format == BcFormat.Bc3 ? offset + 8 : offset;
            if (!BytesEqual(source, colorOffset, output, colorOffset, 8))
                changed++;
        }
        return changed;
    }

    private static void PreserveSourceAlphaBlocks(byte[] source, byte[] output, DdsInfo info)
    {
        if (info.Format != BcFormat.Bc3)
            return;
        for (int block = 0; block < info.BlockCount; block++)
        {
            int offset = info.DataOffset + block * info.BlockBytes;
            Buffer.BlockCopy(source, offset, output, offset, 8);
        }
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
            if (source[offset] != output[offset] || source[offset + 1] != output[offset + 1] || source[offset + 2] != output[offset + 2])
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

    private static byte[] GetAlphaBytes(byte[] bgra)
    {
        byte[] result = new byte[bgra.Length / 4];
        int target = 0;
        for (int offset = 3; offset < bgra.Length; offset += 4)
            result[target++] = bgra[offset];
        return result;
    }

    private static byte[] GetTextureBgra(Texture texture, string label)
    {
        Bitmap picture = texture.Pictrue;
        if (picture == null)
            throw new InvalidDataException("ExtractorSharp could not decode " + label + ".");
        try
        {
            return Bitmaps.ToArray(picture);
        }
        finally
        {
            picture.Dispose();
            texture.Pictrue = null;
        }
    }

    private static void RunTexconv(string texconvFile, string pngFile, string outputDirectory, BcFormat format)
    {
        string formatText = format == BcFormat.Bc1 ? "BC1_UNORM" : "BC3_UNORM";
        string arguments = "-nologo -y -dx9 -m 1 -f " + formatText + " -nogpu --single-proc -bc x -o " +
            QuoteArgument(outputDirectory) + " -- " + QuoteArgument(pngFile);
        string output = RunProcess(texconvFile, arguments);
        if (output.IndexOf("ERROR", StringComparison.OrdinalIgnoreCase) >= 0)
            throw new InvalidDataException("texconv reported an error: " + output);
    }

    private static void RunTexdiag(string texdiagFile, string ddsFile, BcFormat format)
    {
        string output = RunProcess(texdiagFile, "info -nologo -- " + QuoteArgument(ddsFile));
        string expected = format == BcFormat.Bc1 ? "format = BC1_UNORM" : "format = BC3_UNORM";
        if (output.IndexOf(expected, StringComparison.OrdinalIgnoreCase) < 0 ||
            output.IndexOf("mipLevels = 1", StringComparison.OrdinalIgnoreCase) < 0)
            throw new InvalidDataException("texdiag did not confirm " + expected + " single-mip DDS: " + ddsFile);
    }

    private static string RunProcess(string fileName, string arguments)
    {
        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = fileName;
        startInfo.Arguments = arguments;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;
        using (Process process = Process.Start(startInfo))
        {
            string standardOutput = process.StandardOutput.ReadToEnd();
            string standardError = process.StandardError.ReadToEnd();
            process.WaitForExit();
            string combined = standardOutput + Environment.NewLine + standardError;
            if (process.ExitCode != 0)
                throw new InvalidOperationException(Path.GetFileName(fileName) + " failed with exit code " + process.ExitCode + ": " + combined);
            return combined;
        }
    }

    private static string NormalizeImgPath(string value)
    {
        if (String.IsNullOrWhiteSpace(value))
            throw new InvalidDataException("IMG path cannot be empty.");
        string normalized = value.Trim().Replace('\\', '/');
        while (normalized.StartsWith("/", StringComparison.Ordinal))
            normalized = normalized.Substring(1);
        if (!normalized.EndsWith(".img", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("IMG path must end in .img: " + value);
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
            builder.Append("]; ");
        }
        return builder.ToString();
    }

    private static ushort ReadUInt16(byte[] data, int offset)
    {
        return (ushort)(data[offset] | (data[offset + 1] << 8));
    }

    private static uint ReadUInt32(byte[] data, int offset)
    {
        return (uint)(data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24));
    }

    private static bool IsSha256(string value)
    {
        if (value == null || value.Length != 64)
            return false;
        foreach (char c in value)
        {
            bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
            if (!ok)
                return false;
        }
        return true;
    }

    private static void WriteJsonAtomically(string path, object value)
    {
        JavaScriptSerializer serializer = NewSerializer();
        string json = serializer.Serialize(value);
        string temporary = Path.Combine(Path.GetDirectoryName(path), "." + Path.GetFileName(path) + ".tmp-" + Guid.NewGuid().ToString("N"));
        File.WriteAllText(temporary, json, Encoding.UTF8);
        try
        {
            File.Move(temporary, path);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void RequireFile(string path, string label)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException("Missing " + label + ".", path);
    }

    private static void RequireDirectory(string path, string label)
    {
        if (!Directory.Exists(path))
            throw new DirectoryNotFoundException("Missing " + label + ": " + path);
    }

    private static string HashFile(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
            return ToHex(sha.ComputeHash(stream));
    }

    private static string HashBytes(byte[] bytes)
    {
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
        return BytesEqual(left, 0, right, 0, left.Length);
    }

    private static bool BytesEqual(byte[] left, int leftOffset, byte[] right, int rightOffset, int count)
    {
        if (left == null || right == null || leftOffset < 0 || rightOffset < 0 || count < 0 ||
            leftOffset + count > left.Length || rightOffset + count > right.Length)
            return false;
        for (int index = 0; index < count; index++)
        {
            if (left[leftOffset + index] != right[rightOffset + index])
                return false;
        }
        return true;
    }
}

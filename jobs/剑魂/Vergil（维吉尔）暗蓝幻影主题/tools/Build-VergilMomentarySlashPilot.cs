using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using ExtractorSharp.Core.Coder;
using ExtractorSharp.Core.Lib;
using ExtractorSharp.Core.Model;

internal static class BuildVergilMomentarySlashPilot
{
    private const long ExpectedSourceLength = 223755;
    private const string ExpectedSourceSha256 = "B1B0758EC8D958547E3184F9482E83ED4128C8513609E367B6CF3D287CE6B105";

    private static readonly string[] ExpectedPaths =
    {
        "sprite/character/swordman/effect/momentaryslash/drawingsword_blue_ldodge_under.img",
        "sprite/character/swordman/effect/momentaryslash/drawingsword_blue_ldodge_upper.img",
        "sprite/character/swordman/effect/momentaryslash/drawingsword_none_under.img",
        "sprite/character/swordman/effect/momentaryslash/drawingsword_none_upper.img",
        "sprite/character/swordman/effect/momentaryslash/drawingsword_red_ldodge_under.img",
        "sprite/character/swordman/effect/momentaryslash/drawingsword_red_ldodge_upper.img",
        "sprite/character/swordman/effect/momentaryslash/drawingsword_white_ldodge_under.img",
        "sprite/character/swordman/effect/momentaryslash/drawingsword_white_ldodge_upper.img"
    };

    private static readonly HashSet<string> ExcludedFrameKeys =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "sprite/character/swordman/effect/momentaryslash/drawingsword_blue_ldodge_upper.img#0",
            "sprite/character/swordman/effect/momentaryslash/drawingsword_none_upper.img#0",
            "sprite/character/swordman/effect/momentaryslash/drawingsword_red_ldodge_upper.img#0",
            "sprite/character/swordman/effect/momentaryslash/drawingsword_white_ldodge_upper.img#0"
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

    private static readonly PaletteStop[] VergilPalette =
    {
        new PaletteStop(0.00, Color.FromArgb(0x0A, 0x16, 0x33)),
        new PaletteStop(0.25, Color.FromArgb(0x0A, 0x16, 0x33)),
        new PaletteStop(0.58, Color.FromArgb(0x1A, 0x8F, 0xFF)),
        new PaletteStop(0.82, Color.FromArgb(0x00, 0xD4, 0xFF)),
        new PaletteStop(1.00, Color.FromArgb(0xFF, 0xFF, 0xFF))
    };

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
        public int TextureIndex;
        public int TextureWidth;
        public int TextureHeight;
        public int TextureLength;
        public int TextureFullLength;
        public ColorBits TextureType;
        public TextureVersion TextureVersion;
        public Point LeftUp;
        public Point RightDown;
        public int Rotation;
        public int Unknown;
        public byte[] CompressedData;
        public byte[] Dds;
        public int VisibleAlphaPixels;
        public bool Excluded;
    }

    private sealed class AlbumSnapshot
    {
        public string Path;
        public string Version;
        public int TableIndex;
        public string TableSignature;
        public List<FrameSnapshot> Frames = new List<FrameSnapshot>();
    }

    private sealed class DdsInfo
    {
        public int Width;
        public int Height;
        public int DataOffset;
        public int BlockCount;
    }

    private sealed class BuildStats
    {
        public int ChangedTextures;
        public int ExcludedTextures;
        public int ChangedColorBlocks;
        public int PreservedAlphaBlocks;
        public long OutputVisibleAlphaPixels;
        public long OutputWarmVisiblePixels;
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
        if (args.Length != 5)
        {
            Console.Error.WriteLine("Usage: <source.npk> <temporary-output.npk> <texconv.exe> <texdiag.exe> <work-directory>");
            return 2;
        }

        string sourceFile = Path.GetFullPath(args[0]);
        string outputFile = Path.GetFullPath(args[1]);
        string texconvFile = Path.GetFullPath(args[2]);
        string texdiagFile = Path.GetFullPath(args[3]);
        string workDirectory = Path.GetFullPath(args[4]);

        RequireFile(sourceFile, "source NPK");
        RequireFile(texconvFile, "texconv");
        RequireFile(texdiagFile, "texdiag");
        if (File.Exists(outputFile))
            throw new IOException("Temporary output already exists: " + outputFile);

        FileInfo sourceInfo = new FileInfo(sourceFile);
        if (sourceInfo.Length != ExpectedSourceLength)
            throw new InvalidDataException("Source length changed: " + sourceInfo.Length);
        string sourceHash = HashFile(sourceFile);
        if (!String.Equals(sourceHash, ExpectedSourceSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Source SHA-256 changed: " + sourceHash);

        Directory.CreateDirectory(Path.GetDirectoryName(outputFile));
        Directory.CreateDirectory(workDirectory);

        List<Album> analysisAlbums = NpkCoder.Load(sourceFile);
        List<AlbumSnapshot> sourceSnapshots = CaptureAndValidateSource(analysisAlbums);
        List<Album> buildAlbums = NpkCoder.Load(sourceFile);
        CaptureAndValidateSource(buildAlbums);

        BuildStats stats = new BuildStats();
        RecolorAllowedTextures(buildAlbums, analysisAlbums, sourceSnapshots, texconvFile, texdiagFile, workDirectory, stats);
        if (stats.ChangedTextures != 36 || stats.ExcludedTextures != 4)
            throw new InvalidDataException("Unexpected change selection: changed=" + stats.ChangedTextures + ", excluded=" + stats.ExcludedTextures);

        EnsureSpritesClosed(buildAlbums);
        NpkCoder.Save(outputFile, buildAlbums);
        ValidateOutput(outputFile, sourceSnapshots, texdiagFile, workDirectory, stats);

        Console.WriteLine("Source=" + sourceFile);
        Console.WriteLine("SourceLength=" + sourceInfo.Length);
        Console.WriteLine("SourceSha256=" + sourceHash);
        Console.WriteLine("Output=" + outputFile);
        Console.WriteLine("OutputLength=" + new FileInfo(outputFile).Length);
        Console.WriteLine("OutputSha256=" + HashFile(outputFile));
        Console.WriteLine("Albums=8");
        Console.WriteLine("Frames=40");
        Console.WriteLine("ChangedBc3Textures=" + stats.ChangedTextures);
        Console.WriteLine("UnchangedTransparentTextures=" + stats.ExcludedTextures);
        Console.WriteLine("ChangedBc3ColorBlocks=" + stats.ChangedColorBlocks);
        Console.WriteLine("PreservedBc3AlphaBlocks=" + stats.PreservedAlphaBlocks);
        Console.WriteLine("OutputVisibleAlphaPixels=" + stats.OutputVisibleAlphaPixels);
        Console.WriteLine("OutputWarmVisiblePixels=" + stats.OutputWarmVisiblePixels);
        Console.WriteLine("Palette=#0A1633,#1A8FFF,#00D4FF,#FFFFFF");
        Console.WriteLine("StructureValidation=passed");
        Console.WriteLine("TexdiagValidation=passed");
        Console.WriteLine("Deployment=not-performed");
        return 0;
    }

    private static List<AlbumSnapshot> CaptureAndValidateSource(List<Album> albums)
    {
        if (albums == null || albums.Count != ExpectedPaths.Length)
            throw new InvalidDataException("Source IMG count is not 8.");

        List<AlbumSnapshot> result = new List<AlbumSnapshot>();
        HashSet<string> paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (int albumIndex = 0; albumIndex < albums.Count; albumIndex++)
        {
            Album album = albums[albumIndex];
            if (!String.Equals(album.Path, ExpectedPaths[albumIndex], StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Source IMG order/path changed at " + albumIndex + ": " + album.Path);
            if (!paths.Add(album.Path))
                throw new InvalidDataException("Duplicate source IMG path: " + album.Path);
            if (!String.Equals(album.Version.ToString(), "Ver5", StringComparison.Ordinal))
                throw new InvalidDataException("Source IMG is not Ver5: " + album.Path);
            if (album.List == null || album.List.Count != 5)
                throw new InvalidDataException("Source frame count is not 5: " + album.Path);
            Dictionary<int, TextureInfo> map = GetTextureMap(album);
            if (map.Count != 5)
                throw new InvalidDataException("Source texture map count is not 5: " + album.Path);

            AlbumSnapshot albumSnapshot = new AlbumSnapshot();
            albumSnapshot.Path = album.Path;
            albumSnapshot.Version = album.Version.ToString();
            albumSnapshot.TableIndex = album.TableIndex;
            albumSnapshot.TableSignature = GetTableSignature(album);
            HashSet<Texture> mappedTextures = new HashSet<Texture>();

            for (int frameIndex = 0; frameIndex < album.List.Count; frameIndex++)
            {
                Sprite sprite = album.List[frameIndex];
                if (sprite.Index != frameIndex)
                    throw new InvalidDataException("Source frame index/order changed: " + album.Path + "#" + sprite.Index);
                if (sprite.Type != ColorBits.DXT_5 || sprite.CompressMode != CompressMode.DDS_ZLIB)
                    throw new InvalidDataException("Source sprite format is not DXT5/DDS_ZLIB: " + album.Path + "#" + sprite.Index);
                if (sprite.Hidden || sprite.Target != null)
                    throw new InvalidDataException("Source frame unexpectedly hidden or linked: " + album.Path + "#" + sprite.Index);

                TextureInfo textureInfo;
                if (!map.TryGetValue(sprite.Index, out textureInfo) || textureInfo == null || textureInfo.Texture == null)
                    throw new InvalidDataException("Source texture mapping is missing: " + album.Path + "#" + sprite.Index);
                Texture texture = textureInfo.Texture;
                if (texture.Index != frameIndex)
                    throw new InvalidDataException("Source texture index/order changed: " + album.Path + "#" + sprite.Index);
                if (!mappedTextures.Add(texture))
                    throw new InvalidDataException("Source texture is unexpectedly shared: " + album.Path + "#" + sprite.Index);
                if (texture.Type != ColorBits.DXT_5 || !String.Equals(texture.Version.ToString(), "Dxt1", StringComparison.Ordinal))
                    throw new InvalidDataException("Source texture declaration changed: " + album.Path + "#" + sprite.Index);
                if (texture.Data == null || texture.Data.Length != texture.Length)
                    throw new InvalidDataException("Source compressed texture length is inconsistent: " + album.Path + "#" + sprite.Index);

                byte[] dds = Zlib.Decompress(texture.Data, texture.FullLength);
                DdsInfo ddsInfo = ValidateDds(dds, texture.Width, texture.Height);
                if (texture.FullLength != dds.Length)
                    throw new InvalidDataException("Source full texture length is inconsistent: " + album.Path + "#" + sprite.Index);
                int visibleAlphaPixels = CountVisibleAlphaPixels(dds, ddsInfo);
                string frameKey = BuildFrameKey(album.Path, sprite.Index);
                bool excluded = ExcludedFrameKeys.Contains(frameKey);
                if (excluded && visibleAlphaPixels != 0)
                    throw new InvalidDataException("Excluded placeholder is no longer transparent: " + frameKey);
                if (!excluded && visibleAlphaPixels == 0)
                    throw new InvalidDataException("Allowed source texture is unexpectedly transparent: " + frameKey);

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
                frame.TextureIndex = texture.Index;
                frame.TextureWidth = texture.Width;
                frame.TextureHeight = texture.Height;
                frame.TextureLength = texture.Length;
                frame.TextureFullLength = texture.FullLength;
                frame.TextureType = texture.Type;
                frame.TextureVersion = texture.Version;
                frame.LeftUp = textureInfo.LeftUp;
                frame.RightDown = textureInfo.RightDown;
                frame.Rotation = textureInfo.Top;
                frame.Unknown = textureInfo.Unknown;
                frame.CompressedData = CloneBytes(texture.Data);
                frame.Dds = CloneBytes(dds);
                frame.VisibleAlphaPixels = visibleAlphaPixels;
                frame.Excluded = excluded;
                albumSnapshot.Frames.Add(frame);
            }

            if (mappedTextures.Count != map.Count)
                throw new InvalidDataException("Source texture sharing/coverage mismatch: " + album.Path);
            result.Add(albumSnapshot);
        }

        if (CountExcludedFrames(result) != 4)
            throw new InvalidDataException("Source excluded-frame count is not 4.");
        return result;
    }

    private static void RecolorAllowedTextures(
        List<Album> buildAlbums,
        List<Album> analysisAlbums,
        List<AlbumSnapshot> sourceSnapshots,
        string texconvFile,
        string texdiagFile,
        string workDirectory,
        BuildStats stats)
    {
        string pngDirectory = Path.Combine(workDirectory, "png");
        string encodedDirectory = Path.Combine(workDirectory, "encoded");
        Directory.CreateDirectory(pngDirectory);
        Directory.CreateDirectory(encodedDirectory);

        int globalIndex = 0;
        for (int albumIndex = 0; albumIndex < buildAlbums.Count; albumIndex++)
        {
            Album album = buildAlbums[albumIndex];
            Album analysisAlbum = analysisAlbums[albumIndex];
            Dictionary<int, TextureInfo> map = GetTextureMap(album);
            Dictionary<int, TextureInfo> analysisMap = GetTextureMap(analysisAlbum);
            for (int frameIndex = 0; frameIndex < album.List.Count; frameIndex++)
            {
                FrameSnapshot snapshot = sourceSnapshots[albumIndex].Frames[frameIndex];
                Texture texture = map[frameIndex].Texture;
                if (snapshot.Excluded)
                {
                    stats.ExcludedTextures++;
                    globalIndex++;
                    continue;
                }

                Texture analysisTexture = analysisMap[frameIndex].Texture;
                Bitmap sourceBitmap = analysisTexture.Pictrue;
                if (sourceBitmap == null)
                    throw new InvalidDataException("ExtractorSharp could not decode full source texture: " + BuildFrameKey(album.Path, frameIndex));
                if (sourceBitmap.Width != texture.Width || sourceBitmap.Height != texture.Height)
                    throw new InvalidDataException("Full texture bitmap geometry mismatch: " + BuildFrameKey(album.Path, frameIndex));

                string baseName = globalIndex.ToString("D4");
                string pngFile = Path.Combine(pngDirectory, baseName + ".png");
                string ddsFile = Path.Combine(encodedDirectory, baseName + ".DDS");
                try
                {
                    using (Bitmap recolored = RecolorBitmap(sourceBitmap))
                    {
                        recolored.Save(pngFile, ImageFormat.Png);
                    }
                }
                finally
                {
                    sourceBitmap.Dispose();
                    analysisTexture.Pictrue = null;
                }

                RunTexconv(texconvFile, pngFile, encodedDirectory);
                RequireFile(ddsFile, "texconv output");
                RunTexdiag(texdiagFile, ddsFile);

                byte[] encodedDds = File.ReadAllBytes(ddsFile);
                byte[] recoloredDds = MergeBc3ColorBlocks(snapshot.Dds, encodedDds, ref stats.ChangedColorBlocks, ref stats.PreservedAlphaBlocks);
                byte[] compressed = Zlib.Compress(recoloredDds);
                if (compressed == null || compressed.Length == 0)
                    throw new InvalidDataException("Zlib returned an empty texture: " + BuildFrameKey(album.Path, frameIndex));

                texture.Data = compressed;
                texture.Length = compressed.Length;
                texture.FullLength = recoloredDds.Length;
                stats.ChangedTextures++;
                globalIndex++;
            }
        }
    }

    private static void ValidateOutput(
        string outputFile,
        List<AlbumSnapshot> sourceSnapshots,
        string texdiagFile,
        string workDirectory,
        BuildStats stats)
    {
        List<Album> outputAlbums = NpkCoder.Load(outputFile);
        if (outputAlbums.Count != sourceSnapshots.Count)
            throw new InvalidDataException("Output IMG count changed.");

        string finalDdsDirectory = Path.Combine(workDirectory, "final-dds");
        Directory.CreateDirectory(finalDdsDirectory);
        int globalIndex = 0;
        int verifiedChangedTextures = 0;
        int verifiedExcludedTextures = 0;
        int verifiedChangedBlocks = 0;
        long visibleAlphaPixels = 0;
        long warmVisiblePixels = 0;

        for (int albumIndex = 0; albumIndex < outputAlbums.Count; albumIndex++)
        {
            Album album = outputAlbums[albumIndex];
            AlbumSnapshot sourceAlbum = sourceSnapshots[albumIndex];
            if (!String.Equals(album.Path, sourceAlbum.Path, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(album.Version.ToString(), sourceAlbum.Version, StringComparison.Ordinal))
                throw new InvalidDataException("Output IMG identity/version changed at " + albumIndex);
            if (album.TableIndex != sourceAlbum.TableIndex ||
                !String.Equals(GetTableSignature(album), sourceAlbum.TableSignature, StringComparison.Ordinal))
                throw new InvalidDataException("Output table metadata changed: " + album.Path);
            if (album.List.Count != sourceAlbum.Frames.Count)
                throw new InvalidDataException("Output frame/texture count changed: " + album.Path);

            Dictionary<int, TextureInfo> map = GetTextureMap(album);
            if (map.Count != sourceAlbum.Frames.Count)
                throw new InvalidDataException("Output texture map count changed: " + album.Path);
            HashSet<Texture> mappedTextures = new HashSet<Texture>();

            for (int frameIndex = 0; frameIndex < album.List.Count; frameIndex++)
            {
                Sprite sprite = album.List[frameIndex];
                FrameSnapshot source = sourceAlbum.Frames[frameIndex];
                ValidateFrameMetadata(album, sprite, source, map, mappedTextures);

                Texture texture = map[sprite.Index].Texture;
                byte[] dds = Zlib.Decompress(texture.Data, texture.FullLength);
                DdsInfo info = ValidateDds(dds, source.TextureWidth, source.TextureHeight);
                if (!BytesEqual(source.Dds, 0, dds, 0, info.DataOffset))
                    throw new InvalidDataException("DDS header changed: " + BuildFrameKey(album.Path, sprite.Index));
                int changedBlocks;
                if (!Bc3AlphaBlocksEqual(source.Dds, dds, info, out changedBlocks))
                    throw new InvalidDataException("BC3 alpha block changed: " + BuildFrameKey(album.Path, sprite.Index));

                if (source.Excluded)
                {
                    if (!BytesEqual(source.Dds, dds) || !BytesEqual(source.CompressedData, texture.Data))
                        throw new InvalidDataException("Excluded transparent texture changed: " + BuildFrameKey(album.Path, sprite.Index));
                    verifiedExcludedTextures++;
                }
                else
                {
                    if (changedBlocks == 0)
                        throw new InvalidDataException("Allowed texture has no BC3 color change: " + BuildFrameKey(album.Path, sprite.Index));
                    verifiedChangedTextures++;
                    verifiedChangedBlocks += changedBlocks;
                }

                int outputAlphaPixels = CountVisibleAlphaPixels(dds, info);
                if (outputAlphaPixels != source.VisibleAlphaPixels)
                    throw new InvalidDataException("Decoded alpha coverage changed: " + BuildFrameKey(album.Path, sprite.Index));

                string ddsFile = Path.Combine(finalDdsDirectory, globalIndex.ToString("D4") + ".dds");
                File.WriteAllBytes(ddsFile, dds);
                RunTexdiag(texdiagFile, ddsFile);

                Bitmap picture = texture.Pictrue;
                if (picture == null)
                    throw new InvalidDataException("Output texture could not be decoded: " + BuildFrameKey(album.Path, sprite.Index));
                try
                {
                    long textureVisible;
                    long textureWarm;
                    CountOutputPixels(picture, out textureVisible, out textureWarm);
                    visibleAlphaPixels += textureVisible;
                    warmVisiblePixels += textureWarm;
                    if (!source.Excluded && textureVisible == 0)
                        throw new InvalidDataException("Allowed output texture became invisible: " + BuildFrameKey(album.Path, sprite.Index));
                }
                finally
                {
                    picture.Dispose();
                    texture.Pictrue = null;
                }
                globalIndex++;
            }

            if (mappedTextures.Count != map.Count)
                throw new InvalidDataException("Output texture sharing/coverage changed: " + album.Path);
        }

        if (verifiedChangedTextures != 36 || verifiedExcludedTextures != 4)
            throw new InvalidDataException("Output selection validation count mismatch.");
        if (verifiedChangedBlocks != stats.ChangedColorBlocks)
            throw new InvalidDataException("Output changed BC3 block count mismatch.");
        if (warmVisiblePixels != 0)
            throw new InvalidDataException("Output contains warm visible pixels: " + warmVisiblePixels);

        stats.OutputVisibleAlphaPixels = visibleAlphaPixels;
        stats.OutputWarmVisiblePixels = warmVisiblePixels;
    }

    private static void ValidateFrameMetadata(
        Album album,
        Sprite sprite,
        FrameSnapshot source,
        Dictionary<int, TextureInfo> map,
        HashSet<Texture> mappedTextures)
    {
        int targetIndex = sprite.Target == null ? -1 : sprite.Target.Index;
        if (sprite.Index != source.Index ||
            sprite.Type != source.Type ||
            sprite.CompressMode != source.CompressMode ||
            sprite.Hidden != source.Hidden ||
            targetIndex != source.TargetIndex ||
            sprite.Width != source.Width ||
            sprite.Height != source.Height ||
            sprite.CanvasWidth != source.CanvasWidth ||
            sprite.CanvasHeight != source.CanvasHeight ||
            sprite.X != source.X ||
            sprite.Y != source.Y ||
            sprite.Length != source.Length ||
            !BytesEqual(sprite.Data, source.SpriteData))
            throw new InvalidDataException("Output sprite metadata changed: " + BuildFrameKey(album.Path, sprite.Index));

        TextureInfo info;
        if (!map.TryGetValue(sprite.Index, out info) || info == null || info.Texture == null)
            throw new InvalidDataException("Output texture map is missing: " + BuildFrameKey(album.Path, sprite.Index));
        Texture texture = info.Texture;
        if (!mappedTextures.Add(texture) ||
            texture.Index != source.TextureIndex ||
            texture.Width != source.TextureWidth ||
            texture.Height != source.TextureHeight ||
            texture.FullLength != source.TextureFullLength ||
            texture.Type != source.TextureType ||
            texture.Version != source.TextureVersion ||
            info.LeftUp != source.LeftUp ||
            info.RightDown != source.RightDown ||
            info.Top != source.Rotation ||
            info.Unknown != source.Unknown)
            throw new InvalidDataException("Output texture metadata changed: " + BuildFrameKey(album.Path, sprite.Index));
        if (texture.Data == null || texture.Data.Length != texture.Length)
            throw new InvalidDataException("Output compressed texture length is inconsistent: " + BuildFrameKey(album.Path, sprite.Index));
    }

    private static byte[] MergeBc3ColorBlocks(
        byte[] sourceDds,
        byte[] encodedDds,
        ref int totalChangedBlocks,
        ref int totalPreservedAlphaBlocks)
    {
        DdsInfo sourceInfo = ValidateDds(sourceDds, -1, -1);
        DdsInfo encodedInfo = ValidateDds(encodedDds, sourceInfo.Width, sourceInfo.Height);
        if (sourceInfo.BlockCount != encodedInfo.BlockCount)
            throw new InvalidDataException("BC3 block count changed after encoding.");

        byte[] result = CloneBytes(sourceDds);
        int changedBlocks = 0;
        for (int block = 0; block < sourceInfo.BlockCount; block++)
        {
            int sourceOffset = sourceInfo.DataOffset + block * 16;
            int encodedOffset = encodedInfo.DataOffset + block * 16;
            bool changed = false;
            for (int byteIndex = 8; byteIndex < 16; byteIndex++)
            {
                byte replacement = encodedDds[encodedOffset + byteIndex];
                if (result[sourceOffset + byteIndex] != replacement)
                    changed = true;
                result[sourceOffset + byteIndex] = replacement;
            }
            if (changed)
                changedBlocks++;
            totalPreservedAlphaBlocks++;
        }
        if (changedBlocks == 0)
            throw new InvalidDataException("texconv produced no changed BC3 color blocks.");
        totalChangedBlocks += changedBlocks;
        return result;
    }

    private static bool Bc3AlphaBlocksEqual(byte[] source, byte[] output, DdsInfo info, out int changedColorBlocks)
    {
        changedColorBlocks = 0;
        for (int block = 0; block < info.BlockCount; block++)
        {
            int offset = info.DataOffset + block * 16;
            if (!BytesEqual(source, offset, output, offset, 8))
                return false;
            if (!BytesEqual(source, offset + 8, output, offset + 8, 8))
                changedColorBlocks++;
        }
        return true;
    }

    private static DdsInfo ValidateDds(byte[] dds, int expectedWidth, int expectedHeight)
    {
        if (dds == null || dds.Length < 144)
            throw new InvalidDataException("DDS payload is too short.");
        if (BitConverter.ToInt32(dds, 0) != 0x20534444)
            throw new InvalidDataException("DDS magic is invalid.");
        int headerSize = BitConverter.ToInt32(dds, 4);
        int height = BitConverter.ToInt32(dds, 12);
        int width = BitConverter.ToInt32(dds, 16);
        int mipLevels = BitConverter.ToInt32(dds, 28);
        int pixelFormatSize = BitConverter.ToInt32(dds, 76);
        int fourCc = BitConverter.ToInt32(dds, 84);
        if (headerSize != 124 || pixelFormatSize != 32 || fourCc != 0x35545844)
            throw new InvalidDataException("DDS is not a legacy DXT5/BC3 payload.");
        if (width < 1 || height < 1 || (mipLevels != 0 && mipLevels != 1))
            throw new InvalidDataException("DDS dimensions or mip count are invalid.");
        if (expectedWidth > 0 && width != expectedWidth)
            throw new InvalidDataException("DDS width changed: " + width + "/" + expectedWidth);
        if (expectedHeight > 0 && height != expectedHeight)
            throw new InvalidDataException("DDS height changed: " + height + "/" + expectedHeight);

        int blocksWide = (width + 3) / 4;
        int blocksHigh = (height + 3) / 4;
        int blockCount = checked(blocksWide * blocksHigh);
        int dataOffset = 4 + headerSize;
        int requiredLength = checked(dataOffset + blockCount * 16);
        if (dds.Length != requiredLength)
            throw new InvalidDataException("DDS BC3 block length is invalid: " + dds.Length + "/" + requiredLength);

        DdsInfo result = new DdsInfo();
        result.Width = width;
        result.Height = height;
        result.DataOffset = dataOffset;
        result.BlockCount = blockCount;
        return result;
    }

    private static int CountVisibleAlphaPixels(byte[] dds, DdsInfo info)
    {
        int blocksWide = (info.Width + 3) / 4;
        int blocksHigh = (info.Height + 3) / 4;
        int visible = 0;
        for (int blockY = 0; blockY < blocksHigh; blockY++)
        {
            for (int blockX = 0; blockX < blocksWide; blockX++)
            {
                int offset = info.DataOffset + (blockY * blocksWide + blockX) * 16;
                byte[] alphas = DecodeBc3AlphaBlock(dds, offset);
                for (int pixel = 0; pixel < 16; pixel++)
                {
                    int x = blockX * 4 + pixel % 4;
                    int y = blockY * 4 + pixel / 4;
                    if (x < info.Width && y < info.Height && alphas[pixel] != 0)
                        visible++;
                }
            }
        }
        return visible;
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
            for (int i = 1; i <= 6; i++)
                table[i + 1] = (byte)(((7 - i) * alpha0 + i * alpha1) / 7);
        }
        else
        {
            for (int i = 1; i <= 4; i++)
                table[i + 1] = (byte)(((5 - i) * alpha0 + i * alpha1) / 5);
            table[6] = 0;
            table[7] = 255;
        }

        ulong indices = 0;
        for (int i = 0; i < 6; i++)
            indices |= ((ulong)data[offset + 2 + i]) << (8 * i);
        byte[] alpha = new byte[16];
        for (int pixel = 0; pixel < 16; pixel++)
        {
            alpha[pixel] = table[indices & 7];
            indices >>= 3;
        }
        return alpha;
    }

    private static Bitmap RecolorBitmap(Bitmap source)
    {
        Rectangle rectangle = new Rectangle(0, 0, source.Width, source.Height);
        Bitmap result = source.Clone(rectangle, PixelFormat.Format32bppArgb);
        BitmapData data = result.LockBits(rectangle, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        try
        {
            int byteCount = Math.Abs(data.Stride) * data.Height;
            byte[] pixels = new byte[byteCount];
            Marshal.Copy(data.Scan0, pixels, 0, byteCount);
            for (int y = 0; y < data.Height; y++)
            {
                int row = y * Math.Abs(data.Stride);
                for (int x = 0; x < data.Width; x++)
                {
                    int index = row + x * 4;
                    byte alpha = pixels[index + 3];
                    if (alpha == 0)
                        continue;
                    int blue = pixels[index];
                    int green = pixels[index + 1];
                    int red = pixels[index + 2];
                    double intensity = Math.Max(red, Math.Max(green, blue)) / 255.0;
                    Color mapped = MapPalette(intensity);
                    pixels[index] = mapped.B;
                    pixels[index + 1] = mapped.G;
                    pixels[index + 2] = mapped.R;
                }
            }
            Marshal.Copy(pixels, 0, data.Scan0, byteCount);
        }
        finally
        {
            result.UnlockBits(data);
        }
        return result;
    }

    private static Color MapPalette(double intensity)
    {
        for (int i = 1; i < VergilPalette.Length; i++)
        {
            PaletteStop right = VergilPalette[i];
            if (intensity <= right.Position)
            {
                PaletteStop left = VergilPalette[i - 1];
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

    private static void CountOutputPixels(Bitmap picture, out long visible, out long warm)
    {
        visible = 0;
        warm = 0;
        for (int y = 0; y < picture.Height; y++)
        {
            for (int x = 0; x < picture.Width; x++)
            {
                Color color = picture.GetPixel(x, y);
                if (color.A == 0)
                    continue;
                visible++;
                if (color.A >= 16 && color.R > color.B + 12)
                    warm++;
            }
        }
    }

    private static void RunTexconv(string texconvFile, string pngFile, string outputDirectory)
    {
        string arguments =
            "-nologo -y -dx9 -m 1 -f BC3_UNORM -nogpu --single-proc -bc x -o " +
            QuoteArgument(outputDirectory) + " -- " + QuoteArgument(pngFile);
        string output = RunProcess(texconvFile, arguments);
        if (output.IndexOf("ERROR", StringComparison.OrdinalIgnoreCase) >= 0)
            throw new InvalidDataException("texconv reported an error: " + output);
    }

    private static void RunTexdiag(string texdiagFile, string ddsFile)
    {
        string output = RunProcess(texdiagFile, "info -nologo -- " + QuoteArgument(ddsFile));
        if (output.IndexOf("format = BC3_UNORM", StringComparison.OrdinalIgnoreCase) < 0 ||
            output.IndexOf("mipLevels = 1", StringComparison.OrdinalIgnoreCase) < 0)
            throw new InvalidDataException("texdiag did not confirm BC3 single-mip DDS: " + ddsFile);
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

    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static Dictionary<int, TextureInfo> GetTextureMap(Album album)
    {
        FieldInfo mapField = album.Handler.GetType().GetField("_map", BindingFlags.Instance | BindingFlags.NonPublic);
        if (mapField == null)
            throw new InvalidDataException("Ver5 texture map field is unavailable: " + album.Path);
        Dictionary<int, TextureInfo> map = mapField.GetValue(album.Handler) as Dictionary<int, TextureInfo>;
        if (map == null)
            throw new InvalidDataException("Ver5 texture map is unavailable: " + album.Path);
        return map;
    }

    private static void EnsureSpritesClosed(List<Album> albums)
    {
        foreach (Album album in albums)
        {
            foreach (Sprite sprite in album.List)
            {
                if (sprite.IsOpen)
                    throw new InvalidOperationException("A build-tree Sprite was opened before save: " + BuildFrameKey(album.Path, sprite.Index));
                if (sprite.Type != ColorBits.DXT_5 || sprite.CompressMode != CompressMode.DDS_ZLIB)
                    throw new InvalidDataException("Build-tree Sprite declaration changed before save: " + BuildFrameKey(album.Path, sprite.Index));
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

    private static int CountExcludedFrames(List<AlbumSnapshot> albums)
    {
        int count = 0;
        foreach (AlbumSnapshot album in albums)
        {
            foreach (FrameSnapshot frame in album.Frames)
            {
                if (frame.Excluded)
                    count++;
            }
        }
        return count;
    }

    private static string BuildFrameKey(string albumPath, int frameIndex)
    {
        return albumPath + "#" + frameIndex;
    }

    private static void RequireFile(string path, string label)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException("Missing " + label + ".", path);
    }

    private static string HashFile(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
            return ToHex(sha.ComputeHash(stream));
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
        if (left == null || right == null ||
            leftOffset < 0 || rightOffset < 0 || count < 0 ||
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

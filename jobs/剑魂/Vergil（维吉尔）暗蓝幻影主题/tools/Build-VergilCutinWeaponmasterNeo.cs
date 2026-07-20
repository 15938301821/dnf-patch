using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using ExtractorSharp.Core.Coder;
using ExtractorSharp.Core.Lib;
using ExtractorSharp.Core.Model;

internal static class BuildVergilCutinWeaponmasterNeo
{
    private const string TargetImgPath = "sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img";
    private const long ExpectedSourceLength = 137275223;
    private const string ExpectedSourceSha256 = "51C7FF71615DB6982D55BFBFEEA1741F37778CD4B89BE2C8B5833DD329E61224";
    private const int ExpectedEntryCount = 26;

    private sealed class NpkEntry
    {
        public int Index;
        public long Offset;
        public int Size;
        public string Path;
        public byte[] Payload;
    }

    private sealed class FrameSnapshot
    {
        public int Index;
        public ColorBits SpriteType;
        public CompressMode CompressMode;
        public bool Hidden;
        public int TargetIndex;
        public int Width;
        public int Height;
        public int CanvasWidth;
        public int CanvasHeight;
        public int X;
        public int Y;
        public int SpriteLength;
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
        public bool Placeholder;
        public int VisibleAlphaPixels;
    }

    private sealed class DdsInfo
    {
        public int Width;
        public int Height;
        public int DataOffset;
        public int BlockCount;
        public int BlockBytes;
        public string FourCc;
    }

    private sealed class BuildStats
    {
        public int ChangedTextures;
        public int PreservedPlaceholderFrames;
        public int ChangedBc3ColorBlocks;
        public int PreservedBc3AlphaBlocks;
        public int NonTargetPayloadsByteIdentical;
        public int SharedPayloadEntriesReused;
        public long ModifiedImgBytes;
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
        if (args.Length != 6)
        {
            Console.Error.WriteLine("Usage: <source.npk> <temporary-output.npk> <edited-png-directory> <texconv.exe> <texdiag.exe> <work-directory>");
            return 2;
        }

        string sourceFile = Path.GetFullPath(args[0]);
        string outputFile = Path.GetFullPath(args[1]);
        string pngDirectory = Path.GetFullPath(args[2]);
        string texconvFile = Path.GetFullPath(args[3]);
        string texdiagFile = Path.GetFullPath(args[4]);
        string workDirectory = Path.GetFullPath(args[5]);

        RequireFile(sourceFile, "source NPK");
        RequireDirectory(pngDirectory, "edited PNG directory");
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

        List<NpkEntry> sourceEntries = ReadNpkEntries(sourceFile);
        if (sourceEntries.Count != ExpectedEntryCount)
            throw new InvalidDataException("Source NPK entry count changed: " + sourceEntries.Count);
        int targetEntryIndex = FindEntryIndex(sourceEntries, TargetImgPath);
        if (targetEntryIndex < 0)
            throw new InvalidDataException("Target IMG was not found in source NPK.");

        List<Album> analysisAlbums = NpkCoder.Load(sourceFile);
        List<Album> buildAlbums = NpkCoder.Load(sourceFile);
        Album analysisTarget = FindTargetAlbum(analysisAlbums);
        Album buildTarget = FindTargetAlbum(buildAlbums);
        List<FrameSnapshot> sourceFrames = CaptureAndValidateTarget(analysisTarget);
        CaptureAndValidateTarget(buildTarget);

        BuildStats stats = new BuildStats();
        ApplyEditedPngs(buildTarget, sourceFrames, pngDirectory, texconvFile, texdiagFile, workDirectory, stats);
        if (stats.ChangedTextures != 24)
            throw new InvalidDataException("Expected 24 changed visible textures, found " + stats.ChangedTextures);

        byte[] modifiedImg = SaveAlbumToBytes(buildTarget);
        stats.ModifiedImgBytes = modifiedImg.Length;
        ValidateImgPayload(modifiedImg);

        WriteRebuiltNpk(outputFile, sourceEntries, targetEntryIndex, modifiedImg, stats);
        ValidateOutput(outputFile, sourceEntries, sourceFrames, texdiagFile, workDirectory, stats);

        Console.WriteLine("Source=" + sourceFile);
        Console.WriteLine("SourceLength=" + sourceInfo.Length);
        Console.WriteLine("SourceSha256=" + sourceHash);
        Console.WriteLine("TargetImg=" + TargetImgPath);
        Console.WriteLine("EditedPngDirectory=" + pngDirectory);
        Console.WriteLine("Output=" + outputFile);
        Console.WriteLine("OutputLength=" + new FileInfo(outputFile).Length);
        Console.WriteLine("OutputSha256=" + HashFile(outputFile));
        Console.WriteLine("NpkEntries=" + sourceEntries.Count);
        Console.WriteLine("ModifiedImgBytes=" + stats.ModifiedImgBytes);
        Console.WriteLine("ChangedVisibleTextures=" + stats.ChangedTextures);
        Console.WriteLine("PreservedPlaceholderFrames=" + stats.PreservedPlaceholderFrames);
        Console.WriteLine("ChangedBc3ColorBlocks=" + stats.ChangedBc3ColorBlocks);
        Console.WriteLine("PreservedBc3AlphaBlocks=" + stats.PreservedBc3AlphaBlocks);
        Console.WriteLine("NonTargetPayloadsByteIdentical=" + stats.NonTargetPayloadsByteIdentical);
        Console.WriteLine("SharedPayloadEntriesReused=" + stats.SharedPayloadEntriesReused);
        Console.WriteLine("StructureValidation=passed");
        Console.WriteLine("TexdiagValidation=passed");
        Console.WriteLine("Deployment=not-performed");
        return 0;
    }

    private static Album FindTargetAlbum(List<Album> albums)
    {
        Album found = null;
        foreach (Album album in albums)
        {
            if (String.Equals(album.Path, TargetImgPath, StringComparison.OrdinalIgnoreCase))
            {
                if (found != null)
                    throw new InvalidDataException("Duplicate target IMG in decoded NPK.");
                found = album;
            }
        }
        if (found == null)
            throw new InvalidDataException("Target IMG was not decoded from NPK.");
        return found;
    }

    private static List<FrameSnapshot> CaptureAndValidateTarget(Album album)
    {
        if (!String.Equals(album.Path, TargetImgPath, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Unexpected target album path: " + album.Path);
        if (!String.Equals(album.Version.ToString(), "Ver5", StringComparison.Ordinal) || album.List.Count != 27)
            throw new InvalidDataException("Target IMG must be Ver5 with 27 frames.");

        Dictionary<int, TextureInfo> map = GetTextureMap(album);
        List<FrameSnapshot> result = new List<FrameSnapshot>();
        HashSet<Texture> uniqueTextures = new HashSet<Texture>();
        for (int index = 0; index < album.List.Count; index++)
        {
            Sprite sprite = album.List[index];
            if (sprite.Index != index)
                throw new InvalidDataException("Frame index/order changed at target frame " + sprite.Index);
            if (sprite.Hidden || sprite.Target != null)
                throw new InvalidDataException("Target frame is unexpectedly hidden or linked: " + sprite.Index);

            TextureInfo textureInfo;
            if (!map.TryGetValue(sprite.Index, out textureInfo) || textureInfo == null || textureInfo.Texture == null)
                throw new InvalidDataException("Missing Ver5 texture map for frame " + sprite.Index);
            Texture texture = textureInfo.Texture;
            bool placeholder = index <= 2;
            if (!placeholder)
                uniqueTextures.Add(texture);

            byte[] dds = Zlib.Decompress(texture.Data, texture.FullLength);
            DdsInfo ddsInfo = ValidateDds(dds, texture.Width, texture.Height, placeholder ? "DXT1" : "DXT5");

            if (placeholder)
            {
                if (sprite.Width != 1 || sprite.Height != 1 ||
                    sprite.CanvasWidth != 1 || sprite.CanvasHeight != 1 ||
                    sprite.Type != ColorBits.DXT_1 || texture.Type != ColorBits.DXT_1 ||
                    texture.Index != 0 || ddsInfo.FourCc != "DXT1")
                    throw new InvalidDataException("Placeholder frame structure changed: " + index);
            }
            else
            {
                if (sprite.Width != 1067 || sprite.Height != 600 ||
                    sprite.CanvasWidth != 1067 || sprite.CanvasHeight != 600 ||
                    sprite.X != 0 || sprite.Y != 0 ||
                    sprite.Type != ColorBits.DXT_5 || texture.Type != ColorBits.DXT_5 ||
                    texture.Width != 1068 || texture.Height != 600 ||
                    texture.Index != index - 2 || ddsInfo.FourCc != "DXT5")
                    throw new InvalidDataException("Visible frame structure changed: " + index);
            }
            if (sprite.CompressMode != CompressMode.DDS_ZLIB || texture.Data == null || texture.Data.Length != texture.Length)
                throw new InvalidDataException("Texture compression declaration is inconsistent: " + index);

            FrameSnapshot snapshot = new FrameSnapshot();
            snapshot.Index = sprite.Index;
            snapshot.SpriteType = sprite.Type;
            snapshot.CompressMode = sprite.CompressMode;
            snapshot.Hidden = sprite.Hidden;
            snapshot.TargetIndex = sprite.Target == null ? -1 : sprite.Target.Index;
            snapshot.Width = sprite.Width;
            snapshot.Height = sprite.Height;
            snapshot.CanvasWidth = sprite.CanvasWidth;
            snapshot.CanvasHeight = sprite.CanvasHeight;
            snapshot.X = sprite.X;
            snapshot.Y = sprite.Y;
            snapshot.SpriteLength = sprite.Length;
            snapshot.SpriteData = CloneBytes(sprite.Data);
            snapshot.TextureIndex = texture.Index;
            snapshot.TextureWidth = texture.Width;
            snapshot.TextureHeight = texture.Height;
            snapshot.TextureLength = texture.Length;
            snapshot.TextureFullLength = texture.FullLength;
            snapshot.TextureType = texture.Type;
            snapshot.TextureVersion = texture.Version;
            snapshot.LeftUp = textureInfo.LeftUp;
            snapshot.RightDown = textureInfo.RightDown;
            snapshot.Rotation = textureInfo.Top;
            snapshot.Unknown = textureInfo.Unknown;
            snapshot.CompressedData = CloneBytes(texture.Data);
            snapshot.Dds = CloneBytes(dds);
            snapshot.Placeholder = placeholder;
            snapshot.VisibleAlphaPixels = placeholder ? 0 : CountVisibleAlphaPixels(dds, ddsInfo);
            if (!placeholder && snapshot.VisibleAlphaPixels == 0)
                throw new InvalidDataException("Visible source frame has no alpha coverage: " + index);
            result.Add(snapshot);
        }

        if (uniqueTextures.Count != 24)
            throw new InvalidDataException("Target visible texture uniqueness changed: " + uniqueTextures.Count);
        return result;
    }

    private static void ApplyEditedPngs(
        Album target,
        List<FrameSnapshot> sourceFrames,
        string pngDirectory,
        string texconvFile,
        string texdiagFile,
        string workDirectory,
        BuildStats stats)
    {
        string encodedDirectory = Path.Combine(workDirectory, "encoded-dds");
        Directory.CreateDirectory(encodedDirectory);
        Dictionary<int, TextureInfo> map = GetTextureMap(target);

        for (int frameIndex = 0; frameIndex < target.List.Count; frameIndex++)
        {
            FrameSnapshot snapshot = sourceFrames[frameIndex];
            Texture texture = map[frameIndex].Texture;
            if (snapshot.Placeholder)
            {
                if (!BytesEqual(texture.Data, snapshot.CompressedData))
                    throw new InvalidDataException("Placeholder texture was modified before build: " + frameIndex);
                stats.PreservedPlaceholderFrames++;
                continue;
            }

            string pngFile = Path.Combine(pngDirectory, "frame-" + frameIndex.ToString("D3") + ".png");
            RequireFile(pngFile, "edited PNG for frame " + frameIndex);
            using (Bitmap edited = new Bitmap(pngFile))
            {
                if (edited.Width != 1068 || edited.Height != 600)
                    throw new InvalidDataException("Edited PNG geometry mismatch for frame " + frameIndex);
            }

            string ddsFile = Path.Combine(encodedDirectory, "frame-" + frameIndex.ToString("D3") + ".DDS");
            RunTexconv(texconvFile, pngFile, encodedDirectory);
            RequireFile(ddsFile, "texconv output for frame " + frameIndex);
            RunTexdiag(texdiagFile, ddsFile, "BC3_UNORM");

            byte[] encodedDds = File.ReadAllBytes(ddsFile);
            int changedBlocks;
            int preservedAlphaBlocks;
            byte[] mergedDds = MergeBc3ColorBlocks(snapshot.Dds, encodedDds, out changedBlocks, out preservedAlphaBlocks);
            if (changedBlocks == 0)
                throw new InvalidDataException("Edited PNG did not change any BC3 color blocks for frame " + frameIndex);

            texture.Data = Zlib.Compress(mergedDds);
            texture.Length = texture.Data.Length;
            texture.FullLength = mergedDds.Length;
            stats.ChangedTextures++;
            stats.ChangedBc3ColorBlocks += changedBlocks;
            stats.PreservedBc3AlphaBlocks += preservedAlphaBlocks;
        }
    }

    private static byte[] SaveAlbumToBytes(Album album)
    {
        using (MemoryStream stream = new MemoryStream())
        {
            album.Save(stream);
            return stream.ToArray();
        }
    }

    private static void ValidateImgPayload(byte[] payload)
    {
        if (payload == null || payload.Length < 28)
            throw new InvalidDataException("Modified IMG payload is too short.");
        string magic = ReadNullTerminatedAscii(payload, 0, 18);
        if (magic != "Neople Img File" && magic != "Neople Image File")
            throw new InvalidDataException("Modified IMG payload magic is invalid: " + magic);
        int version = BitConverter.ToInt32(payload, 24);
        if (version != 5)
            throw new InvalidDataException("Modified IMG payload is not Ver5: " + version);
    }

    private static void ValidateOutput(
        string outputFile,
        List<NpkEntry> sourceEntries,
        List<FrameSnapshot> sourceFrames,
        string texdiagFile,
        string workDirectory,
        BuildStats stats)
    {
        List<NpkEntry> outputEntries = ReadNpkEntries(outputFile);
        if (outputEntries.Count != sourceEntries.Count)
            throw new InvalidDataException("Output NPK entry count changed.");
        int targetEntryIndex = FindEntryIndex(outputEntries, TargetImgPath);
        if (targetEntryIndex < 0)
            throw new InvalidDataException("Output target IMG is missing.");

        for (int index = 0; index < sourceEntries.Count; index++)
        {
            if (!String.Equals(sourceEntries[index].Path, outputEntries[index].Path, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Output path order changed at entry " + index);
            if (index != targetEntryIndex)
            {
                if (!BytesEqual(sourceEntries[index].Payload, outputEntries[index].Payload))
                    throw new InvalidDataException("Non-target payload changed: " + sourceEntries[index].Path);
                stats.NonTargetPayloadsByteIdentical++;
            }
        }

        List<Album> outputAlbums = NpkCoder.Load(outputFile);
        Album outputTarget = FindTargetAlbum(outputAlbums);
        List<FrameSnapshot> outputFrames = CaptureAndValidateTarget(outputTarget);
        string finalDdsDirectory = Path.Combine(workDirectory, "final-dds");
        Directory.CreateDirectory(finalDdsDirectory);

        for (int frameIndex = 0; frameIndex < outputFrames.Count; frameIndex++)
        {
            FrameSnapshot source = sourceFrames[frameIndex];
            FrameSnapshot output = outputFrames[frameIndex];
            ValidateFrameMetadata(source, output);

            if (source.Placeholder)
            {
                if (!BytesEqual(source.Dds, output.Dds) || !BytesEqual(source.CompressedData, output.CompressedData))
                    throw new InvalidDataException("Placeholder frame changed in output: " + frameIndex);
                continue;
            }

            int changedColorBlocks;
            if (!Bc3AlphaBlocksEqual(source.Dds, output.Dds, out changedColorBlocks))
                throw new InvalidDataException("BC3 alpha block changed in output frame " + frameIndex);
            if (changedColorBlocks == 0)
                throw new InvalidDataException("Visible output frame has no BC3 color change: " + frameIndex);
            if (source.VisibleAlphaPixels != output.VisibleAlphaPixels)
                throw new InvalidDataException("Alpha coverage changed in output frame " + frameIndex);

            string ddsFile = Path.Combine(finalDdsDirectory, "frame-" + frameIndex.ToString("D3") + ".dds");
            File.WriteAllBytes(ddsFile, output.Dds);
            RunTexdiag(texdiagFile, ddsFile, "BC3_UNORM");
        }

        if (stats.NonTargetPayloadsByteIdentical != sourceEntries.Count - 1)
            throw new InvalidDataException("Non-target byte-identical count mismatch.");
    }

    private static void ValidateFrameMetadata(FrameSnapshot source, FrameSnapshot output)
    {
        if (source.Index != output.Index ||
            source.SpriteType != output.SpriteType ||
            source.CompressMode != output.CompressMode ||
            source.Hidden != output.Hidden ||
            source.TargetIndex != output.TargetIndex ||
            source.Width != output.Width ||
            source.Height != output.Height ||
            source.CanvasWidth != output.CanvasWidth ||
            source.CanvasHeight != output.CanvasHeight ||
            source.X != output.X ||
            source.Y != output.Y ||
            source.SpriteLength != output.SpriteLength ||
            !BytesEqual(source.SpriteData, output.SpriteData) ||
            source.TextureIndex != output.TextureIndex ||
            source.TextureWidth != output.TextureWidth ||
            source.TextureHeight != output.TextureHeight ||
            source.TextureFullLength != output.TextureFullLength ||
            source.TextureType != output.TextureType ||
            source.TextureVersion != output.TextureVersion ||
            source.LeftUp != output.LeftUp ||
            source.RightDown != output.RightDown ||
            source.Rotation != output.Rotation ||
            source.Unknown != output.Unknown)
            throw new InvalidDataException("Frame metadata changed: " + source.Index);
    }

    private static void WriteRebuiltNpk(
        string outputFile,
        List<NpkEntry> sourceEntries,
        int targetEntryIndex,
        byte[] modifiedPayload,
        BuildStats stats)
    {
        List<byte[]> payloads = new List<byte[]>();
        for (int index = 0; index < sourceEntries.Count; index++)
            payloads.Add(index == targetEntryIndex ? modifiedPayload : sourceEntries[index].Payload);

        int count = sourceEntries.Count;
        long headerLength = 20L + 264L * count;
        long dataStart = headerLength + 32L;
        long[] outputOffsets = new long[count];
        List<byte[]> uniquePayloads = new List<byte[]>();
        long nextOffset = dataStart;
        for (int index = 0; index < count; index++)
        {
            int sharedWith = FindPreviousSharedPayload(sourceEntries, payloads, targetEntryIndex, index);
            if (sharedWith >= 0)
            {
                outputOffsets[index] = outputOffsets[sharedWith];
                stats.SharedPayloadEntriesReused++;
                continue;
            }

            outputOffsets[index] = nextOffset;
            uniquePayloads.Add(payloads[index]);
            nextOffset += payloads[index].Length;
        }

        using (MemoryStream header = new MemoryStream())
        using (BinaryWriter writer = new BinaryWriter(header, Encoding.ASCII))
        {
            byte[] magic = new byte[16];
            byte[] magicText = Encoding.ASCII.GetBytes("NeoplePack_Bill");
            Buffer.BlockCopy(magicText, 0, magic, 0, magicText.Length);
            writer.Write(magic);
            writer.Write(count);

            for (int index = 0; index < count; index++)
            {
                if (payloads[index].Length <= 0)
                    throw new InvalidDataException("Refusing to write empty NPK payload: " + sourceEntries[index].Path);
                writer.Write(checked((int)outputOffsets[index]));
                writer.Write(payloads[index].Length);
                writer.Write(EncryptPath(sourceEntries[index].Path));
            }

            byte[] headerBytes = header.ToArray();
            if (headerBytes.Length != headerLength)
                throw new InvalidDataException("Internal header length mismatch.");
            int hashInputLength = (int)(headerLength - (headerLength % 17L));
            byte[] headerHash;
            using (SHA256 sha = SHA256.Create())
                headerHash = sha.ComputeHash(headerBytes, 0, hashInputLength);

            using (FileStream output = new FileStream(outputFile, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                output.Write(headerBytes, 0, headerBytes.Length);
                output.Write(headerHash, 0, headerHash.Length);
                for (int index = 0; index < uniquePayloads.Count; index++)
                    output.Write(uniquePayloads[index], 0, uniquePayloads[index].Length);
            }
        }
    }

    private static int FindPreviousSharedPayload(
        List<NpkEntry> sourceEntries,
        List<byte[]> payloads,
        int targetEntryIndex,
        int currentIndex)
    {
        if (currentIndex == targetEntryIndex)
            return -1;
        for (int index = 0; index < currentIndex; index++)
        {
            if (index == targetEntryIndex)
                continue;
            if (sourceEntries[index].Offset == sourceEntries[currentIndex].Offset &&
                sourceEntries[index].Size == sourceEntries[currentIndex].Size &&
                BytesEqual(payloads[index], payloads[currentIndex]))
                return index;
        }
        return -1;
    }

    private static List<NpkEntry> ReadNpkEntries(string file)
    {
        using (FileStream stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read))
        using (BinaryReader reader = new BinaryReader(stream, Encoding.ASCII))
        {
            string magic = Encoding.ASCII.GetString(reader.ReadBytes(16)).TrimEnd('\0');
            if (magic != "NeoplePack_Bill")
                throw new InvalidDataException("Invalid NPK magic: " + magic);
            int count = reader.ReadInt32();
            if (count <= 0)
                throw new InvalidDataException("Invalid NPK entry count: " + count);
            long headerLength = 20L + 264L * count;
            long dataStart = headerLength + 32L;
            if (dataStart > stream.Length)
                throw new InvalidDataException("NPK header exceeds file length.");

            List<NpkEntry> entries = new List<NpkEntry>();
            HashSet<string> paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            for (int index = 0; index < count; index++)
            {
                NpkEntry entry = new NpkEntry();
                entry.Index = index;
                entry.Offset = reader.ReadInt32();
                entry.Size = reader.ReadInt32();
                entry.Path = DecryptPath(reader.ReadBytes(256));
                if (!paths.Add(entry.Path))
                    throw new InvalidDataException("Duplicate NPK path: " + entry.Path);
                if (entry.Offset < dataStart || entry.Size <= 0 || entry.Offset + entry.Size > stream.Length)
                    throw new InvalidDataException("NPK entry is out of bounds: " + entry.Path);
                entries.Add(entry);
            }

            byte[] storedHash = reader.ReadBytes(32);
            if (storedHash.Length != 32)
                throw new InvalidDataException("NPK header hash is truncated.");
            int hashInputLength = (int)(headerLength - (headerLength % 17L));
            stream.Position = 0;
            byte[] hashInput = reader.ReadBytes(hashInputLength);
            byte[] computedHash;
            using (SHA256 sha = SHA256.Create())
                computedHash = sha.ComputeHash(hashInput);
            if (!BytesEqual(storedHash, computedHash))
                throw new InvalidDataException("NPK header hash mismatch.");

            foreach (NpkEntry entry in entries)
            {
                stream.Position = entry.Offset;
                entry.Payload = reader.ReadBytes(entry.Size);
                if (entry.Payload.Length != entry.Size)
                    throw new InvalidDataException("Could not read full payload: " + entry.Path);
                ValidateImgPayload(entry.Payload);
            }
            return entries;
        }
    }

    private static int FindEntryIndex(List<NpkEntry> entries, string path)
    {
        int found = -1;
        for (int index = 0; index < entries.Count; index++)
        {
            if (String.Equals(entries[index].Path, path, StringComparison.OrdinalIgnoreCase))
            {
                if (found >= 0)
                    throw new InvalidDataException("Duplicate NPK path: " + path);
                found = index;
            }
        }
        return found;
    }

    private static byte[] MergeBc3ColorBlocks(byte[] sourceDds, byte[] encodedDds, out int changedBlocks, out int preservedAlphaBlocks)
    {
        DdsInfo sourceInfo = ValidateDds(sourceDds, -1, -1, "DXT5");
        DdsInfo encodedInfo = ValidateDds(encodedDds, sourceInfo.Width, sourceInfo.Height, "DXT5");
        if (sourceInfo.BlockCount != encodedInfo.BlockCount)
            throw new InvalidDataException("BC3 block count changed after encoding.");

        byte[] result = CloneBytes(sourceDds);
        changedBlocks = 0;
        preservedAlphaBlocks = 0;
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
            preservedAlphaBlocks++;
        }
        return result;
    }

    private static bool Bc3AlphaBlocksEqual(byte[] source, byte[] output, out int changedColorBlocks)
    {
        DdsInfo info = ValidateDds(source, -1, -1, "DXT5");
        ValidateDds(output, info.Width, info.Height, "DXT5");
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

    private static DdsInfo ValidateDds(byte[] dds, int expectedWidth, int expectedHeight, string expectedFourCc)
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
        string fourCc = Encoding.ASCII.GetString(dds, 84, 4);
        if (headerSize != 124 || pixelFormatSize != 32)
            throw new InvalidDataException("DDS header size is invalid.");
        if (expectedFourCc != null && fourCc != expectedFourCc)
            throw new InvalidDataException("DDS FourCC mismatch: " + fourCc + "/" + expectedFourCc);
        if (width < 1 || height < 1 || (mipLevels != 0 && mipLevels != 1))
            throw new InvalidDataException("DDS dimensions or mip count are invalid.");
        if (expectedWidth > 0 && width != expectedWidth)
            throw new InvalidDataException("DDS width changed: " + width + "/" + expectedWidth);
        if (expectedHeight > 0 && height != expectedHeight)
            throw new InvalidDataException("DDS height changed: " + height + "/" + expectedHeight);

        int blockBytes;
        if (fourCc == "DXT1")
            blockBytes = 8;
        else if (fourCc == "DXT3" || fourCc == "DXT5")
            blockBytes = 16;
        else
            throw new InvalidDataException("Unsupported DDS FourCC: " + fourCc);

        int blocksWide = (width + 3) / 4;
        int blocksHigh = (height + 3) / 4;
        int blockCount = checked(blocksWide * blocksHigh);
        int dataOffset = 4 + headerSize;
        int requiredLength = checked(dataOffset + blockCount * blockBytes);
        if (dds.Length != requiredLength)
            throw new InvalidDataException("DDS block length is invalid: " + dds.Length + "/" + requiredLength);

        DdsInfo result = new DdsInfo();
        result.Width = width;
        result.Height = height;
        result.DataOffset = dataOffset;
        result.BlockCount = blockCount;
        result.BlockBytes = blockBytes;
        result.FourCc = fourCc;
        return result;
    }

    private static int CountVisibleAlphaPixels(byte[] dds, DdsInfo info)
    {
        if (info.FourCc != "DXT5")
            throw new InvalidDataException("Alpha count only supports DXT5 in this builder.");
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

    private static Dictionary<int, TextureInfo> GetTextureMap(Album album)
    {
        FieldInfo mapField = album.Handler.GetType().GetField("_map", BindingFlags.Instance | BindingFlags.NonPublic);
        if (mapField == null)
            throw new InvalidDataException("Ver5 texture map field is unavailable.");
        Dictionary<int, TextureInfo> map = mapField.GetValue(album.Handler) as Dictionary<int, TextureInfo>;
        if (map == null)
            throw new InvalidDataException("Ver5 texture map is unavailable.");
        return map;
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

    private static void RunTexdiag(string texdiagFile, string ddsFile, string expectedFormat)
    {
        string output = RunProcess(texdiagFile, "info -nologo -- " + QuoteArgument(ddsFile));
        if (output.IndexOf("format = " + expectedFormat, StringComparison.OrdinalIgnoreCase) < 0 ||
            output.IndexOf("mipLevels = 1", StringComparison.OrdinalIgnoreCase) < 0)
            throw new InvalidDataException("texdiag did not confirm " + expectedFormat + " single-mip DDS: " + ddsFile);
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

    private static byte[] EncryptPath(string path)
    {
        byte[] plain = new byte[256];
        byte[] pathBytes = Encoding.ASCII.GetBytes(path);
        if (pathBytes.Length >= 256)
            throw new InvalidDataException("NPK path is too long: " + path);
        Buffer.BlockCopy(pathBytes, 0, plain, 0, pathBytes.Length);

        byte[] key = GetNameKey();
        byte[] encrypted = new byte[256];
        for (int index = 0; index < encrypted.Length; index++)
            encrypted[index] = (byte)(plain[index] ^ key[index]);
        return encrypted;
    }

    private static string DecryptPath(byte[] encrypted)
    {
        if (encrypted == null || encrypted.Length != 256)
            throw new InvalidDataException("Encrypted NPK path has invalid length.");
        byte[] key = GetNameKey();
        byte[] plain = new byte[256];
        for (int index = 0; index < plain.Length; index++)
            plain[index] = (byte)(encrypted[index] ^ key[index]);
        int nullIndex = Array.IndexOf<byte>(plain, 0);
        if (nullIndex < 0)
            throw new InvalidDataException("NPK path is not null terminated.");
        return Encoding.ASCII.GetString(plain, 0, nullIndex);
    }

    private static byte[] GetNameKey()
    {
        string keyText = "puchikon@neople dungeon and fighter " + Repeat("DNF", 73) + "\0";
        byte[] key = Encoding.ASCII.GetBytes(keyText);
        if (key.Length != 256)
            throw new InvalidDataException("Unexpected NPK filename key length: " + key.Length);
        return key;
    }

    private static string Repeat(string value, int count)
    {
        StringBuilder builder = new StringBuilder(value.Length * count);
        for (int index = 0; index < count; index++)
            builder.Append(value);
        return builder.ToString();
    }

    private static string ReadNullTerminatedAscii(byte[] data, int offset, int maxLength)
    {
        int end = offset;
        int limit = Math.Min(data.Length, offset + maxLength);
        while (end < limit && data[end] != 0)
            end++;
        if (end == limit)
            throw new InvalidDataException("ASCII field is not null terminated.");
        return Encoding.ASCII.GetString(data, offset, end - offset);
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

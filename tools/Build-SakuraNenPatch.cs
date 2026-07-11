using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using ExtractorSharp.Core.Coder;
using ExtractorSharp.Core.Lib;
using ExtractorSharp.Core.Model;

internal static class BuildSakuraNenPatch
{
    private static readonly string[] SkillPacks =
    {
        "doublelightningdragon",
        "energyball",
        "energyfield",
        "illusionbomb",
        "inhaledenergyshot",
        "inhaledenergyshot_absorbenergyball",
        "instilwilltonen",
        "lightdragonthirteen",
        "lightningdragon",
        "mininenguard",
        "nencharge",
        "nenflower",
        "nenguard",
        "nenguardex",
        "nenmonster_whitetiger",
        "nenofbrilliance",
        "nenprison",
        "nenshield",
        "roarstun",
        "roarstunex",
        "saintillusion",
        "skythunderstep",
        "spiraldragonwave",
        "thunderrush"
    };

    private static readonly HashSet<string> CommonEffectPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "sprite/character/fighter/effect/energyball.img",
        "sprite/character/fighter/effect/energyballshoot.img",
        "sprite/character/fighter/effect/energycharge.img",
        "sprite/character/fighter/effect/energyfield.img",
        "sprite/character/fighter/effect/gang.img",
        "sprite/character/fighter/effect/gangcast.img",
        "sprite/character/fighter/effect/illusion1.img",
        "sprite/character/fighter/effect/illusion2.img",
        "sprite/character/fighter/effect/illusion3.img",
        "sprite/character/fighter/effect/illusion4.img",
        "sprite/character/fighter/effect/illusionbombeffect.img",
        "sprite/character/fighter/effect/nenguard.img",
        "sprite/character/fighter/effect/nenguardeffect.img",
        "sprite/character/fighter/effect/nenmaster.img",
        "sprite/character/fighter/effect/roarstun.img",
        "sprite/character/fighter/effect/roarstunfloor.img",
        "sprite/character/fighter/effect/spiralnen.img"
    };

    private static readonly HashSet<string> CharacterAlbumPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "sprite/character/fighter/effect/doublelightningdragon/awakebody_nenmaster_0000.img"
    };

    private static readonly HashSet<string> SecondFixCharacterAlbums = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "awakebody_nenmaster_0000.img",
        "character.img",
        "characteraction.img"
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

    private sealed class SpriteExpectation
    {
        public ColorBits Type;
        public int Width;
        public int Height;
        public int X;
        public int Y;
        public int CanvasWidth;
        public int CanvasHeight;
        public ColorBits ExpectedOutputType;
        public bool VisibilityKnown;
        public bool WasVisible;
        public int AlphaPixelCount;
        public bool WasReplaced;
    }

    private static readonly PaletteStop[] SakuraPalette =
    {
        new PaletteStop(0.00, Color.FromArgb(0x00, 0x00, 0x00)),
        new PaletteStop(0.15, Color.FromArgb(0x3A, 0x0D, 0x25)),
        new PaletteStop(0.45, Color.FromArgb(0xC4, 0x3F, 0x73)),
        new PaletteStop(0.75, Color.FromArgb(0xFF, 0xB7, 0xC5)),
        new PaletteStop(1.00, Color.FromArgb(0xFF, 0xF5, 0xF8))
    };

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
        string sourceArgument = Environment.GetEnvironmentVariable("SAKURA_IMAGEPACKS2");
        string outputArgument = Environment.GetEnvironmentVariable("SAKURA_OUTPUT");
        if (String.IsNullOrEmpty(sourceArgument) || String.IsNullOrEmpty(outputArgument))
        {
            if (args.Length != 2)
            {
                Console.Error.WriteLine("Set SAKURA_IMAGEPACKS2 and SAKURA_OUTPUT, or pass <ImagePacks2> <output.npk>.");
                return 2;
            }
            sourceArgument = args[0];
            outputArgument = args[1];
        }

        if (String.IsNullOrEmpty(sourceArgument) || String.IsNullOrEmpty(outputArgument))
            return 2;

        PrintInvalidPathCharacters("Source", sourceArgument);
        PrintInvalidPathCharacters("Output", outputArgument);

        string sourceDirectory = Path.GetFullPath(sourceArgument);
        string outputFile = Path.GetFullPath(outputArgument);
        bool exactSecondFix = String.Equals(
            Environment.GetEnvironmentVariable("SAKURA_EXACT_SECOND_FIX"),
            "1",
            StringComparison.Ordinal);
        if (!Directory.Exists(sourceDirectory))
        {
            Console.Error.WriteLine("ImagePacks2 was not found: " + sourceDirectory);
            return 2;
        }

        string outputDirectory = Path.GetDirectoryName(outputFile);
        if (!String.IsNullOrEmpty(outputDirectory))
            Directory.CreateDirectory(outputDirectory);

        List<Album> outputAlbums = new List<Album>();
        HashSet<string> outputPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, SpriteExpectation> spriteExpectations = new Dictionary<string, SpriteExpectation>(StringComparer.OrdinalIgnoreCase);
        int changedSprites = 0;
        int repairedDdsSprites = 0;
        int skippedSprites = 0;
        int skippedCharacterAlbums = 0;

        string commonPack = Path.Combine(sourceDirectory, "sprite_character_fighter_effect.NPK");
        AddPack(commonPack, outputAlbums, outputPaths, spriteExpectations, ref changedSprites, ref repairedDdsSprites, ref skippedSprites, ref skippedCharacterAlbums, true, exactSecondFix);

        foreach (string skill in SkillPacks)
        {
            string file = Path.Combine(sourceDirectory, "sprite_character_fighter_effect_" + skill + ".NPK");
            AddPack(file, outputAlbums, outputPaths, spriteExpectations, ref changedSprites, ref repairedDdsSprites, ref skippedSprites, ref skippedCharacterAlbums, false, exactSecondFix);
        }

        if (outputAlbums.Count == 0 || changedSprites == 0)
            throw new InvalidOperationException("No skill images were selected or recolored.");
        if (skippedSprites != 0)
            throw new InvalidOperationException("Full-skill build failed because " + skippedSprites + " sprites could not be decoded.");

        string temporaryFile = outputFile + ".tmp";
        if (File.Exists(temporaryFile))
            File.Delete(temporaryFile);

        NpkCoder.Save(temporaryFile, outputAlbums);
        Validate(temporaryFile, outputAlbums.Count, spriteExpectations);

        if (File.Exists(outputFile))
            File.Delete(outputFile);
        File.Move(temporaryFile, outputFile);

        Console.WriteLine("Output=" + outputFile);
        Console.WriteLine("Albums=" + outputAlbums.Count);
        Console.WriteLine("RecoloredSprites=" + changedSprites);
        Console.WriteLine("BoundarySafeDdsSprites=" + repairedDdsSprites);
        Console.WriteLine("UndecodableSpritesKeptOriginal=" + skippedSprites);
        Console.WriteLine("SkippedCharacterAlbums=" + skippedCharacterAlbums);
        Console.WriteLine("BuildMode=" + (exactSecondFix ? "ExactSecondFix" : "OptimizedSecondFix"));
        Console.WriteLine("Palette=#000000,#3A0D25,#C43F73,#FFB7C5,#FFF5F8");
        return 0;
    }

    private static void AddPack(
        string file,
        List<Album> outputAlbums,
        HashSet<string> outputPaths,
        Dictionary<string, SpriteExpectation> spriteExpectations,
        ref int changedSprites,
        ref int repairedDdsSprites,
        ref int skippedSprites,
        ref int skippedCharacterAlbums,
        bool commonPack,
        bool exactSecondFix)
    {
        if (!File.Exists(file))
            throw new FileNotFoundException("Required skill pack was not found.", file);

        List<Album> albums = NpkCoder.Load(file);
        Console.WriteLine("Loading " + Path.GetFileName(file) + " (" + albums.Count + " IMG files)");

        foreach (Album album in albums)
        {
            if (commonPack && !CommonEffectPaths.Contains(album.Path))
                continue;
            bool skipCharacterAlbum = exactSecondFix
                ? SecondFixCharacterAlbums.Contains(album.Name) || album.Name.StartsWith("awakebody_", StringComparison.OrdinalIgnoreCase)
                : CharacterAlbumPaths.Contains(album.Path);
            if (skipCharacterAlbum)
            {
                skippedCharacterAlbums++;
                continue;
            }
            if (!outputPaths.Add(album.Path))
                throw new InvalidDataException("Duplicate IMG path: " + album.Path);

            List<Bitmap> replacementPictures = new List<Bitmap>();
            foreach (Sprite sprite in album.List)
            {
                if (sprite.Type == ColorBits.LINK)
                    continue;

                ColorBits originalType = sprite.Type;
                string spriteKey = BuildSpriteKey(album.Path, sprite.Index);
                SpriteExpectation expectation = new SpriteExpectation
                {
                    Type = originalType,
                    Width = sprite.Width,
                    Height = sprite.Height,
                    X = sprite.X,
                    Y = sprite.Y,
                    CanvasWidth = sprite.CanvasWidth,
                    CanvasHeight = sprite.CanvasHeight,
                    ExpectedOutputType = originalType
                };
                if (spriteExpectations.ContainsKey(spriteKey))
                    throw new InvalidDataException("Duplicate sprite key: " + spriteKey);
                spriteExpectations.Add(spriteKey, expectation);

                if (sprite.Hidden)
                {
                    expectation.VisibilityKnown = true;
                    expectation.WasVisible = false;
                    expectation.AlphaPixelCount = 0;
                    continue;
                }

                Bitmap picture = null;
                Exception decodeException = null;
                bool usedFallback = false;
                try
                {
                    picture = sprite.Picture;
                }
                catch (Exception exception)
                {
                    decodeException = exception;
                }

                if (picture == null)
                {
                    string fallbackReason;
                    if (TryDecodeDds(album, sprite, out picture, out fallbackReason))
                    {
                        usedFallback = true;
                    }
                    else
                    {
                        skippedSprites++;
                        string exceptionName = decodeException == null ? "NullPicture" : decodeException.GetType().Name;
                        Console.WriteLine("Keeping original undecodable sprite: " + spriteKey + " (" + exceptionName + ", " + fallbackReason + ")");
                        continue;
                    }
                }

                try
                {
                    bool sourceVisible;
                    int sourceAlphaPixels;
                    Bitmap recolored = Recolor(picture, out sourceVisible, out sourceAlphaPixels);
                    expectation.VisibilityKnown = true;
                    expectation.WasVisible = sourceVisible;
                    expectation.AlphaPixelCount = sourceAlphaPixels;
                    try
                    {
                        ReplaceSprite(sprite, recolored);
                    }
                    catch
                    {
                        recolored.Dispose();
                        throw;
                    }
                    replacementPictures.Add(recolored);
                    expectation.WasReplaced = true;
                    expectation.ExpectedOutputType = ColorBits.ARGB_8888;
                    changedSprites++;
                    if (usedFallback)
                        repairedDdsSprites++;
                }
                finally
                {
                    picture.Dispose();
                    if (!expectation.WasReplaced)
                        sprite.Picture = null;
                }
            }

            try
            {
                album.Adjust();
                album.Refresh();
            }
            finally
            {
                foreach (Bitmap replacementPicture in replacementPictures)
                    replacementPicture.Dispose();
            }
            outputAlbums.Add(album);
        }
    }

    private static Bitmap Recolor(Bitmap source, out bool sourceVisible, out int sourceAlphaPixels)
    {
        byte[] pixels = source.ToArray();
        sourceVisible = false;
        sourceAlphaPixels = 0;
        for (int i = 0; i < pixels.Length; i += 4)
        {
            byte alpha = pixels[i + 3];
            if (alpha == 0)
                continue;

            sourceAlphaPixels++;

            int blue = pixels[i];
            int green = pixels[i + 1];
            int red = pixels[i + 2];
            if (red != 0 || green != 0 || blue != 0)
                sourceVisible = true;
            double intensity = Math.Max(red, Math.Max(green, blue)) / 255.0;
            Color mapped = MapPalette(intensity);
            pixels[i] = mapped.B;
            pixels[i + 1] = mapped.G;
            pixels[i + 2] = mapped.R;
            pixels[i + 3] = alpha;
        }
        return Bitmaps.FromArray(pixels, source.Size);
    }

    private static void ReplaceSprite(Sprite sprite, Bitmap picture)
    {
        sprite.ReplaceImage(ColorBits.ARGB_8888, false, picture);
    }

    private static string BuildSpriteKey(string albumPath, int spriteIndex)
    {
        return albumPath + "#" + spriteIndex;
    }

    private static ColorBits ExpectedTextureType(ColorBits spriteType)
    {
        int value = (int)spriteType;
        if (value > (int)ColorBits.LINK)
            return (ColorBits)(value - 4);
        return spriteType;
    }

    private static bool TryDecodeDds(Album album, Sprite sprite, out Bitmap result, out string reason)
    {
        result = null;
        reason = "unknown";
        if (sprite.Type != ColorBits.DXT_1 && sprite.Type != ColorBits.DXT_3 && sprite.Type != ColorBits.DXT_5)
        {
            reason = "not a DXT texture";
            return false;
        }

        FieldInfo mapField = album.Handler.GetType().GetField("_map", BindingFlags.Instance | BindingFlags.NonPublic);
        if (mapField == null)
        {
            reason = "texture map unavailable";
            return false;
        }
        Dictionary<int, TextureInfo> map = mapField.GetValue(album.Handler) as Dictionary<int, TextureInfo>;
        TextureInfo info;
        if (map == null || !map.TryGetValue(sprite.Index, out info) || info.Texture == null)
        {
            reason = "texture metadata unavailable";
            return false;
        }

        Texture texture = info.Texture;
        byte[] dds = Zlib.Decompress(texture.Data, texture.FullLength);
        if (dds == null || dds.Length < 128)
        {
            reason = "DDS data too short";
            return false;
        }

        int magic = BitConverter.ToInt32(dds, 0);
        int headerSize = BitConverter.ToInt32(dds, 4);
        int height = BitConverter.ToInt32(dds, 12);
        int width = BitConverter.ToInt32(dds, 16);
        int fourCc = BitConverter.ToInt32(dds, 84);
        bool isDxt1 = fourCc == 0x31545844;
        bool isDxt3 = fourCc == 0x33545844;
        bool isDxt5 = fourCc == 0x35545844;
        if (magic != 0x20534444 || headerSize < 124 || (!isDxt1 && !isDxt3 && !isDxt5) || width < 1 || height < 1)
        {
            reason = "invalid DDS header";
            return false;
        }

        int dataOffset = 4 + headerSize;
        int blocksWide = (width + 3) / 4;
        int blocksHigh = (height + 3) / 4;
        int blockSize = isDxt1 ? 8 : 16;
        int requiredLength = dataOffset + blocksWide * blocksHigh * blockSize;
        if (requiredLength > dds.Length)
        {
            reason = "DDS blocks truncated " + requiredLength + "/" + dds.Length;
            return false;
        }

        byte[] pixels = new byte[width * height * 4];
        int offset = dataOffset;
        for (int blockY = 0; blockY < blocksHigh; blockY++)
        {
            for (int blockX = 0; blockX < blocksWide; blockX++)
            {
                byte[][] colors;
                byte[] alpha = null;
                uint indices;
                if (isDxt1)
                {
                    ushort color0 = BitConverter.ToUInt16(dds, offset);
                    ushort color1 = BitConverter.ToUInt16(dds, offset + 2);
                    indices = BitConverter.ToUInt32(dds, offset + 4);
                    colors = BuildDxt1Colors(color0, color1);
                }
                else if (isDxt3)
                {
                    alpha = new byte[16];
                    ulong alphaBits = BitConverter.ToUInt64(dds, offset);
                    for (int pixel = 0; pixel < 16; pixel++)
                        alpha[pixel] = (byte)(((alphaBits >> (pixel * 4)) & 0xF) * 17);
                    ushort color0 = BitConverter.ToUInt16(dds, offset + 8);
                    ushort color1 = BitConverter.ToUInt16(dds, offset + 10);
                    indices = BitConverter.ToUInt32(dds, offset + 12);
                    colors = BuildOpaqueDxtColors(color0, color1);
                }
                else
                {
                    alpha = DecodeDxt5Alpha(dds, offset);
                    ushort color0 = BitConverter.ToUInt16(dds, offset + 8);
                    ushort color1 = BitConverter.ToUInt16(dds, offset + 10);
                    indices = BitConverter.ToUInt32(dds, offset + 12);
                    colors = BuildOpaqueDxtColors(color0, color1);
                }
                offset += blockSize;

                for (int pixel = 0; pixel < 16; pixel++)
                {
                    int x = blockX * 4 + (pixel % 4);
                    int y = blockY * 4 + (pixel / 4);
                    int colorIndex = (int)(indices & 3);
                    indices >>= 2;
                    if (x >= width || y >= height)
                        continue;

                    int destination = (y * width + x) * 4;
                    pixels[destination] = colors[colorIndex][0];
                    pixels[destination + 1] = colors[colorIndex][1];
                    pixels[destination + 2] = colors[colorIndex][2];
                    pixels[destination + 3] = alpha == null ? colors[colorIndex][3] : alpha[pixel];
                }
            }
        }

        using (Bitmap textureBitmap = Bitmaps.FromArray(pixels, new Size(width, height)))
        {
            Rectangle rectangle = info.Rectangle;
            if (rectangle.X < 0 || rectangle.Y < 0 || rectangle.Right > width || rectangle.Bottom > height)
            {
                reason = "crop " + rectangle + " outside DDS " + width + "x" + height + ", texture " + texture.Width + "x" + texture.Height + ", top " + info.Top;
                return false;
            }
            result = textureBitmap.Clone(rectangle, PixelFormat.Format32bppArgb);
        }
        if (info.Top != 0)
            result.RotateFlip(RotateFlipType.Rotate270FlipNone);
        reason = "ok";
        return true;
    }

    private static byte[][] BuildDxt1Colors(ushort color0, ushort color1)
    {
        byte[][] colors =
        {
            DecodeRgb565(color0),
            DecodeRgb565(color1),
            new byte[4],
            new byte[4]
        };
        if (color0 > color1)
        {
            for (int channel = 0; channel < 3; channel++)
            {
                colors[2][channel] = (byte)((colors[0][channel] * 2 + colors[1][channel]) / 3);
                colors[3][channel] = (byte)((colors[0][channel] + colors[1][channel] * 2) / 3);
            }
            colors[2][3] = 255;
            colors[3][3] = 255;
        }
        else
        {
            for (int channel = 0; channel < 3; channel++)
                colors[2][channel] = (byte)((colors[0][channel] + colors[1][channel]) / 2);
            colors[2][3] = 255;
            colors[3][3] = 0;
        }
        return colors;
    }

    private static byte[][] BuildOpaqueDxtColors(ushort color0, ushort color1)
    {
        byte[][] colors =
        {
            DecodeRgb565(color0),
            DecodeRgb565(color1),
            new byte[4],
            new byte[4]
        };
        for (int channel = 0; channel < 3; channel++)
        {
            colors[2][channel] = (byte)((colors[0][channel] * 2 + colors[1][channel]) / 3);
            colors[3][channel] = (byte)((colors[0][channel] + colors[1][channel] * 2) / 3);
        }
        colors[2][3] = 255;
        colors[3][3] = 255;
        return colors;
    }

    private static byte[] DecodeDxt5Alpha(byte[] data, int offset)
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

    private static byte[] DecodeRgb565(ushort color)
    {
        int blue = color & 0x1F;
        int green = (color >> 5) & 0x3F;
        int red = (color >> 11) & 0x1F;
        return new byte[]
        {
            (byte)((blue << 3) | (blue >> 2)),
            (byte)((green << 2) | (green >> 4)),
            (byte)((red << 3) | (red >> 2)),
            255
        };
    }

    private static Color MapPalette(double intensity)
    {
        for (int i = 1; i < SakuraPalette.Length; i++)
        {
            PaletteStop right = SakuraPalette[i];
            if (intensity <= right.Position)
            {
                PaletteStop left = SakuraPalette[i - 1];
                double span = right.Position - left.Position;
                double amount = span <= 0 ? 0 : (intensity - left.Position) / span;
                return Color.FromArgb(
                    Lerp(left.Color.R, right.Color.R, amount),
                    Lerp(left.Color.G, right.Color.G, amount),
                    Lerp(left.Color.B, right.Color.B, amount));
            }
        }
        return SakuraPalette[SakuraPalette.Length - 1].Color;
    }

    private static int Lerp(int from, int to, double amount)
    {
        return (int)Math.Round(from + (to - from) * amount);
    }

    private static void PrintInvalidPathCharacters(string label, string path)
    {
        char[] invalid = Path.GetInvalidPathChars();
        for (int i = 0; i < path.Length; i++)
        {
            if (Array.IndexOf(invalid, path[i]) >= 0)
                Console.Error.WriteLine(label + "InvalidCharIndex=" + i + ",U+" + ((int)path[i]).ToString("X4"));
        }
    }

    private static void Validate(string file, int expectedAlbumCount, Dictionary<string, SpriteExpectation> spriteExpectations)
    {
        using (FileStream stream = File.OpenRead(file))
        {
            List<Album> albums = NpkCoder.ReadInfo(stream);
            if (albums.Count != expectedAlbumCount)
                throw new InvalidDataException("Validation failed: output IMG count mismatch.");

            HashSet<string> paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (Album album in albums)
            {
                if (!paths.Add(album.Path))
                    throw new InvalidDataException("Validation failed: duplicate output path " + album.Path);
            }
        }

        List<Album> decodedAlbums = NpkCoder.Load(file);
        if (decodedAlbums.Count != expectedAlbumCount)
            throw new InvalidDataException("Validation failed: decoded IMG count mismatch.");

        int decodedSprites = 0;
        long visiblePixels = 0;
        long nonSakuraPixels = 0;
        int fullyTransparentSprites = 0;
        int unexpectedlyTransparentSprites = 0;
        string firstFullyTransparentSprite = null;
        string firstUnexpectedlyTransparentSprite = null;
        string firstNonSakuraPixel = null;
        foreach (Album album in decodedAlbums)
        {
            FieldInfo mapField = album.Handler.GetType().GetField("_map", BindingFlags.Instance | BindingFlags.NonPublic);
            Dictionary<int, TextureInfo> textureMap = mapField == null
                ? null
                : mapField.GetValue(album.Handler) as Dictionary<int, TextureInfo>;
            foreach (Sprite sprite in album.List)
            {
                if (sprite.Type == ColorBits.LINK)
                    continue;

                string spriteKey = BuildSpriteKey(album.Path, sprite.Index);
                SpriteExpectation expectation;
                if (!spriteExpectations.TryGetValue(spriteKey, out expectation))
                    throw new InvalidDataException("Validation failed: unexpected sprite " + spriteKey);
                if (sprite.Type != expectation.ExpectedOutputType)
                    throw new InvalidDataException("Validation failed: unexpected sprite format " + spriteKey + " (" + sprite.Type + ", expected " + expectation.ExpectedOutputType + ")");
                if (sprite.Width != expectation.Width || sprite.Height != expectation.Height ||
                    sprite.X != expectation.X || sprite.Y != expectation.Y ||
                    sprite.CanvasWidth != expectation.CanvasWidth || sprite.CanvasHeight != expectation.CanvasHeight)
                    throw new InvalidDataException("Validation failed: sprite geometry changed " + spriteKey);
                if (sprite.Hidden)
                {
                    fullyTransparentSprites++;
                    if (firstFullyTransparentSprite == null)
                        firstFullyTransparentSprite = spriteKey;
                    if (expectation.VisibilityKnown && expectation.AlphaPixelCount != 0)
                    {
                        unexpectedlyTransparentSprites++;
                        if (firstUnexpectedlyTransparentSprite == null)
                            firstUnexpectedlyTransparentSprite = spriteKey;
                    }
                    decodedSprites++;
                    continue;
                }
                if (textureMap != null)
                {
                    TextureInfo textureInfo;
                    if (!textureMap.TryGetValue(sprite.Index, out textureInfo) || textureInfo.Texture == null)
                        throw new InvalidDataException("Validation failed: missing texture " + spriteKey);
                    if (textureInfo.Texture.Type != expectation.ExpectedOutputType)
                        throw new InvalidDataException("Validation failed: sprite/texture format mismatch " + spriteKey);
                }
                Bitmap picture = null;
                Exception decodeException = null;
                try
                {
                    picture = sprite.Picture;
                }
                catch (Exception exception)
                {
                    decodeException = exception;
                }
                if (picture == null)
                {
                    string fallbackReason;
                    if (!TryDecodeDds(album, sprite, out picture, out fallbackReason))
                    {
                        string exceptionName = decodeException == null ? "NullPicture" : decodeException.GetType().Name;
                        throw new InvalidDataException("Validation failed: undecodable sprite " + spriteKey + " (" + exceptionName + ", " + fallbackReason + ")", decodeException);
                    }
                }
                try
                {
                    byte[] pixels = picture.ToArray();
                    int spriteAlphaPixels = 0;
                    for (int i = 0; i < pixels.Length; i += 4)
                    {
                        if (pixels[i + 3] == 0)
                            continue;
                        spriteAlphaPixels++;
                        visiblePixels++;
                        int blue = pixels[i];
                        int green = pixels[i + 1];
                        int red = pixels[i + 2];
                        int channelTolerance = Math.Max(2, 255 / pixels[i + 3] + 2);
                        if (pixels[i + 3] >= 64 && (red + channelTolerance < green || red + channelTolerance < blue))
                        {
                            nonSakuraPixels++;
                            if (firstNonSakuraPixel == null)
                                firstNonSakuraPixel = album.Path + "#" + sprite.Index + " BGRA=" + blue + "," + green + "," + red + "," + pixels[i + 3];
                        }
                    }
                    if (expectation.VisibilityKnown && expectation.AlphaPixelCount == 0 && spriteAlphaPixels != 0)
                        throw new InvalidDataException("Validation failed: transparent source sprite became visible " + spriteKey);
                    if (spriteAlphaPixels == 0)
                    {
                        fullyTransparentSprites++;
                        if (firstFullyTransparentSprite == null)
                            firstFullyTransparentSprite = spriteKey;
                        if (expectation.VisibilityKnown && expectation.AlphaPixelCount != 0)
                        {
                            unexpectedlyTransparentSprites++;
                            if (firstUnexpectedlyTransparentSprite == null)
                                firstUnexpectedlyTransparentSprite = spriteKey;
                        }
                    }
                }
                finally
                {
                    picture.Dispose();
                    sprite.Picture = null;
                }
                decodedSprites++;
            }
        }
        if (decodedSprites != spriteExpectations.Count)
            throw new InvalidDataException("Validation failed: output sprite count mismatch " + decodedSprites + "/" + spriteExpectations.Count);
        if (unexpectedlyTransparentSprites != 0)
            throw new InvalidDataException("Validation failed: output contains " + unexpectedlyTransparentSprites + " unexpectedly transparent sprites; first=" + firstUnexpectedlyTransparentSprite);
        if (nonSakuraPixels != 0)
            throw new InvalidDataException("Validation failed: output contains " + nonSakuraPixels + " non-sakura visible pixels; first=" + firstNonSakuraPixel);
        Console.WriteLine("ValidatedSprites=" + decodedSprites);
        Console.WriteLine("ValidatedVisiblePixels=" + visiblePixels);
        Console.WriteLine("FullyTransparentSprites=" + fullyTransparentSprites);
        Console.WriteLine("UnexpectedlyTransparentSprites=" + unexpectedlyTransparentSprites);
        if (firstFullyTransparentSprite != null)
            Console.WriteLine("FirstFullyTransparentSprite=" + firstFullyTransparentSprite);
        Console.WriteLine("NonSakuraVisiblePixels=" + nonSakuraPixels);
    }
}

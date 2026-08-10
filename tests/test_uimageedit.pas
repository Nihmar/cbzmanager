unit test_uimageedit;
{$mode objfpc}{$h+}

{ Tests for the page-editor image operations (uimageedit.pas) and the
  encode helpers of uimgutil.pas (EncodeIntfImage / EncodeExtFor). }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils, IntfGraphics, FPImage, GraphType, uimageedit, uimgutil;

type
  TImageEditTest = class(TTestCase)
  private
    { Creates a W x H solid-colour BGRA32 image (alpha 255). }
    function MakeSolid(W, H: integer; R, G, B: byte): TLazIntfImage;
    { Creates a W x H BGRA32 image where every pixel's grey value equals its
      row index (clamped to 255). }
    function MakeRowGradient(W, H: integer): TLazIntfImage;
    { Reads the RGB bytes of a BGRA32 image pixel. }
    procedure PixelRGB(Img: TLazIntfImage; X, Y: integer;
      out R, G, B: byte);
    { Asserts that A and B differ by at most ATol. }
    procedure AssertNear(AMsg: string; A, B, ATol: integer);
    { Decodes Stream with the reader for Ext into a TLazIntfImage. }
    function DecodeStream(Stream: TMemoryStream; const Ext: string): TLazIntfImage;
  published
    { AdjustColors }
    procedure TestColors_Identity;
    procedure TestColors_Brightness;
    procedure TestColors_Contrast;
    procedure TestColors_SaturationZeroGivesGray;
    procedure TestColors_Invert;
    procedure TestColors_Gamma;
    procedure TestColors_Grayscale;
    procedure TestColors_Sepia;
    procedure TestColors_RedGain;
    procedure TestColors_AlphaPreserved;
    { Resample }
    procedure TestResample_Downscale;
    procedure TestResample_Upscale;
    procedure TestResample_InvalidInput;
    { Split }
    procedure TestSplit_HorizontalHalf;
    procedure TestSplit_VerticalQuarter;
    procedure TestSplit_MultipleLines;
    procedure TestSplit_DedupeAndClamp;
    procedure TestSplit_InvalidInput;
    { Encode }
    procedure TestEncode_PngRoundTrip;
    procedure TestEncode_JpegRoundTrip;
    procedure TestEncode_BmpRoundTrip;
    procedure TestEncode_WebpRoundTrip;
    procedure TestEncode_UnsupportedExt;
    procedure TestEncodeExtFor;
  end;

implementation

uses
  uwebp;

{ Builds a solid-colour image through the canonical LCL idiom. }
function TImageEditTest.MakeSolid(W, H: integer; R, G, B: byte): TLazIntfImage;
var
  Desc: TRawImageDescription;
  x, y: integer;
  C: TFPColor;
begin
  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(W, H);
  Result := TLazIntfImage.Create(0, 0);
  Result.DataDescription := Desc;
  C.Red := R * 256;
  C.Green := G * 256;
  C.Blue := B * 256;
  C.Alpha := 65535;
  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
      Result.Colors[x, y] := C;
end;

{ Builds a BGRA32 image whose pixels carry the row index as grey value. }
function TImageEditTest.MakeRowGradient(W, H: integer): TLazIntfImage;
var
  Desc: TRawImageDescription;
  x, y: integer;
  C: TFPColor;
begin
  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(W, H);
  Result := TLazIntfImage.Create(0, 0);
  Result.DataDescription := Desc;
  C.Alpha := 65535;
  for y := 0 to H - 1 do
  begin
    C.Red := y * 256;
    C.Green := y * 256;
    C.Blue := y * 256;
    for x := 0 to W - 1 do
      Result.Colors[x, y] := C;
  end;
end;

procedure TImageEditTest.PixelRGB(Img: TLazIntfImage; X, Y: integer;
  out R, G, B: byte);
var
  P: pbyte;
begin
  P := Img.GetDataLineStart(Y);
  Inc(P, X * 4);
  B := P[0];
  G := P[1];
  R := P[2];
end;

procedure TImageEditTest.AssertNear(AMsg: string; A, B, ATol: integer);
begin
  AssertTrue(AMsg + Format(' (%d vs %d)', [A, B]), Abs(A - B) <= ATol);
end;

function TImageEditTest.DecodeStream(Stream: TMemoryStream;
  const Ext: string): TLazIntfImage;
begin
  if SameText(Ext, '.webp') then
    Result := WebPToIntfImage(Stream.Memory, Stream.Size)
  else
    Result := StreamToIntfImage(Stream, ReaderClassForExt(Ext));
end;

{ --- AdjustColors ---------------------------------------------------------- }

procedure TImageEditTest.TestColors_Identity;
var
  Img, Out: TLazIntfImage;
  R, G, B: byte;
begin
  Img := MakeSolid(2, 2, 120, 90, 60);
  try
    Out := AdjustColors(Img, NeutralColorAdjust);
    try
      AssertNotNull('result', Out);
      PixelRGB(Out, 0, 0, R, G, B);
      AssertEquals('R', 120, R);
      AssertEquals('G', 90, G);
      AssertEquals('B', 60, B);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_Brightness;
var
  Img, Out: TLazIntfImage;
  Adj: TColorAdjust;
  R, G, B: byte;
begin
  Img := MakeSolid(1, 1, 100, 100, 100);
  try
    Adj := NeutralColorAdjust;
    Adj.Brightness := 100;
    Out := AdjustColors(Img, Adj);
    try
      PixelRGB(Out, 0, 0, R, G, B);
      AssertEquals('R', 200, R);
      AssertEquals('G', 200, G);
      AssertEquals('B', 200, B);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_Contrast;
var
  Img, Out: TLazIntfImage;
  Adj: TColorAdjust;
  R, G, B: byte;
begin
  Img := MakeSolid(1, 1, 100, 128, 200);
  try
    Adj := NeutralColorAdjust;
    Adj.Contrast := 2.0;
    Out := AdjustColors(Img, Adj);
    try
      PixelRGB(Out, 0, 0, R, G, B);
      { (c - 128) * 2 + 128 }
      AssertEquals('R', 72, R);
      AssertEquals('G (midpoint unchanged)', 128, G);
      AssertEquals('B (clamped)', 255, B);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_SaturationZeroGivesGray;
var
  Img, Out: TLazIntfImage;
  Adj: TColorAdjust;
  R, G, B: byte;
begin
  Img := MakeSolid(1, 1, 255, 0, 0);
  try
    Adj := NeutralColorAdjust;
    Adj.Saturation := 0.0;
    Out := AdjustColors(Img, Adj);
    try
      PixelRGB(Out, 0, 0, R, G, B);
      { Rec.601 luma of pure red = 0.299 * 255 = 76.2 }
      AssertNear('R = luma', R, 76, 2);
      AssertNear('G = luma', G, 76, 2);
      AssertNear('B = luma', B, 76, 2);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_Invert;
var
  Img, Out: TLazIntfImage;
  Adj: TColorAdjust;
  R, G, B: byte;
begin
  Img := MakeSolid(1, 1, 10, 128, 245);
  try
    Adj := NeutralColorAdjust;
    Adj.Invert := True;
    Out := AdjustColors(Img, Adj);
    try
      PixelRGB(Out, 0, 0, R, G, B);
      AssertEquals('R', 245, R);
      AssertEquals('G', 127, G);
      AssertEquals('B', 10, B);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_Gamma;
var
  Img, Out: TLazIntfImage;
  Adj: TColorAdjust;
  R, G, B: byte;
begin
  Img := MakeSolid(1, 1, 100, 255, 0);
  try
    Adj := NeutralColorAdjust;
    Adj.Gamma := 2.0;   { brightens: c' = 255 * (c/255)^(1/2) }
    Out := AdjustColors(Img, Adj);
    try
      PixelRGB(Out, 0, 0, R, G, B);
      AssertNear('R', R, Round(255 * Sqrt(100 / 255)), 1);
      AssertEquals('G (max stays max)', 255, G);
      AssertEquals('B', 0, B);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_Grayscale;
var
  Img, Out: TLazIntfImage;
  Adj: TColorAdjust;
  R, G, B: byte;
begin
  Img := MakeSolid(1, 1, 255, 0, 0);
  try
    Adj := NeutralColorAdjust;
    Adj.Grayscale := True;
    Out := AdjustColors(Img, Adj);
    try
      PixelRGB(Out, 0, 0, R, G, B);
      AssertEquals('R = G', R, G);
      AssertEquals('R = B', R, B);
      AssertNear('luma', R, 76, 2);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_Sepia;
var
  Img, Out: TLazIntfImage;
  Adj: TColorAdjust;
  R, G, B: byte;
begin
  { Neutral gray input makes the expected values exact. }
  Img := MakeSolid(1, 1, 100, 100, 100);
  try
    Adj := NeutralColorAdjust;
    Adj.Sepia := True;
    Out := AdjustColors(Img, Adj);
    try
      PixelRGB(Out, 0, 0, R, G, B);
      AssertNear('R', R, Round((0.393 + 0.769 + 0.189) * 100), 1);
      AssertNear('G', G, Round((0.349 + 0.686 + 0.168) * 100), 1);
      AssertNear('B', B, Round((0.272 + 0.534 + 0.131) * 100), 1);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_RedGain;
var
  Img, Out: TLazIntfImage;
  Adj: TColorAdjust;
  R, G, B: byte;
begin
  Img := MakeSolid(1, 1, 100, 50, 25);
  try
    Adj := NeutralColorAdjust;
    Adj.RGain := 2.0;
    Out := AdjustColors(Img, Adj);
    try
      PixelRGB(Out, 0, 0, R, G, B);
      AssertEquals('R doubled', 200, R);
      AssertEquals('G unchanged', 50, G);
      AssertEquals('B unchanged', 25, B);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestColors_AlphaPreserved;
var
  Img, Out: TLazIntfImage;
  Desc: TRawImageDescription;
  C: TFPColor;
  P: pbyte;
begin
  { Build an image with a non-opaque pixel. }
  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(1, 1);
  Img := TLazIntfImage.Create(0, 0);
  Img.DataDescription := Desc;
  C.Red := 0;
  C.Green := 0;
  C.Blue := 0;
  C.Alpha := 32768;   { 50% }
  Img.Colors[0, 0] := C;
  try
    Out := AdjustColors(Img, NeutralColorAdjust);
    try
      P := Out.GetDataLineStart(0);
      AssertEquals('alpha preserved', 128, P[3]);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

{ --- Resample -------------------------------------------------------------- }

procedure TImageEditTest.TestResample_Downscale;
var
  Img, Out: TLazIntfImage;
  R, G, B: byte;
begin
  Img := MakeSolid(4, 4, 10, 20, 30);
  try
    Out := ResampleIntfImage(Img, 2, 2);
    try
      AssertNotNull('result', Out);
      AssertEquals('width', 2, Out.Width);
      AssertEquals('height', 2, Out.Height);
      PixelRGB(Out, 1, 1, R, G, B);
      AssertEquals('colour preserved', 10, R);
      AssertEquals('colour preserved', 20, G);
      AssertEquals('colour preserved', 30, B);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestResample_Upscale;
var
  Img, Out: TLazIntfImage;
  R, G, B: byte;
begin
  Img := MakeSolid(2, 2, 200, 100, 50);
  try
    Out := ResampleIntfImage(Img, 4, 4);
    try
      AssertEquals('width', 4, Out.Width);
      AssertEquals('height', 4, Out.Height);
      PixelRGB(Out, 3, 3, R, G, B);
      AssertEquals('colour preserved', 200, R);
    finally
      Out.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestResample_InvalidInput;
begin
  AssertNull('nil input', ResampleIntfImage(nil, 10, 10));
  AssertNull('zero target', ResampleIntfImage(MakeSolid(2, 2, 1, 1, 1), 0, 0));
end;

{ --- Split ---------------------------------------------------------------- }

procedure TImageEditTest.TestSplit_HorizontalHalf;
var
  Img, Piece: TLazIntfImage;
  Pieces: TIntfImageArray;
  R, G, B: byte;
begin
  { 4x10 gradient: row y has grey value y.  Cut at 50% (row 5). }
  Img := MakeRowGradient(4, 10);
  try
    Pieces := SplitIntfImage(Img, True, [0.5]);
    try
      AssertEquals('two pieces', 2, Length(Pieces));
      Piece := Pieces[0];
      AssertEquals('top piece size', 4, Piece.Width);
      AssertEquals('top piece size', 5, Piece.Height);
      PixelRGB(Piece, 0, 4, R, G, B);
      AssertEquals('top last row = 4', 4, R);
      Piece := Pieces[1];
      AssertEquals('bottom piece size', 4, Piece.Width);
      AssertEquals('bottom piece size', 5, Piece.Height);
      PixelRGB(Piece, 0, 0, R, G, B);
      AssertEquals('bottom first row = 5', 5, R);
    finally
      FreeImageArray(Pieces);
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestSplit_VerticalQuarter;
var
  Img, Piece: TLazIntfImage;
  Pieces: TIntfImageArray;
  R, G, B: byte;
begin
  { 12x4 solid; cut at 25% (column 3).  Left piece 3 px, right piece 9 px. }
  Img := MakeSolid(12, 4, 42, 43, 44);
  try
    Pieces := SplitIntfImage(Img, False, [0.25]);
    try
      AssertEquals('two pieces', 2, Length(Pieces));
      Piece := Pieces[0];
      AssertEquals('left width', 3, Piece.Width);
      AssertEquals('left height', 4, Piece.Height);
      Piece := Pieces[1];
      AssertEquals('right width', 9, Piece.Width);
      AssertEquals('right height', 4, Piece.Height);
      PixelRGB(Piece, 8, 3, R, G, B);
      AssertEquals('colour preserved', 42, R);
    finally
      FreeImageArray(Pieces);
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestSplit_MultipleLines;
var
  Img: TLazIntfImage;
  Pieces: TIntfImageArray;
  R, G, B: byte;
begin
  { 4x12 gradient; cuts at 25% (row 3) and 50% (row 6): pieces 3, 3, 6. }
  Img := MakeRowGradient(4, 12);
  try
    Pieces := SplitIntfImage(Img, True, [0.5, 0.25]);
    try
      AssertEquals('three pieces', 3, Length(Pieces));
      AssertEquals('piece 0 height', 3, Pieces[0].Height);
      AssertEquals('piece 1 height', 3, Pieces[1].Height);
      AssertEquals('piece 2 height', 6, Pieces[2].Height);
      { Reading order: top to bottom — piece 1 starts at original row 3. }
      PixelRGB(Pieces[1], 0, 0, R, G, B);
      AssertEquals('piece 1 first row = 3', 3, R);
      PixelRGB(Pieces[2], 0, 0, R, G, B);
      AssertEquals('piece 2 first row = 6', 6, R);
    finally
      FreeImageArray(Pieces);
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestSplit_DedupeAndClamp;
var
  Img: TLazIntfImage;
  Pieces: TIntfImageArray;
begin
  Img := MakeSolid(10, 10, 1, 2, 3);
  try
    { Duplicate cuts collapse to one. }
    Pieces := SplitIntfImage(Img, True, [0.5, 0.5]);
    try
      AssertEquals('duplicate collapses', 2, Length(Pieces));
    finally
      FreeImageArray(Pieces);
    end;
    { Out-of-range cuts clamp to the first/last pixel line. }
    Pieces := SplitIntfImage(Img, True, [0.0, 1.0]);
    try
      AssertEquals('clamped cuts still split', 3, Length(Pieces));
    finally
      FreeImageArray(Pieces);
    end;
    { No cuts → nothing. }
    Pieces := SplitIntfImage(Img, False, []);
    AssertEquals('no cuts -> empty', 0, Length(Pieces));
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestSplit_InvalidInput;
var
  Pieces: TIntfImageArray;
begin
  Pieces := SplitIntfImage(nil, True, [0.5]);
  AssertEquals('nil input', 0, Length(Pieces));
end;

{ --- Encode ---------------------------------------------------------------- }

procedure TImageEditTest.TestEncode_PngRoundTrip;
var
  Img, Out: TLazIntfImage;
  Stream: TMemoryStream;
  R, G, B: byte;
begin
  Img := MakeSolid(3, 2, 130, 80, 200);
  try
    Stream := EncodeIntfImage(Img, '.png');
    try
      AssertNotNull('encoded', Stream);
      Out := DecodeStream(Stream, '.png');
      try
        AssertNotNull('decoded', Out);
        AssertEquals('width', 3, Out.Width);
        AssertEquals('height', 2, Out.Height);
        PixelRGB(Out, 2, 1, R, G, B);
        AssertEquals('lossless R', 130, R);
        AssertEquals('lossless G', 80, G);
        AssertEquals('lossless B', 200, B);
      finally
        Out.Free;
      end;
    finally
      Stream.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestEncode_JpegRoundTrip;
var
  Img, Out: TLazIntfImage;
  Stream: TMemoryStream;
  R, G, B: byte;
begin
  Img := MakeSolid(8, 8, 200, 100, 50);
  try
    Stream := EncodeIntfImage(Img, '.jpg');
    try
      AssertNotNull('encoded', Stream);
      Out := DecodeStream(Stream, '.jpg');
      try
        AssertNotNull('decoded', Out);
        AssertEquals('width', 8, Out.Width);
        AssertEquals('height', 8, Out.Height);
        PixelRGB(Out, 4, 4, R, G, B);
        { Lossy: tolerate some drift. }
        AssertNear('R', R, 200, 25);
        AssertNear('G', G, 100, 25);
        AssertNear('B', B, 50, 25);
      finally
        Out.Free;
      end;
    finally
      Stream.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestEncode_BmpRoundTrip;
var
  Img, Out: TLazIntfImage;
  Stream: TMemoryStream;
  R, G, B: byte;
begin
  Img := MakeSolid(3, 2, 12, 34, 56);
  try
    Stream := EncodeIntfImage(Img, '.bmp');
    try
      AssertNotNull('encoded', Stream);
      Out := DecodeStream(Stream, '.bmp');
      try
        AssertNotNull('decoded', Out);
        AssertEquals('width', 3, Out.Width);
        AssertEquals('height', 2, Out.Height);
        PixelRGB(Out, 1, 0, R, G, B);
        AssertEquals('R', 12, R);
        AssertEquals('G', 34, G);
        AssertEquals('B', 56, B);
      finally
        Out.Free;
      end;
    finally
      Stream.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestEncode_WebpRoundTrip;
var
  Img, Out: TLazIntfImage;
  Stream: TMemoryStream;
begin
  if not WebPAvailable then
  begin
    { Degraded environment (libwebp missing): nothing to test. }
    Exit;
  end;
  Img := MakeSolid(4, 4, 90, 120, 150);
  try
    Stream := EncodeIntfImage(Img, '.webp');
    try
      AssertNotNull('encoded', Stream);
      Out := DecodeStream(Stream, '.webp');
      try
        AssertNotNull('decoded', Out);
        AssertEquals('width', 4, Out.Width);
        AssertEquals('height', 4, Out.Height);
      finally
        Out.Free;
      end;
    finally
      Stream.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestEncode_UnsupportedExt;
var
  Img: TLazIntfImage;
begin
  Img := MakeSolid(2, 2, 1, 1, 1);
  try
    AssertNull('unsupported ext', EncodeIntfImage(Img, '.xyz'));
    AssertNull('nil image', EncodeIntfImage(nil, '.png'));
  finally
    Img.Free;
  end;
end;

procedure TImageEditTest.TestEncodeExtFor;
begin
  AssertEquals('gif -> png', '.png', EncodeExtFor('.gif'));
  AssertEquals('tif -> png', '.png', EncodeExtFor('.tif'));
  AssertEquals('tiff -> png', '.png', EncodeExtFor('.tiff'));
  AssertEquals('jpg kept', '.jpg', EncodeExtFor('.jpg'));
  AssertEquals('jpeg kept', '.jpeg', EncodeExtFor('.jpeg'));
  AssertEquals('png kept', '.png', EncodeExtFor('.png'));
  AssertEquals('webp kept', '.webp', EncodeExtFor('.webp'));
  AssertEquals('bmp kept', '.bmp', EncodeExtFor('.bmp'));
  AssertEquals('case normalized', '.png', EncodeExtFor('.PNG'));
end;

initialization
  RegisterTest(TImageEditTest);
end.

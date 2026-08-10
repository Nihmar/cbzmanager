unit uimageedit;

{
  uImageEdit — Pure image-editing operations for the page editor dialog.

  All functions work entirely on TLazIntfImage in memory (no widgetset/GDI),
  so they are callable from any context and directly unit-testable:

    - ResampleIntfImage: box-filter resize in BOTH directions (enlarge and
      shrink), with the same BGRA32 fast path / generic path split used by
      uimgutil.ScaleIntfImage.
    - AdjustColors: a fixed per-pixel pipeline (invert -> grayscale -> sepia
      -> per-channel gains -> saturation -> contrast -> brightness -> gamma).
    - SplitIntfImage: cuts the page along N parallel lines (horizontal or
      vertical) into N+1 pieces.

  The output of every function is a 32-bit BGRA TLazIntfImage, top-to-bottom,
  like every decoder used by the app.  The caller owns the result.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  IntfGraphics,
  FPImage,
  GraphType,
  Math;

type
  { --------------------------------------------------------------------------
    TColorAdjust — parameters of the color-adjustment pipeline, in
    application order:

      1. Invert      — c' = 255 - c
      2. Grayscale   — c' = Rec.601 luma (keeps alpha)
      3. Sepia       — standard sepia matrix
      4. RGain/GGain/BGain — per-channel multipliers (1.0 = unchanged)
      5. Saturation  — mix toward the Rec.601 luma (1.0 = unchanged, 0 = gray)
      6. Contrast    — factor around the 128 midpoint (1.0 = unchanged)
      7. Brightness  — additive offset in 0..255 units (0 = unchanged)
      8. Gamma       — exponent curve, 1.0 = unchanged, > 1 brightens
                       (c' = 255 * (c/255)^(1/Gamma)), < 1 darkens

    Defaults are the identity.  All intermediate math is float; results are
    clamped to 0..255.
    -------------------------------------------------------------------------- }
  TColorAdjust = record
    Invert: boolean;
    Grayscale: boolean;
    Sepia: boolean;
    RGain: double;
    GGain: double;
    BGain: double;
    Saturation: double;
    Contrast: double;
    Brightness: double;
    Gamma: double;
  end;

  { Identity adjustment (all gains 1, saturation/contrast/gamma 1, offsets 0,
    no flags). }
function NeutralColorAdjust: TColorAdjust;

{
  Resamples Src to NewW x NewH with a box filter (nearest-neighbour quality,
  works both for enlargement and reduction; unlike ScaleIntfImage it never
  caps the factor at 1).  Returns nil for nil/empty input or invalid target
  dimensions.  The result is 32-bit BGRA; the caller owns it. }
function ResampleIntfImage(Src: TLazIntfImage; NewW, NewH: integer): TLazIntfImage;

{ Applies the TColorAdjust pipeline to Src.  Returns nil for nil/empty input.
  The result is 32-bit BGRA; the caller owns it. }
function AdjustColors(Src: TLazIntfImage; const AAdj: TColorAdjust): TLazIntfImage;

type
  { Result of a split: one owned TLazIntfImage per piece, in reading order. }
  TIntfImageArray = array of TLazIntfImage;

{
  Splits Src along N parallel cut lines into N+1 pieces.

    HorizontalLine = True  — horizontal lines cut the page into stacked
                             strips; pieces come top to bottom.
    HorizontalLine = False — vertical lines cut it into side-by-side strips;
                             pieces come left to right.

  CutPos holds normalized positions in 0..1 of the page dimension (height for
  horizontal lines, width for vertical).  Positions are sorted ascending,
  clamped to keep every strip at least one pixel tall/wide, and duplicates
  are dropped.  Returns nil for nil/empty input or when no usable cut
  remains.  Every piece is 32-bit BGRA; the caller owns each element (use
  FreeImageArray). }
function SplitIntfImage(Src: TLazIntfImage; HorizontalLine: boolean;
  const CutPos: array of double): TIntfImageArray;

{ Frees every element of AImages and resets the array to nil. }
procedure FreeImageArray(var AImages: TIntfImageArray);

implementation

{ Creates an empty W x H 32-bit BGRA TLazIntfImage (the canonical LCL idiom:
  an empty image given a DataDescription; LoadFromStream/assignment fills it). }
function CreateBGRA(W, H: integer): TLazIntfImage;
var
  Desc: TRawImageDescription;
begin
  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(W, H);
  Result := TLazIntfImage.Create(0, 0);
  Result.DataDescription := Desc;
end;

{ True if Img is 32-bit BGRA, 8 bits per channel, little-endian
  (B at byte 0, G at 1, R at 2, A at 3): the layout produced by every decoder
  used by the app.  On such data the operations work on raw bytes. }
function IsBGRA32(const Img: TLazIntfImage): boolean;
var
  D: TRawImageDescription;
begin
  D := Img.DataDescription;
  Result := (D.BitsPerPixel = 32) and (D.RedPrec = 8) and (D.GreenPrec = 8) and
    (D.BluePrec = 8) and (D.AlphaPrec = 8) and
    (D.RedShift = 16) and (D.GreenShift = 8) and (D.BlueShift = 0) and
    (D.AlphaShift = 24);
end;

{ ----------------------------------------------------------------------------
  Resample — box filter.
  ---------------------------------------------------------------------------- }

{ Box filter on raw BGRA bytes (fast path; same algorithm as the generic
  path).  Stepping caps the per-pixel cost at MaxSamples^2 reads regardless
  of how large the source is. }
procedure ResampleBGRA32(Src, Dst: TLazIntfImage; DW, DH: integer);
const
  MaxSamples = 4;
var
  x, y, ix, iy: integer;
  sx0, sx1, sy0, sy1, StepX, StepY, N: integer;
  SrcLine, DstLine, P: pbyte;
  R, G, B, A: cardinal;
begin
  for y := 0 to DH - 1 do
  begin
    sy0 := (y * Src.Height) div DH;
    sy1 := ((y + 1) * Src.Height) div DH;
    if sy1 <= sy0 then sy1 := sy0 + 1;
    StepY := Max(1, (sy1 - sy0 + MaxSamples - 1) div MaxSamples);
    DstLine := Dst.GetDataLineStart(y);
    for x := 0 to DW - 1 do
    begin
      sx0 := (x * Src.Width) div DW;
      sx1 := ((x + 1) * Src.Width) div DW;
      if sx1 <= sx0 then sx1 := sx0 + 1;
      StepX := Max(1, (sx1 - sx0 + MaxSamples - 1) div MaxSamples);
      R := 0;
      G := 0;
      B := 0;
      A := 0;
      N := 0;
      iy := sy0;
      while iy < sy1 do
      begin
        SrcLine := Src.GetDataLineStart(iy);
        ix := sx0;
        while ix < sx1 do
        begin
          P := SrcLine + PtrUInt(ix) * 4;
          Inc(B, P[0]);
          Inc(G, P[1]);
          Inc(R, P[2]);
          Inc(A, P[3]);
          Inc(N);
          Inc(ix, StepX);
        end;
        Inc(iy, StepY);
      end;
      if N = 0 then Continue;
      P := DstLine + PtrUInt(x) * 4;
      P[0] := B div N;
      P[1] := G div N;
      P[2] := R div N;
      P[3] := A div N;
    end;
  end;
end;

{ Box filter through the Colors property (any pixel format). }
procedure ResampleGeneric(Src, Dst: TLazIntfImage; DW, DH: integer);
const
  MaxSamples = 4;
var
  x, y, ix, iy: integer;
  sx0, sx1, sy0, sy1, StepX, StepY, N: integer;
  R, G, B, A: cardinal;
  C: TFPColor;
begin
  for y := 0 to DH - 1 do
  begin
    sy0 := (y * Src.Height) div DH;
    sy1 := ((y + 1) * Src.Height) div DH;
    if sy1 <= sy0 then sy1 := sy0 + 1;
    StepY := Max(1, (sy1 - sy0 + MaxSamples - 1) div MaxSamples);
    for x := 0 to DW - 1 do
    begin
      sx0 := (x * Src.Width) div DW;
      sx1 := ((x + 1) * Src.Width) div DW;
      if sx1 <= sx0 then sx1 := sx0 + 1;
      StepX := Max(1, (sx1 - sx0 + MaxSamples - 1) div MaxSamples);
      R := 0;
      G := 0;
      B := 0;
      A := 0;
      N := 0;
      iy := sy0;
      while iy < sy1 do
      begin
        ix := sx0;
        while ix < sx1 do
        begin
          C := Src.Colors[Min(ix, Src.Width - 1), Min(iy, Src.Height - 1)];
          Inc(R, C.Red);
          Inc(G, C.Green);
          Inc(B, C.Blue);
          Inc(A, C.Alpha);
          Inc(N);
          Inc(ix, StepX);
        end;
        Inc(iy, StepY);
      end;
      if N = 0 then Continue;
      C.Red := R div N;
      C.Green := G div N;
      C.Blue := B div N;
      C.Alpha := A div N;
      Dst.Colors[Min(x, DW - 1), Min(y, DH - 1)] := C;
    end;
  end;
end;

function ResampleIntfImage(Src: TLazIntfImage; NewW, NewH: integer): TLazIntfImage;
begin
  Result := nil;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  if (NewW <= 0) or (NewH <= 0) then Exit;
  Result := CreateBGRA(NewW, NewH);
  try
    if IsBGRA32(Src) then
      ResampleBGRA32(Src, Result, NewW, NewH)
    else
      ResampleGeneric(Src, Result, NewW, NewH);
  except
    FreeAndNil(Result);
  end;
end;

{ ----------------------------------------------------------------------------
  Color adjustment pipeline.
  ---------------------------------------------------------------------------- }

type
  { Single-pixel float pipeline; AColor is RGBA in 0..255. }
  TColorTransform = record
    R, G, B: double;
  end;

function NeutralColorAdjust: TColorAdjust;
begin
  Result.Invert := False;
  Result.Grayscale := False;
  Result.Sepia := False;
  Result.RGain := 1.0;
  Result.GGain := 1.0;
  Result.BGain := 1.0;
  Result.Saturation := 1.0;
  Result.Contrast := 1.0;
  Result.Brightness := 0.0;
  Result.Gamma := 1.0;
end;

{ Transforms one RGB triple through the pipeline in the fixed order. }
function TransformPixel(R, G, B: double; const AAdj: TColorAdjust): TColorTransform;
var
  L: double;
begin
  if AAdj.Invert then
  begin
    R := 255 - R;
    G := 255 - G;
    B := 255 - B;
  end;
  if AAdj.Grayscale then
  begin
    L := 0.299 * R + 0.587 * G + 0.114 * B;
    R := L;
    G := L;
    B := L;
  end;
  if AAdj.Sepia then
  begin
    { Temporaries: each output channel mixes the ORIGINAL R/G/B. }
    Result.R := 0.393 * R + 0.769 * G + 0.189 * B;
    Result.G := 0.349 * R + 0.686 * G + 0.168 * B;
    Result.B := 0.272 * R + 0.534 * G + 0.131 * B;
    R := Result.R;
    G := Result.G;
    B := Result.B;
  end;
  R := R * AAdj.RGain;
  G := G * AAdj.GGain;
  B := B * AAdj.BGain;
  if AAdj.Saturation <> 1.0 then
  begin
    L := 0.299 * R + 0.587 * G + 0.114 * B;
    R := L + (R - L) * AAdj.Saturation;
    G := L + (G - L) * AAdj.Saturation;
    B := L + (B - L) * AAdj.Saturation;
  end;
  if AAdj.Contrast <> 1.0 then
  begin
    R := (R - 128) * AAdj.Contrast + 128;
    G := (G - 128) * AAdj.Contrast + 128;
    B := (B - 128) * AAdj.Contrast + 128;
  end;
  if AAdj.Brightness <> 0.0 then
  begin
    R := R + AAdj.Brightness;
    G := G + AAdj.Brightness;
    B := B + AAdj.Brightness;
  end;
  if AAdj.Gamma <> 1.0 then
  begin
    R := 255 * Power(R / 255, 1 / AAdj.Gamma);
    G := 255 * Power(G / 255, 1 / AAdj.Gamma);
    B := 255 * Power(B / 255, 1 / AAdj.Gamma);
  end;
  if R < 0 then R := 0 else if R > 255 then R := 255;
  if G < 0 then G := 0 else if G > 255 then G := 255;
  if B < 0 then B := 0 else if B > 255 then B := 255;
  Result.R := R;
  Result.G := G;
  Result.B := B;
end;

{ Fast path on raw BGRA bytes. }
procedure AdjustBGRA32(Src, Dst: TLazIntfImage; const AAdj: TColorAdjust);
var
  x, y: integer;
  SrcLine, DstLine, SP, DP: pbyte;
  T: TColorTransform;
begin
  for y := 0 to Src.Height - 1 do
  begin
    SrcLine := Src.GetDataLineStart(y);
    DstLine := Dst.GetDataLineStart(y);
    for x := 0 to Src.Width - 1 do
    begin
      SP := SrcLine + PtrUInt(x) * 4;
      T := TransformPixel(SP[2], SP[1], SP[0], AAdj);
      DP := DstLine + PtrUInt(x) * 4;
      DP[0] := Round(T.B);
      DP[1] := Round(T.G);
      DP[2] := Round(T.R);
      DP[3] := SP[3];  { alpha preserved from the source }
    end;
  end;
end;

{ Generic path through the Colors property. }
procedure AdjustGeneric(Src, Dst: TLazIntfImage; const AAdj: TColorAdjust);
var
  x, y: integer;
  C: TFPColor;
  T: TColorTransform;
begin
  for y := 0 to Src.Height - 1 do
    for x := 0 to Src.Width - 1 do
    begin
      C := Src.Colors[x, y];
      T := TransformPixel(C.Red / 256, C.Green / 256, C.Blue / 256, AAdj);
      C.Red := Round(T.R) * 256;
      C.Green := Round(T.G) * 256;
      C.Blue := Round(T.B) * 256;
      Dst.Colors[x, y] := C;
    end;
end;

function AdjustColors(Src: TLazIntfImage; const AAdj: TColorAdjust): TLazIntfImage;
begin
  Result := nil;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  Result := CreateBGRA(Src.Width, Src.Height);
  try
    if IsBGRA32(Src) then
      AdjustBGRA32(Src, Result, AAdj)
    else
      AdjustGeneric(Src, Result, AAdj);
  except
    FreeAndNil(Result);
  end;
end;

{ ----------------------------------------------------------------------------
  Split.
  ---------------------------------------------------------------------------- }

{ Builds the sorted, clamped, deduplicated pixel positions of the cut lines.
  Returns the number of usable cuts (0 when none). }
function NormalizeCuts(const CutPos: array of double; ADim: integer;
  out Cuts: array of integer): integer;
var
  i, j, n, P: integer;
begin
  { Insertion-sort the clamped positions (arrays are tiny). }
  n := 0;
  for i := 0 to High(CutPos) do
  begin
    P := Round(CutPos[i] * ADim);
    if P < 1 then P := 1;
    if P > ADim - 1 then P := ADim - 1;
    j := n;
    while (j > 0) and (Cuts[j - 1] > P) do
    begin
      Cuts[j] := Cuts[j - 1];
      Dec(j);
    end;
    Cuts[j] := P;
    Inc(n);
  end;
  { Drop adjacent duplicates, compacting in place. }
  Result := 0;
  for i := 0 to n - 1 do
  begin
    if (Result > 0) and (Cuts[Result - 1] = Cuts[i]) then Continue;
    Cuts[Result] := Cuts[i];
    Inc(Result);
  end;
end;

{ Copies a rectangular region of a BGRA32 source into a freshly created
  BGRA32 destination of DW x DH, row by row. }
function CopyRegion(Src: TLazIntfImage; SrcX0, SrcY0, DW, DH: integer;
  OutX0, OutY0: integer; Dst: TLazIntfImage): boolean;
var
  y, x: integer;
  SrcLine, DstLine: pbyte;
begin
  Result := False;
  if (DW <= 0) or (DH <= 0) then Exit;
  if (SrcX0 + DW > Src.Width) or (SrcY0 + DH > Src.Height) then Exit;
  if (OutX0 + DW > Dst.Width) or (OutY0 + DH > Dst.Height) then Exit;
  if IsBGRA32(Src) then
  begin
    for y := 0 to DH - 1 do
    begin
      SrcLine := Src.GetDataLineStart(SrcY0 + y);
      DstLine := Dst.GetDataLineStart(OutY0 + y);
      Move(SrcLine[PtrUInt(SrcX0) * 4], DstLine[PtrUInt(OutX0) * 4],
        DW * 4);
    end;
  end
  else
  begin
    { Generic path: per-pixel copy through the Colors property. }
    for y := 0 to DH - 1 do
      for x := 0 to DW - 1 do
        Dst.Colors[OutX0 + x, OutY0 + y] := Src.Colors[SrcX0 + x, SrcY0 + y];
  end;
  Result := True;
end;

function SplitIntfImage(Src: TLazIntfImage; HorizontalLine: boolean;
  const CutPos: array of double): TIntfImageArray;
var
  Cuts: array of integer;
  n, i, PieceW, PieceH, StartPx, EndPx: integer;
  Piece: TLazIntfImage;
begin
  Result := nil;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  if Length(CutPos) = 0 then Exit;

  SetLength(Cuts, Length(CutPos));
  FillChar(Cuts[0], Length(Cuts) * SizeOf(integer), 0);
  if HorizontalLine then
    n := NormalizeCuts(CutPos, Src.Height, Cuts)
  else
    n := NormalizeCuts(CutPos, Src.Width, Cuts);
  if n = 0 then Exit;

  { Reading order: top-to-bottom for horizontal lines, left-to-right for
    vertical lines — i.e. always in increasing pixel position. }
  if HorizontalLine then
  begin
    PieceW := Src.Width;
    StartPx := 0;
    for i := 0 to n do
    begin
      if i < n then EndPx := Cuts[i] else EndPx := Src.Height;
      PieceH := EndPx - StartPx;
      if PieceH > 0 then
      begin
        Piece := CreateBGRA(PieceW, PieceH);
        try
          if CopyRegion(Src, 0, StartPx, PieceW, PieceH, 0, 0, Piece) then
          begin
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := Piece;
          end
          else
            Piece.Free;
        except
          Piece.Free;
          raise;
        end;
      end;
      StartPx := EndPx;
    end;
  end
  else
  begin
    PieceH := Src.Height;
    StartPx := 0;
    for i := 0 to n do
    begin
      if i < n then EndPx := Cuts[i] else EndPx := Src.Width;
      PieceW := EndPx - StartPx;
      if PieceW > 0 then
      begin
        Piece := CreateBGRA(PieceW, PieceH);
        try
          if CopyRegion(Src, StartPx, 0, PieceW, PieceH, 0, 0, Piece) then
          begin
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := Piece;
          end
          else
            Piece.Free;
        except
          Piece.Free;
          raise;
        end;
      end;
      StartPx := EndPx;
    end;
  end;
end;

procedure FreeImageArray(var AImages: TIntfImageArray);
var
  i: integer;
begin
  for i := 0 to High(AImages) do
    AImages[i].Free;
  AImages := nil;
end;

end.

unit uWebP;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Graphics;

function WebPToBitmap(const Data: Pointer; DataSize: SizeInt): TBitmap;

implementation

uses
  dl;

var
  hLib: Pointer = nil;
  _WebPGetInfo: function(data: PByte; data_size: SizeInt; pw, ph: PInteger): Integer; cdecl;
  _WebPDecodeRGB: function(data: PByte; data_size: SizeInt; pw, ph: PInteger): PByte; cdecl;
  _WebPFree: procedure(ptr: Pointer); cdecl;

procedure InitLib;
begin
  if hLib <> nil then Exit;
  hLib := dlopen('libwebp.so', RTLD_NOW);
  if hLib = nil then
    hLib := dlopen('libwebpdecoder.so', RTLD_NOW);
  if hLib = nil then Exit;
  Pointer(_WebPGetInfo) := dlsym(hLib, 'WebPGetInfo');
  Pointer(_WebPDecodeRGB) := dlsym(hLib, 'WebPDecodeRGB');
  Pointer(_WebPFree) := dlsym(hLib, 'WebPFree');
  if not Assigned(_WebPGetInfo) or not Assigned(_WebPDecodeRGB) or not Assigned(_WebPFree) then
  begin
    dlclose(hLib);
    hLib := nil;
  end;
end;

function WebPToBitmap(const Data: Pointer; DataSize: SizeInt): TBitmap;
var
  W, H: Integer;
  RawData: PByte;
  x, y: Integer;
  Src: PByte;
begin
  Result := nil;
  InitLib;
  if hLib = nil then Exit;

  if _WebPGetInfo(PByte(Data), DataSize, @W, @H) = 0 then Exit;
  if (W <= 0) or (H <= 0) then Exit;

  RawData := _WebPDecodeRGB(PByte(Data), DataSize, @W, @H);
  if RawData = nil then Exit;

  try
    Result := TBitmap.Create;
    Result.PixelFormat := pf24bit;
    Result.SetSize(W, H);
    for y := 0 to H - 1 do
    begin
      Src := RawData + y * W * 3;
      for x := 0 to W - 1 do
      begin
        Result.Canvas.Pixels[x, y] := RGBToColor(Src[0], Src[1], Src[2]);
        Inc(Src, 3);
      end;
    end;
  finally
    _WebPFree(RawData);
  end;
end;

finalization
  if hLib <> nil then
  begin
    dlclose(hLib);
    hLib := nil;
  end;

end.

unit uservicevalidate;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uZipEditor, uservicebase;

type
  TImageCheckResult = record
    EntryName: string;
    Valid: boolean;
    ErrorMsg: string;
  end;

  TValidationEntry = record
    FileName: string;
    Valid: boolean;
    ImageCount: integer;
    ErrorMsg: string;
    { Per-image details — set only when ValidateDeep is used }
    ImageChecks: TImageChecks;
  end;
  TValidationResults = array of TValidationEntry;

  { TValidateService }
  TValidateService = class
  public
    { Quick check: just verifies file is a valid CBZ with at least one image. }
    class function Validate(const AFiles: TStringArray;
      const ADir: string): TValidationResults;

    { Deep check: also decodes every image and reports per-entry errors. }
    class function ValidateDeep(const AFiles: TStringArray;
      const ADir: string): TValidationResults;
  end;

implementation

class function TValidateService.Validate(const AFiles: TStringArray;
  const ADir: string): TValidationResults;
var
  i: integer;
  FullPath: string;
begin
  Result := nil;
  SetLength(Result, Length(AFiles));
  for i := 0 to High(AFiles) do
  begin
    FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
    Result[i].FileName := AFiles[i];
    try
      if IsValidCBZ(FullPath) then
      begin
        Result[i].Valid := True;
        Result[i].ImageCount := GetImageCount(FullPath);
        Result[i].ErrorMsg := '';
      end
      else
      begin
        Result[i].Valid := False;
        Result[i].ImageCount := 0;
        if GetImageCount(FullPath) = 0 then
          Result[i].ErrorMsg := 'No readable images found'
        else
          Result[i].ErrorMsg := 'Invalid CBZ';
      end;
    except
      on E: Exception do
      begin
        Result[i].Valid := False;
        Result[i].ImageCount := 0;
        Result[i].ErrorMsg := E.ClassName + ': ' + E.Message;
      end;
    end;
  end;
end;

class function TValidateService.ValidateDeep(const AFiles: TStringArray;
  const ADir: string): TValidationResults;
var
  i: integer;
  FullPath: string;
  TotalValid: integer;
  Checks: TImageChecks;
  j: integer;
begin
  Result := nil;
  SetLength(Result, Length(AFiles));
  for i := 0 to High(AFiles) do
  begin
    FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
    Result[i].FileName := AFiles[i];
    try
      TotalValid := ValidateCBZImages(FullPath, Checks);
      Result[i].ImageChecks := Checks;
      Result[i].ImageCount := TotalValid;
      Result[i].Valid := TotalValid > 0;
      if TotalValid = 0 then
      begin
        if Length(Checks) = 0 then
          Result[i].ErrorMsg := 'No images found'
        else
          Result[i].ErrorMsg := 'All images failed to decode';
      end
      else
      begin
        { Check if any individual image failed }
        for j := 0 to High(Checks) do
          if not Checks[j].Valid then
          begin
            Result[i].ErrorMsg := Format('%d/%d images valid',
              [TotalValid, Length(Checks)]);
            Break;
          end;
      end;
    except
      on E: Exception do
      begin
        Result[i].Valid := False;
        Result[i].ImageCount := 0;
        Result[i].ErrorMsg := E.ClassName + ': ' + E.Message;
      end;
    end;
  end;
end;

end.

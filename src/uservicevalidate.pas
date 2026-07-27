{
  uservicevalidate.pas — CBZ Validation Service

  This unit provides the TValidateService class for checking the integrity of
  CBZ comic archive files.  Two levels of validation are offered:

    - Validate      — Quick check: verifies each file is a well-formed CBZ
                      archive containing at least one readable image.  Useful
                      for fast bulk scans.
    - ValidateDeep  — Thorough check: decodes every image entry inside each
                      CBZ and reports per-image pass/fail status.  Slower but
                      catches corrupted image data that a quick check would
                      miss.

  Both methods return a TValidationResults array (one entry per input file)
  with a validity flag, image count, error message, and (for ValidateDeep)
  per-image detail records.

  Dependencies: uZipEditor (IsValidCBZ, GetImageCount, ValidateCBZImages,
  TImageCheck, TImageChecks) and uservicebase (TStringArray).
}
unit uservicevalidate;
{$mode objfpc}{$h+}
interface

uses
  Classes,
  SysUtils,
  uZipEditor,
  uservicebase;

type
  { TValidationEntry — Validation result for a single CBZ file.

    Fields:
      FileName    — Base name of the checked file (no path).
      Valid       — True if the file is a well-formed CBZ with at least one
                    readable image (quick check) or with at least one
                    successfully decoded image (deep check).
      ImageCount  — Number of image entries found (quick) or number of
                    successfully decoded images (deep).
      ErrorMsg    — Human-readable description when Valid = False.
      ImageChecks — Per-image detail records; populated only by ValidateDeep.
                    Element type is TImageCheck (from uZipEditor). }
  TValidationEntry = record
    FileName: string;
    Valid: boolean;
    ImageCount: integer;
    ErrorMsg: string;
    { Per-image details — set only when ValidateDeep is used }
    ImageChecks: TImageChecks;
  end;

  { TValidationResults — Dynamic array of per-file validation entries,
    one element for each input file passed to Validate or ValidateDeep. }
  TValidationResults = array of TValidationEntry;

  { TValidateService — Stateless service for CBZ validation.  All methods are
    class methods; no instantiation is required. }
  TValidateService = class
  public
    { Quick check: verifies each file is a valid CBZ with at least one image.

      Parameters:
        AFiles — Array of CBZ filenames (base names, not full paths).
        ADir   — Directory containing the files.

      Returns:
        A TValidationResults array with one entry per input file.  Each entry's
        Valid field is True when the file passes IsValidCBZ and contains at
        least one image.  ImageCount reflects total image entries, not just
        valid ones.  ErrorMsg is populated on failure or exception.

      This method does NOT decode image data; use ValidateDeep when you need
      to detect corrupted pixel data. }
    class function Validate(const AFiles: TStringArray;
      const ADir: string): TValidationResults;

    { Deep check: decodes every image and reports per-entry errors.

      Parameters:
        AFiles — Array of CBZ filenames (base names, not full paths).
        ADir   — Directory containing the files.

      Returns:
        A TValidationResults array.  Each entry's Valid is True when at least
        one image decoded successfully.  ImageCount equals the number of
        successfully decoded images.  The ImageChecks field is populated with
        a TImageCheck for every image entry (including failures), so callers
        can inspect individual decode errors.

      This method calls ValidateCBZImages, which attempts to decode every
      image entry in the CBZ using the FPImage readers.  Non-image entries
      (e.g. ComicInfo.xml) are skipped and not reported. }
    class function ValidateDeep(const AFiles: TStringArray;
      const ADir: string;
      AOnProgress: TProgressEvent = nil): TValidationResults;
  end;

implementation

{ ---------------------------------------------------------------------------
  Validate (quick check)

  Iterates over every input file and, for each one:
    1. Calls IsValidCBZ to verify the file is a readable ZIP archive
       containing image entries.
    2. If valid, records the image count via GetImageCount.
    3. If invalid, provides a specific error message: "No readable images
       found" when the image count is zero (file is a ZIP but has no
       images), or "Invalid CBZ" for other structural problems.
    4. Any exception (e.g. file not found, permissions) is caught and
       recorded as an error with the exception class and message.

  Important: GetImageCount only counts entries with recognised image
  extensions (jpg, png, webp, etc.).  It does not decode pixel data, so
  a corrupted image that has a valid extension will still be counted.
  --------------------------------------------------------------------------- }
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
        { Distinguish between "not a ZIP at all" and "ZIP without images" }
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

{ ---------------------------------------------------------------------------
  ValidateDeep (deep check)

  Similar to Validate but uses ValidateCBZImages to attempt decoding every
  image entry.  For each input file:

    1. ValidateCBZImages returns the number of successfully decoded images
       (TotalValid) and an out-parameter array Checks with per-entry results.
    2. The entry is marked Valid when TotalValid > 0.
    3. The ImageChecks array is stored directly so callers can enumerate
       individual decode failures.
    4. ErrorMsg is set to a summary when not all images pass:
         - "No images found" when Checks is empty (CBZ has zero image entries).
         - "All images failed to decode" when Checks is non-empty but every
           image failed.
         - "X/Y images valid" when some (but not all) images passed.

  Note on performance: ValidateCBZImages reads and decodes every image
  stream into memory.  For large archives this can be slow and
  memory-intensive.  Use the quick Validate method for routine scans.
  --------------------------------------------------------------------------- }
class function TValidateService.ValidateDeep(const AFiles: TStringArray;
  const ADir: string; AOnProgress: TProgressEvent): TValidationResults;
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
    if Assigned(AOnProgress) then
      AOnProgress(i * 100 div Length(AFiles),
        Format('Validating %s (%d/%d)', [AFiles[i], i + 1, Length(AFiles)]));
    try
      { ValidateCBZImages attempts to decode every image and returns both
        the count of successes and a per-entry status array. }
      TotalValid := ValidateCBZImages(FullPath, Checks);
      Result[i].ImageChecks := Checks;
      Result[i].ImageCount := TotalValid;
      Result[i].Valid := TotalValid > 0;

      if TotalValid = 0 then
      begin
        { No image could be decoded — explain why }
        if Length(Checks) = 0 then
          Result[i].ErrorMsg := 'No images found'
        else
          Result[i].ErrorMsg := 'All images failed to decode';
      end
      else
      begin
        { At least one image passed.  Check if any individual image failed
          so we can report a partial-failure summary. }
        for j := 0 to High(Checks) do
          if not Checks[j].Valid then
          begin
            Result[i].ErrorMsg :=
              Format('%d/%d images valid', [TotalValid, Length(Checks)]);
            Break;                          // one summary is enough
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

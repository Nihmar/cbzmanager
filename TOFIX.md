# TOFIX — `feat/add-image-from-internet` vs `main` (`05666fd`, 8 files +1127/-32)

Read-only audit of the branch. No files were modified during evaluation.
Issues are grouped by severity with `file:line` references and actionable fixes.

## 1. Critical — feature silently untested / CI false-green / build breakage

- **`tests/test_uimgsrc.pas:1`** missing `initialization RegisterTest(TImgSrcTest); end.`
  The file ends at `148: end.` with no registration. `tests/testrunner.pp:29`
  adds `test_uimgsrc` to `uses`, but `fpcunit` never discovers it. `make test`
  reports `202` run on both `main` and branch (should be `211`). CI is
  false-green; JSON parser and `GuessExtFromURL` are never exercised.
  Fix: add the `initialization` block.

- **`Makefile:46-61`** `test-compile-checks` is missing `-Fu …/fcl-web` and
  `-Fu …/openssl` while `build:16-17` and `test-compile:35-36` add them.
  On hosts without wildcard `fpc.cfg` this target fails with
  `Fatal: Can't find unit opensslsockets` (`src/uimgsrc.pas:20`). Also the
  `FPC … -Fu` command is triplicated (DRY violation) with hard-coded version
  `3.2.2` / arch `x86_64-linux` / absolute `/usr/lib/lazarus/...`.
  Fix: factor into `FPC_UNITS` var; use `$(shell fpc -iV)` or rely on
  `fpc.cfg` wildcard; add the two `-Fu` to `test-compile-checks`.

- **`cbzmanager.lpi`** drift — `git diff main...HEAD -- cbzmanager.lpi` is empty.
  The two new units are not listed in `<Units>` (13 other existing units are
  also missing, but a newly added *form* must be present for the IDE).
  `fpc -Fusrc` compiles via `main.pas:469 uses udlgaddimage → uimgsrc`, but
  `lazbuild cbzmanager.lpi` / IDE designer shows "unit not part of project".
  Fix: add `<Unit>` entries for `src/uimgsrc.pas` and
  `src/udlgaddimage.pas/.lfm` (`HasResources=True`, `ComponentName=dlgAddImage`).
  `cbzmanager.lpr:5-38` omits `udlgaddimage`/`uimgsrc` too (consistent with
  pre-existing drift; not strictly required since dynamically created, but
  should be added for consistency).

## 2. High — Correctness / resource / UX blockers

### `src/uimgsrc.pas` (network & parsing, `:81-404`)

- **Unbounded download → OOM** `HttpGetString:128-155` (string body) and
  `DownloadImage:157-196` (`TMemoryStream`) buffer the entire response with no
  `Content-Length` / `MaxSize` check. A malicious redirect serving 200 MB is
  fully buffered before `DecodeImage`. Fix: cap via `OnDataReceived` /
  `MaxDownloadSize` (e.g. 20 MB) and pre-check header.

- **Sparse-array bug (Openverse)** `ParseOpenverseResults:268-282` does
  `SetLength(Results, arr.Count); for i… if el=nil then Continue; Results[i]:=r`
  leaving holes (default `FullURL=''`) that still count toward `Length`.
  Wikimedia compacts via `n`/`SetLength(Results,n):335-366`. Fix: compact
  Openverse the same way. Trigger: `results:[null, {"url":…}]` leaves
  `Results[0].FullURL=''`.

- **Too-loose `ispUrl` validation** `SearchImages:388 Pos('http',LowerCase(q))<>1`
  accepts `httpx://`, `httpsomething`, `http`, and rejects `ftp://` only by
  accident. Should be `StartsText('http://') or StartsText('https://')`.
  Also an empty query hits `?q=&page_size=20` (400/429) — add an early
  `q='' → Err='Enter search terms'`.

- **GuessExt `?`/`#` stripping uses wrong index** `GuessExtFromURL:204-211`:
  `i:=URL.IndexOf('?'); path:=URL.Substring(0,i); i:=URL.IndexOf('#'); path:=path.Substring(0,i)`
  — second `IndexOf` is on the original `URL`, not `path`; `Substring(0,i)`
  clamps when `i>Length(path)`, so it works by accident but fails for `#`
  before `?` / `…#frag?x=1`. Fix: search `path.IndexOf` (or strip fragment
  first).

- **`URLEncode:81-97`** is a byte-wise UTF-8 loop — correct for `{$H+}`
  `AnsiString` but undocumented; `+` for space is intentional for `q=`;
  double-encode `%20→%2520` is acceptable. Note for clarity only.

- **`HttpGetString:149-150`** leaves `ErrMsg` stale on success; `StatusCode`
  only `200` is success (204/206 errors, 429 surfaces as generic
  `HTTP 429` instead of a throttle UX). No explicit `MaxRedirects`, no
  `OnRedirect` SSRF guard (`file://`), `USER_AGENT='cbzmanager/1.0':64` is
  minimal vs Wikimedia etiquette (contact URL recommended).

- **`data.Free` on `nil` is safe** in FPC (`285,369`); `Exit` inside
  `try…finally` correctly runs `finally`. `GetJSON('')` AV is caught
  generically → opaque `Invalid JSON` (`257,321`).

### `src/udlgaddimage.pas` (dialog, `:57-297`)

- **Blocks main thread** `DoSearch:153-163`, `SelectResult:201-212` (IOTimeout
  60s), `AddFromURL:254-263` all run **synchronous** `SearchImages` /
  `DownloadImage` under `Screen.Cursor:=crHourGlass`. UI freezes 15–60s, no
  Cancel, `BtnSearch`/`LstResults` stay enabled, `ProcessMessages` not pumped
  so the hourglass may never paint. Fix: move to a background `TThread`+`Queue`
  like the other services (or at minimum disable controls + pump messages).

- **No input validation** — empty `EdQuery` builds `OPENVERSE_API?q=&page_size=20`.
  Fix: disable `BtnSearch` when `Trim(EdQuery)=''`.

- **Leak / stale hint** `ClearPreview:87-93` frees `FPreviewStream` but not
  `LabelLicense.Hint` (stale URL persists) and not `LabelInfo` overflow.
  `SelectResult:222-228` `Bmp:=IntfToBitmap(Img)` needs `try/finally` around
  `Img.Free` (exception between `IntfToBitmap` and `Img.Free` leaks `Img`).

- **Duplicate-fetch reuse is correct for `ispUrl`**
  (`SameText(FullURL,FPreviewURL) && FPreviewStream<>nil:243`) but
  `SameText` (case-insensitive) may mis-reuse on a case-sensitive host; add
  non-empty URL guard.

- **`FormCloseQuery:278-284` silent refusal** — `if mrOk then CanClose:=Assigned(FImageStream)`
  traps Alt+F4/Enter with no `ShowInfo`. If network fails, `mrOk` is not set
  so the dialog stays open (acceptable), but external `mrOk` would trap the user.

- **`CurrentProvider:78-85`** falls back to `ispOpenverse` when `CbProvider`
  is editable (`csDropDown` not `csDropDownList`: `udlgaddimage.lfm:36`). User
  typing arbitrary text silently maps to Openverse. Fix: `Style=csDropDownList`.

### `src/main.pas` (integration, `:2542-2646`, `:639-657`)

- **`AddFrontFromStream:2542-2591`** ownership is *correct* (`try…finally Stream.Free`
  runs even on early `Exit` after `SetStatus` decode/scale failure `2560,2568`).
  But `Thumb:=ScaleIntfImage(Img,CacheW,CacheH); Img.Free` — if `Scale` raises,
  `Img.Free` is skipped → leak. Fix: `try Img.Free` guard. Also
  `FPagePreviews.Add(Thumb)` + `NewPage.Image:=Thumb` share the pointer (cache
  owns); exception before `PageInsertFront` leaves an orphan in the cache.

- **Hardcoded `frontispiece` name** `2574 PageName:='frontispiece'+PageExt`
  collides when adding twice before `Save` (two pages `frontispiece.jpg` at
  index 0/1). `LVPages` shows duplicates; `OrigName` duplicates break the
  binary-search assumption (save mitigates via `Consumed` array, but UX is
  confusing). Fix: unique name (`frontispiece-N` or GUID).

- **`MnuPageAddFrontClick:2593-2612` empty `finally`** — `MemStream.LoadFromFile`
  raising (`EFOpenError`) leaks `MemStream` (never passed to `AddFront…`).
  Fix: `except FreeAndNil(MemStream); raise;`. Also missing guards
  `FPagesThread<>nil`/`FPageFile=''` (the internet handler has them at
  `:2627-2633`); "Add front" while `TPagesThread` is loading → inserts a page
  that is then overwritten by `PagesThreadTerminated`.

- **`MnuPageAddInternetClick`** uses hard-coded `Desc='image from internet'`
  (`:2641`), losing title/license for `SetStatus`.

- **`SetPageOpsEnabled:639-657`** toggles `MnuPageAddInternet`/`MnuPgAddInternet`
  but `BtnPgAddInternet` only via `PanelPageTools.Enabled`; for CBR read-only
  the button stays enabled (handler early-exits with
  `SetStatus('CBR previews are read-only')`) — message vs disabled-state mismatch.

## 3. Medium — LFM / layout / persistence / style

- **`src/udlgaddimage.lfm:14-83`** all `Align=alNone` + fixed `Left/Top/Width/Height`,
  `PanelBottom:108 Align=alNone Top=552` (should be `alBottom`), no `Anchors`.
  The dialog is `bsSizeable` (`6`) and can be shrunk/maximised to clip/blank
  areas. Fix: `Anchors=[akLeft,akTop,akRight,akBottom]` or `Align=alClient` +
  splitter. `ImgPreview Stretch=True` without `Proportional/Center` distorts
  aspect (other previews use `MakeThumb` letterboxing).

- **`main.lfm:308-321`** `PanelPageTools` children `Align=alLeft` (so `Left` is
  ignored), but duplicate `Left=146` for `BtnPgAddInternet` and `BtnPgEdit`
  signals a designer bug, and both have duplicate `TabOrder=2`. `Caption='Add net'`
  is truncated/ambiguous; `Hint` is correct.

- **`udlgaddimage.lfm:36`** `CbProvider` editable → should be `csDropDownList`.
  `BtnSearch Default=True` (`:53`) makes Enter trigger *Search* not *Add*
  (intentional). `LabelLicense Width=232` fixed, `WordWrap=False` → long
  license+URL clipped; `LabelInfo Height=44` fixed 2-line truncates long
  `HTTP 429` errors.

- **`udlgaddimage.pas:115-122`** `FormCreate` calls `InitSettingsPersistence`
  (`udlgbase.pas:55-58` overwrites `OnClose`). `OnClose` vs `OnCloseQuery`
  coexistence is ok but fragile; `CbProviderChange` is not called after
  `LoadSettings`, so `BtnSearch.Caption` (`Search` vs `Fetch`) is stale if a
  `ispUrl` provider was persisted.

## 4. Low — Tests & docs

- **`tests/test_uimgsrc.pas` fixtures minimal** — `OPENVERSE_JSON` only
  `title/url/thumbnail/foreign_landing_url/license`; missing `null`, missing
  `url`, `thumbnail` non-string, `results` being `null`/non-array.
  `WIKIMEDIA_JSON` only one valid + one `imageinfo:[]`; missing `imageinfo`
  absent / object-not-array / `url` empty / `thumburl` missing fallback /
  `extmetadata.License.value` non-string. No error-path tests
  (`Invalid JSON`, `No "results" array`, `No "query.pages"`). No assertions on
  `PageURL`, `ErrMsg=''` on success, or empty-result length on `False`.

- **`GuessExtFromURL` tests incomplete** — only `?x=1`, `#frag`, `.WEBP`;
  missing combined `?+#`, dot-in-directory, trailing dot, port `:8080`,
  `.jpeg/.tif/.tiff/.gif/.bmp`. No combined `?`+`#` case would expose the bug above.

- **`AGENTS.md` is gitignored** — the documentation added to it (file-table rows
  for `uimgsrc`/`udlgaddimage` + page-editor bullet) is on-disk but not in
  `05666fd`. The unit headers are the only versioned docs.

## Suggested fix order

**P0 (must before merge — broken tests/CI):**
1. `tests/test_uimgsrc.pas:145` add `initialization RegisterTest(TImgSrcTest); end.`
   (expect `202 → 211` tests).
2. `Makefile:46` add `-Fu …/fcl-web -Fu …/openssl` to `test-compile-checks`;
   factor triplicated `FPC … -Fu` into `FPC_UNITS`; replace hard-coded `3.2.2`
   with `$(shell fpc -iV)` / `fpc.cfg` wildcard.
3. `cbzmanager.lpi` add `<Unit>` entries for `src/uimgsrc.pas` and
   `src/udlgaddimage.pas/.lfm`.

**P1 (correctness/leak):**
4. `src/uimgsrc.pas:268` compact Openverse `Results` (use `n` counter like Wikimedia).
5. `src/uimgsrc.pas:204` fix `GuessExtFromURL` to strip `#` then `?` from `path`.
6. `src/uimgsrc.pas:388` tighten `ispUrl` to `StartsText('http://') or StartsText('https://')`; reject `q=''`.
7. `src/udlgaddimage.pas` `ClearPreview` clear `LabelLicense.Hint`; `SelectResult:222` wrap `Img.Free` in `try/finally`.
8. `src/main.pas:2574` make `PageName` unique (`frontispiece-N` or GUID).

**P2 (UX/blocking & robustness):**
9. Move `DoSearch`/`SelectResult`/`AddFromURL` off the main thread (or at least
   disable controls during fetch, add Cancel/timeout, pump `ProcessMessages`).
10. `udlgaddimage.lfm` anchoring (`Align=alClient`/`alBottom`, `Anchors`,
    `Proportional`, `csDropDownList`, fix `TabOrder` duplicates).

**Verification:** `make test` (now 211), `make test-checks`, `make build` (or
`lazbuild cbzmanager.lpi`), manual smoke: search each provider, paste URL, CBR
read-only still gates, add twice before save shows distinct names, cancel after
preview shows no leak (heaptrc).

# cbzmanager — Code Analysis Report

~10.500 righe · 25 unit Pascal · 8 dialog · 4 servizi · 795 righe di test · 27 luglio 2026

---

## Sommario

| Severità | Conteggio |
|----------|-----------|
| Critical | 4 |
| Major | 19 |
| Minor | 22 |
| Servizi testati | 4 / 12 |

---

## Critical (4)

### C1. God Form: TfrmMain ha 12+ responsabilità in 2042 righe

**File:** `src/main.pas`

`TfrmMain` gestisce: browsing directory, file listing, preview pagine, modello editing in-memory (FPages, FBaseline, FChanges), manipolazione pagine (delete/move/sort/reverse/renumber), stage bar + save/revert, thumbnail/zoom, orchestrazione validazione, conversione WebP, merge, ComicInfo, rename/delete file, cancellazione batch, drag-and-drop, keyboard shortcut dispatch, context menu state.

La logica di mutazione del modello pagine vive direttamente negli event handler. Sort, delete, move, renumber — tutti implementati inline nei click handler dei menu. Impossibile fare unit test senza istanziare il form.

`uPageEditModel.pas` esiste già e definisce i tipi `TPageState`, `TPageStates`, `TChanges`, ma il form non lo usa come controller — usa i tipi direttamente e implementa tutta la logica di mutazione inline.

> **Fix:** Estrarre un `TPageEditController` che incapsuli tutte le operazioni su FPages. Il form dovrebbe chiamare metodi come `Controller.DeletePages(Indices)`, `Controller.Sort`, `Controller.MoveUp(Indices)`. Il thread launch/terminate può essere gestito da un service orchestrator generico.

### C2. Memory leak: stream parziali persi in caso di eccezione

**File:** `src/uzipeditor.pas` — `ConvertCBZToWebP` (linee 546-663), `MergeIntoVolume` (666-707), `FilterPagesFromCBZ` (709-766)

L'array `Result` accumula `TMemoryStream` durante il loop. Se un'eccezione avviene a metà (es. `TMemoryStream.Create` o `CopyFrom` fallisce), gli stream già allocati in `Result[0..PageNum-1]` vengono persi perché il `finally` esterno libera solo `AllEntries`, non `Result`. Il caller riceve un Result nil o parziale senza modo di liberare gli stream allocati.

> **Fix:** Aggiungere un `try/except` attorno al loop di costruzione del risultato che chiami `FreeZipEntries(Result)` prima di ri-lanciare l'eccezione.

### C3. Eccezioni silenziate: bare `except/end` in udlgcomicinfoeditor

**File:** `src/udlgcomicinfoeditor.pas:656-658`

```pascal
try
  Entries := CollectZipEntries(AFilePath);
  ...
except
end;  // SILENZIOSO — inghiotte out-of-memory, access violation, errori disco
```

Un secondo blocco a linee 666-669 fa fallback silenzioso su `DefaultComicInfo` senza logging.

> **Fix:** Almeno loggare l'errore con `Log()` o mostrare un messaggio. Meglio ancora: propagare l'eccezione al chiamante.

### C4. WriteComicInfoToCBZ può lasciare l'utente senza file

**File:** `src/ucomicinfo.pas:292-339`

Se `BackupFile` ha successo (rinomina l'originale in `_OLD.cbz`) ma poi `WriteZipFromEntriesDeflated` fallisce, il file originale è stato rinominato e nessun nuovo file viene scritto. L'utente resta solo con il backup `_OLD`.

> **Fix:** Usare il pattern atomico `ReplaceCBZ` già presente in `uservicebase.pas` (scrivi su temp, poi rinomina).

---

## Major (19)

### M1. Bug logico: SkipExistingWebP non funziona come previsto

**File:** `src/uzipeditor.pas:582`

Le immagini WebP sono già escluse dal branch `not IsConvertibleExt(Ext)` (linea 568), perché `.webp` non è nella lista convertibili. Il check `SkipExistingWebP` a linea 582 si applica quindi alle immagini non-WebP. Quando il flag è `True`, TUTTE le immagini convertibili vengono mantenute as-is — il flag significa "disabilita tutta la conversione" invece di "salta immagini già WebP".

> **Fix:** Spostare il check `SkipExistingWebP` dentro il branch `not IsConvertibleExt`, applicandolo solo quando `SameText(Ext, '.webp')`.

### M2. BackupFile: return value ignorato da tutti i caller

**File:** `src/uservicecomicinfo.pas:198`, `src/userviceconvert.pas:146`, `src/ucomicinfo.pas:333`

Se il backup fallisce (file bloccato, disco pieno), la scrittura procede e l'utente perde l'unica copia del file originale.

> **Fix:** Controllare il valore di ritorno e abortire la scrittura in caso di fallimento.

### M3. God Unit: uzipeditor.pas ha 9+ responsabilità

**File:** `src/uzipeditor.pas` (768 righe)

Un'unica unit gestisce: estrazione ZIP in memoria, scrittura ZIP, decodifica immagini, enumerazione immagini, validazione CBZ, conversione WebP, merge volumi, filtraggio pagine, naming pagine.

> **Fix:** Separare in `uzipcore.pas` (primitives ZIP read/write), `ucbzimages.pas` (operazioni immagini su CBZ). Logica di conversione e merge nei rispettivi servizi.

### M4. Blocco "keep entry with renumber" duplicato 5 volte in ConvertCBZToWebP

**File:** `src/uzipeditor.pas:570-578, 582-590, 606-615, 624-632, 637-645`

Lo stesso blocco di 8 righe (if RenumberPages / KeepEntry con o senza rinumerazione) è copia-incollato 5 volte nella stessa funzione.

> **Fix:** Estrarre una procedura locale `KeepWithOptionalRenumber`.

### M5. Progress reporting duplicato tra TServiceThread e TSaveChangesThread

**File:** `src/uthreadservice.pas:58-73, 286-319` e `src/uPageEditModel.pas:94-181`

Entrambe le classi implementano indipendentemente lo stesso pattern: `FPendingPct/FPendingMsg`, `SyncProgress` via main thread, metodo dispatch lato worker.

> **Fix:** `TSaveChangesThread` dovrebbe ereditare da `TServiceThread`.

### M6. Complessità ciclomatica elevata: ConvertCBZToWebP (~20+)

**File:** `src/uzipeditor.pas:501-664` (163 righe)

Il main loop ha 6 branch principali (ComicInfo skip, non-convertibile, skip-existing-WebP, errore decode, errore encode WebP, confronto dimensioni), ciascuno ulteriormente diviso da `RenumberPages`.

> **Fix:** Decomporre in: `HandleComicInfoEntry`, `HandleNonConvertible`, `AttemptWebPConversion`, `KeepOriginalEntry`.

### M7. TMergeService.Merge: 158 righe, 3 fasi mischiate, nessun exception handler

**File:** `src/uservicemerge.pas:237-395`

Preparazione, creazione volumi e cleanup sono mescolati in un unico metodo con 15+ variabili locali. A differenza di Convert, Validate e Remove, non ha handler di eccezioni top-level.

### M8. Business logic nei dialog: zip I/O e filename parsing in UI

**File:** `src/udlgcomicinfoeditor.pas:628-693`, `src/udlgcomicinfo.pas:128-153`

`BtnRemoveClick` chiama direttamente `TComicInfoService.Remove`. `LoadFile` fa ispezione ZIP (`CollectZipEntries`), parsing numero capitolo dal filename via `RPos`, e I/O file con `ReadComicInfoFromCBZ`. Questa logica appartiene al service layer.

### M9. Thread.Queue(nil, @SyncProgress): rischio dangling method call

**File:** `src/uthreadservice.pas:307`, `src/uPageEditModel.pas:168`

Con `nil` come primo argomento, se il thread viene distrutto prima che il main thread processi la call in coda, `SyncProgress` esegue su un oggetto liberato.

> **Fix:** Usare `TThread.Queue(Self, @SyncProgress)`.

### M10. "Collect selected indices": pattern identico duplicato 3 volte

**File:** `src/main.pas:1473, 1513, 1550`

```pascal
Sel := nil;
for i := 0 to LVPages.Items.Count - 1 do
  if LVPages.Items[i].Selected then begin
    SetLength(Sel, Length(Sel) + 1);
    Sel[High(Sel)] := i;
  end;
```

> **Fix:** Estrarre `GetSelectedPageIndices: TIntArray`.

### M11. Thread launch/terminate boilerplate ripetuto 4 volte ciascuno

**File:** `src/main.pas:1003-1009, 1076-1082, 1173-1179, 1387-1392` (launch) e `1018-1037, 1092-1118, 1188-1202, 1331-1346` (terminate)

Ogni servizio: SetStatus, StatusProgress.Visible, disabilita toolbar button e menu item, crea thread, assegna OnTerminate, Start. Lo stesso in reverse per la terminazione.

> **Fix:** Creare `LaunchServiceThread(Thread, StatusMsg, Button, MenuItem)` e `HandleServiceDone`.

### M12. MoveUp/MoveDown e MoveStart/MoveEnd sono near-duplicate

**File:** `src/main.pas:1505-1570, 1578-1617`

Le coppie Up/Down e Start/End condividono il codice di raccolta selezione e differiscono solo nella direzione dello swap.

> **Fix:** Parametrizzare la direzione: `MovePage(Direction: TMoveDir)`.

### M13. 10 metodi superano le 30 righe in main.pas

| Metodo | Righe | Note |
|--------|-------|------|
| `MnuMergeClick` | 50 | Dialog + series detection + thread launch |
| `MnuDeleteRowsClick` | 50 | Due path completamente diversi (batch vs single) |
| `FormCreate` | 45 | Init caches, dimensioni, image lists, zoom, hints |
| `MnuManageComicInfoClick` | 43 | Guard, path, dialog, branch remove/write |
| `SaveChangesThreadTerminated` | 42 | Model compaction, renumbering, baseline reset |
| `FormKeyDown` | 40 | If-else chain per 7 shortcut |
| `MnuConvertWebPClick` | 37 | Guard, file collection, dialog, thread |
| `RenderPages` | 33 | ListView rebuild con thumbnail |
| `MnuPageDeleteClick` | 32 | Selection + deletion |
| `BtnStageSaveClick` | 31 | Confirmation, snapshot, thread |

### M14. 9+ magic number senza costanti nominate

**File:** `src/main.pas`

| Linea | Valore | Significato |
|-------|--------|-------------|
| 374 | `150` | Thumbnail width (mai usato altrove — dead code?) |
| 375 | `180` | Thumbnail height (mai usato altrove — dead code?) |
| 376-379 | `128`, `160` | Dimensioni image list |
| 388 | `48` | Zoom minimo |
| 390 | `128` | Zoom default |
| 557, 598, 847 | `1.25` | Aspect ratio thumbnail (ripetuto 3x) |
| 596 | `16` | Zoom minimo effettivo |
| 1437, 1447 | `32` | Zoom step |
| 1704, 1743 | `4` | Zero-padding width per page naming |

### M15. Nessun base dialog condiviso: boilerplate ripetuto in 8 dialog

**File:** tutti i `src/udlg*.pas`

Ogni dialog ripete:
- `BorderStyle := bsDialog; BorderIcons := [biSystemMenu];` (8 volte)
- Creazione `PanelBottom` con `Align := alBottom; BevelOuter := bvNone;` (7 volte)
- Setup `TListView` read-only report-style (4 volte)
- Bottone Close con `Cancel := True; ModalResult := mrOK; Width := 80; Height := 30;` (4 volte)

> **Fix:** Creare `TBaseDialog` con `CreateBottomPanel`, `CreateButton`, `CreateResultListView`.

### M16. Validazione input mancante nei dialog

- **udlgmerge.pas**: nessun check che Start ≤ End; sequenza custom vuota ritorna nil; nome serie non validato
- **udlgcomicinfoeditor.pas**: giorno 31 per febbraio accettato; mese 0 = "unset" non documentato; nessuna validazione ISO language; nessun controllo contenuto campi testo
- **udlgrows.pas**: token invalidi nel range silenziosamente ignorati senza feedback utente

### M17. Error handling inconsistente tra servizi

| Servizio | Formato errore |
|----------|---------------|
| Validate | `E.ClassName + ': ' + E.Message` (con classe eccezione) |
| Convert | `E.Message` (senza classe) |
| ComicInfo | `E.Message` (senza classe) |
| DeletePages | Nessun error handling per-file (il batch si ferma alla prima eccezione) |
| Merge | Nessun handler top-level |

### M18. ucomicinfo.pas mischia data model e I/O (SRP violation)

**File:** `src/ucomicinfo.pas`

Definisce il record `TComicInfo` e la serializzazione XML (data layer puro) ma contiene anche `ReadComicInfoFromCBZ` e `WriteComicInfoToCBZ` (I/O che dipende da `uzipeditor` e `uservicebase`). La unit data model non dovrebbe conoscere i file ZIP.

### M19. MnuDeleteRowsClick: dual-mode — due path incompatibili in un metodo

**File:** `src/main.pas:1363-1413`

Un `if/else` a linea 1381 biforca in: (1) lancio thread batch su tutti i file, oppure (2) mutazione modello in-memory su singolo file. Dovrebbero essere due metodi separati.

---

## Minor (22)

### m1. Stringhe italiane residue nel codice altrimenti inglese

- `src/main.pas:394` — `'=== Avvio, log in %s ==='`
- `src/main.pas:1678` — `'inversione'` tra label inglesi ('sort', 'renumber')
- Log messages misti italiano/inglese nei service e utility

### m2. ComicInfo.xml lookup loop duplicato 4 volte

`for j := 0 to High(Entries) do if SameText(Entries[j].Name, 'ComicInfo.xml')` scritto manualmente in:
- `src/uservicecomicinfo.pas:111, 166`
- `src/ucomicinfo.pas:277, 305`

> **Fix:** Estrarre `FindComicInfoIndex(Entries): Integer`.

### m3. Path building duplicato ~10 volte

`IncludeTrailingPathDelimiter(ADir) + AFiles[i]` ripetuto in 7 unit: `uservicevalidate`, `userviceconvert`, `uservicecomicinfo`, `uservicemerge`, `uthreadservice`, `uzipeditor`, `uloaderthread`.

### m4. IsConvertibleExt vs IsImageExt: liste quasi identiche

- `src/uzipeditor.pas:494` — `IsConvertibleExt`: jpg, jpeg, png, gif, bmp, tiff, tif
- `src/uimgutil.pas:63` — `IsImageExt`: png, jpg, jpeg, bmp, gif, webp, tiff, tif

L'unica differenza è che `IsConvertibleExt` esclude `.webp`.

> **Fix:** `IsConvertibleExt := IsImageExt(Ext) and not SameText(Ext, '.webp')`.

### m5. O(n²) SetLength grow-by-one in tutta la codebase

~15 occorrenze di `SetLength(Arr, Length(Arr) + 1)` in 8 file. Per CBZ grandi (migliaia di pagine) diventa significativo.

### m6. Naming file inconsistente: uPageEditModel.pas vs lowercase

Tutti gli altri file usano lowercase (`uservicebase.pas`). Solo `uPageEditModel.pas` usa PascalCase.

### m7. Campo errore nominato in 3 modi diversi

| Tipo | Campo |
|------|-------|
| `TServiceResult` | `Message` |
| `TMergeResult`, `TDeletePagesResult`, `TSaveChangesResult`, `TConvertEntry`, `TValidationEntry` | `ErrorMsg` |
| `TComicInfoEntry` | `Error` |

Inoltre 4 result type strutturalmente identici (`TServiceResult`, `TMergeResult`, `TDeletePagesResult`, `TSaveChangesResult`) che potrebbero essere unificati.

### m8. Hardcoded `_OLD.cbz` in 5+ posizioni

`src/udlgcomicinfo.pas:70`, `src/udlgrows.pas:227`, `src/udlgwebp.pas:118`, `src/uservicebase.pas:113,153`.

> **Fix:** Definire `BACKUP_SUFFIX = '_OLD.cbz'` in `uservicebase.pas`.

### m9. Opzione backup inconsistente tra dialog

| Dialog | Widget | Caption |
|--------|--------|---------|
| udlgcomicinfo | Checkbox | "Create backup (_OLD.cbz) before rewriting" |
| udlgcomicinfoeditor | Checkbox | "Backup before saving" |
| udlgwebp | RadioGroup | "Create backup (_OLD.cbz)" / "Permanently delete" |
| udlgrows | Checkbox (invertita) | "Permanently delete (no _OLD.cbz backup)" |

### m10. "Open a folder first" guard ripetuto 5 volte

**File:** `src/main.pas:991, 1053, 1138, 1263, 1305`

> **Fix:** Estrarre `function RequireFolder: Boolean`.

### m11. "Preview visible" guard ripetuto 9 volte

**File:** `src/main.pas` — 9 occorrenze di `if not PanelSingleFile.Visible then Exit;`

> **Fix:** Estrarre `function RequirePreview: Boolean`.

### m12. Dead code: FThumbW/FThumbH assegnati ma mai letti

**File:** `src/main.pas:374-375` — I thumbnail usano `CacheW/CacheH` dal sistema zoom.

### m13. Dead code: CreatedFiles array costruito ma mai usato

**File:** `src/uservicemerge.pas:247, 302, 371-372` — Accumula path dei volumi creati ma non viene restituito né letto.

### m14. Dead code: TImageCheckResult dichiarato come "unused"

**File:** `src/uservicevalidate.pas:38-43` — Il commento dice esplicitamente "currently unused within the unit".

### m15. GetFileSize ridefinito: shadow del built-in

**File:** `src/userviceconvert.pas:102-113` — FPC ha già `SysUtils.FileSize`. La funzione fa shadow di `System.FileSize`.

### m16. CollectCBZFiles: FindClose non in try/finally

**File:** `src/uservicebase.pas:131-138` — Se `SetLength` causa out-of-memory tra `FindFirst` e `FindClose`, l'OS search handle va in leak.

### m17. nDel/nMov calcolati ma non visualizzati in UpdateStageBar

**File:** `src/main.pas:651-652` — Solo `nTotal` viene usato. I conteggi separati per deleted/moved vengono calcolati per niente.

### m18. FormKeyDown: 40 righe di if-else chain per shortcut

**File:** `src/main.pas:450-490` — 7 condizioni in cascata. Sarebbe più mantenibile con una tabella di shortcut o action list binding.

### m19. ScrollBox setup duplicato 4 volte in udlgcomicinfoeditor

**File:** `src/udlgcomicinfoeditor.pas:262, 314, 366, 406` — Le stesse 5 righe per ogni tab.

> **Fix:** Estrarre `CreateTabScrollBox(ATab): TScrollBox`.

### m20. udlgvalidate e udlgconvertresults quasi identici

Stessa struttura: ListView + PanelBottom + Close button + `ShowResults`. Differiscono solo per colonne e mapping.

> **Fix:** Unificare in `TdlgResultViewer` configurabile.

### m21. Renumbering off-by-one quando ComicInfo.xml è preservato

**File:** `src/uzipeditor.pas:556-577` — Quando `RemoveComicInfo=False` e `RenumberPages=True`, il counter `PageNum` viene incrementato per ComicInfo.xml, causando la prima immagine a diventare `page_0002` invece di `page_0001`.

### m22. Posizionamento bottoni assoluto e inconsistente tra dialog

Coordinate pixel diverse per OK/Cancel in ogni dialog. Alcuni usano `Anchors := [akTop, akRight]`, altri no.

---

## Test Coverage

### Unit con test

| Unit | Test file | Note |
|------|-----------|------|
| `uservicevalidate` | `test_uservicevalidate.pas` | Coperto |
| `uservicemerge` | `test_uservicemerge.pas` | Coperto |
| `uservicecomicinfo` | `test_uservicecomicinfo.pas` | Coperto |
| `uzipeditor` | `test_uzipeditor.pas` | Coperto |

### Unit senza test (testabili)

| Unit | Testabilità | Note |
|------|-------------|------|
| **ucomicinfo** | Alta | Funzioni pure XML — gap più grave |
| **userviceconvert** | Alta | Stesso pattern dei servizi testati |
| **uservicebase** | Alta | Fondazione di tutti i servizi (BackupFile, CollectCBZFiles, ReplaceCBZ) |
| **uPageEditModel** | Media | Thread richiede setup |
| **ulog** | Bassa | Infrastruttura |

### Unit non testabili (GUI)

`uwebp` (dipende da DLL), `uloaderthread` (GUI-dependent), `uthreadservice` (thin wrapper), tutti i `udlg*.pas`, `main.pas`.

### Edge case mancanti nei test esistenti

- **IsImageExt**: nessun test case-insensitive (`.PNG`, `.Jpg`)
- **Merge Force=True**: path non testato (capitoli residui nell'ultimo volume)
- **Merge GenerateComicInfo=True**: branch intero non testato
- **Merge con ChaptersList custom**: mai esercitato
- **Validate multi-file**: tutti i test passano un singolo file
- **ValidateDeep partial failure**: CBZ con immagini miste valide/corrotte non testato
- **ComicInfo case sensitivity**: `COMICINFO.XML` mai testato
- **FilterPagesFromCBZ**: funzione pubblica completamente non testata
- **FormatPageName**: testato solo implicitamente

### Problemi qualità test

- 5 assertion `<> ''` su ErrorMsg — non verificano il contenuto specifico
- `TestValidateCBZImages`: 3 scenari in un unico metodo (se il primo fallisce, gli altri non vengono eseguiti)
- Riuso `TMemoryStream` condiviso tra entry in `Merge_TwoChapters` — fragile
- Boilerplate `SetLength(Files, 1); Files[0] := ...` ripetuto ovunque — manca helper `MakeFileArray`

---

## Priorità di Refactoring

| Priorità | Intervento | Impatto | Effort |
|----------|-----------|---------|--------|
| **P0** | Fix memory leak: try/except con FreeZipEntries(Result) in uzipeditor | Correttezza | Piccolo |
| **P0** | Fix bug SkipExistingWebP | Correttezza | Piccolo |
| **P0** | Controllare return value di BackupFile prima di sovrascrivere | Sicurezza dati | Piccolo |
| **P0** | WriteComicInfoToCBZ: usare pattern atomico ReplaceCBZ | Sicurezza dati | Piccolo |
| **P1** | Estrarre TPageEditController da main.pas | Testabilità, SRP | Grande |
| **P1** | Decomporre ConvertCBZToWebP in funzioni più piccole | Leggibilità, bug | Medio |
| **P1** | Aggiungere test per ucomicinfo (roundtrip XML) e userviceconvert | Copertura test | Medio |
| **P1** | Separare uzipeditor in uzipcore + ucbzimages | SRP, modularità | Medio |
| **P2** | Creare TBaseDialog per eliminare boilerplate duplicato | DRY | Medio |
| **P2** | Unificare thread launch/terminate con helper generico | DRY | Medio |
| **P3** | Definire costanti per magic numbers e stringhe ripetute | Manutenibilità | Piccolo |
| **P3** | Uniformare naming (ErrorMsg vs Message vs Error, file casing) | Coerenza | Piccolo |
| **P3** | Rimuovere dead code (FThumbW/H, CreatedFiles, TImageCheckResult) | Pulizia | Triviale |

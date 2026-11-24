# Handoff fra il coordinatore del porting di STAI (claude.ai) e l'agente locale

## Protocollo

- Branch: `stai/porting` su `pandaro/Beyond-All-Reason`. Il coordinatore scrive qui il compito; l'agente locale lo esegue e scrive qui i risultati.
- Quando l'utente scrive «esegui»:
  1. `git pull` su `stai/porting`;
  2. leggi «Compito attuale» ed eseguilo, rispettando `CLAUDE.local.md` e `.github/agents.md`;
  3. scrivi i risultati sotto «Risultati», con intestazione `### S<n> (agente locale, <data>)` (cosa hai fatto, file toccati, numeri, problemi, domande);
  4. commit e push su `stai/porting`, poi fermati e di' all'utente «fatto».
- «esegui» autorizza i commit e il push su `stai/porting` previsti dal compito. Mai push su `master`, mai PR, mai force push.
- `.ai-notes/` è escluso da git sulla macchina locale: per questi file usa `git add -f`. Prima di `git add -A` o `git commit -a` segui la skill `submodule-pointer`.
- `.ai-notes/stai/nuovo-stai.md` lo aggiorna il coordinatore, non modificarlo.
- Tutto ciò che va nel repository è in inglese: messaggi di commit, commenti, nomi, log, test. Solo `.ai-notes/` resta in italiano.
- Un cambio al framework (`shard_runtime/`, `ShardAILoader.lua`) solo se il compito lo chiede, in un commit a parte che inizia con «Shard …».
- Test con l'engine vero: `.ai-notes/tools/run_engine_tests.sh`; il `PASS` del test runner di BAR non conta. Partite: `.ai-notes/tools/run_engine_game.sh`.
- Strumenti fissati: StyLua 2.5.2 ed EmmyLua 0.24.0 (`emmylua_check`) in `~/.local/bin`, da chiamare con il percorso intero; `lx` è in `/usr/local/bin`. `lx test` riscrive `.emmyrc.json`: ripristinalo, non committarlo.

## Compito attuale

### S3: pulizia di `MapHST`

**Impegno: medio.** Primo passo dei «fondamenti» (`nuovo-stai.md` §5 n. 3, punto 2). `MapHST` resta `"team"`; **il gioco non deve cambiare**: si toglie solo codice che nessuno chiama e si spostano due funzioni che non sono di mappa. I difetti trovati (punto 15) **non** si correggono qui.

**1. Codice morto da togliere da `maphst.lua`** (il coordinatore ha controllato con grep che nessuno li chiama; ricontrolla prima di togliere ciascuno, anche nei file fuori da `STAI/`)

- funzioni: `PosToHeightMap`, `HeightMapToPos`, `PosToNodeIndex`, `NodeIndexToGrid`, `NormalizeHeighMapIndex`, `NodeIndexToPos`, `NodeIndexToHeighMap`, `InitPathCost` (e la sua chiamata commentata in `Init`), `SetStartLocation`, `GuessStartLocations`, `MergePositions`, `GetPathGraph` (con `local pathGraphs` e `local mCeil`; in `attackhst.lua` r. 110 e `raidhst.lua` r. 112 ci sono solo chiamate commentate: togli anche quelle righe), `ClosestFreeGeo`, `MobilitynetworkSizeHere`, `AccessibleMetalSpotsHere`, `AccessibleGeoSpotsHere`, `IsUnderWater`;
- campi mai letti: `waterMetals`, `groundMetals` (con il ramo `map:CanBuildHere` in `metalScan` che li riempie e l'assegnazione `self.ai.armyhst.UWMetalSpotCheckUnitType` in `Init`, usata solo lì), `startLocations`;
- il controllo `map_loaded` in `Init` (ogni istanza è nuova: non scatta mai);
- blocchi commentati: l'`Update` (r. 101–121), `gridThePathBackup` in fondo al file, la vecchia versione commentata dentro `ClosestFreeMex`;
- in `damagehst.lua` le righe commentate che citano funzioni tolte (r. 101–108 circa).

**Restano** (servono a qualcuno): `GridToNodeIndex` (la usa `DamageHST`; la sostituirà l'indice di `GridHST`), `isInMap`, `RawPosIsInMap`, `GridToRawPos`, `getPath`, `gridThePath`, `topology`, `TopologyFooded`, tutte le funzioni di griglia, `MobilityNetworkHere`, `MobilityOfUnit`, `UnitCanGoHere`, `UnitCanGetToUnit`, `AccessibleSpotsHere`, `DrawDebug`, `basicMapInfo` com'è. `astarclass.lua` e `UWMetalSpotCheckUnit` in `armyhst.lua` restano anche se dopo questo compito nessuno li usa: scrivilo nei risultati.

**2. Funzioni che passano in `BuildingsHST`** (decisione dell'utente)

- `ClosestFreeMex` → `BuildingsHST:ClosestFreeMex`, stessa firma e stesso corpo; le chiamate a `self:MobilityOfUnit`, `self:GetCell`, `self:UnitCanGoHere` diventano `self.ai.maphst:…`, `self.ai.buildingshst:PlansOverlap` diventa `self:PlansOverlap`. Chiamante: `buildersbst.lua` r. 295.
- `UnitMexMoveTest` → `BuildingsHST:UnitMexMoveTest`; chiamante: `commanderbst.lua` r. 14. Il valore `trampled` **esce dalle celle di `MapHST`** (via `cell.trampled = 0` da `NewCell`, via le righe di `trampled` da `MapHST:DrawDebug`) e va in una tabella di `BuildingsHST`, `self.trampled[X][Z]`, con 0 in ogni cella prima del conteggio. Per non cambiare niente:
  - scorri le celle **nello stesso ordine** di oggi: `X` da 1 a `gridSideX`, dentro `Z` da 1 a `gridSideZ` (oggi `pairs` su tabelle-array, che va in quest'ordine);
  - `self.trampledCells` si crea **in `BuildingsHST:Init`** (`{}`) e `UnitMexMoveTest` ci **aggiunge** le posizioni (`self.ai.maphst.GRID[X][Z].POS`) senza sostituire la tabella: `TasksHST` ne tiene il riferimento (`taskshst.lua` r. 653, 1094, 1104, da cambiare in `self.ai.buildingshst.trampledCells`). Controlla che `BuildingsHST:Init` giri prima del punto in cui `TasksHST` legge il riferimento;
  - stesse formule, stessa soglia (`average * 1.5`), stesso `nil` sulle celle sotto soglia; `self.ttt` può diventare locale.

**3. Prova che il gioco non cambia** (modifica temporanea, **non committata**)

Aggiungi in fondo a `UnitMexMoveTest` un `Spring.Echo` con: numero di `trampledCells`, somma delle `x` e delle `z` delle posizioni, `average`; e in fondo a `MapHST:Init` uno con `#self.METALS`, `#self.GEOS`, `#self.hotSpots` e il numero di zone per ogni `layer` di `self.networks`. Fai **una partita A col codice di prima** (`git stash` o il commit di partenza) e **una col codice nuovo**, stessa partita: le righe devono essere identiche. Riporta le righe nei risultati, poi togli gli `Echo`.

**Partite**: oltre alle due della prova, una partita C (`c_stai_vs_stai.txt`): unità e mex di tutte e due le STAI, righe `[AI Loader] error`. Le tre partite A non servono (il gioco non cambia); se la prova del punto 3 dà righe diverse, **fermati** e scrivi cosa cambia.

**Controlli**: `grep` finale dei nomi tolti in tutto il repository (solo `.ai-notes/` può citarli); `lx --lua-version 5.1 test`, `run_engine_tests.sh`; StyLua 2.5.2 ed EmmyLua 0.24.0 sui file toccati (nessun errore nuovo). `.emmyrc.json` ripristinato.

**Commit**, in inglese: uno per il codice morto («STAI MapHST: remove unused code»), uno per lo spostamento in `BuildingsHST`, uno per i risultati. Righe tolte e aggiunte per file nei risultati.

## Risultati

### S2 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Cosa ho fatto** (commit `bf496c6431`, «STAI: run modules and behaviours in turns through the framework scheduler»)

- `STAI/ai.lua`: `STAI.MScheduler` e `STAI.BScheduler` copiati da `SchedulerHST`, stessi nomi e stesso ordine, `OverviewHST` e `BomberBST` commentati come prima.
- `git rm STAI/schedulerHST.lua`; tolti `shard_include("schedulerhst")` e `SchedulerHST` da `STAI/modules.lua`.
- Tolti i 20 controlli di turno: moduli `EcoHST`, `LosHST`, `TargetHST`, `DamageHST`, `ScoutHST`, `AttackHST`, `RaidHST`, `BomberHST`, `LabsHST`; behaviour `BootBST`, `CommanderBST`, `BuildersBST`, `EngineerBST`, `LabsBST`, `ScoutBST` (`Update`), `RaidBST`, `AttackerBST`, `ReclaimBST`, `CleanerBST`, `NukeBST`.
- Codice prima del controllo: solo `local f = self.game:Frame()` in `CleanerBST`, `CommanderBST`, `AttackerBST`, `RaidBST`, `ReclaimBST`, `EngineerBST` (una lettura, nessun effetto). Nessun contatore né timer prima di un controllo: nessuna decisione da prendere. `CleanerBST.frameCounter` è solo inizializzato in `Init`, mai letto.
- `MexUpBST`: `self.ai.schedulerhst.` → `self.ai.scheduler.` (2 riferimenti), il resto com'è. `BomberBST`, `ScoutBST:Draw`, `overviewhst.lua` r. 18 non toccati.
- `grep -rn schedulerhst luarules/gadgets/ai/STAI`: 3 righe, `scoutbst.lua:243` (`Draw`), `overviewhst.lua:18` e `bomberbst.lua:63` (commenti).
- File toccati: `ai.lua`, `modules.lua`, `schedulerHST.lua` (tolto), `mexupbst.lua` e i 20 file sopra.

**Da segnalare: `AntinukeBST`.** È in `BScheduler` ma il suo `Update` (`SetStock`, ordine `STOCKPILE` se `stock + pile < 2`) **non aveva il controllo di turno**: con `SchedulerHST` girava ogni frame. Ora il runtime lo chiama solo nel suo turno (una volta ogni 12 frame con una STAI, ogni 24 con due). Ho tenuto la lista identica come chiede il compito, quindi qui il comportamento cambia. Prima girava ogni frame mandando lo stesso ordine finché il relay non aggiornava `pile` (probabilmente più `STOCKPILE` in coda), ora al massimo uno ogni giro. Per tenerlo uguale bisognerebbe toglierlo da `BScheduler`, ma così il giro scenderebbe a 11 e cambierebbe il turno di `NukeBST`. **Domanda**: va bene così, o lo tolgo dalla lista?

**Test**: nessun test di STAI usa `SchedulerHST`. `lx --lua-version 5.1 test`: 2728 successi, 0 falliti, 1 pending. `run_engine_tests.sh`: `RESULT: ok`. StyLua 2.5.2 sui file toccati: ok. EmmyLua 0.24.0: 20 errori, gli stessi di sempre. `.emmyrc.json` ripristinato.

**Tre partite A** (`SHARD_MEM_STATS=1`, 15 minuti, uscita 0 tutte e tre)

| | partita 1 | partita 2 | partita 3 | S1 (intervallo) |
| --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 5 / 35 / 87 / 136 | 6 / 39 / 92 / 137 | 5 / 37 / 97 / 162 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14) | 141 unità, 1 fabbrica, 26 mex | 143, 2, 14 | 179, 2, 33 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 140, 2, 23 | 141, 2, 11 | 196, 2, 36 | — |
| relay: messaggi | 3222 | 3899 | 3717 | 3405–3933 |
| relay: ordini dati | 12063 | 16249 | 16454 | 10445–15948 |
| relay: ordini rifiutati | 21 | 20 | 4 | 9–16 |
| messaggi rifiutati per motivo | nessuno | nessuno | nessuno | nessuno |
| memoria per frame, medie per minuto | 0,18–0,55 (media 0,34) | 0,19–0,67 (0,44) | 0,18–0,73 (0,39) | 0,18–0,90 (0,37–0,45) |
| memoria per frame, picco | 98,8 KB (ultimo, dopo `SUMMARY`) | 84,4 KB (min. 14) | 84,9 KB (min. 11) | 67,9–73,5 KB |
| heap | 13,0–14,6 MB | 13,1–15,8 MB | 13,0–14,6 MB | 13,1–15,5 MB |
| righe `[AI Loader] error` | 0 | 0 | 0 | 0 |
| tempo reale | 20 s | 19 s | 20 s | 19–21 s |

- Nessuna condizione di arresto: le unità (141/143/179) e i mex (26/14/33) non stanno **tutti** sotto il minimo di S1 (141 unità, 23 mex). Al minuto 13 le unità sono tutte nell'intervallo di S1.
- Da notare: la partita 2 ha 14 mex al minuto 14 (11 a fine), sotto i 15 dei riferimenti in §6; i rifiutati di 1 e 2 (21, 20) sono un po' sopra i 9–16 di S1 (ordini singoli, nessun messaggio rifiutato); i picchi di memoria per frame (84–99 KB) sono più alti di S1 (68–74), sotto quelli di T14 (159). Le medie sono uguali. Con tre partite non lo distinguo dalla variabilità.
- Al minuto 1 due partite hanno 5 unità e 0 fabbriche (S1: 6): la prima fabbrica parte qualche secondo più tardi, poi le unità al minuto 5 sono nell'intervallo.
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown). Nessuno cita Shard o STAI.

**Partita C** (`c_stai_vs_stai.txt`, 15 minuti, senza `SHARD_MEM_STATS`, uscita 0, 21 s): tutte e due le STAI ospitate dal giocatore 0 (`AI team 0/1 hosted by player 0`), quindi un solo scheduler che fa ruotare due team.

| | team 0 STAI | team 1 STAI |
| --- | --- | --- |
| unità min. 1 / 5 / 10 / 13 | 6 / 36 / 85 / 136 | 6 / 37 / 88 / 120 |
| min. 14 | 145 unità, 2 fabbriche, 25 mex | 131, 2, 22 |
| `SUMMARY` | 165, 2, 28 | 142, 2, 24 |

- Relay: 3986 messaggi, 23929 ordini, 29 rifiutati; nessun messaggio rifiutato. 0 righe `[AI Loader] error`, solo gli errori di sempre. Le due STAI crescono allo stesso ritmo, quindi la rotazione dà i turni a tutte e due.

**Controlli**: `git status` pulito a parte questo file.

### S1 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**1. Istruzioni locali** (`CLAUDE.local.md`, un solo file, non committato): fase attuale «porting di STAI»; il protocollo ora rimanda per primo a `.ai-notes/stai/handoff.md` sul branch `stai/porting` («esegui» o «vai»: pull, compito S<n>, risultati qui, commit e push), con commit di framework a parte che iniziano con «Shard …» e `nuovo-stai.md` riservato al coordinatore; il protocollo `shard/fase1` è segnato come chiuso. `git add -f` vale per tutti i file tracciati di `.ai-notes/`; l'impegno si riferisce ai compiti di questo file. Le decisioni numerate sono invariate.

**2. Partenza**: `HEAD` = `origin/stai/porting` = `9d112fd841`. `lx --lua-version 5.1 test`: 2728 successi, 0 falliti, 1 pending. `run_engine_tests.sh`: `RESULT: ok`. `.emmyrc.json` ripristinato.

**3. Tre partite A** (`SHARD_MEM_STATS=1`, 15 minuti, uscita 0 tutte e tre)

| | partita 1 | partita 2 | partita 3 |
| --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6 / 41 / 101 / 159 | 6 / 25 / 54 / 117 | 6 / 39 / 95 / 141 |
| fine partita (min. 14, l'ultimo riportato) | 186 unità, 2 fabbriche, 35 mex | 141, 2, 23 | 161, 2, 29 |
| relay: messaggi | 3933 | 3545 | 3405 |
| relay: ordini dati | 15948 | 10445 | 14569 |
| relay: ordini rifiutati | 9 | 15 | 16 |
| messaggi rifiutati per motivo | nessuno | nessuno | nessuno |
| memoria per frame, medie per minuto | 0,18–0,90 KB (media 0,45) | 0,19–0,59 (0,37) | 0,18–0,78 (0,38) |
| memoria per frame, picco | 73,5 KB (min. 12) | 70,2 KB (min. 13) | 67,9 KB (min. 13) |
| heap | 13,1–15,3 MB | 13,1–15,5 MB | 13,1–15,0 MB |
| righe `[AI Loader] error` | 0 | 0 | 0 |
| tempo reale | 21 s | 19 s | 19 s |

- Nessuna riga `Shard relay: N messages rejected (…)`: quindi `excluded = 0` e `count = 0`, nessun gruppo oltre 20 ordini. I rifiutati (9–16) sono ordini singoli per unità non valide o di un altro team, dentro messaggi accettati.
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown). Nessuno cita Shard o STAI.
- Confronto con §6: tutte dentro i riferimenti (141–186 unità, 23–35 mex, 10–16 mila ordini, 9–16 rifiutati, heap 13–15,5 MB). La partita 2 è al limite basso (141 unità, ordini 10.445 sotto il «circa 15.000»), ma niente sotto le soglie di arresto. La media mensile di memoria della partita 1 arriva a 0,90 KB nell'ultimo minuto, poco sopra 0,7; i picchi per frame (68–74 KB) stanno fra T15 (74) e T14 (159).
- Il tempo reale è quello di `run_engine_game.sh`, headless senza limite di velocità.

**Controlli**: `git status` pulito a parte questo file.


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
- Il codice di STAI nuovo o spostato segue lo **stile di STAI** (`nuovo-stai.md` §7): leggilo prima di ogni compito.
- Un cambio al framework (`shard_runtime/`, `ShardAILoader.lua`) solo se il compito lo chiede, in un commit a parte che inizia con «Shard …».
- Test con l'engine vero: `.ai-notes/tools/run_engine_tests.sh`; il `PASS` del test runner di BAR non conta. Partite: `.ai-notes/tools/run_engine_game.sh`.
- Strumenti fissati: StyLua 2.5.2 ed EmmyLua 0.24.0 (`emmylua_check`) in `~/.local/bin`, da chiamare con il percorso intero; `lx` è in `/usr/local/bin`. `lx test` riscrive `.emmyrc.json`: ripristinalo, non committarlo.

## Compito attuale

### S4a: `GridHST`, la geometria

**Impegno: alto.** Nasce `GridHST` (`nuovo-stai.md` punto 5, §5 n. 4). Qui **solo la geometria**: le griglie di oggi restano `[X][Z]`, cambia solo chi fa i conti. **Il gioco non deve cambiare.** Gli strati sono S4b. **Stile**: `nuovo-stai.md` §7.

**1. File nuovo `STAI/gridhst.lua`**

- `GridHST = class(Module)`, `Name` `"GridHST"`, `internalName` `"gridhst"`, `Scope` `"team"` (diventa `"global"` con `MapHST` più avanti). In `modules.lua` incluso e messo nella lista **prima di `MapHST`**.
- `Init` come macro, prima riga `self.DebugEnabled = false`, poi i passi (nomi indicativi, nel tuo stile): `self:basicGridInfo()`, `self:createCells()`.
- `basicGridInfo`: misure della mappa in elmo prese da `map:MapDimensions()` (come `MapHST:basicMapInfo`) e **`self.gridSize = 256`, l'unico punto in tutto STAI dove sta la misura della cella** (commento a fine riga che lo dice), poi `gridSizeHalf`, `gridSizeDouble`, `gridSideX`, `gridSideZ`, `gridArea` con le stesse formule di oggi.
- `createCells`: **`self.CELLS[i]`** per tutte le celle, una volta sola, cicli `X` 1..`gridSideX`, dentro `Z` 1..`gridSideZ`; ogni cella `INDEX`, `X`, `Z`, `POS` (`POS` calcolato come oggi in `MapHST:NewCell`: centro della cella, `y` con `GetGroundHeight`), campo per campo.
- Indice: `i = (X - 1) * gridSideZ + Z`. Funzioni nuove: `GridToIndex(X, Z)`, `PosToIndex(pos)`, `RawPosToIndex(x, z)`; all'indietro si legge `self.CELLS[i].X` / `.Z` (niente funzione).

**2. Da `MapHST` passano in `GridHST`**, con lo **stesso nome, stessa firma, stesso corpo, stesso commento**: `PosToGrid`, `RawPosToGrid`, `GridToPos`, `GridToRawPos`, `IsCellInGrid`, `areaCells`, `GetCell`, `getCellsFields`, e `isInMap`, `RawPosIsInMap` (servono a `GridToPos` / `GridToRawPos`; senza di loro `GridHST` dipenderebbe da `MapHST`, che dipende da `GridHST`).
- `PosToGrid` e `RawPosToGrid` oggi controllano `self.GRID[X][Z]` di `MapHST` solo per un `EchoDebug`: in `GridHST` usa `IsCellInGrid` (stessa condizione: `GRID` è pieno).
- **Tolti** da `MapHST`: le funzioni sopra, i campi della griglia in `basicMapInfo` (`gridSize` … `gridArea`) e `GridToNodeIndex`. `MapHST` tiene le sue misure in elmo (`elmoMapSizeX`, `elmoMapCenter`, …), usate da altri. Dentro `MapHST` (`createGrid`, `NewCell`, `TopologyFooded`, `SimplifyMetalSpots(self.gridSize * 2)`, `DrawDebug`, `metalScan`, `geoScan`, `MobilityNetworkHere`…) i conti passano a `self.ai.gridhst`. `NewCell` prende `POS` dalla cella di `GridHST` (`self.ai.gridhst.CELLS[i].POS`, stessa tabella) invece di ricalcolarlo.
- **Chiamanti da aggiornare** (`self.ai.maphst:` / `.` → `self.ai.gridhst:` / `.`), contati dal coordinatore: `attackhst`, `buildingshst`, `commanderbst`, `damagehst`, `labsbst`, `labshst`, `loshst`, `nukebst`, `raidhst`, `scoutbst`, `scouthst`, `targethst`. Ricontrolla con grep: alla fine nessun `maphst` per questi nomi.
- `DamageHST`: `nodeCostIndex = self.ai.maphst:GridToNodeIndex(X, Z)` → `self.ai.gridhst:GridToIndex(X, Z)` (usato solo nel testo di `Draw`).

**3. Test busted** di `GridHST`, se si riesce a caricarla da sola con un `map` finto (o con `shard_null`): andata e ritorno indice ↔ `X`, `Z` su una griglia **non quadrata**; prima e ultima cella; `PosToIndex` sul bordo di una cella; `IsCellInGrid` fuori dai bordi. Mutazioni (per esempio `gridSideX` al posto di `gridSideZ` nella formula). Se non si riesce senza toccare il framework, scrivi perché e non toccarlo.

**4. Prova che il gioco non cambia**: come in S3, `Echo` temporanei **non committati** (le righe `[S3-PROOF]` di S3, più in fondo a `GridHST:Init` `gridSideX`, `gridSideZ`, numero di `CELLS`, somma di tutti gli `INDEX`), partita `c_stai_vs_stai.txt` di 2 minuti col codice di partenza e col codice nuovo: le righe `[S3-PROOF]` identiche (quella di `GridHST` c'è solo nel nuovo; la somma degli `INDEX` deve essere `n·(n+1)/2`). Se cambiano, **fermati**.

**Partite**: oltre alla prova, una partita C di 15 minuti (unità e mex di tutte e due le STAI, errori).

**Controlli**: StyLua 2.5.2, EmmyLua 0.24.0 (nessun errore nuovo), `lx --lua-version 5.1 test`, `run_engine_tests.sh`; `.emmyrc.json` ripristinato.

**Commit**, in inglese: uno per `GridHST` e lo spostamento, uno per i test (se ci sono), uno per i risultati. Righe per file nei risultati.

## Risultati

### S4a (agente locale, 25 novembre 2026) — verificato dal coordinatore

**Cosa ho fatto**

- Commit `3868bef297` «STAI: move the grid geometry from MapHST to a new GridHST».
  - `STAI/gridhst.lua` nuovo: `GridHST = class(Module)`, `Scope` `"team"`; `Init` come macro (`self.DebugEnabled = false`, `basicGridInfo`, `createCells`). `basicGridInfo` prende `elmoMapSizeX`/`Z` da `map:MapDimensions()` (servono a `isInMap` e `RawPosIsInMap`, così `GridHST` non legge `MapHST`), `self.gridSize = 256 --the only place in STAI that holds the cell size`, poi `gridSizeHalf` … `gridArea` con le formule di prima e l'`EchoDebug` «grid size» che stava in `MapHST`. `createCells`: `self.CELLS[i]` con cicli `X` 1..`gridSideX`, dentro `Z` 1..`gridSideZ`; `POS` come in `NewCell` (stesse righe, `map:GetGroundHeight`, che chiama `Spring.GetGroundHeight`) e campo per campo `INDEX`, `X`, `Z`, `POS`. La chiamata `self:isInMap(cellPos) --move here ,is in map!!` di `NewCell` è passata qui (serve solo all'`EchoDebug`).
  - Nuove `GridToIndex(X, Z)` = `(X - 1) * self.gridSideZ + Z`, `PosToIndex(pos)`, `RawPosToIndex(x, z)`. **Scelta mia**: le due `…ToIndex` da posizione danno `nil` fuori dalla griglia (`IsCellInGrid`), perché fuori dai bordi l'indice cadrebbe su un'altra cella (per esempio `Z = 0` → ultima cella della colonna prima); `GridToIndex` non controlla (la chiamano cicli su coordinate valide). Dimmi se le vuoi senza controllo.
  - Spostate con stesso nome, firma, corpo e commento: `PosToGrid`, `RawPosToGrid`, `GridToPos`, `GridToRawPos`, `IsCellInGrid`, `areaCells`, `GetCell`, `getCellsFields`, `isInMap`, `RawPosIsInMap` (con il `pos` inesistente nel debug, difetto del punto 15, lasciato com'è). In `PosToGrid`/`RawPosToGrid` il controllo per l'`EchoDebug` è `IsCellInGrid`.
  - `MapHST`: tolte le funzioni sopra, `GridToNodeIndex` e i campi della griglia di `basicMapInfo`; i conti di `Init` (`SimplifyMetalSpots`), `createGrid`, `NewCell`, `gridAnalisy`, `LayerScan`, `TopologyFooded`, `metalScan`, `geoScan`, `gridThePath`, `MobilityNetworkHere`, `DrawDebug` passano a `self.ai.gridhst`. `NewCell` prende `cellPos = self.ai.gridhst.CELLS[self.ai.gridhst:GridToIndex(gx, gz)].POS` (stessa tabella).
  - **Da segnalare**: in `DrawDebug` il testo della cella era `((X - 1) * gridSideX) + Z` (lo stesso errore di `GridToNodeIndex`); l'ho messo `self.ai.gridhst:GridToIndex(X, Z)`, come per `DamageHST`. Solo disegno di debug (`ai.drawDebug`).
  - `modules.lua`: `shard_include("gridhst")` e `GridHST` subito prima di `MapHST`. `GridHST` non ha eventi né `Update`, quindi gli handler e i turni dello scheduler non cambiano.
  - Chiamanti aggiornati: `attackhst`, `buildingshst`, `commanderbst`, `damagehst` (anche `nodeCostIndex = self.ai.gridhst:GridToIndex(X, Z)`), `labshst`, `loshst`, `nukebst`, `raidhst`, `scoutbst`, `scouthst`, `targethst`. `labsbst` nel conteggio del coordinatore: l'unico riferimento è la riga commentata morta r. 281 (`maphst.gridArea`, con `mobilityCount` e `UWMetalSpots` che non esistono più): non l'ho toccata; è l'unica riga che il grep finale trova ancora. In `loshst` sono cambiate anche due righe commentate (`-- if not self.ai.gridhst:GridToPos(X,Z)`) e il commento a fine r. 282. `raidhst` r. 397/420 usa `local maphst` solo per `UnitCanGoHere`, che resta in `MapHST`.
- Commit `910603182b` «STAI: test the GridHST geometry»: `spec/luarules/gadgets/ai/STAI/gridhst_spec.lua`, carica `class`, `AIBase`, `Module` e `gridhst.lua` in un ambiente con un `map` finto, senza toccare il framework. Griglia 6×4 (non quadrata): misure; andata e ritorno indice ↔ `X`, `Z` su tutte le celle, nessun indice doppio né mancante; `i + 1` = `Z + 1`, `i + gridSideZ` = `X + 1`; prima e ultima cella con `POS` (altezza finta `x + z/1000`, così si vede dove è letta); `PosToIndex`/`RawPosToIndex` sul bordo di una cella (256 → cella 1, 257 → la successiva) e sull'angolo della mappa; `IsCellInGrid` e `…ToIndex` fuori dai quattro bordi.
- **Mutazioni** (12, tutte fanno fallire il test): `gridSideX` al posto di `gridSideZ` nell'indice; `floor` al posto di `ceil` in `PosToGrid` e `RawPosToGrid`; `>=` al posto di `>` e `Z < 0` in `IsCellInGrid`; `POS.z` da `X`; `POS` senza mezza cella; `gridSideZ` da `elmoMapSizeX`; controllo tolto in `PosToIndex` e in `RawPosToIndex`; `x`, `z` scambiate in `RawPosToIndex`; `x`, `z` scambiate in `GetGroundHeight`.

**Righe per file**

| commit | file | + | − |
| --- | --- | --- | --- |
| `3868bef297` | `gridhst.lua` (nuovo) | 194 | 0 |
| | `maphst.lua` | 15 | 150 |
| | `modules.lua` | 2 | 0 |
| | `attackhst.lua` | 7 | 7 |
| | `buildingshst.lua` | 10 | 10 |
| | `loshst.lua` | 10 | 10 |
| | `raidhst.lua` | 10 | 10 |
| | `targethst.lua` | 5 | 5 |
| | `damagehst.lua` | 4 | 4 |
| | `scoutbst.lua` | 4 | 4 |
| | `scouthst.lua` | 3 | 3 |
| | `labshst.lua` | 2 | 2 |
| | `commanderbst.lua` | 1 | 1 |
| | `nukebst.lua` | 1 | 1 |
| `910603182b` | `spec/luarules/gadgets/ai/STAI/gridhst_spec.lua` | 100 | 0 |

`maphst.lua`: da 623 a 488 righe.

**Prova che il gioco non cambia** (`Echo` temporanei, non committati; `c_stai_vs_stai.txt`, 2 minuti)

Codice di partenza `3d68ef9014`: righe identiche a quelle di S3. Codice nuovo:

```
[S3-PROOF] grid, 0, 32, 24, 768, 295296, 295296
[S3-PROOF] map, 0, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] grid, 1, 32, 24, 768, 295296, 295296
[S3-PROOF] map, 1, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] trampled, 1, 79, 406400.0000000000 296576.0000000000 2.118384599685669
[S3-PROOF] trampled, 0, 68, 208640.0000000000 141568.0000000000 2.246112346649170
```

- `grid` = team, `gridSideX`, `gridSideZ`, `#CELLS`, somma degli `INDEX`, `n·(n+1)/2`: 768 celle, somma 295296 = 768·769/2. Anche la mappa vera ha una griglia non quadrata (32×24).
- Senza le righe `grid`, `diff` con la partenza vuoto. `Echo` tolti; nessuna riga di prova nei commit.

**Partita C** (`c_stai_vs_stai.txt`, 15 minuti, codice finale, uscita 0, 21 s): tutte e due le STAI ospitate dal giocatore 0.

| | team 0 STAI | team 1 STAI |
| --- | --- | --- |
| unità min. 1 / 5 / 10 / 13 | 7 / 36 / 79 / 111 | 6 / 36 / 89 / 136 |
| mex min. 5 / 10 / 13 | 5 / 13 / 17 | 6 / 15 / 24 |
| min. 14 | 123 unità, 1 fabbrica, 19 mex | 151, 2, 25 |
| `SUMMARY` | 136, 2, 20 | 156, 2, 28 |

- Relay: 4050 messaggi, 22569 ordini, 29 rifiutati; nessun messaggio rifiutato. 0 righe `[AI Loader] error`; errori solo quelli di sempre (`gui_pip` `CreateShader`, `gui_sensor_ranges_jammer_preview` in Shutdown, `AdvSky`, …), nessuno cita Shard o STAI. Nel log `adding GridHST module` subito prima di `adding MapHST module` per tutti e due i team.
- Come in S3 il team 0 resta indietro (qui dal minuto 10); l'inizializzazione è identica, quindi lo attribuisco alla variabilità.

**Controlli**

- grep finale dei nomi spostati con `maphst` in tutto il repository: solo `labsbst.lua` r. 281 (commento morto, sopra).
- `lx --lua-version 5.1 test`: 2734 successi (+6), 0 falliti, 1 pending. `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 su tutti i file toccati: ok.
- EmmyLua 0.24.0: 20 errori, gli stessi della base. Avvisi per file STAI uguali alla base tranne `maphst.lua` 9 → 11: due `need-check-nil` su `network.area` (`LayerScan`, `TopologyFooded`), perché `area = self.ai.gridhst.gridArea` non ha un tipo noto all'analizzatore. `gridhst.lua`: 0 avvisi, 8 hint (variabili inutilizzate del codice spostato); il test: nessuno. Il totale dell'albero non è confrontabile: due esecuzioni sullo stesso albero danno 23517 e 23469 avvisi (264 righe diverse nell'elenco per file, in file non toccati), la base 23130.
- `.emmyrc.json` ripristinato; `git status` pulito a parte questo file.

### S3 (agente locale, 25 novembre 2026) — verificato dal coordinatore. Nota: la `collect` di `MapHST:Init` **non** è contro le regole: è una decisione aperta dell'utente (`nuovo-stai.md` §4 n. 5), resta finché non decide

**Cosa ho fatto**

- Commit `84b5a964a9` «STAI MapHST: remove unused code»: tolto da `maphst.lua` tutto l'elenco del punto 1 (le 19 funzioni, `pathGraphs`, `mCeil`, la chiamata commentata a `InitPathCost`, `waterMetals`, `groundMetals` col ramo `map:CanBuildHere` di `metalScan`, `UWMetalSpotCheckUnitType`, `startLocations`, il controllo `map_loaded` con `self.map_loaded = true`, l'`Update` commentato, `gridThePathBackup`, la vecchia versione commentata dentro `ClosestFreeMex`); in `damagehst.lua` il blocco commentato r. 101–108 (cita `PosToNodeIndex`, `PosToHeightMap`, `SetPathNodeCost`); in `attackhst.lua` e `raidhst.lua` la riga commentata `GetPathGraph`. Ricontrollato ogni nome con grep in tutto il repository prima di toglierlo: nessun chiamante fuori dai punti dell'elenco. Il commit ha solo righe tolte.
- Commit `58a4ff9b2d` «STAI: move ClosestFreeMex and UnitMexMoveTest from MapHST to BuildingsHST»:
  - `BuildingsHST:ClosestFreeMex`: stessa firma, corpo e commento; `self:MobilityOfUnit`, `self:GetCell`, `self:UnitCanGoHere` → `self.ai.maphst:…`, `self.ai.buildingshst:PlansOverlap` → `self:PlansOverlap`, e anche `self.networks` → `self.ai.maphst.networks` (non era nell'elenco, ma serve). Chiamante `buildersbst.lua` r. 295 aggiornato.
  - `BuildingsHST:UnitMexMoveTest`: stessa firma e commento; `self.TRAMPLED[X][Z]`, messo a 0 in ogni cella all'inizio della funzione (cicli numerici `X` 1..`gridSideX`, `Z` 1..`gridSideZ`), conteggio, media e soglia nello stesso ordine con cicli numerici, stesse formule, `nil` sotto `average * 1.5`; `ttt` locale. `METALS`, `getPath`, `PosToGrid`, `elmoMapCenter`, `elmoMapMaxCenterDistance`, `elmoMapMaxDistance`, `GRID[X][Z].POS` letti da `self.ai.maphst`. Chiamante `commanderbst.lua` r. 14 aggiornato.
  - `self.trampledCells = {}` in `BuildingsHST:Init`; `UnitMexMoveTest` ci aggiunge con `table.insert`. `taskshst.lua` r. 653, 1094, 1104 → `self.ai.buildingshst.trampledCells`. Ordine verificato: `ShardAI:Init` chiama gli `Init` nell'ordine di `modules.lua` (`MapHST`, …, `BuildingsHST`, …, `TasksHST`), quindi la tabella esiste quando `TasksHST:startRolesParams` ne prende il riferimento; `UnitMexMoveTest` gira dopo, nell'`Init` di `CommanderBST`.
  - Da `MapHST` tolti `cell.trampled = 0` in `NewCell`, le righe di `trampled` in `DrawDebug`, `self.trampledCells = {}` in `Init`.
  - StyLua ha spezzato su più righe la formula di `TRAMPLED` (oltre 120 colonne con `self.ai.maphst.`): stesso calcolo, stesse parentesi.
- `astarclass.lua` (lo include ancora `tool.lua` r. 1) e `ArmyHST.UWMetalSpotCheckUnit` (`armyhst.lua` r. 838) restano, ma dopo questo compito nessuno usa `GraphAStar` né `UWMetalSpotCheckUnit`.
- `MapHST:Init` tiene `collectgarbage("collect")` (contro le regole del progetto, ma il compito non lo tocca): da togliere in un compito a parte.
- Una differenza solo nel caso d'errore: prima una seconda chiamata a `UnitMexMoveTest` (un secondo `CommanderBST` nello stesso team) andava in errore sulle celle messe a `nil` dalla prima; ora `TRAMPLED` riparte da 0 e `trampledCells` riceve le posizioni una seconda volta. Con un comandante per team non succede.

**Righe per file**

| commit | file | + | − |
| --- | --- | --- | --- |
| `84b5a964a9` | `maphst.lua` | 0 | 445 |
| | `damagehst.lua` | 0 | 8 |
| | `attackhst.lua` | 0 | 1 |
| | `raidhst.lua` | 0 | 1 |
| `58a4ff9b2d` | `buildingshst.lua` | 125 | 0 |
| | `maphst.lua` | 0 | 116 |
| | `taskshst.lua` | 3 | 3 |
| | `buildersbst.lua` | 1 | 1 |
| | `commanderbst.lua` | 1 | 1 |

`maphst.lua`: da 1184 a 623 righe.

**Prova che il gioco non cambia** (`Echo` temporanei, non committati; partita `c_stai_vs_stai.txt` di 2 minuti, due STAI)

Righe `[S3-PROOF]`: `map` = team, `#METALS`, `#GEOS`, `#hotSpots`, zone per layer; `trampled` = team, `#trampledCells`, somma `x`, somma `z`, `average`.

```
[S3-PROOF] map, 0, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] map, 1, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] trampled, 1, 79, 406400.0000000000 296576.0000000000 2.118384599685669
[S3-PROOF] trampled, 0, 68, 208640.0000000000 141568.0000000000 2.246112346649170
```

- A (codice di partenza `f4e632969e`), due esecuzioni: identiche fra loro.
- Dopo il primo commit (solo codice morto): identiche ad A.
- Dopo il secondo commit (spostamento): identiche ad A (`diff` vuoto).
- `Echo` tolti dopo ogni prova; nessuna riga di prova nei commit.

**Partita C** (`c_stai_vs_stai.txt`, 15 minuti, codice finale, uscita 0, 22 s): tutte e due le STAI ospitate dal giocatore 0.

| | team 0 STAI | team 1 STAI |
| --- | --- | --- |
| unità min. 1 / 5 / 10 / 13 | 7 / 35 / 91 / 108 | 6 / 34 / 93 / 129 |
| mex min. 5 / 10 / 13 | 6 / 17 / 14 | 6 / 17 / 25 |
| min. 14 | 114 unità, 2 fabbriche, 16 mex | 143, 2, 24 |
| `SUMMARY` | 118, 2, 18 | 173, 2, 26 |

- Relay: 4301 messaggi, 22292 ordini, 28 rifiutati; nessun messaggio rifiutato. 0 righe `[AI Loader] error`; errori solo quelli di sempre (`gui_sensor_ranges_jammer_preview` in Shutdown e gli altri), nessuno cita Shard o STAI.
- Il team 0 si ferma fra il minuto 11 e il 13 (106 → 108 unità, mex 19 → 14): sta perdendo contro il team 1, che cresce. In S2 le due STAI erano pari; con una sola partita non lo distinguo dalla variabilità, e la prova sopra dice che l'inizializzazione è identica.

**Controlli**

- grep finale dei nomi tolti in tutto il repository (fuori da `.ai-notes/` e `.lux/`): 0 righe; `.trampled` resta solo come `ttt.trampled` in `BuildingsHST`; `mCeil` resta in `astarclass.lua` e `shard_help_draw.lua` (locali loro).
- `lx --lua-version 5.1 test`: 2728 successi, 0 falliti, 1 pending. `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 sui file toccati: ok, a parte due hunk preesistenti di `taskshst.lua` (r. 814, 1050) che non ho scritto né toccato.
- EmmyLua 0.24.0: 20 errori, gli stessi della base. Avvisi per file confrontati con la base `f4e632969e`: `maphst.lua` 20 → 9, `buildingshst.lua` 24 → 26 (i due avvisi che il codice spostato aveva già in `MapHST`: `if waypoints` «always falsy» e `average = sum / count` su un `integer`), gli altri file uguali.
- `.emmyrc.json` ripristinato; `git status` pulito a parte questo file.

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


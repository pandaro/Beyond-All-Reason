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

### S5: `Tool` diviso in libreria e modulo di team; indice del codice tolto

**Impegno: alto.** Decisioni dell'utente del 25 novembre 2026 (`nuovo-stai.md` §4 n. 6 e 8). Serve a S6: `MapHST` diventerà `"global"` e non potrà più usare un modulo di team. **Il gioco non deve cambiare.** **Stile**: `nuovo-stai.md` §7.

**1. La libreria: file nuovo `STAI/toolbox.lua`, tabella `Toolbox`** (nome proposto dal coordinatore; l'utente può cambiarlo)

- Ci vanno le funzioni di `tool.lua` che **non hanno stato e non toccano il gioco**: niente `self.<campo>`, niente `self.ai`, `self.game`, `game`, `map`, `Spring`. Dalla lettura del coordinatore: `RawDistance`, `DISTANCE`, `distance`, `AngleAdd`, `AngleAtoB`, `PositionWithinRect`, `RectsOverlap`, `pairsByKeys`, `tableSorting`, `sortByDistance`, `listHasValue`, `gcd`, `tableConcat`, `TableToString`, `StringToTable` (ricontrolla ognuna con questa regola).
- Restano in `Tool` (modulo `"team"`): quelle con stato o che toccano il gioco — `RezTable`, `KillTable`, `ResetTable` (pool per team), `GiveOrder`, `RandomAway`, `RandomAway2`, `getTeamUnitsByClass`, `countFinished`, `countMyUnit`, `mtypedLvCount`, `UnitPos`, `HorizontalLine`, `Plot4`, e ogni altra che non passa la regola.
- Le funzioni della libreria si scrivono con i due punti come oggi (`function Toolbox:distance(POS1, POS2)`): stesso corpo, stesso commento. Al posto di `self:altraFunzione` dentro la libreria resta `self:` (il `self` è `Toolbox`).
- **I chiamanti di oggi non cambiano**: `self.ai.tool:distance(...)` deve continuare a funzionare. `Tool` prende le funzioni della libreria senza copiarne il codice (per esempio riferimenti assegnati una volta, o `__index`): scegli la forma più semplice e leggibile, e controlla che una funzione della libreria chiamata come `self.ai.tool:distance` non usi niente di `Tool`.
- **Solo `MapHST`** passa già alla libreria: `self.ai.tool:RawDistance` / `distance` / `gcd` / `tableConcat` (8 chiamate) → `Toolbox:…`. Dopo, `maphst.lua` non deve avere `self.ai.tool`.
- Come si condivide fra ambiti: controlla come `shard_include` carica i file di STAI (ambiente dell'AI, una volta per tipo o per istanza) e scrivi nei risultati se `Toolbox` è una sola tabella per tutte le STAI. Deve esserlo, o almeno non avere stato: per questo la regola sopra.

**2. Via le funzioni di `Tool` mai chiamate**: `StoreOrder`, `SerializeOrder`, `DeserializeOrder`, `TableToStringBackup`, `sumPos`, `MiddleOfTwo`, `ApplyVector`, `AnglePosPos`, `CheckRect`, `sortByValue`, `reverseSortByValue`, `listHasKey`, `dictHasKey`, `WhatHurtsUnit`, `FillCircle`, `SimplifyPath`. Ricontrolla con grep in tutto il repository (anche `local tool = self.ai.tool` e chiamate interne con `self:`) prima di togliere ciascuna. Se una è usata, lasciala e scrivilo.

**3. Indice del codice tolto: `.ai-notes/stai/codice-tolto.md`** (decisione dell'utente: si toglie, si tiene l'indice). Una tabella: nome, file d'origine, commit che l'ha tolto, una riga su cosa faceva. Dentro: quello tolto in S2 (`schedulerHST.lua`), S3 (`maphst.lua` e righe commentate di `attackhst`, `raidhst`, `damagehst`), S4a (`GridToNodeIndex`), S4b (`topology`) e S5. In testa come si riprende: `git show <commit>^:<file>`. Commit con `git add -f`.

**4. Prova che il gioco non cambia**: le stesse righe `[S3-PROOF]` di S4b col codice di partenza e col nuovo (`c_stai_vs_stai.txt`, 2 minuti): identiche. Se cambiano, **fermati**.

**Test**: se `Toolbox` si carica da solo come `GridHST` nel suo test, un test busted di poche funzioni (`distance`, `RawDistance`, `gcd`, `tableConcat`, `sortByDistance`) con mutazioni; altrimenti scrivi perché.

**Partite**: oltre alla prova, una partita C di 15 minuti.

**Controlli**: StyLua 2.5.2, EmmyLua 0.24.0 (confronto per file toccati), `lx --lua-version 5.1 test`, `run_engine_tests.sh`; `.emmyrc.json` ripristinato.

**Commit**, in inglese: uno per la libreria e `MapHST`, uno per le funzioni tolte, uno per l'indice e i risultati.

## Risultati

### S4b (agente locale, 25 novembre 2026) — verificato dal coordinatore

**Cosa ho fatto**

- Commit `eff060d665` «STAI: add grid layers to GridHST» (`gridhst.lua` e test):
  - **Forma: classe `GridLayer = class(function(layer, resetCell) ... end)`** del framework, in fondo a `gridhst.lua`. Perché: STAI usa `class()` anche per le classi che non sono moduli (`PathfinderAStar = class(function(a) ...)` in `astarclass.lua`, `BehaviourFactory = class(AIBase)`), e così i metodi stanno una volta sola nella classe invece che in ogni strato. Campi: `CELLS` (`---@type table<integer, table>`), `LIST`, `marked` (il segno interno, minuscolo perché non lo legge nessuno da fuori), `resetCell`.
  - `Get(i)`: se `CELLS[i]` c'è lo restituisce; altrimenti `{}`, `resetCell` una volta se c'è, `CELLS[i]`. Non segna. `Mark(i)`: uscita anticipata se segnata, poi `marked[i] = true` e `LIST[#LIST + 1] = i`. `Clear()`: ciclo numerico su `LIST`, `resetCell(CELLS[i])` se c'è `resetCell` **e** la cella (**scelta mia**: un `Mark` su una cella mai creata con `Get` non chiama `resetCell(nil)`), toglie il segno, `LIST[n] = nil`; nessuna tabella nuova.
  - `GridHST:NewLayer(resetCell)`, `GridHST:PosToCell(pos)`, `GridHST:RawPosToCell(x, z)`: le ultime due da `PosToIndex`/`RawPosToIndex`, `nil` fuori dalla griglia.
  - Per EmmyLua: `---@diagnostic disable-next-line: call-non-callable` sulla chiamata `GridLayer(resetCell)` (come `loader/types.lua` per le classi del framework) e `---@type table<integer, table>` su `self.CELLS = {}` di `createCells`.
- Commit `d3c0d23ac4` «STAI: make MapHST.GRID a grid layer and read the geometry from GridHST»:
  - `createGrid`: `self.GRID = self.ai.gridhst:NewLayer()` senza `resetCell`, poi `for i = 1, gridArea` → `NewCell(i)`, che prende la cella con `self.GRID:Get(i)` e scrive campo per campo `moveLayers` (da `self.ai.gridhst.CELLS[i].POS`), `metalSpots`, `geoSpots`, `allSpots`. Tolti `POS`, `X`, `Z` della cella e il `return` di `NewCell` (nessuno lo usava).
  - `gridAnalisy`, `DrawDebug`: ciclo numerico sull'indice; `X`, `Z`, `POS` da `self.ai.gridhst.CELLS[i]`. In `DrawDebug` il testo resta `X:Z = i`.
  - `TopologyFooded`: stessa firma `(x, z, layer, net)`, stesso controllo dei bordi e stessi vicini da `x`, `z`; la cella è `self.GRID.CELLS[GridToIndex(x, z)]`.
  - `metalScan`, `geoScan`, `MobilityNetworkHere`: `PosToIndex`, con la stessa uscita (`return` su cella mancante, difetto del punto 15, lasciato com'è) e poi `self.GRID.CELLS[index]`.
  - `self.topology` tolto (`Init`, `moveLayerTest`, `TopologyFooded`); grep prima in `luarules/` e `spec/`: nessun altro lettore.
  - Lettori: `attackhst`/`raidhst` `Watchdog` e `raidhst` r. 379 → `self.ai.gridhst:PosToCell(...)`; `buildingshst` r. 856 e `loshst` r. 282 → `self.ai.gridhst.CELLS[self.ai.gridhst:GridToIndex(X, Z)].POS`; `scouthst` `PerimetralCells` → `local gridhst = self.ai.gridhst`, ciclo numerico su `gridhst.CELLS` con `CELL.X`, `CELL.Z`, `CELL.POS`. Il `local` serve: con `self.ai.gridhst.CELLS[i]` scritto per intero EmmyLua dà 5 avvisi `undefined-field` solo in `scouthst.lua` (non in `maphst.lua`, con le stesse espressioni); è la forma che STAI usa già (`local loshst = self.ai.loshst`).
  - grep finale: nessun `maphst.GRID` fuori da `maphst.lua`, nessun `topology`.
- **`allSpots` della cella di `MapHST` non lo legge nessuno** (lasciato): `allSpots` letti oggi sono solo `maphst.allSpots`, `networks[...].allSpots` e `layers[...].allSpots`.
- **Da notare (nessun cambio)**: `squad.watchdogCell` di `AttackHST`/`RaidHST` ora è una cella della geometria di `GridHST` invece che di `MapHST`; si confrontano solo `X` e `Z`, quindi il comportamento è lo stesso.

**Test** (nel file di S4a): `PosToCell`/`RawPosToCell` dentro e fuori dai bordi (anche `Z = 5`, che senza controllo cadrebbe sulla cella 2, 1); `Get` crea una volta, chiama `resetCell` solo alla creazione, non segna; senza `resetCell` celle vuote; `Mark` due volte → un indice, in ordine di arrivo; `Clear` chiama `resetCell` solo sulle celle della lista, svuota `LIST`, stessa `LIST` e stesse celle dopo (`rawequal`), nessun `resetCell` al `Get` successivo; si risegna dopo `Clear`; due strati non si toccano. **Mutazioni** (16, tutte fanno fallire il test): niente `resetCell` alla creazione; `Get` crea sempre; `Get` segna; `Get` non salva la cella; `resetCell` chiamato senza controllo; `Mark` senza controllo; `Mark` senza segno; `Clear` su tutte le celle; `Clear` con `LIST` nuova; `Clear` non toglie il segno; `Clear` non svuota `LIST`; `Clear` senza `resetCell`; `PosToCell` e `RawPosToCell` senza controllo; `x`, `z` scambiate in `RawPosToCell`; strati con `CELLS` in comune. La prima versione dei casi fuori griglia di `RawPosToCell` non prendeva la mutazione «senza controllo» (cadevano su indici senza cella): aggiunto il caso `Z = 5`.

**Righe per file**

| commit | file | + | − |
| --- | --- | --- | --- |
| `eff060d665` | `gridhst.lua` | 62 | 1 |
| | `spec/luarules/gadgets/ai/STAI/gridhst_spec.lua` | 93 | 0 |
| `d3c0d23ac4` | `maphst.lua` | 52 | 65 |
| | `scouthst.lua` | 5 | 5 |
| | `raidhst.lua` | 3 | 3 |
| | `attackhst.lua` | 2 | 2 |
| | `buildingshst.lua` | 1 | 1 |
| | `loshst.lua` | 1 | 1 |

`maphst.lua`: da 488 a 475 righe; `gridhst.lua`: da 194 a 255.

**Prova che il gioco non cambia** (stessi `Echo` temporanei di S4a, non committati; `c_stai_vs_stai.txt`, 2 minuti)

Codice di partenza `468ced3032` e codice finale `d3c0d23ac4` (anche una versione intermedia prima delle correzioni per EmmyLua): righe identiche fra loro e a quelle di S4a (`diff` vuoto).

```
[S3-PROOF] grid, 0, 32, 24, 768, 295296, 295296
[S3-PROOF] map, 0, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] grid, 1, 32, 24, 768, 295296, 295296
[S3-PROOF] map, 1, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] trampled, 1, 79, 406400.0000000000 296576.0000000000 2.118384599685669
[S3-PROOF] trampled, 0, 68, 208640.0000000000 141568.0000000000 2.246112346649170
```

**Partita C** (`c_stai_vs_stai.txt`, 15 minuti, codice finale, uscita 0, 22 s): tutte e due le STAI ospitate dal giocatore 0.

| | team 0 STAI | team 1 STAI |
| --- | --- | --- |
| unità min. 1 / 5 / 10 / 13 | 6 / 36 / 84 / 125 | 6 / 37 / 95 / 133 |
| mex min. 5 / 10 / 13 | 6 / 16 / 21 | 6 / 15 / 25 |
| min. 14 | 141 unità, 2 fabbriche, 27 mex | 148, 2, 28 |
| `SUMMARY` | 153, 2, 24 | 157, 2, 30 |

- Relay: 4739 messaggi, 27682 ordini, 24 rifiutati; nessun messaggio rifiutato. 0 righe `[AI Loader] error`; errori solo quelli di sempre (`gui_pip` `CreateShader`, `gui_sensor_ranges_jammer_preview` in Shutdown, `AdvSky`, `ceg_test_projectile`, atlas groundFX, shader AoE Napalm/Reclaim Field), nessuno cita Shard o STAI. `adding GridHST module` subito prima di `adding MapHST module` per tutti e due i team.
- Qui le due STAI sono pari (in S3 e S4a il team 0 restava indietro): conferma che era variabilità. Gli ordini (27682) sono i più alti finora (S4a 22569, S2 23929).

**Controlli**

- `lx --lua-version 5.1 test`: 2741 successi (+7), 0 falliti, 1 pending. `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 sui file toccati: ok.
- EmmyLua 0.24.0, confronto con un worktree della base `468ced3032`: 20 errori, gli stessi. Avvisi per file uguali alla base in tutti i file toccati (`maphst` 11, `attackhst` 7, `raidhst` 5, `buildingshst` 26, `loshst` 21, `scouthst` 0, `gridhst` 0, test 0); `gridhst.lua` 8 → 9 hint.
- `.emmyrc.json` ripristinato; `git status` pulito a parte questo file.

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


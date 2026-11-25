# Codice di STAI tolto durante il porting

Decisione dell'utente del 25 novembre 2026 (`nuovo-stai.md` §4 n. 8): il codice morto si toglie e qui se ne tiene l'indice.

**Come si riprende**: `git show <commit>^:<file>` dà il file com'era subito prima del commit che l'ha tolto (per esempio `git show e06200dd72^:luarules/gadgets/ai/STAI/tool.lua`). I file sono sotto `luarules/gadgets/ai/STAI/`.

## S2 — `bf496c6431` «STAI: run modules and behaviours in turns through the framework scheduler»

| nome | file | cosa faceva |
| --- | --- | --- |
| `SchedulerHST` (file intero) | `schedulerHST.lua` | modulo di STAI che teneva i turni di moduli e behaviour (`MScheduler`, `BScheduler`); i turni ora li tiene lo scheduler del framework, con le stesse liste in `ai.lua` |

## S3 — `84b5a964a9` «STAI MapHST: remove unused code»

| nome | file | cosa faceva |
| --- | --- | --- |
| `MapHST:PosToHeightMap` | `maphst.lua` | posizione in elmo → coordinate della mappa d'altezza (`/ 8 + 1`) |
| `MapHST:HeightMapToPos` | `maphst.lua` | coordinate della mappa d'altezza → posizione (con l'errore di precedenza `x - 1 * 8`) |
| `MapHST:PosToNodeIndex` | `maphst.lua` | posizione → indice di nodo per il costo dei percorsi, con `GridToNodeIndex` |
| `MapHST:NodeIndexToGrid` | `maphst.lua` | indice di nodo → `X`, `Z` della griglia |
| `MapHST:NormalizeHeighMapIndex` | `maphst.lua` | indice meno 1 |
| `MapHST:NodeIndexToPos` | `maphst.lua` | indice di nodo → posizione del centro della cella |
| `MapHST:NodeIndexToHeighMap` | `maphst.lua` | indice di nodo → coordinate della mappa d'altezza |
| `MapHST:InitPathCost` (e la sua chiamata commentata in `Init`) | `maphst.lua` | preparava una tabella di costi dei nodi per `Spring.SetPathNodeCost` |
| `MapHST:MergePositions` | `maphst.lua` | fondeva le posizioni più vicine di una soglia |
| `MapHST:SetStartLocation`, `startLocations` | `maphst.lua` | indovinava i punti di partenza dai metal spot e li metteva nelle reti di mobilità |
| `MapHST:GuessStartLocations` | `maphst.lua` | cercava i gruppi di metal spot che sembrano punti di partenza |
| `MapHST:ClosestFreeGeo` | `maphst.lua` | geo libero più vicino raggiungibile da un costruttore |
| `MapHST:MobilitynetworkSizeHere` | `maphst.lua` | dimensione della rete di mobilità in una posizione |
| `MapHST:AccessibleMetalSpotsHere` | `maphst.lua` | metal spot della rete di mobilità in una posizione |
| `MapHST:AccessibleGeoSpotsHere` | `maphst.lua` | geo della rete di mobilità in una posizione |
| `MapHST:IsUnderWater` | `maphst.lua` | `position.y < 0` |
| `MapHST:GetPathGraph`, `pathGraphs`, `mCeil` | `maphst.lua` | costruiva (e teneva in memoria) un grafo `GraphAStar` per tipo di movimento e dimensione di nodo |
| `MapHST:Update` (commentato) | `maphst.lua` | prova dei costi dei nodi (`Spring.SetPathNodeCosts`) ogni 100 frame |
| `MapHST:gridThePathBackup` (commentato) | `maphst.lua` | versione vecchia di `gridThePath` |
| vecchia versione commentata dentro `ClosestFreeMex` | `maphst.lua` | ricerca del mex libero più vicino scritta prima della versione attuale |
| `waterMetals`, `groundMetals`, ramo `map:CanBuildHere` di `metalScan`, `UWMetalSpotCheckUnitType` | `maphst.lua` | dividevano i metal spot in sott'acqua e a terra provando la costruzione con un'unità di prova |
| `map_loaded` | `maphst.lua` | segno di mappa già analizzata, controllato in `Init` |
| blocco commentato `SetPathNodeCost` / `GetPathNodeCost` | `damagehst.lua` | stampe di prova del costo dei nodi per le celle danneggiate |
| riga commentata `squad.graph = ...GetPathGraph(...)` | `attackhst.lua`, `raidhst.lua` | dava alla squadra il grafo di `GetPathGraph` |

## S4a — `3868bef297` «STAI: move the grid geometry from MapHST to a new GridHST»

| nome | file | cosa faceva |
| --- | --- | --- |
| `MapHST:GridToNodeIndex` | `maphst.lua` | `X`, `Z` → indice di nodo `((X - 1) * gridSideX + Z) - 1`, sbagliato su griglie non quadrate (al posto giusto c'è `GridHST:GridToIndex`) |

## S4b — `d3c0d23ac4` «STAI: make MapHST.GRID a grid layer and read the geometry from GridHST»

| nome | file | cosa faceva |
| --- | --- | --- |
| `MapHST.topology` | `maphst.lua` | `topology[layer][x][z] = true` per le celle visitate da `TopologyFooded`; non la leggeva nessuno |

## S5 — `f5d91af207` «STAI: move the stateless helpers of Tool to a Toolbox library»

| nome | file | cosa faceva |
| --- | --- | --- |
| `self:EchoDebug` in `tableSorting` e `sortByDistance` | `tool.lua` | stampa di debug di chiavi e distanze; non usciva mai (`Tool` non accende `DebugEnabled`) |
| `self:Warn` in `tableConcat` | `tool.lua` | avviso «concatenation require a table of tables» su un argomento non tabella; tutti i chiamanti passano una tabella scritta sul posto |

## S5 — `e06200dd72` «STAI Tool: remove functions nobody calls»

Mai chiamate:

| nome | file | cosa faceva |
| --- | --- | --- |
| `Tool:StoreOrder` | `tool.lua` | metteva un ordine in `game.orders` (vecchia coda degli ordini) |
| `Tool:SerializeOrder` | `tool.lua` | ordine → stringa `&id:…&cmd:…&parameters:…&options:…&method:…` (vecchio protocollo a stringhe) |
| `Tool:DeserializeOrder` | `tool.lua` | stringa `[ST]…[ST]` → ordine |
| `Tool:TableToStringBackup` | `tool.lua` | versione vecchia di `TableToString` |
| `Tool:sumPos` | `tool.lua` | somma di due posizioni |
| `Tool:MiddleOfTwo` | `tool.lua` | punto medio di due posizioni |
| `Tool:ApplyVector` | `tool.lua` | posizione dopo `frames` frame a una velocità; chiamava `Tool:ConstrainToMap`, che non esiste |
| `Tool:AnglePosPos` | `tool.lua` | `AngleAtoB` su due posizioni |
| `Tool:CheckRect` | `tool.lua` | rimetteva in ordine i lati di un rettangolo (`x1 < x2`, `z1 < z2`) |
| `Tool:sortByValue` | `tool.lua` | lista di `{ chiave, valore }` in ordine crescente di valore |
| `Tool:reverseSortByValue` | `tool.lua` | lo stesso, in ordine decrescente |
| `Tool:listHasKey` | `tool.lua` | valore di una chiave cercata con `pairs` |
| `Tool:dictHasKey` | `tool.lua` | `true` se la chiave c'è |
| `Tool:WhatHurtsUnit`, `whatHurtsUnit`, `whatHurtsMtype` | `tool.lua` | strati (`ground`, `air`, `submerged`) che possono colpire un'unità o un tipo di movimento, con cache per file |
| `Tool:FillCircle` | `tool.lua` | riempiva un cerchio su una griglia `[x][z]` (algoritmo del punto medio) |
| `Tool:SimplifyPath` | `tool.lua` | toglieva i nodi di un percorso dove l'angolo cambia meno di 0,2 rad |

Chiamate solo dalle funzioni sopra:

| nome | file | cosa faceva |
| --- | --- | --- |
| `Tool:TableToString`, `serialized` | `tool.lua` | appiattiva una tabella o una posizione nella stringa di `SerializeOrder` (stato nel `local serialized` del file) |
| `Tool:StringToTable` | `tool.lua` | `"a,b|c,d"` → tabelle, per `DeserializeOrder` |
| `Tool:AngleAtoB` | `tool.lua` | angolo da A a B con `atan2` |
| `AngleDist` (funzione globale) | `tool.lua` | distanza fra due angoli |
| `Tool:HorizontalLine` | `tool.lua` | scriveva o sommava valori su una riga della griglia, per `FillCircle` |
| `Tool:Plot4` | `tool.lua` | due righe simmetriche di `HorizontalLine`, per `FillCircle` |

Altro:

| nome | file | cosa faceva |
| --- | --- | --- |
| `mapBuffer`, `layerNames`, `unitThreatLayers`, `quadX`, `quadZ`, `output` | `tool.lua` | `local` del file mai letti |
| `Tool:CustomCommand` (commentata) | `tool.lua` | comando personalizzato con `api.vectorFloat` |
| ciclo commentato su `WhatHurtsUnit` in `AddBadPosition` | `damagehst.lua` | un record per ogni strato che può colpire il tipo di movimento |

## S7 — `ba9a8b29fe` «STAI MapHST: drop the collectgarbage at the end of Init»

| nome | file | cosa faceva |
| --- | --- | --- |
| `collectgarbage("collect")` alla fine di `MapHST:Init` | `maphst.lua` | raccolta completa dopo le analisi della mappa; ora il loader raccoglie una volta alla fine di `StartAIs` (`5d8d4a9b6e`, `shard_runtime/loader/lifecycle.lua`) |

## S8a — `98759bfc3c` «STAI LosHST: keep the enemy cells in an ENEMY layer of GridHST»

| nome | file | cosa faceva |
| --- | --- | --- |
| `LosHST:GetCellFromPool` | `loshst.lua` | prendeva la cella `X`, `Z` dal pool della griglia (`poolENEMY`, `poolOWN`, `poolALLIES`) |
| `LosHST:setupCell` (diventa `LosHST.resetCell`) | `loshst.lua` | cella dal pool, `X`, `Z`, `POS` e azzeramento dei campi; l'azzeramento resta in `resetCell`, `X`, `Z`, `POS` si scrivono quando la cella nasce (`getEnemyCell`) |
| `buildPools("poolENEMY")` in `Init` | `loshst.lua` | il pool delle celle di `ENEMY` (una tabella per cella, 768 su Comet Catcher) |
| parametro `grid` di `setCellLos`, `setCellRadar` | `loshst.lua` | la griglia da riempire; c'era solo `ENEMY` |
| commento sul pool («What is a cell pool?») e righe commentate con `GridToPos` | `loshst.lua` | spiegazione del pool; vecchio controllo di bordo |

## S8a — `500ba9cf56` «STAI LosHST: drop the OWN, ALLY and ALLIES grids and the dead code»

| nome | file | cosa faceva |
| --- | --- | --- |
| `OWN`, `ALLY`, `ALLIES` | `loshst.lua` | griglie `[X][Z]` delle unità proprie e alleate, mai riempite |
| `LosHST:buildPools`, `poolOWN`, `poolALLIES` | `loshst.lua` | pool di celle per griglia (`X` → `Z` → tabella) |
| `LosHST:FreeCellsToPool` | `loshst.lua` | rimetteva nel pool le celle di una griglia a ogni `Update` (anche `"ALLY"`, che un pool non l'aveva) |
| `knownEnemies`, `ownMobile`, `allyImmobile`, `allyMobile` | `loshst.lua` | campi di `Init` scritti (`UnitCreated`, `UnitDead`) e mai letti |
| `LosHST:UnitDamaged` | `loshst.lua` | vuota, con un blocco commentato (l'attaccante in los); faceva arrivare l'evento a `LosHST` per niente |
| `LosHST:viewPos`, `LosHST:posInLos` | `loshst.lua` | stato di una posizione (aria, sott'acqua, los, radar) con `Spring.GetPositionLosState` e `Spring.IsPosInAirLos`; mai chiamate |
| `LosHST:setPosLayer` | `loshst.lua` | strato (aria, sott'acqua, terra) di un tipo di unità in una posizione; mai chiamata, resta `setPosLayer2` |
| ciclo su `OWN` in `LosHST:Draw` | `loshst.lua` | disegno delle celle proprie |
| righe commentate `uPos` e `target` («NEVER USED») | `loshst.lua` | posizione e punto davanti all'unità in `setCellLos`, `setCellRadar` |
| ramo `OWN` di `AttackHST:SquadAttackbackup` | `attackhst.lua` | `FIGHT` verso una posizione difensiva propria |
| rami `OWN` e `ALLY` di `ScoutHST:TargetAvailable` | `scouthst.lua` | scartavano uno spot in una cella propria o alleata |

## S9 — `f03fb8edf0` «STAI DamageHST: keep the damaged cells in a DAMAGED layer of GridHST»

| nome | file | cosa faceva |
| --- | --- | --- |
| campo `groundAirSubmerged` delle celle di `DAMAGED` | `damagehst.lua` | in `AddBadPosition` copiava nella cella il globale `groundAirSubmerged`, mai definito (valeva sempre `nil`); nessuno lo leggeva |
| tabella `newRecord` di `AddBadPosition` | `damagehst.lua` | la cella nuova, costruita a ogni colpo anche quando la cella c'era già; ora i campi si scrivono nella cella dello strato quando entra nella lista |
| `GridHST:areaGridCells`, `GridHST:getGridCellsFields` | `gridhst.lua` | sorelle di `areaCells` e `getCellsFields` per una griglia `[X][Z]`, scritte in S8a solo per `DAMAGED` (`--TODO remove when DAMAGED is a layer`) |
| test «sums the fields of the cells of a grid X, Z around a position» | `spec/luarules/gadgets/ai/STAI/gridhst_spec.lua` | il test di `getGridCellsFields` |

## S9 — `1432104f6c` «STAI ScoutHST: keep the scouted cells in a SCOUTED layer of GridHST»

| nome | file | cosa faceva |
| --- | --- | --- |
| riga commentata `-- cell = nil` in `ScoutHST:Update` | `scouthst.lua` | resto di una vecchia scadenza delle celle |

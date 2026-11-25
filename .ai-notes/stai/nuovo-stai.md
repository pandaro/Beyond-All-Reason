# Nuovo STAI — porting di STAI sul nuovo framework Shard

Stato al 25 novembre 2026. Il framework è sul branch `shard/fase1` (compiti T1–T16, in `.ai-notes/handoff.md`), fermo dopo T16. Il porting si fa sul branch **`stai/porting`**, creato da `shard/fase1` dopo la verifica di T16.

Questo documento raccoglie in modo essenziale ciò che si sa del porting. È il punto di partenza: le righe «da verificare» sono ipotesi, non decisioni.

## 1. Scopo e regole

- **Scopo**: STAI gira sul nuovo framework e ne usa i pezzi (scheduler, ambiti, elezione), senza perdere forza di gioco; poi si migliora.
- **Due passi**: prima il porting con le opzioni di compatibilità (`legacyElection`), confrontando le partite con quelle di oggi; poi si tolgono, una alla volta, sempre confrontando.
- **Regole dell'utente** (le stesse del framework, `.ai-notes/coordinatore.md` §2): fedeltà a Shard e a STAI; preferenza per le cose esplicite; funzioni piccole composte in «macro»; codice ordinato; tutto ciò che va nel repository in inglese, le note in italiano; prima la struttura globale, poi i miglioramenti locali; non riscrivere da capo; niente `/luarules reload`; le richieste di percorso sono rinviate.
- **Il framework si tocca solo se serve a tutte le AI**: ogni cambio va motivato, approvato dall'utente e fatto in commit separati che iniziano con «Shard …».

## 2. Cosa offre il framework a STAI

Dettagli nella guida (`.ai-notes/drafts/README.md`).

| Cosa | Come | Nota per STAI |
| --- | --- | --- |
| Ambiti | `Scope()` obbligatorio: `"team"`, `"ally"`, `"global"`; dipendenze solo verso l'alto; un modulo di team raggiunge tutti come `self.ai.<nome>` | tutti i moduli di STAI oggi dichiarano `"team"` |
| Turni dei moduli | `STAI.MScheduler = { ... }` nella classe; un turno per frame, senza budget; i moduli non elencati ogni frame | il runtime chiama il modulo **solo nel suo turno**: i controlli di turno dentro i moduli diventano inutili |
| Turni dei behaviour | `STAI.BScheduler = { ... }`; stesso schema | un behaviour a turni deve contare i frame, non le chiamate |
| Di chi è il turno | `self.ai.scheduler.moduleTeam`, `.moduleUpdate`, `.behaviourTeam`, `.behaviourUpdate` | **non** `self.ai.schedulerhst.*`: la compatibilità prevista nella proposta non è stata fatta |
| Elezione | vince solo una priorità > 0; se nessuno, nessun behaviour attivo | STAI oggi ha `STAI.legacyElection = true` (la regola vecchia) |
| Eventi | solo ai moduli e behaviour che li ridefiniscono; ordine global → ally → team | |
| Ordini | `game:GiveOrder(...)` e i metodi di `ShardUnit` vanno in una coda; al massimo 20 ordini per messaggio, un messaggio per frame | una sola chiamata con più di 20 ordini viene **rifiutata intera** |
| Percezione | il framework non filtra: `game:GetEnemies()` dà tutti i nemici; `PerceptionHandler` (ambito ally, `los`, `radar`, `Sees`, `OnRadar`) è facoltativo | |
| Pool di tabelle | `local TablePool = shard_include("tablepool")`: `New`, `Get`, `Release`; facoltativo | |
| Errori | un errore in partita si scrive e l'AI va avanti; riepilogo a fine partita | |
| Istanze | al massimo 2 AI dello stesso tipo per partita (`MAX_INSTANCES_PER_AI_TYPE`) | |
| Memoria | rete di sicurezza della GC del vecchio loader; misura con `SHARD_MEM_STATS=1` | |
| Prove senza engine | `shard_null`, con oggetti ally e global | STAI oggi non parte sotto `shard_null` |

## 3. Punti del porting

| # | Punto | Dove | Cosa si sa | Stato |
| --- | --- | --- | --- | --- |
| 1 | Scheduler | `STAI/schedulerHST.lua`; i controlli di turno in testa all'`Update` dei moduli e dei behaviour | le liste di `SchedulerHST` passano nella classe (`STAI.MScheduler`, `STAI.BScheduler`); i controlli `self.ai.schedulerhst.moduleTeam ~= self.ai.id ...` si tolgono; `SchedulerHST` sparisce | deciso |
| 2 | Ambiti globali | `armyhst.lua`, `maphst.lua` | `ArmyHST` e `MapHST` diventano `"global"`: oggi l'analisi della mappa si rifà per ogni AI. Le funzioni di `MapHST` che dipendono dal team (`ClosestFreeMex` usa `buildingshst`, `loshst`, `targethst`; i costi dei percorsi usano `game:GetTeamID()`) ricevono l'AI come parametro o passano in un modulo di team. Decisione del 25 novembre 2026 (utente): `MapHST` si occupa solo della mappa (analisi una volta per partita e domande sulla mappa); la geometria della griglia passa in `GridHST` (punto 5); `ClosestFreeMex` e `UnitMexMoveTest`/`trampled` vanno in `BuildingsHST` (un `CommanderHST` non esiste). Per diventare `"global"` `MapHST` deve smettere di usare moduli di team (`self.ai.armyhst`, `self.ai.tool`). S6 (25 novembre 2026): `ArmyHST`, `GridHST`, `MapHST` sono `"global"`, analisi della mappa una volta per client. Da sapere: `MapHST:DrawDebug` fa `EraseAll` prima del controllo su `drawDebug`; sul globale la squadra è `nil` e con il widget `shard_help_draw` acceso andrebbe in errore (proposta: controllo prima del ciclo) | fatto (S6) |
| 3 | Ambiti d'alleanza | `loshst.lua`, `targethst.lua`, `damagehst.lua` | `LosHST` diventa `"ally"`; `self.ai.friendlyTeamID` (scritto da `LosHST:Init`, letto da `DamageHST`) passa su `ShardAlly`; `UnitCreated` riconosce le unità proprie con `self.ai.id`; `TargetHST` e `DamageHST` probabilmente `"ally"` | da verificare |
| 4 | `self.ai.id` nei moduli condivisi | tutti i moduli che diventano global o ally | in un modulo condiviso `self.ai` è l'oggetto ally o global, non un team | da controllare a ogni modulo spostato |
| 5 | Griglia | `loshst.lua` (griglie `ENEMY`, `OWN`, `ALLIES`, pool di celle) | **l'utente non vuole più la griglia così**. Idea dell'utente: una griglia unica per tutto, ogni cella una tabella di dati, più liste delle celle «vere» per tema (nemici, metallo, unità proprie…). Difetto noto: `Update` libera `"ALLY"`, ma le griglie sono `ALLY` e `ALLIES`; il controllo su `loshst.ALLY` in `ScoutHST` non scatta mai. Decisione del 25 novembre 2026 (utente): **una geometria, tanti strati**. `GridHST` (`"global"`) tiene la geometria: celle fisse e persistenti con indice unico `i = (X-1)·sideZ + Z` (al contrario `X = floor((i-1)/sideZ)+1`, `Z = (i-1)%sideZ+1`; ogni cella tiene `X`, `Z`, `POS`), conversioni posizione ↔ indice, vicini (`i ± 1`, `i ± sideZ`). Ogni modulo ha il suo **strato**, nel suo ambito, con lo stesso indice: dati per cella creati quando servono, **lista delle celle vere** in un array con ordine fisso, azzeramento solo delle celle della lista (via il pool di `LosHST`). Scrive solo il padrone dello strato, leggono tutti. Decisione del 25 novembre 2026 (utente): la misura della cella (`gridSize`) sta **in un solo punto**, `GridHST:Init`, a **256**; divisione in S4a (geometria) e S4b (strati); nomi `CELLS`, `LIST`, `INDEX`, `PosToIndex`, `GridToIndex`, `NewLayer`, `Mark`, `Clear` accettati. Decisione del 25 novembre 2026 (utente): `Clear` usa una **funzione di azzeramento** data da chi crea lo strato (`NewLayer(resetCell)`), chiamata solo sulle celle della lista; le tabelle restano e si riusano. Proposte del coordinatore senza obiezioni dell'utente: `Mark` separato da `Get` (si segna solo quando si scrive); `PosToIndex`/`RawPosToIndex` danno `nil` fuori dalla griglia | deciso |
| 6 | Percezione | `loshst.lua`; letture dirette `Spring.*` (circa 26 in `maphst.lua`, 10 in `loshst.lua`, 6 in `damagehst.lua`) | tre strade: tenere `LosHST`, usare `PerceptionHandler`, o barare | aperto |
| 7 | Elezione | `STAI/ai.lua` (`legacyElection`); `bootbst.lua`, `cleanerbst.lua` | con la regola nuova: `BootBST` è spesso primo e a priorità zero; vanno controllati i behaviour che fanno qualcosa in `Activate`; `CleanerBST:Priority` è vuota (vale zero) | aperto: tenere `legacyElection` o passare alla regola nuova |
| 8 | Gestore delle unità | `unithst.lua` | la proposta diceva: `UnitHST` lascia il posto a `UnitHandler`. Oggi `UnitHandler` sta in `Shard/` (l'esempio), non nel runtime | aperto |
| 9 | `collect` di `MapHST` | `maphst.lua` r. 52, `collectgarbage("collect")` alla fine di `Init` | la proposta diceva di toglierla (costa 65–70 ms); l'utente tiene alle `collect` come sicurezza; con `MapHST` globale girerebbe una volta per partita | aperto |
| 10 | Ordini grandi | moduli e behaviour che danno ordini a molte unità | oltre 20 ordini in una chiamata l'ordine si perde; in teoria `GiveOrderArrayToUnitArray` lo evita (non verificato). Guardare i «rifiutati» delle partite. S16 (25 novembre 2026): nessun ordine perso per dimensione (oltre 20 unità solo latenza; si perde solo un gruppo `2-1` con più di 20 comandi, oggi al massimo 10 in `labsbst.lua:160`); squadre al massimo 15 unità. Difetto trovato: `raidhst.lua` r. 271–280 riempie `squad.cmdUnitId[i]` con buchi e `game:GiveOrder '1-2'` usa `#` | chiuso (S16); difetto `#` da correggere |
| 11 | Difetti noti | `buildersbst.lua`, `bomberhst.lua`; `EchoDebug` in tutti i file | ID di unità vecchi; `EchoDebug` con argomenti costosi calcolati anche a debug spento; stallo di metallo | da fare |
| 12 | `shard_null` | `STAI/boot.lua`; nomi dei file | boot da sistemare; maiuscole (`schedulerHST.lua` incluso come `"schedulerhst"`); serve uno `Spring` finto per le letture dirette | da fare |
| 13 | Un solo cervello per alleanza | — | idea dell'utente: più STAI nella stessa alleanza comandate da una sola AI; passo naturale dopo gli ambiti | futuro |
| 15 | Difetti delle griglie e di `MapHST` (trovati il 25 novembre 2026) | `loshst.lua`, `maphst.lua` | `LosHST`: `OWN`, `ALLIES`, `ALLY` mai riempite (i controlli di `ScoutHST` e `AttackHST` su queste non scattano mai); in `setCellLos` e `setCellRadar` `CELL.unarmAI = CELL.unarmAM + M` (e `SI`, `GI`): copia il mobile nell'immobile. `MapHST`: `metalScan`/`geoScan` fanno `return` su una cella mancante (si ferma tutto il giro); `SimplifyMetalSpots` scorre `z` fino a `elmoMapSizeX` e fa `table.remove` dentro `pairs`; `RawPosIsInMap` usa `pos` inesistente nel debug; `GridToNodeIndex` usa `gridSideX` al posto di `gridSideZ`. `Toolbox:tableConcat` (S5): `table.insert(T, -1, value)` rovescia l'ordine e lascia gli ultimi due valori nelle chiavi `0` e `-1`, fuori da `#` (`#MapHST.allSpots` 78 su 80; reti con 1–2 spot hanno `#allSpots == 0`); il test di `toolbox_spec.lua` fissa il comportamento di oggi. Decisione del 25 novembre 2026 (utente): **si corregge subito**, in S6 — fatto (S6); `ratioSpots` non lo legge nessuno | da fare: un commit per difetto, con partite, dopo gli strati. Dopo S3 nessuno usa più `astarclass.lua` (`GraphAStar`, incluso da `tool.lua`) né `ArmyHST.UWMetalSpotCheckUnit`: da togliere con l'ok dell'utente |
| 16 | Stato nelle classi (S5) | `tool.lua` | `Tool._TABLES` (riserva di `RezTable`/`KillTable`) sta nella classe: una sola riserva per tutte le STAI del client, non per team. Oggi senza effetti | da sapere |
| 17 | Memoria per frame (S6) | partite A | picchi 90–159 KB (S1: 68–74; S2: 84–99), medie uguali a S1; heap fino a 16,0 MB. Con tre partite non si distingue dalla variabilità. S8a: picco 218 KB in una partita, medie uguali, heap più basso (12,9 MB all'inizio) | da osservare |
| 18 | Seme casuale (S8a) | `shard_runtime/loader/types.lua` (`TeamSeed`) | il seme di `math.random` di ogni AI viene dall'hash del `GameID`, diverso a ogni avvio: due partite con lo stesso codice si separano prima di ogni contatto. Le prove «gioco invariato» fra due versioni funzionano solo per l'avvio; per la partita intera serve un seme fisso (opzione del loader, commit «Shard …») o la prova nella stessa partita (come S8a) | Decisione del 25 novembre 2026 (utente): **saltato** per risparmiare token; niente `springsettings.cfg`, tutto autocontenuto. Trovato dal coordinatore: `thisAI.randomseed` è calcolato ma nessuno lo usa, e in Lua unsynced `math.random` è salato con un indirizzo di memoria (commento in `game_autocolors.lua`), quindi servirebbe un generatore dell'AI |
| 19 | Difetti visti in S8a | `loshst.lua`, `targethst.lua`, `attackhst.lua` | `CELL.base` di `ENEMY` mai azzerato (una cella che ha visto una fabbrica resta «base»); `TargetHST:NearbyVulnerable` legge `subValues.armed`/`unarm` ma le chiavi sono `ARMED`/`UNARM` (mai vero); `LosHST:getCenter` divide per zero senza edifici propri (`CENTER` = NaN); `posG`, `posS`, `posB`, `posA` globali in `LosHST:Draw`. S8b: `DamageHST` r. 41 scrive in `losEnemy` il `defId` del difensore invece di quello dell'attaccante (oggi senza effetti: il valore non lo legge nessuno). Codice morto: `AttackHST:SquadAttackbackup` (mai chiamata) e la vecchia `SquadAttack` commentata in fondo a `attackhst.lua`. S9: `TargetHST:GetPathModifierFunc` (e `pathModifierFuncs`) non la chiama nessuno (codice morto o attesa del servizio percorsi, punto 14); `DamageHST:AddBadPosition` riceve `mtype` e `duration` ma nessuno li usa. S21: `labshst.lua:367` (`PostPositionalFilter`) indicizza `maphst.networks[mtype][network]` con `network` `nil` quando `MobilityNetworkHere` non trova la rete (errore del loader una volta in una partita A); `bomberhst.lua:158–160` riempie `cmdUnitId` con `bomber.id` (buchi, come il difetto corretto in S21; oggi mai chiamato). Già tolto: `GridToNodeIndex` (il difetto di `gridSideX` del punto 15 non c'è più). `RawPosIsInMap` ora sta in `gridhst.lua` | da fare, con i difetti del punto 15 |
| 14 | Percorsi | `maphst.lua` r. 595 e 883, `attackhst.lua` r. 310 | `map:RequestPath` sincrono, senza cache | **rinviato** dall'utente |

## 4. Decisioni aperte (le prende l'utente)

1. ~~Griglia: forma nuova (punto 5).~~ Decisa il 25 novembre 2026: una geometria, tanti strati.
2. Percezione: `LosHST`, `PerceptionHandler` o barare (punto 6). Decisione del 25 novembre 2026 (utente): **STAI non bara**. Decisione del 25 novembre 2026 (utente): **`LosHST` sopra `PerceptionHandler`**: `PerceptionHandler` dà i fatti dell'engine (los, radar), `LosHST` tiene la memoria come un giocatore. L'engine e il gioco danno ragione a STAI: un'unità in radar che è stata in los si vede come «ombra» del modello (tipo noto), un edificio uscito dalla vista resta. Nota del coordinatore: oggi un'unità **mobile** che esce dalla los ma resta nel radar sparisce da `LosHST` (`UnitLeftLos` la toglie dalla los e nessun `UnitEnteredRadar` arriva, perché il radar non si è mai interrotto); con i due insiemi di `PerceptionHandler` sotto si può tenere come radar a tipo noto.
3. Elezione: tenere `legacyElection` o passare alla regola nuova, e quando (punto 7). Decisione del 25 novembre 2026 (utente, dopo S13): **regola nuova** (fatto in S22) (`legacyElection = false`, in S22). `AttackerBST` (mai attivo: `attacking` mai vero) resta com'è, da capire più avanti. Decisione del 25 novembre 2026 (utente): **se la regola nuova è migliore si usa quella** (da provare con partite).
4. `UnitHST`: resta in STAI o diventa un `UnitHandler` del runtime (punto 8). Decisione del 25 novembre 2026 (utente): **`UnitHST` resta in STAI**; si adeguerà il framework (`UnitHandler` sul modello di `UnitHST`: evento solo all'unità interessata).
5. `collect` di `MapHST`: resta o va tolta (punto 9). Fatto in S7. Idea dell'utente (25 novembre 2026): cercare un posto migliore, per esempio una sola `collect` alla fine di tutti gli `Init`, nel loader. Decisione del 25 novembre 2026 (utente): **una `collect` alla fine di `StartAIs`** (`shard_runtime/loader/lifecycle.lua`, dopo gli `Init` di globali, alleanze e team), commit «Shard …» a parte; quella di `MapHST` poi si toglie.
6. `Tool` (25 novembre 2026, utente). Decisione del 25 novembre 2026 (utente), dopo S5: approvate le 6 funzioni tolte in più; `Toolbox` senza `Warn`.
   `Tool`: è una cassetta di attrezzi matematici e logici di largo uso, senza `Update` né eventi; quelli inutili si tolgono. Decisione del 25 novembre 2026 (utente): **la matematica diventa una libreria** (file che restituisce una tabella di funzioni, senza ambito, usabile da ogni ambito); gli attrezzi di squadra (`GiveOrder`, `countMyUnit`, `countFinished`, `getTeamUnitsByClass`, `mtypedLvCount`, …) restano in un modulo di team; le circa 16 funzioni mai chiamate si tolgono.
7. `astarclass.lua` (25 novembre 2026, utente): resta finché non si studia il pathfinding dell'engine (se `RequestPath` funziona non serve, se è difettoso sì).
8. Codice morto: toglierlo o «stoccarlo» (25 novembre 2026, cosa da decidere per l'utente). Decisione del 25 novembre 2026 (utente): **si toglie**, e si tiene un indice in `.ai-notes/stai/codice-tolto.md` (nome, file, commit; si riprende con `git show <commit>^:<file>`).

Decisione del 25 novembre 2026 (utente): S8 diviso in **S8a** (strato `ENEMY`, via `OWN`, `ALLY`, `ALLIES` mai riempite e il resto che non serve) e **S8b** (percezione).

Decisione del 25 novembre 2026 (utente, per S24): **la squadra dà gli ordini** (`AttackHST`, un ordine per squadra con il nuovo ordine «un comando a molte unità» del framework, S24a); **`AttackerBST` è il sensore** dell'unità (eventi alla squadra, priorità 0, nessun ordine; eccezioni individuali in futuro). Il formato del codec lo decide poi l'utente con il coordinatore del framework.

Decisione del 25 novembre 2026 (utente, per S12b): in ambito ally **`DamageHST` registra i danni a tutte le unità dell'alleanza**, anche dei giocatori umani alleati (`defender:AllyTeam() == self.ai.allyId`).

Decisioni del 25 novembre 2026 (utente, dopo S12a): **`CENTER` è la media degli edifici propri; senza edifici la posizione attuale del comandante** (sostituisce «com'era» e «posizione del comandante finché non ci sono edifici», date su una descrizione sbagliata del coordinatore: nella base `CENTER` era la tabella viva della posizione del comandante); ciclo numerico in `TargetHST:GetBlobs` (con `pairs` la somma di `metal` dipendeva dalla tabella presa dalla riserva). In S12a2; il gioco cambia, tre partite A.

Decisioni del 25 novembre 2026 (utente, per S12a): `CENTER` e `ownImmobile` in `BuildingsHST`; via `isDamaged` di `DamageHST` e quello che serve solo a lui («togli quello che non serve»); la riserva dei blob di `TargetHST` usa `TablePool` del framework («almeno le abbiamo per qualcosa»); se si perdono tutti gli edifici `CENTER` resta sull'ultimo centro («lascialo com'era»). Trovato dal coordinatore: `friendlyTeamID` è creato vuoto e mai riempito (in S12a si toglie; in S12b va deciso se `DamageHST` conta i danni di tutta l'alleanza).

Decisioni del 25 novembre 2026 (utente, dopo S10): via `TargetHST:NearbyVulnerable` e `TargetHST:GetPathModifierFunc` (codice morto, in S11); `CENTER` di `LosHST` è la posizione del comandante finché non ci sono edifici.

Decisioni del 25 novembre 2026 (utente, dopo S8b), sui consigli del coordinatore:
- **`GridLayer:Unmark(i)`** per gli strati che durano (`DAMAGED`, `SCOUTED`): una cella esce dalla lista tenendo l'ordine delle altre.
- **`TRAMPLED` resta com'è** (lo legge solo `UnitMexMoveTest`, una volta all'avvio; fuori serve solo `trampledCells`): niente strato.
- **Difetti**: un commit e un test per difetto, **tre partite A per gruppo** (S10, S11), non per ogni difetto.
- **L'esploratore non insegue le ombre** (`scoutbst.lua` r. 135 resta su `losEnemy`).

**Cose da fare dell'utente** (sue, non compiti S):
- sincronizzare `UnitHandler` del framework con il modello di `UnitHST` di STAI;
- prima o poi: studiare il pathfinding dell'engine (`RequestPath`): se è difettoso come aggiustarlo, se no come si usa; da lì dipende `astarclass.lua`.

## 5. Ordine di lavoro proposto

Un compito per riga, come per il framework; l'impegno si decide compito per compito.

1. **Partenza**: branch `stai/porting`; tre partite A di riferimento (la variabilità fra partite è grande: 146–201 unità, 15–37 mex); controllo che STAI giri com'è oggi.
2. **Scheduler** (punto 1): liste nella classe, via `SchedulerHST` e i controlli di turno. Confronto con le partite di riferimento.
3. ~~**Ambiti globali** (punti 2 e 4): `ArmyHST`, poi `MapHST`.~~
4. ~~**Discussione con l'utente sulla griglia** (punto 5), poi **ambiti d'alleanza** (punti 3 e 4) con la griglia nuova.~~

Piano del 25 novembre 2026, dopo S8b (proposto dal coordinatore, approvato dall'utente):

- **S9** (verificato) strati che durano: `GridLayer:Unmark`, `DAMAGED` (`DamageHST`) e `SCOUTED` (`ScoutHST`, scritto solo dal padrone); via `areaGridCells`/`getGridCellsFields`. Gioco invariato, prova nella stessa partita.
- **S10** (verificato) difetti della mappa e della griglia (punto 15): `metalScan`/`geoScan` (`return` su cella mancante), `SimplifyMetalSpots`, `RawPosIsInMap`, `unarmAI = unarmAM + M` (e `SI`, `GI`) in `setCellLos`/`setCellRadar`; via `ArmyHST.UWMetalSpotCheckUnit`. Tre partite A.
- **S11** (verificato) difetti di tattica (punto 19): `CELL.base` mai azzerato, `NearbyVulnerable` (chiavi `ARMED`/`UNARM`), `getCenter` NaN, globali in `LosHST:Draw`, `defId` del difensore in `DamageHST`; via `SquadAttackbackup` e la vecchia `SquadAttack` commentata di `AttackHST`. Tre partite A.
- **S12a**, **S12a2** (verificati) preparazione degli ambiti d'alleanza (gioco invariato): fuori da `LosHST`, `TargetHST`, `DamageHST` le cose di squadra — `CENTER` (scritto anche da `CommanderBST`, che gli assegna la stessa tabella di `self.position`; decisione del 25 novembre 2026 (utente): posizione del comandante finché non ci sono edifici) e `ownImmobile`, `self.ai.id`, `needAntiAir` in `LosHST`; `self.ai.tool` (8 volte in `TargetHST`, `RezTable`: `Toolbox` o `TablePool`); `isDamaged` di `DamageHST` (lo usa solo il debug). **S12b** `LosHST`, `TargetHST`, `DamageHST` `"ally"`, `friendlyTeamID` su `ShardAlly`; prova con una partita B (due STAI nella stessa alleanza). Impegno extra.
- **S13** elezione (punto 7): prima `BootBST` (priorità zero), `CleanerBST` (priorità vuota), i behaviour che agiscono in `Activate`; poi partite con `legacyElection = false` contro quelle di oggi.
- Dopo, da ordinare: `EchoDebug` costoso (punto 11), ordini grandi (punto 10), `shard_null` (punto 12), `gridSize` 128 (§5b), `ShardMemStats` autocontenuto.

Ordine del 25 novembre 2026 (utente: «prima si parte dai fondamenti»; separare quello che non cambia il gioco da quello che lo cambia):

3. **Pulizia di `MapHST`** (S3): via il codice morto; `ClosestFreeMex` e `trampled` in `BuildingsHST`. Gioco invariato.
4. **`GridHST`**: geometria, indice, strati; `MapHST` la usa. Gioco invariato salvo l'ordine fisso al posto di `pairs`.
5. **Ambiti globali**: `ArmyHST`, ciò che `MapHST` usa di `Tool`, poi `MapHST` e `GridHST` `"global"`.
6. **Strati negli altri moduli**, uno alla volta (`LosHST`, `DamageHST`, `ScoutHST`, `TargetHST` e chi li legge), poi **ambiti d'alleanza** (punti 3 e 4).
7. **Difetti delle griglie e di `MapHST`** (punto 15): un commit per difetto, con partite.

Poi, come prima:

8. **Percezione** (punto 6), secondo la decisione.
9. **Elezione** (punto 7), secondo la decisione.
10. **Difetti noti e ordini grandi** (punti 10 e 11).
11. **`shard_null`** (punto 12).
12. **Chiusura**: guida per STAI, partite finali, branch pulito.

## 5b. Numeri da mettere alla prova

| Numero | Oggi | Da provare | Nota |
| --- | --- | --- | --- |
| `gridSize` (`GridHST:Init`) | 256 | 128 — S19 (25 novembre 2026): tre partite A peggiori (90–175 unità), più memoria, ricorsione al 78 % del limite su 2048×2048: **ritirato**, resta 256 | celle ×4; i raggi «in celle» (`getCellsFields(..., 2, ...)`, `areaCells`) cambiano significato e vanno ritarati insieme; percorribilità provata solo al centro della cella (256 è grossa per l'analisi della mappa); `TopologyFooded` ricorsivo, Lua 5.1 regge circa 20.000 chiamate annidate (32×32 a 128 = 16.384 celle) |

## 6. Come si verifica

- **Partita A**: STAI contro SimpleAI, Comet Catcher Remake 1.8, 15 minuti, `SHARD_MEM_STATS=1`, con `.ai-notes/tools/run_engine_game.sh`. Righe da confrontare: unità ai minuti 1/5/10/13, unità, fabbriche e mex a fine partita, messaggi/ordini/rifiutati del relay, memoria per frame, heap, righe `[AI Loader] error`.
- **Riferimenti** (sul framework, prima del porting): circa 145–194 unità a fine partita, 15–37 mex, circa 15.000 ordini, 10–15 rifiutati, memoria media 0,2–0,7 KB per frame, heap 13–15 MB. Una partita sola non basta per dire che un cambio peggiora il gioco: servono almeno tre partite.
- **Varianza** (S10): con codice che gioca come S9, tre partite A hanno dato 132–175 unità e 19–32 mex (una con una fabbrica sola): una partita sotto S1 da sola non dice che il codice peggiora.
- **Riferimenti dopo T16** (S1, tre partite A, 24 novembre 2026): unità a fine partita 141 / 161 / 186; mex 23 / 29 / 35; fabbriche 2; ordini 10.445–15.948, rifiutati 9–16 (nessun messaggio rifiutato, quindi niente `excluded` né gruppi oltre 20); memoria media 0,37–0,45 KB per frame, picco 68–74 KB; heap 13,1–15,5 MB; nessuna riga `[AI Loader] error`. Unità al minuto 13: 117–159.
- **Controlli**: test busted con prova delle mutazioni, StyLua 2.5.2, EmmyLua 0.24.0, `lx --lua-version 5.1 test`, `.ai-notes/tools/run_engine_tests.sh`.

## 7. Stile di STAI (da seguire in ogni compito)

Richiesta dell'utente (25 novembre 2026): il codice nuovo o spostato si scrive **il più possibile come quello di STAI**, che è suo. Descrizione presa dal codice:

- **Struttura**: `X = class(Module)`, poi `Name`, `internalName`, `Scope`, `Init`; prima riga di `Init`: `self.DebugEnabled = false`. `Init` (e le funzioni grandi) come «macro»: una fila di chiamate a funzioni piccole che si leggono come passi (`MapHST:Init`). Gli altri moduli con `self.ai.<nome>`; gli aiuti comuni in `Tool` (`self.ai.tool:distance`, `tableConcat`, `sortByDistance`).
- **Nomi**: MAIUSCOLO per i dati centrali, le griglie e i valori aggregati (`GRID`, `CELL`, `METALS`, `ENEMY`, `DAMAGED`, `POS`, `ARMED`, `UNARM`); `X`, `Z` maiuscole per la griglia, `x`, `z` per gli elmo. Metodi chiamati da fuori in PascalCase, passi interni in camelCase (`basicMapInfo`, `metalScan`). Coppie con «Raw» per la versione con `x, y, z` (`RawPosToGrid` / `PosToGrid`). Variabili dei cicli che dicono cosa sono (`for X, Zetas in pairs(self.GRID)`, `for Z, CELL in pairs(Zetas)`). Suffissi `HST` (moduli), `BST` (behaviour).
- **Commenti**: brevi, in inglese, **a fine riga**, `--` attaccato, dicono a cosa serve (`--hold the metalSpots of this cell`); avvisi in maiuscolo (`TODO`, `CAUTION`, `WARNING`, `TEST`).
- **Codice**: uscite anticipate; tabelle costruite campo per campo; `pairs` quasi sempre (quando l'ordine conta, cicli numerici); `self:EchoDebug` abbondante, `self:Warn` per gli avvisi; funzioni che restituiscono più valori.
- **Nomi esistenti** (anche con refusi: `gridAnalisy`, `TopologyFooded`) non si rinominano senza chiedere; nei nomi e commenti nuovi inglese corretto, nella stessa forma.
- Eccezione decisa: il codice morto e i blocchi commentati morti si tolgono (utente, 25 novembre 2026: «vedi tu»).

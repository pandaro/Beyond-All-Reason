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

### S8b: percezione, `LosHST` sopra `PerceptionHandler`

**Impegno: alto.** Decisioni dell'utente del 25 novembre 2026 (`nuovo-stai.md` §4 n. 2): **STAI non bara**; `PerceptionHandler` dà i fatti dell'engine (los, radar), `LosHST` tiene la memoria come un giocatore. L'utente ha anche approvato le funzioni tolte in più in S8a (`viewPos`, `posInLos`, `setPosLayer`, righe commentate, `getCenter` doppio). **Il gioco cambia.** **Stile**: `nuovo-stai.md` §7. Restano fuori: ambiti d'alleanza (`LosHST` resta `"team"`, `friendlyTeamID` com'è), `UnitDead` che sa sempre chi muore, la `DamageHST` r. 41 (chi spara si vede: resta).

**1. `PerceptionHandler` in STAI**: `shard_include("perceptionhandler")` e `PerceptionHandler` in `modules.lua` (il file del runtime, ambito `"ally"`), come fa `Shard/modules.lua`. Controlla nei log che ci sia una sola istanza per alleanza e che riceva gli eventi **prima** di `LosHST` (ordine global → ally → team).

**2. La memoria di `LosHST`: le «ombre»**

- Oggi un'unità **mobile** che esce dalla los ma resta nel radar sparisce (`UnitLeftLos` la toglie da `losEnemy` e nessun `UnitEnteredRadar` arriva, perché il radar non si è mai interrotto). Nel gioco il giocatore la vede come icona radar del tipo già visto.
- Nuovo insieme `self.ghostEnemy` (`[unitID] = unitDefID`; nome proposto, «ombra»): in `UnitLeftLos` di un'unità mobile, se `self.ai.perceptionhandler:OnRadar(unitID)`, l'unità va in `ghostEnemy` invece di sparire. Esce da `ghostEnemy` con `UnitEnteredLos` (torna in `losEnemy`), `UnitLeftRadar`, `cleanEnemy`.
- In `Update` le ombre si segnano nello strato `ENEMY` come le unità in los (tipo noto: `setCellLos`), alla posizione che dà l'engine come oggi per il radar. Il `Warn` «in los and in radar» vale anche per le ombre (un'unità in un solo insieme alla volta).
- Edifici e unità in radar mai viste: come oggi.
- Lettori di `losEnemy` fuori da `LosHST` (`scoutbst.lua` r. 135, `damagehst.lua` r. 41–42): controlla se devono vedere anche le ombre e scrivi cosa hai deciso.

**3. Coerenza con l'engine**: dove `LosHST` decide «in los»/«in radar», usa `PerceptionHandler` (`Sees`, `OnRadar`) invece di dedurlo da solo, se rende il codice più semplice; se no lascia gli eventi come sono e scrivi perché. Nessuna lettura diretta nuova di `Spring.*` per sapere cosa si vede.

**4. Misure**: `Echo` temporanei (non committati) ogni 300 frame, per team: unità in `losEnemy`, `radarEnemy`, `ghostEnemy`; celle vere di `ENEMY`. Scrivi quante ombre ci sono di solito e se qualcuna resta appesa (ombra di un'unità che non è più nel radar).

**Test**: se `LosHST` si carica come `MapHST` nel suo test, test busted degli eventi con un `PerceptionHandler` finto (mobile esce dalla los in radar → ombra; fuori dal radar → niente; rientra in los → `losEnemy`; edificio → resta in `losEnemy`), con mutazioni; altrimenti scrivi perché.

**Partite**: tre partite A, confronto con S8a, S6 e i riferimenti dopo T16. Se le tre stanno sotto, scrivilo chiaramente.

**Controlli**: StyLua 2.5.2 (dalla radice), EmmyLua 0.24.0 (confronto per file toccati), `lx --lua-version 5.1 test`, `run_engine_tests.sh`; `.emmyrc.json` ripristinato.

**Commit**, in inglese: uno per `PerceptionHandler` in `modules.lua`; uno per le ombre (con il test); uno per i risultati.

## Risultati

### S8b (agente locale, 25 novembre 2026)

**In breve**: `PerceptionHandler` del runtime è in `modules.lua` (una istanza per alleanza, riceve ogni evento prima di `LosHST`: 0 eccezioni su 457 eventi per team); un'unità mobile che esce dalla los restando nel radar diventa un'**ombra** (`ghostEnemy`) e si segna in `ENEMY` come unità di tipo noto. Nelle partite: 71–233 ombre per partita, al massimo 1–12 insieme, **nessuna ombra appesa**, nessun avviso «più di un insieme». Le tre partite A **non stanno sotto** i riferimenti.

**Commit**

- `c8f47e8677` «STAI: load the runtime's PerceptionHandler in the ally scope»: `shard_include("perceptionhandler")` (dopo `tool`) e `PerceptionHandler` nella lista subito dopo `MapHST` (prima i globali, poi l'alleanza, poi i team). Il `shard_include` di STAI ricade sul runtime (`shard_generate_include_func(RUNTIME_PATH, AI_PATH .. aiName, env)`), quindi niente file in `STAI/`.
- `9d87d53c19` «STAI LosHST: keep a mobile unit that leaves the los on radar as a ghost»: `loshst.lua` e il test nuovo `loshst_spec.lua`.
- Un commit per questi risultati.

**1. Una istanza, eventi prima di `LosHST`**

- Dal codice: `DeliverSight` (`loader/delivery.lua` r. 173) manda l'evento prima agli oggetti `ShardAlly` dell'alleanza **che vede** (`Shard.alliesByAllyID[allyTeam]`), poi a tutte le AI. Quindi `PerceptionHandler` vede solo gli eventi della sua alleanza (non gli serve il filtro `allyTeam` che ha `LosHST`) e li vede prima. Il team prende l'istanza dell'alleanza in `LoadModule` (`self[internalname] = shared`).
- Prova (patch `[S8B-PH]` non committata, partita B: due STAI nell'alleanza 0, 10 minuti): una sola riga `ally 0, ShardAlly, Info: , adding PerceptionHandler module`; in ogni evento di `LosHST`, dopo il filtro, controllo che `PerceptionHandler` lo abbia già registrato (`Sees` vero in `UnitEnteredLos`, falso in `UnitLeftLos`; `OnRadar` vero in `UnitEnteredRadar`, falso in `UnitLeftRadar`): **457 eventi per ciascuno dei due team, 0 al contrario**. Nessuna riga `[AI Loader] error`.

**2. Le ombre** (`loshst.lua`)

- `Init`: `self.ghostEnemy = {}` (`[unitID] = unitDefID`), commento a fine riga.
- `UnitLeftLos`: fra il ramo degli edifici e quello di prima, `elseif self.ai.perceptionhandler:OnRadar(unitID) then` → `losEnemy` nil, `ghostEnemy[unitID] = unitDefID`. Edifici e unità mobili fuori dal radar come prima.
- Uscite: `UnitEnteredLos` (torna in `losEnemy`), `UnitLeftRadar`, `cleanEnemy` (quindi anche `UnitDead` e le unità morte o senza posizione in `Update`).
- `Update`: terzo ciclo, su `ghostEnemy`, uguale a quello del radar ma con `setCellLos` (tipo noto) alla posizione di `GetRawPos`, come oggi per il radar.
- Il `Warn` vale per i tre insiemi: `LosHST:countSets(id)` (in quanti dei tre è l'unità), `if self:countSets(id) > 1` nei tre cicli; testo «unit in more than one of los, radar and ghost, with losStatus:». Nelle partite non è mai uscito.
- `Draw`: le ombre in giallo, come gli altri due insiemi.
- Ordine degli eventi dell'engine, da sapere: quando un'unità esce insieme da los e radar, `UnitLeftLos` arriva prima di `UnitLeftRadar`, quindi diventa ombra per un attimo e l'evento dopo la toglie. Le misure (nessuna appesa) lo confermano.
- `UnitEnteredRadar` non l'ho toccato: un'ombra non può ricevere `UnitEnteredRadar` (il radar non si è interrotto); se succedesse, il `Warn` lo direbbe.

**Lettori di `losEnemy` fuori da `LosHST`**: nessuno cambia.

- `damagehst.lua` r. 41–42: scrive in `losEnemy` solo un attaccante **edificio** (`attackerut.isBuilding`), e gli edifici non diventano mai ombre. **Difetto visto**: scrive il `defId` del **difensore** (`defenderUt.defId`), non dell'attaccante. Le misure lo mostrano: 1–3 unità «mobili» in `losEnemy` che `PerceptionHandler` non vede, e sono torrette che sparano da fuori vista (`corllt` scritta come `armham`, `armhlt` come `corstorm`, `armbeamer` come `corthud`…). Oggi senza effetti: il valore di `losEnemy` non lo legge nessuno (`Update` usa `unit:Name()`), e per `UnitLeftLos` conta l'`unitDefID` dell'evento. Non toccato.
- `scoutbst.lua` r. 135 (`Attacking`): l'esploratore insegue solo ciò che vede (`self.attacking` viene da `Spring.GetUnitNearestEnemy` con `useLos`, nel raggio di vista). Ho deciso di **non** fargli inseguire le ombre: comportamento uguale a prima (lascia il bersaglio quando esce dalla vista), e la posizione dell'ombra è quella del radar, imprecisa. Se vuoi che insegua anche le ombre è una riga (`and not self.ai.loshst.ghostEnemy[...]`).

**3. Coerenza con l'engine**: `PerceptionHandler` serve in un punto solo, `UnitLeftLos` (`OnRadar`), dove `LosHST` da solo non lo sa. Il resto resta sugli eventi, perché:

- il filtro `allyTeam ~= self.ai.allyId` serve finché `LosHST` è `"team"` (le AI ricevono gli eventi di tutte le alleanze);
- `UnitEnteredRadar` controlla `losEnemy`, che è **memoria** (gli edifici usciti dalla vista restano), non un fatto dell'engine: con `Sees` un edificio ricordato che entra nel radar finirebbe anche in `radarEnemy`;
- leggere in `Update` gli insiemi di `PerceptionHandler` al posto degli eventi toglierebbe il momento in cui un'unità passa da los a ombra, cioè proprio la memoria.
- Nessuna lettura nuova di `Spring.*`.

**4. Misure** (`[S8B-MEASURE]`, non committate: al primo `Update` di `LosHST` ogni 300 frame, per team; in più contatori delle ombre fatte e di come escono, ombre appese = in `ghostEnemy` ma non `OnRadar`, ombre che `Sees`)

| partita | campioni | `losEnemy` media (max) | `radarEnemy` media | `ghostEnemy` media | campioni con ombre | celle vere di `ENEMY` media (max) | ombre fatte | → los | → fuori radar | → `cleanEnemy` | max insieme | appese | in los |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | 89 | 1,5 (6) | 0,01 | 0 | 0 | 1,2 (5) | 71 | 5 | 66 | 0 | 1 | 0 | 0 |
| A2 | 89 | 5,9 (14) | 0,44 | 0,34 | 12 | 5,3 (11) | 176 | 59 | 117 | 0 | 6 | 0 | 0 |
| A3 | 89 | 12,5 (27) | 0,06 | 0 | 0 | 9,1 (20) | 125 | 17 | 108 | 0 | 3 | 0 | 0 |
| C, team 0 | 89 | 4,2 | 2,0 | 0,87 | 9 | 4,1 | 233 | 57 | 176 | 0 | 12 | 0 | 0 |
| C, team 1 | 89 | 2,7 | 1,6 | 0,33 | 8 | 2,9 | 182 | 56 | 124 | 0 | 12 | 0 | 0 |

- **Quante ombre**: di solito **nessuna** nell'istante del campione; durano poco. Per partita se ne fanno 71–233; il 65–90 % esce perché l'unità lascia anche il radar, il resto torna in los. Al massimo 1–6 insieme nelle partite A, 12 nella C (STAI contro STAI, più radar).
- **Ombre appese: 0** in ogni campione, e nessuna ombra mentre `PerceptionHandler` la vede in los. Nessuna esce con `cleanEnemy`: nessuna ombra è morta da ombra, o l'engine manda `UnitLeftRadar` prima di `UnitDestroyed` (non l'ho verificato).
- `radarEnemy` è quasi sempre vuoto nelle partite A: contro SimpleAI su Comet Catcher STAI vede poco in solo radar.

**Test** (`spec/luarules/gadgets/ai/STAI/loshst_spec.lua`; `LosHST` si carica come `MapHST` nel suo test, con `gridhst`, `UnitDefs`, `game` e `PerceptionHandler` finti)

- «keeps a mobile unit that leaves the los while on radar as a ghost of its type»; «forgets a mobile unit that leaves the los off radar»; «moves a ghost back to the los when it enters the los again»; «forgets a ghost when it leaves the radar, or dies» (`UnitLeftRadar` e `cleanEnemy`); «keeps a building that leaves the los in the los, on radar or not»; «marks a ghost in the cell of its radar position as a unit of known type» (`Update` con `setCellLos`/`setCellRadar` registrati; c'è anche un'unità di un'altra alleanza, che resta fuori).
- Mutazioni, ognuna fa fallire almeno un test: `loshst.lua` della base (1 fallito, 5 in errore: anche il test degli edifici, che legge `ghostEnemy`); ombra mai fatta (2); ombra sempre, senza `OnRadar` (1); `UnitEnteredLos` che lascia l'ombra (1); `UnitLeftRadar` che la lascia (1); `cleanEnemy` che la lascia (1); ombra segnata con `setCellRadar` (1). Col codice giusto 2757 successi, 0 falliti.

**Tre partite A** (`a_stai_vs_simpleai.txt`, `SHARD_MEM_STATS=1`, 15 minuti, codice `9d87d53c19` più la patch di misura, uscita 0 tutte e tre)

| | partita 1 | partita 2 | partita 3 | S8a | S6 | S1 (intervallo) |
| --- | --- | --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 5 / 38 / 108 / 152 | 5 / 38 / 86 / 149 | 6 / 37 / 101 / 171 | 6/34/91/160 · 6/36/89/148 · 5/37/96/174 | 6/33/79/138 · 5/36/101/154 · 6/33/88/133 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14) | 168 unità, 2 fabbriche, 33 mex | 166, 2, 29 | 198, 2, 39 | 182/178/202, 2, 34/34/38 | 157/178/155, 1–2, 26/33/30 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 190, 2, 34 | 197, 2, 34 | 212, 2, 43 | 202/194/219 | 175/200/181 | — |
| relay: messaggi | 3891 | 3359 | 3301 | 3825 / 4389 / 3316 | 3095 / 3572 / 3247 | 3405–3933 |
| relay: ordini dati | 13383 | 14721 | 19508 | 13138 / 18564 / 16422 | 12678 / 15278 / 14002 | 10445–15948 |
| relay: ordini rifiutati | 16 | 8 | 13 | 17 / 11 / 19 | 7 / 4 / 8 | 9–16 |
| messaggi rifiutati | nessuno | nessuno | nessuno | nessuno | nessuno | nessuno |
| memoria per frame, medie per minuto | 0,19–0,76 (media 0,40) | 0,18–0,67 (0,37) | 0,18–0,62 (0,38) | 0,36–0,38 di media | 0,35 / 0,37 / 0,39 | 0,37–0,45 |
| memoria per frame, picco | 127,8 KB (min. 11) | 64,2 KB (min. 13) | 75,0 KB (min. 11) | 111,9 / 104,2 / 217,9 | 159,0 / 124,6 / 90,1 | 67,9–73,5 |
| heap | 12,9–14,8 MB | 12,9–14,4 MB | 12,9–15,1 MB | 12,9–15,5 | 13,1–16,0 | 13,1–15,5 |
| righe `[AI Loader] error` | 0 | 0 | 0 | 0 | 0 | 0 |
| tempo reale | 20 s | 19 s | 20 s | 18–20 s | 18–21 s | 19–21 s |

- **Nessuna partita sta sotto i riferimenti**: a fine partita 168/166/198 unità e 33/29/39 mex, dentro o sopra S1 e S6; la partita 3 è la più alta finora per mex al `SUMMARY` (43). Al minuto 13 le partite 1 e 2 sono nell'intervallo di S1, la 3 sopra (171).
- Ordini: la partita 3 (19508) sopra S1, come la 2 di S8a; rifiutati 8–16, nell'intervallo. Messaggi delle partite 2 e 3 (3359, 3301) un po' sotto S1, come in S6 e S8a.
- Memoria: medie come S1–S8a; la partita 1 ha l'ultimo minuto a 0,76 (dopo il `SUMMARY`), il valore più alto delle medie per minuto finora; picchi 64–128 KB, sotto S8a. Heap come prima. Con il seme che cambia a ogni partita non lo attribuisco al cambio.
- Partita C (`c_stai_vs_stai.txt`, solo per le misure): team 0 146 unità, 2 fabbriche, 26 mex al minuto 14, team 1 162, 1, 23; relay 5204 / 29055 / 40 rifiutati (S7: 4551–4826 / 23553–26134 / 16–31).
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown). Nessuno cita Shard, STAI, `LosHST` o `PerceptionHandler`.

**Controlli**

- `lx --lua-version 5.1 test`: 2757 successi, 0 falliti, 1 pending (2751 + 6). `run_engine_tests.sh` (codice finale): `RESULT: ok`.
- StyLua 2.5.2 (dalla radice) su `loshst.lua`, `modules.lua`, `loshst_spec.lua`: ok.
- EmmyLua 0.24.0, confronto con un worktree della base `7ba9c26c05`: 20 errori, negli stessi file. `loshst.lua` 10 avvisi prima e dopo, hint 15 → 17 (i due `def` non usati dei cicli nuovi su `ghostEnemy`, in `Update` e `Draw`, scritti come gli altri cicli di STAI); `modules.lua` e `loshst_spec.lua` senza diagnostiche.
- `.emmyrc.json` ripristinato; `git status` pulito a parte i file di `.ai-notes/`. Niente codice tolto, quindi `codice-tolto.md` non cambia.

**Difetti visti, non toccati**

- `DamageHST` r. 41: `losEnemy[attacker:ID()] = defenderUt.defId` scrive il tipo del difensore (sopra).

### S8a (agente locale, 25 novembre 2026) — verificato dal coordinatore

**In breve**: `ENEMY` è uno strato di `GridHST`; `OWN`, `ALLY`, `ALLIES`, i pool e il resto morto di `LosHST` sono tolti. **La condizione di stop del punto 4 è scattata** (righe separate al frame 4200, prima di un nemico in vista nella partita di partenza), ma la prova fra partite diverse non può funzionare: **due partite con lo stesso codice di partenza si separano anche loro**, perché il seme di `math.random` di ogni AI viene dal `GameID`, diverso a ogni avvio. Al suo posto ho fatto la prova **nella stessa partita** (vecchia griglia ricalcolata accanto allo strato, confronto cella per cella a ogni `Update`): **0 differenze in tutta la partita**. L'utente ha visto i numeri e ha deciso di proseguire. Le tre partite A non stanno sotto i riferimenti.

**Commit**

- `1b2d66a725` «STAI GridHST: read the marked cells of a layer; cell fields of a grid X, Z»: `GridLayer:GetMarked(i)` (cella se l'indice è nella lista, se no `nil`; `marked` resta interno); `areaGridCells` e `getGridCellsFields`, sorelle per le griglie `[X][Z]` con `--TODO remove when DAMAGED is a layer`; `getCellsFields` e la sorella sommano con `sumCellsFields` (il corpo di prima, uguale). `TargetHST:GetPathModifierFunc` (`DAMAGED`) passa a `getGridCellsFields`. Test.
- `98759bfc3c` «STAI LosHST: keep the enemy cells in an ENEMY layer of GridHST»: `LosHST`, `GetCell`/`areaCells`/`getCellsFields` sugli strati, i lettori, test.
- `500ba9cf56` «STAI LosHST: drop the OWN, ALLY and ALLIES grids and the dead code».
- Un commit per l'indice e questi risultati.

**Scelta per le funzioni di `GridHST`** (punto 1): `GetCell`, `areaCells`, `getCellsFields` **tengono il nome e prendono uno strato**; le sorelle sono quelle **per `[X][Z]`** (`areaGridCells`, `getGridCellsFields`), usate solo da `DAMAGED` (un lettore, `targethst.lua` r. 170). Così ora cambia una riga per `DAMAGED` invece di otto per `ENEMY`, e quando `DAMAGED` diventa uno strato si tolgono le due sorelle senza toccare i lettori. `GetCell` per `[X][Z]` non serve a nessuno, quindi niente sorella. Bordi: `areaCells` e `GetCell` chiamano `IsCellInGrid` prima di `GridToIndex` (commento sul perché); `Blobbing` passa da `GetCell`.

**`LosHST`** (`98759bfc3c`)

- `self.ENEMY = self.ai.gridhst:NewLayer(self.resetCell)`. `LosHST.resetCell(CELL)` è la parte di azzeramento di `setupCell` (stessi campi, stesso ordine; `units` e `buildings` svuotate e riusate, create se mancano). Funzione con il punto al posto di `setupCell`, così sta dove stava e `Init` resta prima.
- `LosHST:getEnemyCell(X, Z)`: indice, `Get`, `X`/`Z`/`POS` scritti solo se la cella è nuova (`if not CELL.POS`), `Mark`. `setCellLos(unit, X, Z)` e `setCellRadar(unit, X, Z)`: `IsCellInGrid` come prima, poi `getEnemyCell`; senza il parametro `grid` e senza `grid[X][Z] = CELL` finale.
- `Update`: `self.ENEMY:Clear()` al posto di `FreeCellsToPool("ENEMY")`. Via `GetCellFromPool`, `buildPools("poolENEMY")`, il commento sul pool.
- `Draw`: ciclo numerico su `LIST`.

**Lettori** (grep `loshst.ENEMY`, `loshst.OWN`, `loshst.ALLY`, `local loshst`: la lista del coordinatore era completa; nient'altro legge `ENEMY`)

| dove (righe della base) | prima | dopo |
| --- | --- | --- |
| `targethst.lua` r. 42 (`GetBlobs`) | `pairs` su `ENEMY[X][Z]` | ciclo su `LIST`, `blobref = CELL.X .. ":" .. CELL.Z` |
| `targethst.lua` r. 56–61 | `ENEMY[v.X][v.Z]` quattro volte | `local CELL = gridhst:GetCell(v.X, v.Z, ENEMY)` |
| `targethst.lua` r. 71–74 (`Blobbing`) | `grid[x] and grid[x][z] and …` | `GetCell(x, z, layer)` (nil fuori dai bordi; la ricorsione va oltre) |
| `targethst.lua` r. 112 (`EnemiesCellsAnalisy`) | `pairs` | ciclo su `LIST` |
| `targethst.lua` r. 170 | `getCellsFields(…, DAMAGED)` | `getGridCellsFields(…, DAMAGED)` |
| `attackhst.lua` r. 343–347 | `ENEMY[X][Z]` tre volte | `local CELL = GetCell(…)`, poi `CELL` |
| `attackhst.lua` r. 561–562 | `ENEMY[X] and ENEMY[X][Z]` | `GetCell(…)` |
| `raidhst.lua` r. 400, 424 | `loshst.ENEMY[X][Z]` | `self.ai.gridhst:GetCell(X, Z, loshst.ENEMY)` |
| `nukebst.lua` r. 55–56 | `not ENEMY[X] or not ENEMY[X][Z]` | `not GetCell(…)` |
| `nukebst.lua` r. 72–74, `bomberhst.lua` r. 164 | `pairs` | ciclo su `LIST` |
| `scouthst.lua` r. 77 | `ENEMY[X] and ENEMY[X][Z]` | `GetCell(X, Z, ENEMY)` |
| `attackhst` r. 268, `raidhst` r. 291, `buildingshst` r. 765, `targethst` r. 140 e 162, `scoutbst` r. 195, `nukebst` r. 74, `commanderbst` r. 25 | passano `ENEMY` | invariati: `ENEMY` ora è lo strato |

**Codice morto** (`500ba9cf56`; tutto in `codice-tolto.md`)

- `LosHST`: `OWN`, `ALLY`, `ALLIES`, `buildPools`, `poolOWN`, `poolALLIES`, `FreeCellsToPool` (e le sue due chiamate in `Update`), il ciclo di `OWN` in `Draw`; da `Init` `knownEnemies`, `ownMobile`, `allyImmobile`, `allyMobile` (grep in tutto STAI: solo scritture in `Init`, `UnitCreated`, `UnitDead`); `UnitDamaged` con il blocco commentato (il runtime registra un modulo per un evento solo se lo ridefinisce, `WantsEvent` in `shardai.lua`: ora `LosHST` non lo riceve più); il commento della classe («OWN ALLY ENEMY»), ora sbagliato, riscritto.
- **Oltre l'elenco** (dimmi se va bene): `viewPos`, `posInLos`, `setPosLayer` (mai chiamate: `viewPos` la chiama solo `posInLos`, che non chiama nessuno; resta `setPosLayer2`), le righe commentate `uPos`/`target` («NEVER USED») di `setCellLos`/`setCellRadar`. In `UnitCreated`, tolto il ramo alleato, restava un `getCenter()` doppio (dentro il ramo e alla fine): l'ho lasciato una volta sola; `getCenter` ricalcola `CENTER` da zero, quindi stesso risultato. `friendlyTeamID`, `losEnemy`, `radarEnemy`, gli eventi di los e radar e le note sui bit di los in fondo al file **restano** (S8b).
- Lettori, riga per riga (righe della base):
  - `attackhst.lua` r. 544–557, in `SquadAttackbackup`: tutto il blocco `if self.ai.loshst.OWN[…] … end` (due cicli su `squad.members`, il primo vuoto, `GiveOrder` con `FIGHT`, `EchoDebug` «execute defense», `return true`). Il resto della funzione com'è.
  - `scouthst.lua` r. 81–84, in `TargetAvailable`: i due `elseif` su `OWN` e `ALLY` con i loro `EchoDebug`.
  - `attackhst.lua` r. 596 e 612 **non li ho toccati**: sono dentro il blocco commentato `--[[ … ]]` che va da r. 584 alla fine del file (una vecchia `SquadAttack`). Da sapere: anche `SquadAttackbackup` non la chiama nessuno (grep). Se vuoi, si tolgono tutte e due in un compito di pulizia di `AttackHST`.

**Prova (punto 4)**

Patch `[S8A-PROOF]` (non committata, `c_stai_vs_stai.txt`, 15 minuti): al primo `Update` di `LosHST` da ogni multiplo di 300, per team, celle vere e somme di `ENEMY`, `ARMED`, `UNARM`, `unitsCount` in ordine di indice, più il numero di unità in `losEnemy`/`radarEnemy`. `LosHST` gira agli stessi frame in tutte le partite (2, 308, 614, 902 …).

| confronto | seme team 0 | prima riga diversa | cosa |
| --- | --- | --- | --- |
| partenza `1b2d66a725` (p. 1) | 29484 | — | primo nemico in vista al frame 7500 |
| codice nuovo `98759bfc3c` contro p. 1 | 15381 | frame 4200 (team 0) | il codice nuovo vede un nemico a 4200, la partenza non ne vede fino a 7500 |
| partenza (p. 2) contro partenza (p. 1), **stesso codice** | 33689 | frame 6900 | la p. 2 vede il primo nemico a 6900 |

- Quindi il gioco si separa fra partite **anche a codice uguale**, prima di ogni contatto. Causa: `[AI Loader] AI team <n> random seed <seme>`, con il seme dall'hash del `GameID` (`shard_runtime/loader/types.lua`, `TeamSeed`), e STAI usa `math.random` in `buildingshst.lua` (r. 171 angolo iniziale, r. 642, 663), `labsbst.lua` (r. 285, 293), `behaviourfactory.lua` (r. 60), `bomberbst.lua`, `attackhst.lua` (colore). I semi delle tre partite: 29484, 33689, 15381.
- **Prova nella stessa partita** (`[S8A-SHADOW]`, non committata): dopo ogni `Update` di `LosHST` (codice nuovo) ricalcolo la griglia `[X][Z]` con le funzioni della base (`setupCell`, `setCellLos`, `setCellRadar` copiate, con un pool per `X`, `Z` che si comporta come quello vecchio, quindi anche `base` che resta) sugli stessi `losEnemy`/`radarEnemy`, e confronto **ogni cella**: presenza, ogni campo numerico, `units`, `buildings`, `base`, `X`, `Z`, `POS`; in più `#LIST` = celle segnate.

| codice | team | `Update` controllati | celle confrontate | differenze |
| --- | --- | --- | --- | --- |
| `98759bfc3c` (strato e lettori) | 0 / 1 | 1501 / 1501 | 8520 / 7730 | 0 / 0 |
| `500ba9cf56` prima del ritocco per EmmyLua (sotto) | 0 / 1 | 1501 / 1501 | 10427 / 10960 | 0 / 0 |
| codice finale | 0 / 1 | 1501 / 1501 | 7109 / 6402 | 0 / 0 |

- La prova vede gli errori: con la mutazione `CELL.unitsCount = CELL.unitsCount or 0` in `resetCell` escono subito le differenze (`mismatch, 0, 4700, 16, 11, field unitsCount 1 2`, …).
- Quindi lo strato contiene esattamente quello che conteneva la griglia, per tutta la partita. Il gioco cambia solo per l'ordine dei lettori (`LIST` al posto di `pairs`), e da una partita all'altra cambia comunque per il seme.
- **Proposta**: per confrontare partite fra versioni di codice serve un seme fisso (per esempio una variabile d'ambiente o un'opzione del loader che sostituisce l'hash del `GameID`). È un cambio al framework: non l'ho fatto.

**Tre partite A** (`a_stai_vs_simpleai.txt`, `SHARD_MEM_STATS=1`, 15 minuti, codice finale, uscita 0 tutte e tre)

| | partita 1 | partita 2 | partita 3 | S6 | S1 (intervallo) |
| --- | --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6 / 34 / 91 / 160 | 6 / 36 / 89 / 148 | 5 / 37 / 96 / 174 | 6/33/79/138 · 5/36/101/154 · 6/33/88/133 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14) | 182 unità, 2 fabbriche, 34 mex | 178, 2, 34 | 202, 2, 38 | 157/178/155, 1–2, 26/33/30 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 202, 2, 37 | 194, 2, 41 | 219, 2, 41 | 175/200/181 | — |
| relay: messaggi | 3825 | 4389 | 3316 | 3095 / 3572 / 3247 | 3405–3933 |
| relay: ordini dati | 13138 | 18564 | 16422 | 12678 / 15278 / 14002 | 10445–15948 |
| relay: ordini rifiutati | 17 | 11 | 19 | 7 / 4 / 8 | 9–16 |
| messaggi rifiutati | nessuno | nessuno | nessuno | nessuno | nessuno |
| memoria per frame, medie per minuto | 0,19–0,58 (media 0,38) | 0,19–0,66 (0,36) | 0,18–0,66 (0,37) | 0,35 / 0,37 / 0,39 | 0,37–0,45 |
| memoria per frame, picco | 111,9 KB (min. 11) | 104,2 KB (min. 12) | **217,9 KB** (min. 12) | 159,0 / 124,6 / 90,1 | 67,9–73,5 |
| heap | 12,9–14,5 MB | 13,0–15,5 MB | 12,9–14,6 MB | 13,1–16,0 | 13,1–15,5 |
| righe `[AI Loader] error` | 0 | 0 | 0 | 0 | 0 |
| tempo reale | 18 s | 20 s | 19 s | 18–21 s | 19–21 s |

- **Nessuna partita sta sotto i riferimenti**: unità a fine partita 182/178/202 e mex 34/34/38, alla pari o sopra S6 e il massimo di S1 (la partita 3 sopra: 202 unità, 38 mex). Al minuto 13 le partite 1 e 3 sono sopra l'intervallo di S1 (160, 174). Con il seme che cambia a ogni partita non lo attribuisco al cambio.
- Ordini: la partita 2 (18564) sopra S1; rifiutati 11–19, la partita 3 (19) poco sopra S1. Messaggi della partita 3 (3316) sotto S1, come la partita 1 di S6. Nessun messaggio rifiutato.
- **Picco di memoria per frame 217,9 KB** nella partita 3: il più alto finora (S6 159,0). Le medie sono le stesse di S1 e S6; l'heap parte un po' più basso (12,9 MB contro 13,1; probabilmente perché non ci sono più i tre pool da 768 tabelle per team) e non supera S6. Il punto 17 di `nuovo-stai.md` resta «da osservare».
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown). Nessuno cita Shard, STAI o i moduli toccati.

**Test** (`gridhst_spec.lua`)

- «gives the data of a cell only while the cell is in the list» (`GetMarked`): `nil` prima di `Mark`, la cella dopo, `nil` su un'altra, `nil` dopo `Clear` con la tabella ancora in `CELLS`.
- «sums the fields of the cells of a grid X, Z around a position» (`getGridCellsFields`).
- «reads only the true cells of a layer, and nothing past the edges»: griglia 6 × 4; celle segnate in 2, 1 e 3, 1, che hanno l'indice di 1, 5 e 2, 5 (oltre il bordo `Z = 4`); `areaCells(1, 4, 1)` dà solo le due celle vere dentro la griglia, nell'ordine; `GetCell` con `X, Z` e con una posizione; `nil` su 1, 5, su 0, 2 e su una cella con dati ma non segnata; `getCellsFields` somma solo quelle.
- Mutazioni, ognuna fa fallire un test: `GetMarked` che ignora la lista; `gridhst.lua` della base (commit 1: due test in errore; commit 2: il test dei bordi); `areaCells` senza `IsCellInGrid`; `GetCell` senza `IsCellInGrid`.

**Controlli**

- `lx --lua-version 5.1 test`: 2751 successi, 0 falliti, 1 pending (2748 + 3). `run_engine_tests.sh` (codice finale): `RESULT: ok`.
- StyLua 2.5.2 (dalla radice) su tutti i file toccati: ok.
- EmmyLua 0.24.0, confronto con un worktree della base `a21bf909da`: 20 errori, negli stessi file. Per file (avvisi/hint, base → finale): `loshst.lua` 21/25 → 10/15, `gridhst.lua` 0/9 → 0/9, `targethst.lua` 63/18 → 63/15, `attackhst.lua` 7/27 → 7/24, `raidhst.lua` 5/24 → 5/24, `nukebst.lua` 5/5 → 5/3, `scouthst.lua` 0/5 → 0/5, `bomberhst.lua` 5/12 → 5/10; `gridhst_spec.lua` senza diagnostiche.
- Da sapere su EmmyLua: togliendo il ciclo su `self.OWN` da `Draw` comparivano 15 avvisi `cellElmosHalf value may be nil` nel ciclo di `ENEMY` (prima il ciclo su un campo inesistente faceva saltare l'analisi di tutta la funzione); risolti con `---@type number` sulla riga di `cellElmosHalf`. In `getEnemyCell` `X`, `Z` vengono dai parametri (sono gli stessi numeri di `CELLS[i].X`, `.Z`), così niente avvisi «Undefined field». Tutti e due i ritocchi sono dentro i commit 2 e 3 (prima del push); la prova nella stessa partita e i test sono rifatti sul codice finale, le tre partite A no (il ritocco non cambia niente in gioco).
- `.emmyrc.json` ripristinato; `git status` pulito a parte i file di `.ai-notes/`.

**Difetti visti, non toccati** (il gioco non cambia, quindi li lascio a te)

- `CELL.base` (fabbrica nemica nella cella) non si azzera mai: non lo faceva `setupCell` e il pool teneva una tabella per cella, quindi una cella che ha visto una fabbrica resta «base» per sempre quando torna vera. Con lo strato è uguale (la prova lo confronta). Si sistema aggiungendo `CELL.base = nil` a `resetCell`, ma cambia `TargetHST.enemyBasePosition`.
- `TargetHST:NearbyVulnerable` legge `subValues.armed`/`subValues.unarm`, ma le chiavi sono `"ARMED"`/`"UNARM"`: la condizione non è mai vera.
- `LosHST:getCenter` divide per `count` anche quando è 0 (nessun edificio proprio): `CENTER` diventa `NaN`.
- `posG`, `posS`, `posB`, `posA` in `LosHST:Draw` sono globali.

### S7 (agente locale, 25 novembre 2026) — verificato dal coordinatore. La guardia `next(fresh) ~= nil` va bene (il coordinatore consiglia di lasciare `GameStart` com'è)

**Cosa ho fatto**

- Commit `5d8d4a9b6e` «Shard loader: collect the garbage once at the end of StartAIs» (`lifecycle.lua` e il suo test):
  - in `StartAIs`, dopo l'ultimo `DropFailed(failed)` e prima di `return fresh`: `if next(fresh) ~= nil then collectgarbage("collect") -- clean up after the start-up analyses of the AIs end`. **La guardia `next(fresh) ~= nil` non era nel compito**: senza, in una partita normale le `collect` sarebbero due (sotto). Una riga in più nel commento sopra `StartAIs` dice perché.
  - `CatchUpAfterReload`: `return` dopo `CatchUp(StartAIs())`. A partita avviata la `collect` di `StartAIs` gira sempre (dopo un reload tutti gli oggetti sono nuovi, quindi `fresh` non è vuota) e quella vecchia era doppia; al frame 0 `StartAIs` non viene chiamata e la `collect` vecchia («clean start, as in the old loader») resta.
- Commit `ba9a8b29fe` «STAI MapHST: drop the collectgarbage at the end of Init»: solo la riga 38 di `maphst.lua`. Aggiunta a `codice-tolto.md` (S7).
- Commit `6883bf0a2c` «STAI MapHST: check drawDebug before erasing the debug channels» (parte 2b, arrivata sul remoto dopo il mio primo pull; l'ho vista al push e l'ho fatta dopo il rebase): `if not self.ai.drawDebug then return end` prima del ciclo `EraseAll`, nient'altro. Con un `Echo` temporaneo nel ciclo: 0 chiamate a `EraseAll` nella partita di prova. Test nuovo in `spec/luarules/gadgets/ai/STAI/maphst_spec.lua` (stesso schema di `gridhst_spec.lua`).

**Quante volte gira `StartAIs`** (traceback temporaneo, partita C)

| chiamata | da dove | quando | `fresh` | `collect` |
| --- | --- | --- | --- | --- |
| 1 | `UnitCreated` → `StartAIsOnce` (le unità di partenza nascono nel `GameStart` di `game_initial_spawn`, prima di quello del loader) | frame 0 | 5 (globale, 2 alleanze, 2 team) | sì |
| 2 | `GameStart` del loader, che chiama `StartAIs` senza `Once` | frame 0, subito dopo | 0 | no (con la guardia) |

- Quindi in una partita normale `StartAIs` gira **due volte**, la `collect` **una**. In alternativa alla guardia si può far chiamare `StartAIsOnce` a `GameStart` (`ShardAILoader.lua` r. 152); non l'ho fatto perché tocca un altro file del framework e il compito non lo chiede. Decidi tu.
- Altre chiamate: `CatchUpAfterReload` (solo con `/luarules reload` a partita avviata: una `collect`, quella di `StartAIs`; al frame 0 non chiama `StartAIs` e fa la sua `collect`, 1 ms) e `HostChanged`, quando un team passa a questo client a partita avviata: `AddAI` + `StartAIs` con l'alleanza (se nuova) e il team nuovi, quindi **una `collect` in più a metà partita**, una volta per cambio di host. `AddAI` da sola (in `AddHostedAIs`, all'`Initialize`) non chiama `StartAIs`.

**Prova che il gioco non cambia** (patch `[S3-PROOF]` di S6, `c_stai_vs_stai.txt`): righe identiche fra partenza `2379418f9c`, codice con le parti 1 e 2, e codice finale con la 2b (2 minuti; `diff` vuoto tutte e due le volte):

```
[S3-PROOF] grid, global, 32, 24, 768, 295296, 295296
[S3-PROOF] map, global, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] tool, global, 80, 400, 5120.0000000000 10240.0000000000 130983.9921875000 103122.6718750000, 80, 2048
[S3-PROOF] trampled, 1, 79, 406400.0000000000 296576.0000000000 2.118384599685669
[S3-PROOF] trampled, 0, 68, 208640.0000000000 141568.0000000000 2.246112346649170
```

**Misure** (`SHARD_MEM_STATS=1`, partita C di 5 minuti prima e dopo; timer temporanei, non committati). `Spring.DiffTimers` qui dà solo millesimi interi (1, 12, 13 ms): risoluzione 1 ms.

| | prima (`2379418f9c`) | dopo |
| --- | --- | --- |
| `collect` dell'`Initialize` (frame 0) | 1 ms, 9552 → 7057 KB | 1 ms, 9553 → 7058 KB |
| `collect` di avvio | `MapHST:Init`: 12 ms, 30285 → 12621 KB | fine di `StartAIs`: 13 ms, 31637 → 13602 KB |
| frame | 0 (dentro la prima `StartAIs`) | 0 (fine della prima `StartAIs`) |
| heap alla fine della prima `StartAIs` | 13980 KB (dopo la `collect` di `MapHST` gli `Init` di alleanze e team aggiungono ~1,4 MB) | 13602 KB |
| heap alla seconda `StartAIs` (dopo gli eventi delle unità di partenza) | 15081 KB | 14703 KB |
| memoria per frame, min. 1–5: media / picco KB | 0,31/25,9 · 0,28/15,1 · 0,35/36,9 · 0,42/37,9 · 0,42/28,7 | 0,34/25,9 · 0,28/11,7 · 0,32/34,9 · 0,41/27,9 · 0,41/17,1 |
| heap min. 1–5 | 13,7 · 13,7 · 13,7 · 14,1 · 14,3 MB | 13,7 · 13,7 · 13,9 · 13,9 · 14,1 MB |

- La `collect` costa uguale (12–13 ms: c'è più roba, perché ora raccoglie anche gli `Init` di alleanze e team) e lascia l'heap ~0,4 MB più basso a fine avvio. Dal minuto 1 i numeri sono gli stessi.

**Partite C** (`c_stai_vs_stai.txt`, 15 minuti, `SHARD_MEM_STATS=1`, uscita 0, 21–22 s). Le partite 1 e 2 sono senza la 2b (codice `ba9a8b29fe`); la 2 l'ho fatta perché nella 1 il team 1 restava sotto le partite C di prima (16 mex al minuto 14). La partita 3 è con il codice finale `6883bf0a2c`.

| | p. 1, team 0 | p. 1, team 1 | p. 2, team 0 | p. 2, team 1 | p. 3, team 0 | p. 3, team 1 |
| --- | --- | --- | --- | --- | --- | --- |
| unità min. 1 / 5 / 10 / 13 | 7 / 37 / 99 / 153 | 6 / 34 / 87 / 126 | 7 / 36 / 87 / 107 | 6 / 36 / 105 / 157 | 7 / 35 / 97 / 132 | 6 / 34 / 72 / 123 |
| mex min. 5 / 10 / 13 | 6 / 20 / 26 | 5 / 14 / 18 | 5 / 15 / 18 | 6 / 17 / 25 | 6 / 17 / 20 | 5 / 11 / 16 |
| min. 14 | 155 unità, 2 fabbriche, 30 mex | 129, 2, 16 | 107, 2, 17 | 156, 2, 26 | 144, 2, 23 | 134, 2, 19 |
| `SUMMARY` | 158, 2, 29 | 135, 2, 18 | 113, 2, 15 | 175, 2, 29 | 151, 2, 24 | 126, 2, 18 |

| | partita 1 | partita 2 | partita 3 (finale) |
| --- | --- | --- | --- |
| relay: messaggi / ordini / rifiutati | 4686 / 26134 / 31 | 4826 / 23553 / 16 | 4551 / 24582 / 17 |
| messaggi rifiutati | nessuno | nessuno | nessuno |
| memoria per frame, medie per minuto | 0,28–0,98 KB | 0,28–0,87 KB | 0,29–0,92 KB |
| memoria per frame, picco | 81,1 KB (min. 11) | 156,5 KB (min. 12) | 153,1 KB (min. 14) |
| heap | 13,7–17,2 MB | 13,7–16,6 MB | 13,7–16,5 MB |
| `Shard memory record` | 17634 | — | 17759 |
| righe `[AI Loader] error` | 0 | 0 | 0 |

- In C le due STAI si combattono: nella partita 1 resta indietro il team 1, nella 2 il team 0; la squadra in vantaggio sta nei valori delle partite C di prima (S4a, S4b, S5). Lo attribuisco alla variabilità (l'avvio è identico, righe di prova sopra). Nella partita 3 il team 0 è nei valori di prima (144 unità, 23 mex al minuto 14), il team 1 un po' sotto nei mex (19; prima 20–32).
- Le partite C di prima non avevano `SHARD_MEM_STATS`, quindi per memoria e heap a 15 minuti non c'è un riferimento C: medie e heap sono più alti delle partite A di S6 (0,35–0,39 KB, 13,1–16,0 MB), con due STAI invece di una.
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown). Nessuno cita Shard, STAI o `MapHST`.

**Test** (`shard_ai_loader_unsynced_spec.lua`)

- Nuovo: «collects once at the start, after every Init, when GameStart follows the start units»: `Initialize`, poi `UnitCreated` di un'unità del team 0, `GameStart`, `GameFrame(1)` → una sola `collectgarbage`, dopo l'ultimo `Init`.
- Rinominato «collects the garbage once, after the catch-up of a reload» → «collects the garbage once on a reload, after the Init of every object» (la `collect` ora viene prima del catch-up; le asserzioni non cambiano).
- Mutazioni, ognuna fa fallire un test (2746 successi, 1 fallito): `lifecycle.lua` della base (test nuovo: 0 `collect`); `collect` senza guardia (test nuovo: 2); `collect` del reload anche a partita avviata (test del reload: 2). Col codice giusto 2747, 0 falliti.
- Nuovo `maphst_spec.lua`: «erases no debug channel when the debug drawing is off» (`drawDebug = false`, `EraseAll` registrata → nessun canale). Mutazione: `maphst.lua` prima della 2b → il test fallisce (2747 successi, 1 fallito); col codice finale 2748, 0 falliti.

**Controlli**

- `lx --lua-version 5.1 test` (codice finale): 2748 successi, 0 falliti, 1 pending. `run_engine_tests.sh` (codice finale): `RESULT: ok`.
- StyLua 2.5.2 sui file toccati (anche `maphst_spec.lua`): ok.
- EmmyLua 0.24.0, confronto con un worktree della base `2379418f9c`: 20 errori, negli stessi file. Per file: `maphst.lua` 11 avvisi e 15 hint prima e dopo, `lifecycle.lua` nessuna diagnostica, `shard_ai_loader_unsynced_spec.lua` 10 hint prima e dopo. Il totale degli avvisi cambia (22873 → 23121) solo in file non toccati (per esempio `common/springFunctions.lua`, `.ai-notes/drafts/ShardAILoader.lua`). Dopo la 2b: 20 errori, `maphst.lua` ancora 11 avvisi e 15 hint, `maphst_spec.lua` nessuna diagnostica.
- `.emmyrc.json` ripristinato; `git status` pulito a parte i file di `.ai-notes/`.

### S6 (agente locale, 25 novembre 2026) — verificato dal coordinatore

**Cosa ho fatto**

- Commit `b854dc7d88` «STAI: run ArmyHST, GridHST and MapHST in the global scope»: solo `Scope()` → `"global"` nei tre file, nient'altro (non è servito altro).
- Commit `c7debb58fb` «Shard outbox: describe the position params without citing removed STAI code»: `outbox.lua` r. 77 → `-- A position table becomes x, y, z, followed by its [1] when it has one.` Solo il commento.
- Commit `405a8d5136` «STAI Toolbox: keep every value of tableConcat in the array part, in order»: `table.insert(T, value)`, tolto il `WARNING`; il resto uguale (anche i due `pairs`). Test aggiornato (sotto).

**Controlli sugli ambiti** (la lettura del coordinatore è giusta, con una correzione su `drawDebug`)

- `ArmyHST`: nessun `self.ai`, `game`, `map`, `Spring`. `GridHST`: solo `map:MapDimensions` e `map:GetGroundHeight`. `MapHST`: `self.ai.armyhst`, `self.ai.gridhst`, `self.ai.drawDebug`, `map:`/`self.map:`, `Spring.GetGameRulesParam`, `Spring.TestMoveOrder`, `Spring.GetGroundHeight`. Nessuno dei tre usa `self.ai.id`, `game:GetTeamID()` o moduli di team (dopo S5 `MapHST` non usa più `self.ai.tool`).
- Scritture da fuori: grep di assegnazioni `ai.(maphst|gridhst|armyhst).<campo>… =` e di `table.insert/remove/sort` su di loro: 0. Ho guardato anche gli alias locali (`local ut = self.ai.armyhst.unitTable[...]`, `self.spec`, `.army` di `LabsBST`, `local networks = self.ai.maphst.networks` di `LabsHST`, `networkSpots` di `ScoutHST`, il risultato di `AccessibleSpotsHere`, `sortByDistance` su `networks[...].metals`): solo letture. `GridHST:NewLayer` lo chiama solo `MapHST`.
- **`map` di `ShardGlobal` e dei team**: ogni oggetto ha la sua `api` (`NewAPI` in `loader/types.lua`, `VFS.Include` di `api.lua` senza cache), quindi un suo `map` e `game`; `map.ai` è l'oggetto che l'ha preso in `Init`. Per le chiamate di `MapHST`/`GridHST` sono equivalenti: `TestPath`, `GetPathObject`, `GetPathWaypoints`, `NextPath`, `GetGroundHeight`, `MapDimensions` leggono solo `Spring`/`Game`; `GetMetalSpots` legge i game rules param (cache per oggetto, stessi valori); `GetGeoSpots` è la lista di `spring_lua/geo.lua`, calcolata per ogni `api` dalle feature al caricamento (stesse feature, stessi spot: la riga `map` lo conferma, 0 geo prima e dopo). Gli unici metodi di `map` che dipendono dall'oggetto sono i `Draw*`/`Erase*` (`self.ai.game:GetTeamID()`): li usa solo `MapHST:DrawDebug`.
- **`drawDebug` (correzione)**: su `ShardGlobal` c'è, vale `false`: `ShardAI:Init` chiama `self.game:DrawDisplay(false)`, che scrive `self.ai.drawDebug` sull'oggetto che sta inizializzando, anche globale. E nessuno chiama mai `DrawDisplay(true)` (grep in `luarules` e `luaui`: solo la chiamata di `ShardAI:Init`), quindi `MapHST:DrawDebug` non disegnava neanche prima. Lasciato così.
- **Da sapere su `DrawDebug`**: prima del controllo su `drawDebug` fa `self.map:EraseAll(0..9)` a ogni `Init`. Sul globale `game:GetTeamID()` è `ShardGlobal.id` = `nil`, quindi chiama `ShardDrawClearShapes(nil, i)`. Con il widget `shard_help_draw` spento (è il default) non succede niente; acceso, `GetShapes(nil, …)` fa `aiTeams[nil] = {}` e va in errore dentro LuaUI (non ho provato se l'errore torna nell'`Init` di `MapHST`). Forma semplice, se vuoi: spostare `if not self.ai.drawDebug then return end` prima del ciclo `EraseAll` (all'`Init` non c'è niente da cancellare). Non l'ho fatto.
- Funzioni chiamate dai moduli e behaviour di team: `MapHST:getPath`, `MobilityNetworkHere`, `MobilityOfUnit`, `UnitCanGoHere`, `UnitCanGetToUnit`, `AccessibleSpotsHere`; di `GridHST` tutte le conversioni, `GetCell`, `areaCells`, `getCellsFields`, `isInMap`, `NewLayer`, `PosToCell`; di `ArmyHST` solo campi (`unitTable`, `factoryMobilities`, …). Nessuna legge o scrive dati di un team: le uniche cose del team arrivano come argomenti (`unit`, posizioni, la griglia passata a `GetCell`/`areaCells`). Unica differenza visibile: i `Warn`/`EchoDebug` di queste funzioni ora escono con il prefisso `global` anche quando le chiama un team.
- `modules.lua` non cambia: `ArmyHST`, `GridHST`, `MapHST` restano prima dei moduli di team (dopo `SleepST`). Nel log: `global, ShardGlobal, Info: , adding ArmyHST module`, poi `GridHST`, `MapHST`, una volta sola; poi i moduli di ogni team, senza i tre.

**Prova** (`Echo` temporanei, non committati; `c_stai_vs_stai.txt`, 2 minuti). Patch di S5 con due ritocchi per il globale: `tostring(self.ai.id or "global")` al posto di `self.ai.id` (sul globale è `nil`, e `%d` darebbe errore) e `Toolbox:gcd` al posto di `self.ai.tool:gcd` (sul globale non c'è `Tool`; è la stessa funzione).

Partenza `9463fe9826` (identica a S5):

```
[S3-PROOF] grid, 0, 32, 24, 768, 295296, 295296
[S3-PROOF] map, 0, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] tool, 0, 78, 390, 5120.0000000000 10240.0000000000 130983.9921875000 103122.6718750000, 80, 2048
[S3-PROOF] grid, 1, … (uguali al team 0)
[S3-PROOF] trampled, 1, 79, 406400.0000000000 296576.0000000000 2.118384599685669
[S3-PROOF] trampled, 0, 68, 208640.0000000000 141568.0000000000 2.246112346649170
```

Dopo la parte 1 (`b854dc7d88`): `grid`, `map`, `tool` **una volta**, con `global`, stessi valori; `trampled` identiche.

```
[S3-PROOF] grid, global, 32, 24, 768, 295296, 295296
[S3-PROOF] map, global, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] tool, global, 78, 390, 5120.0000000000 10240.0000000000 130983.9921875000 103122.6718750000, 80, 2048
[S3-PROOF] trampled, 1, 79, 406400.0000000000 296576.0000000000 2.118384599685669
[S3-PROOF] trampled, 0, 68, 208640.0000000000 141568.0000000000 2.246112346649170
```

Dopo la parte 3 (`405a8d5136`): `grid`, `map`, `trampled` uguali; nella riga `tool` cambiano solo `#allSpots` (78 → 80) e la somma delle reti (390 → 400).

```
[S3-PROOF] tool, global, 80, 400, 5120.0000000000 10240.0000000000 130983.9921875000 103122.6718750000, 80, 2048
```

Dai numeri: le 7 reti hanno 400 spot in tutto con al massimo 80 ciascuna, quindi `air`, `amp`, `bot`, `hov` e una rete `veh` hanno tutti gli 80 spot e le altre due reti `veh` nessuno (prima: 5 × 78 = 390).

**Cosa cambia per i lettori di `allSpots`**

| lettore | cosa legge | prima | dopo |
| --- | --- | --- | --- |
| `MapHST:LayerScan` | `#self.allSpots`, `#network.allSpots` → `network.ratioSpots` | `#` = n − 2 (0 per reti di 1–2 spot) | `#` = n; `ratioSpots` giusto. **Nessuno legge `ratioSpots`** (grep), quindi nessun effetto |
| `BuildingsHST:DontBuildOnMetalOrGeoSpots` (r. 137) | `pairs(maphst.allSpots)` | `pairs` vedeva anche le chiavi `0` e `-1`: tutti gli 80 | tutti gli 80; cambia solo l'ordine dei rettangoli in `dontBuildRects`. Stessi rettangoli |
| `ScoutHST` r. 60 | `pairs(networks[...].allSpots)` → `lastSpotCheck[distanza] = indice` | tutti gli spot (anche `0`, `-1`) | stessi spot, indici diversi; l'ordine di `pairs` su `lastSpotCheck` può cambiare, quindi a parità di distanza il primo spot scelto può essere un altro |
| `LabsBST:ampRating` (via `AccessibleSpotsHere`) | `#ampSpots`, `#vehSpots` | n − 2 | n. Su Comet Catcher `amphRank` non cambia (78/78 → 80/80 = 0; rete `veh` vuota: 1 prima e dopo); su mappe con reti piccole sì |
| `LabsHST` | `layers[...].allSpots` | è un conteggio (`#metals + #geos`), non passa da `tableConcat` | invariato |

**Test** (`toolbox_spec.lua`): il caso diventa «concatenates every value in the array part, in the order of the given tables»: `{ {a, b}, {}, {c, d, e} }` → `#T == 5` e `assert.same({ a, b, c, d, e }, T)` (quindi niente chiavi `0`/`-1`); in più `{ {x} }` → `{ x }` (la rete di uno spot); resta `nil` su un argomento non tabella. Mutazioni: `table.insert(T, -1, value)` (il codice di prima) e `table.insert(T, 1, value)`: tutte e due fanno fallire il test (2745 successi, 1 fallito); col codice giusto 2746, 0 falliti.

**Tre partite A** (`SHARD_MEM_STATS=1`, 15 minuti, codice finale `405a8d5136`, uscita 0 tutte e tre)

| | partita 1 | partita 2 | partita 3 | S1 (intervallo) |
| --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6 / 33 / 79 / 138 | 5 / 36 / 101 / 154 | 6 / 33 / 88 / 133 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14) | 157 unità, 1 fabbrica, 26 mex | 178, 2, 33 | 155, 2, 30 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 175, 2, 28 | 200, 2, 36 | 181, 2, 33 | — |
| relay: messaggi | 3095 | 3572 | 3247 | 3405–3933 |
| relay: ordini dati | 12678 | 15278 | 14002 | 10445–15948 |
| relay: ordini rifiutati | 7 | 4 | 8 | 9–16 |
| messaggi rifiutati per motivo | nessuno | nessuno | nessuno | nessuno |
| memoria per frame, medie per minuto | 0,19–0,58 (media 0,35) | 0,18–0,61 (0,37) | 0,19–0,63 (0,39) | 0,18–0,90 (0,37–0,45) |
| memoria per frame, picco | 159,0 KB (min. 14) | 124,6 KB (min. 12) | 90,1 KB (min. 13) | 67,9–73,5 KB |
| heap | 13,1–14,9 MB | 13,1–15,2 MB | 13,2–16,0 MB | 13,1–15,5 MB |
| righe `[AI Loader] error` | 0 | 0 | 0 | 0 |
| tempo reale | 18 s | 21 s | 18 s | 19–21 s |

- **Nessuna partita sta sotto i riferimenti**: unità a fine partita 157/178/155 e mex 26/33/30, tutti dentro 141–186 e 23–35; al minuto 13 tutte nell'intervallo di S1. Gli ordini sono nell'intervallo, i rifiutati (4–8) più bassi di S1; i messaggi della partita 1 (3095) sono sotto i 3405 di S1, come la partita 1 di S2 (3222).
- Da notare: i picchi di memoria per frame (90–159 KB) sono più alti di S1 (68–74), come già in S2 (84–99); 159 è il picco di T14. Le medie sono uguali a S1. L'heap della partita 3 arriva a 16,0 MB (S1 fino a 15,5). Con tre partite non lo distinguo dalla variabilità.
- Partita 1: una sola fabbrica fino al minuto 14 (la seconda arriva prima del `SUMMARY`), come la partita 1 di S2. Al minuto 1 la partita 2 ha 0 fabbriche (5 unità), come due partite di S2.
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown). Nessuno cita Shard, STAI, `MapHST` o `Toolbox`.

**Controlli**

- `lx --lua-version 5.1 test`: 2746 successi, 0 falliti, 1 pending (stesso numero di S5: il caso di `tableConcat` è sostituito, non aggiunto). `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 (dalla radice) sui file toccati: ok.
- EmmyLua 0.24.0, confronto con un worktree della base `9463fe9826`: 20 errori, gli stessi (stessi file). Per file uguali alla base: `armyhst.lua` 39 avvisi, `maphst.lua` 11, `gridhst.lua` 0 (9 hint), `toolbox.lua` 0 (11 hint); `outbox.lua` e `toolbox_spec.lua` senza diagnostiche.
- `.emmyrc.json` ripristinato; `git status` pulito a parte questo file. Niente codice tolto, quindi `codice-tolto.md` non cambia.

### S5 (agente locale, 25 novembre 2026) — verificato dal coordinatore. Approvati dall'utente (25 novembre 2026): le 6 funzioni tolte oltre l'elenco e i tre avvisi tolti da `Toolbox` (niente `Warn` in `Toolbox`)

**Cosa ho fatto**

- Commit `f5d91af207` «STAI: move the stateless helpers of Tool to a Toolbox library»:
  - `STAI/toolbox.lua` nuovo: `Toolbox = {}` (tabella semplice, senza `class`), `local sqrt`, `local twicePi` propri (così il file non dipende dai globali che `tool.lua` assegna e si carica da solo). Dentro, con i due punti, stesso corpo e stesso commento: `RawDistance`, `DISTANCE`, `distance`, `AngleAdd`, `PositionWithinRect`, `RectsOverlap`, `pairsByKeys`, `tableSorting`, `sortByDistance`, `listHasValue`, `gcd`, `tableConcat`. I `self:` interni (`self:pairsByKeys`, `self:distance`, `self:gcd`) restano.
  - **Tre righe cambiate (scelta mia)**, perché `Toolbox` non ha console: tolti gli `self:EchoDebug` di `tableSorting` e `sortByDistance` (non stampavano mai: `Tool` non ha `Init` e non accende `DebugEnabled`) e il `self:Warn` di `tableConcat` (l'uscita anticipata resta, col testo dell'avviso come commento a fine riga). Il `Warn` non poteva scattare: tutti i 31 chiamanti passano una tabella scritta sul posto (`tableConcat({ a, b })`). In alternativa `Toolbox` potrebbe avere un suo `Warn` con `Spring.Echo`, ma la regola del compito vieta `Spring`: dimmi se lo vuoi.
  - **`Tool` prende le funzioni con rimandi**, in `tool.lua` subito dopo `Scope`: `for name, func in pairs(Toolbox) do Tool[name] = function(_, ...) return func(Toolbox, ...) end end`. Così `self.ai.tool:distance(...)` funziona come prima e dentro la libreria `self` è sempre `Toolbox`, mai l'istanza di `Tool`. Ho scartato `Tool[name] = func` (più corto): lì `self` sarebbe l'istanza di `Tool`, e `sortByDistance` userebbe `Tool.distance` dell'istanza (oggi la stessa funzione, ma basta un campo con quel nome per cambiarla) — il test lo distingue. Costo: una chiamata in più per ogni `self.ai.tool:<funzione della libreria>`, senza tabelle nuove.
  - `tool.lua` fa `shard_include("toolbox")` dopo `astarclass`; `maphst.lua` lo fa in testa (prima riga), così la dipendenza di `MapHST` si vede nel file. `shard_include` del tipo d'AI tiene una cache: il file gira una volta.
  - `MapHST`: le 8 chiamate → `Toolbox:tableConcat` (2), `Toolbox:distance` (3), `Toolbox:gcd`, `Toolbox:RawDistance` (2). `grep self.ai.tool maphst.lua`: 0 righe. StyLua ha rimesso su una riga l'`if` di `gridThePath` (più corto con `Toolbox:`).
  - Test `spec/luarules/gadgets/ai/STAI/toolbox_spec.lua` (sotto).
- Commit `e06200dd72` «STAI Tool: remove functions nobody calls»: solo righe tolte.
  - Le 16 dell'elenco; grep in tutto il repository (anche `.md`, `luaui`, `common`, `Shard`, `tool[`/`Tool[` con stringa) prima di toglierle: nessuna è usata. L'unico riferimento fuori da `tool.lua` era la riga commentata `--local gas = self.ai.tool:WhatHurtsUnit(...)` di `damagehst.lua`: l'ho tolta con il resto del ciclo commentato che la usava (`--for groundAirSubmerged, yes in pairs(gas) do`, `--	if yes then`, i due `--end`).
  - **In più, scelta mia (fermami se non va)**: funzioni chiamate *solo* da quelle dell'elenco, che dopo restavano senza chiamanti — `TableToString` e `StringToTable` (solo `SerializeOrder`, `DeserializeOrder`, `TableToStringBackup`), `AngleAtoB` (solo `AnglePosPos` e `SimplifyPath`), `AngleDist` (funzione globale, solo `SimplifyPath`), `HorizontalLine` e `Plot4` (solo `FillCircle`). Il coordinatore ne metteva quattro nella libreria e due in `Tool`; `TableToString` comunque non passava la regola (stato nel `local serialized` del file). Con loro: i `local` che usavano (`serialized`, `whatHurtsUnit`, `whatHurtsMtype`), i `local` mai letti (`mapBuffer`, `layerNames`, `unitThreatLayers`, `quadX`, `quadZ`, `output`) e `Tool:CustomCommand` commentata in fondo. Tutto è nell'indice; si riprende con `git show e06200dd72^:luarules/gadgets/ai/STAI/tool.lua`.
  - `tool.lua`: da 785 a 261 righe. Resta in `Tool`: `COLOURS`, `_TABLES`, `RezTable`, `KillTable`, `ResetTable`, `GiveOrder`, `RandomAway`, `RandomAway2`, `getTeamUnitsByClass`, `countFinished`, `countMyUnit`, `mtypedLvCount`, `UnitPos`, i rimandi a `Toolbox` e i globali `sqrt`, `random`, `pi`, … (li usano altri file di STAI). `RandomAway2` la chiama `scoutbst.lua` r. 103.
- `.ai-notes/stai/codice-tolto.md` (questo commit): una tabella per commit (S2, S3, S4a, S4b, S5), nome, file, cosa faceva; in testa come si riprende.

**Come si condivide `Toolbox` fra ambiti.** `LoadAIType` (`shard_runtime/loader/types.lua`) legge ogni tipo d'AI una volta, in un ambiente suo (`setmetatable({}, { __index = gadget })`), e `shard_include` di quel tipo (`shard_generate_include_func` con `env`) esegue ogni file una volta e poi restituisce dalla cache. Quindi `Toolbox` è **una sola tabella per tutte le STAI** del client, di qualunque ambito; non ha stato, e i suoi `local` (`sqrt`, `twicePi`) sono costanti. Lo stesso vale già per le classi: anche `Tool._TABLES` (la riserva di `RezTable`/`KillTable`) sta nella classe, quindi è **una sola riserva per tutte le STAI**, non per team come diceva il compito (le tabelle vuote passano da un team all'altro; nessun effetto oggi, ma da sapere per S6).

**Da segnalare: `tableConcat` è difettosa** (lasciata com'è, il gioco non deve cambiare; ho messo un `WARNING` a fine riga). `table.insert(T, -1, value)` in Lua 5.1 sposta gli elementi e scrive in `T[-1]`: gli ultimi due valori finiscono nelle chiavi `0` e `-1`, fuori dalla parte array, e l'ordine è rovesciato. Con 80 metalli e 0 geo `#MapHST.allSpots` è 78 (riga `tool` della prova). Le reti con 1 o 2 spot hanno `#allSpots == 0`. Il test fissa il comportamento di oggi: chi lo corregge aggiorna il test.

**Test** `spec/luarules/gadgets/ai/STAI/toolbox_spec.lua`: carica `toolbox.lua` da solo con `loadfile` in un ambiente suo; un secondo caso carica `class`, `AIBase`, `Module` e `tool.lua` (con uno `shard_include` finto che esegue solo `toolbox`). Casi: `distance` sul piano, `DISTANCE` e `RawDistance` in tre dimensioni (anche con i punti scambiati); `gcd` (anche `gcd(10240, 6144) = 2048` e con `b = 0`); `sortByDistance` dal più vicino, sul piano (il più vicino ha `y = 900`); `tableConcat` com'è oggi (sopra) e `nil` su un argomento non tabella; un'istanza di `Tool` con `distance` sostituita da una funzione che dà errore: `tool:sortByDistance` funziona lo stesso (quindi `self` è `Toolbox`) e `tool:gcd` = `Toolbox:gcd`. **Mutazioni** (12, tutte fanno fallire il test): `distance` con `y`; `DISTANCE` senza `y`; `RawDistance` senza `y`; `gcd` con argomenti scambiati; `gcd` che restituisce `b`; `sortByDistance` in ordine inverso; `sortByDistance` che tiene l'ordine della lista; `tableConcat` con `table.insert(T, value)`; con `table.insert(T, 1, value)`; senza il controllo del tipo; rimando che passa l'istanza di `Tool` al posto di `Toolbox`; `Tool[name] = func`.

**Righe per file**

| commit | file | + | − |
| --- | --- | --- | --- |
| `f5d91af207` | `toolbox.lua` (nuovo) | 104 | 0 |
| | `tool.lua` | 7 | 104 |
| | `maphst.lua` | 10 | 10 |
| | `spec/luarules/gadgets/ai/STAI/toolbox_spec.lua` (nuovo) | 88 | 0 |
| `e06200dd72` | `tool.lua` | 0 | 427 |
| | `damagehst.lua` | 0 | 5 |

**Prova che il gioco non cambia** (`Echo` temporanei, non committati; `c_stai_vs_stai.txt`, 2 minuti). Alle righe di S4b ho aggiunto una riga `tool` = team, `#allSpots`, somma dei `#allSpots` delle reti, `elmoMapMaxCenterDistance`, `elmoMapMaxDistance`, somma `x` e `z` degli `hotSpots`, somma dei pesi, `self.ai.tool:gcd(elmoMapSizeX, elmoMapSizeZ)`: sono i valori che `MapHST` calcola con le funzioni spostate (e `gcd` passa per i rimandi di `Tool`).

Codice di partenza `103285ea7b`, codice dopo il primo commit e codice finale: righe identiche (`diff` vuoto), e le righe `grid`, `map`, `trampled` identiche a quelle di S4b.

```
[S3-PROOF] grid, 0, 32, 24, 768, 295296, 295296
[S3-PROOF] map, 0, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] tool, 0, 78, 390, 5120.0000000000 10240.0000000000 130983.9921875000 103122.6718750000, 80, 2048
[S3-PROOF] grid, 1, 32, 24, 768, 295296, 295296
[S3-PROOF] map, 1, 80, 0, 32,  air=1 amp=1 bot=1 hov=1 veh=3
[S3-PROOF] tool, 1, 78, 390, 5120.0000000000 10240.0000000000 130983.9921875000 103122.6718750000, 80, 2048
[S3-PROOF] trampled, 1, 79, 406400.0000000000 296576.0000000000 2.118384599685669
[S3-PROOF] trampled, 0, 68, 208640.0000000000 141568.0000000000 2.246112346649170
```

**Partita C** (`c_stai_vs_stai.txt`, 15 minuti, codice finale, uscita 0, 23 s): tutte e due le STAI ospitate dal giocatore 0.

| | team 0 STAI | team 1 STAI |
| --- | --- | --- |
| unità min. 1 / 5 / 10 / 13 | 6 / 35 / 90 / 127 | 6 / 37 / 105 / 162 |
| mex min. 5 / 10 / 13 | 5 / 17 / 20 | 6 / 20 / 30 |
| min. 14 | 141 unità, 2 fabbriche, 20 mex | 182, 2, 32 |
| `SUMMARY` | 142, 2, 21 | 190, 2, 34 |

- Relay: 4924 messaggi, 28074 ordini, 28 rifiutati; nessun messaggio rifiutato. 0 righe `[AI Loader] error`; errori solo quelli di sempre (`gui_pip` `CreateShader`, `gui_sensor_ranges_jammer_preview` in Shutdown, `AdvSky`, `ceg_test_projectile`, atlas groundFX, shader AoE Napalm/Reclaim Field), nessuno cita Shard, STAI o `Tool`.
- Qui il team 1 va avanti dal minuto 10 (come il team 1 di S3 e S4a); l'inizializzazione è identica, lo attribuisco alla variabilità.

**Controlli**

- `lx --lua-version 5.1 test`: 2746 successi (+5), 0 falliti, 1 pending. `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 sui file toccati: ok. (Va lanciato dalla radice del repository: da `STAI/` non trova `.stylua.toml` e usa la configurazione predefinita.)
- EmmyLua 0.24.0, confronto con un worktree della base `103285ea7b`: 20 errori, gli stessi (stessi file). Per file: `tool.lua` 6 → 1 avviso (44 → 15 hint), `maphst.lua` 11 → 11, `damagehst.lua` uguale (1 errore di prima, 7 avvisi), `toolbox.lua` 0 avvisi e 11 hint (variabili inutilizzate del codice spostato), il test 0 avvisi. L'avviso rimasto in `tool.lua` è nuovo: `param-type-mismatch` su `func(Toolbox, ...)` nel rimando (l'analizzatore non capisce `self` dei metodi presi con `pairs`); gli altri cinque erano nel codice tolto.
- `.emmyrc.json` ripristinato; `git status` pulito a parte questo file.
- Nota: il commento di `shard_runtime/spring_lua/outbox.lua` r. 77 cita ancora «STAI's Tool:SerializeOrder» (che non c'è più). È nel framework, quindi non l'ho toccato: va in un commit «Shard …» se vuoi correggerlo.

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


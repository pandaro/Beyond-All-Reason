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

Due compiti: «esegui s24b» → **solo S24b**; poi «esegui s17» → **solo S17**. Risultati separati.

### S24b: `AttackerBST` solo sensore

**Impegno: medium. Modello: Sonnet 5.5.** Decisione dell'utente (25 novembre 2026): la squadra (`AttackHST`) dà gli ordini, `AttackerBST` è il sensore dell'unità (eventi alla squadra, priorità 0, nessun ordine). **Il gioco cambia** (sotto): tre partite A. **Stile**: `nuovo-stai.md` §7.

Trovato dal coordinatore: `AttackerBST:OwnerIdle` (r. 66–71) chiama `AttackHST:MemberIdle` **solo se `self.active`**, e `AttackerBST` non è mai attivo (`attacking` mai vero, S13): quindi `squad.idleCount` non sale mai dagli eventi, e la condizione di `attackhst.lua` r. 190 (`idleCount > 85 % dei membri`) non scatta per questa via. Correggerlo cambia il gioco.

1. `attackerbst.lua`:
   - `Priority` restituisce sempre 0 (commento a fine riga: la squadra dà gli ordini);
   - via `attacking` (r. 49, 58, 109 e il ramo di `Priority`), `Activate`/`Deactivate` (o vuoti), il ramo di `Update` che chiama `ElectBehaviour` (r. 93–95) e la chiamata in `Free` se resta inutile;
   - `OwnerIdle` chiama `MemberIdle` **sempre** (la squadra controlla `squad`); `OwnerMoveFailed` come oggi (passa da `OwnerIdle`);
   - `OwnerDamaged`/`damaged`: grep se qualcuno lo legge; se no lascialo (segnale per il futuro) e scrivilo;
   - il blocco commentato `IsAttacker` in testa: via (indice).
2. Grep in `luarules/` e `spec/` per `attacking`, `.active` letti da fuori su un `AttackerBST`.
3. Test busted: `OwnerIdle` con e senza squadra incrementa `idleCount`; `Priority` 0.
4. Misura (patch non committata, una partita A): quante volte `MemberIdle` è chiamato e quante volte r. 190 scatta, prima e dopo.
5. **Tre partite A** e **una C** (confronto con S26, S24a, S1). Se peggio in più di una A, scrivilo e non tentare altro.
- Controlli: StyLua 2.5.2, EmmyLua 0.24.0 (file toccati), `lx --lua-version 5.1 test`, `run_engine_tests.sh`; `.emmyrc.json` ripristinato; skill `submodule-pointer`.
- Commit, in inglese: uno per `AttackerBST` con test, uno per i risultati.

### S17: STAI sotto `shard_null` (punto 12)

**Impegno: high. Modello: Sonnet 5.5.** Approvato dall'utente (25 novembre 2026): ultimo compito prima della chiusura. Si esegue **dopo S24b** («esegui s17»). **Il gioco non cambia.** **Stile**: `nuovo-stai.md` §7.

Obiettivo: uno spec busted che **carica STAI fuori dall'engine** con `shard_null` (come fa `spec/luarules/gadgets/ai/shard_runtime/shard_null_spec.lua` per l'AI d'esempio), esegue `Init` e qualche `Update` senza errori. Serve come rete di sicurezza per i cambi futuri.

1. **`STAI/boot.lua`**: oggi `require("shard_runtime/shard_null/boot")` fuori dall'engine; allinealo a come `shard_null_spec.lua` carica l'AI d'esempio (`SetAIFolder` o equivalente). Il ramo `ShardSpringLua` non cambia.
2. **Nomi dei file**: controlla che ogni `shard_include` di STAI trovi il file con le stesse maiuscole (in engine VFS non distingue, su Linux `require` sì). Elenca e correggi le differenze (rinomina del file o del nome incluso: il più piccolo).
3. **Letture dirette dell'engine** (`Spring.*`, `UnitDefs`, `CMD`, `Game`, `VFS` in circa 25 file di STAI): **non** cambiare STAI per questo. Metti i finti necessari **nello spec** (o in un aiuto dello spec): `UnitDefs` minimo con pochi tipi (comandante, costruttore, fabbrica, mex, un combattente), `Spring.*` usate nell'`Init`/`Update` con risposte semplici, `CMD` con le costanti usate. Elenca nei risultati cosa hai dovuto fingere. Se `ArmyHST`/`MapHST` chiedono troppo (tabelle intere di unità, mappa), usa una mappa piccola finta di `shard_null` e scrivi i limiti.
4. **Spec** `spec/luarules/gadgets/ai/STAI/stai_null_spec.lua`: carica STAI, `Init` di global, ally e team, alcuni `Update`, un `UnitCreated`/`UnitBuilt` del comandante; nessun errore e nessun `Warn` inatteso. Mutazione: un errore voluto in un modulo deve far fallire lo spec.
5. Se un passo richiede cambi grossi a STAI o al framework, **fermati** e descrivi le opzioni.
- Controlli: StyLua 2.5.2, EmmyLua 0.24.0 (file toccati), `lx --lua-version 5.1 test`, `run_engine_tests.sh`; **una** partita A (il gioco non cambia); `.emmyrc.json` ripristinato; skill `submodule-pointer`.
- Commit, in inglese: uno per `boot.lua` e i nomi, uno per lo spec, uno per i risultati.

## Risultati

### S17 (agente locale, 25 novembre 2026) — STAI sotto `shard_null`: spec in verde con 3 casi, il gioco non cambia

**In breve**: fatto, due commit di codice (`5f2637ae50` `boot.lua`, `8b619014e0` lo spec). STAI si carica fuori dall'engine, fa `Init` di global, ally e team, `Update` e un comandante che ordina il primo mex. Test: 2816 successi (2813 + 3), 0 fallimenti; StyLua 2.5.2 pulito sui due file; EmmyLua: lo spec 0 avvisi, `boot.lua` gli stessi 2 di prima (`STAI()` «call-non-callable», lo stesso di `Shard/boot.lua`), `.emmyrc.json` ripristinato; `run_engine_tests.sh` `RESULT: ok`. Lo spec dura 0,02 s.

**1. `STAI/boot.lua`**: ora come `Shard/boot.lua`: `ShardNull = require("shard_runtime/shard_null/boot")`, `ShardNull.SetAIFolder("STAI")`, `ShardNull.Start(ai, "STAI")` (global, ally, team nell'ordine del loader). Il ramo `ShardSpringLua` non è cambiato. Con il `boot.lua` di prima i 3 casi dello spec falliscono (`cannot open luarules/gadgets/ai/ai.lua`: `shard_include` non conosce la cartella di STAI).

**2. Nomi dei file**: 39 `shard_include` distinti in STAI (più quelli del runtime): **nessuna differenza di maiuscole**, file e nomi sono tutti minuscoli. Niente da correggere. Altri `require`/`VFS.Include` in STAI: `boot.lua` (sopra), `buildingshst.lua:27` (`VFS.Include("common/stai_factory_rect.lua")`, funziona nell'ambiente dello spec) e `test.lua:15` (`require("boot")`, vecchio, non lo carica nessuno: da guardare in chiusura, come già annotato in S25).

**3. Cosa ho dovuto fingere** (tutto nello spec, STAI e framework intatti)
- **Ambiente**: lo spec non scrive nessun globale della suite. `SpecEnv.new` dà un ambiente con `Spring`/`VFS`/… a strati; ci metto un `require` e un `package` miei (cercano sotto `luarules/gadgets/ai/` e eseguono ogni file in quell'ambiente), quindi `class`, `STAI`, `ai`, `game`, `map`, `continue`, `parent` di `armyhst.lua` restano lì dentro. `print` dell'ambiente raccoglie le righe: **ogni riga con «Warning» fa fallire** lo spec.
- **`UnitDefs`/`UnitDefNames`/`FeatureDefs`/`WeaponDefs`**: 44 tipi, non «pochi»: `ArmyHST` nomina unità vere in più punti e indicizza senza guardia. Servono: `armcom`/`corcom`, `armmex`/`cormex`, `armpw`/`corpw`, i nano `*nanotc`/`*nanotcplat` (il comandante li conta per scegliere il ruolo, `tool.lua:187`), **tutte e 28 le fabbriche di `factoryMobilities`** (`LabsHST:factoriesRating` le valuta in `Init` e indicizza `unitTable[factory].unitsCanBuild`; ognuna costruisce `*pw`), e i sei costruttori d'esempio di `mobUnitExampleName` (`armcv`, `armck`, `armbeaver`, `armch`, `armcs`, `armacsub`: `MapHST:moveLayerTest` chiede all'engine dove possono andare). Ogni def ha tutti i campi che `GetUnitTable` legge (valori semplici).
- **`Spring.*`** (4): `GetGameRulesParam` (nil), `GetTeamResources`, `TestMoveOrder` (sempre vero), `GetGroundHeight`.
- **Mappa** (`shard_null/map.lua`, a cui lo spec aggiunge): `game_engine:Map():MapDimensions()` (128 × 128, che `shard_null` chiama ma non definisce), `GetGroundHeight`, `CanBuildHere` (vero), `TestPath` (50), `GetPathObject`/`GetPathWaypoints` (percorso senza punti), `GetMetalSpots` (3 spot). Griglia 4 × 4 celle; tutta transitabile, una sola rete. Limite: nessun terreno, acqua o geotermia.
- **Gioco** (`shard_null/game.lua`, a cui lo spec aggiunge): `GiveOrder` (registra), `GetTypeByName` (da `UnitDefNames`, con `ID`, `Name`, `CanBuild`), `GetUnitByID`, `GetTeamUnitDefCount`, `GetTeamUnitsByDefs`, `getUnitsInCylinder`. `Frame` resta 0 per sempre in `shard_null`.
- **Unità del motore**: una sola (il comandante): `ID`, `Team`, `IsMine`, `Name`, `GetRawPos`, `GetPosition`, `GetHealth`, `GetMaxHealth`, `GetHealtsParams`, `CanBuild`, `Move`, `Patrol`, `Guard`.
- **Non fingo**: LOS/radar, nessun nemico, nessuna fabbrica costruita, `Frame` fermo a 0 (quindi i comportamenti a tempo non scattano), nessuna altra unità. Lo spec non prova il gioco: prova che il codice carica, parte e non rompe.

**4. Spec** `spec/luarules/gadgets/ai/STAI/stai_null_spec.lua` (3 casi, 339 righe; più del doppio del codice cambiato, ma il codice cambiato è `boot.lua` e quasi tutto è l'ambiente finto)
1. boot di global, ally e team: i moduli stanno nel proprio ambito (`maphst` del global è lo stesso oggetto per l'AI, `loshst` dell'ally idem), nessun «Warning».
2. `Update` su global, ally e AI, e tutti i turni dello scheduler (`ScheduledUpdate` di 1…`#MScheduler`) per 3 giri, senza errori né avvisi.
3. Il comandante (`UnitCreated`, `UnitBuilt`, un `Update`): ha `BootBST`, `BuildersBST`, `CommanderBST` e dà **un ordine**, costruire `armmex` (`cmd = -id`, unità 1).
- **Mutazione**: `error("boom")` come prima riga di `DamageHST:Update`, di `MapHST:Init` e di `BuildersBST:Update` (tolti con `git checkout`): lo spec fallisce ogni volta (1 caso, 3 casi, 1 caso).

**5. Partita A** (`run_engine_game.sh`, 15 minuti, `SHARD_MEM_STATS=1`, uscita 0): fine STAI **145 unità, 2 fabbriche, 16 mex**; SimpleAI 56, 1, 6. Relay: 3280 messaggi / 13226 ordini / 7 rifiutati; 2550 gruppi; `Shard memory record` 15502. Righe `[AI Loader] error`: 0 (nell'infolog restano solo gli errori di rendering dell'headless). Il gioco non cambia (`boot.lua` non si carica in partita): 145 unità sta fra A1 (110) e A2/A3 di S24b, sotto S26 (188–203), come varianza del seme.

**Trovato mentre fingevo** (non toccato)
- `LabsHST:factoriesRating` (`labshst.lua` r. 70–96) divide per `topRatingSpots`: su una mappa **senza spot di metallo** vale 0, `v.allSpots / 0` dà NaN e `rank[rating]` fallisce con «table index is NaN» (provato nello spec togliendo gli spot). Le mappe di BAR hanno spot, quindi in partita non succede; da sapere.
- `shard_null/game.lua` e `map.lua` non hanno quello che STAI chiama (sopra); non li ho toccati (cambio al framework, non chiesto). Se vuoi che lo spec si semplifichi, si possono spostare lì i finti comuni a tutte le AI.

### S24b (agente locale, 25 novembre 2026) — verificato dal coordinatore. L'ordine azzeramento/lettura di `idleCount` (r. 233/190 di `AttackHST`, r. 248/204 di `RaidHST`) va in S24c, se l'utente lo vuole

**In breve**: fatto, commit `a51a5d646e`. Test: 2813 successi, 0 fallimenti; `run_engine_tests.sh` `RESULT: ok`; StyLua pulito; EmmyLua su `attackerbst.lua` da 20 a 13 avvisi (`.emmyrc.json` ripristinato). **Ma la correzione non arriva a r. 190**: `MemberIdle` ora è chiamato (0 → 208 in una partita A), r. 190 scatta ancora 0 volte, perché la condizione è irraggiungibile per un altro motivo (sotto). Partite: A2, A3 e C nei riferimenti, A1 sotto (una sola).

**1. `attackerbst.lua`**
- `Priority` restituisce sempre 0 (`--the squad gives the orders`).
- Tolti: `attacking` (in `OwnerBuilt`, `OwnerDead`, `Priority`, `Free`), `Activate`/`Deactivate` (restano quelli vuoti di `Behaviour`; `self.active` lo scrive già `PreActivate`/`PreDeactivate` del runtime), il ramo di `Update` con `ElectBehaviour`, `self.active = nil` in `OwnerDead`, il blocco commentato `IsAttacker`.
- `Free`: tolta la chiamata a `ElectBehaviour` (serviva solo a togliere il controllo a un `AttackerBST` attivo, che non esiste più). Tolto anche `self.target = nil`: `target` di un `AttackerBST` non lo scrive nessuno (grep in `luarules/`: `AttackHST` usa `squad.target`), lo leggeva solo il ramo tolto di `Update`.
- `OwnerIdle` chiama `MemberIdle` sempre; `MemberIdle` controlla già `squad`. `OwnerMoveFailed` invariato.
- `OwnerDamaged`/`damaged`: nessuno lo legge fuori da `AttackerBST` (`raidbst.lua` ha un `damaged` suo). Lasciato, con commento `--frame of the last hit`. Anche `self.idle` (scritto in `OwnerIdle`, tolto in `Free`) non lo legge nessuno: lasciato, non era nel compito.

**2. Grep** in `luarules/` e `spec/`: nessuno legge `attacking` o `.active` di un `AttackerBST` da fuori. Gli `attacking` di `scoutbst.lua` sono un campo di `ScoutBST`. `behaviourfactory.lua` aggiunge `AttackerBST` a molte categorie; con `rezs` è in alternativa a `ReclaimBST`.

**3. Test** `spec/luarules/gadgets/ai/STAI/attackerbst_spec.lua` (5, con `AttackHST` vero): idle con squadra (+1), squadra senza `idleCount` (→ 1), `OwnerMoveFailed` conta come idle, una recluta senza squadra accanto a un membro (conta solo il membro, la recluta ha `idle` e nessuna squadra), `Priority` 0. Tutti e 5 falliscono sul codice prima del commit. Il test di `Priority` fallisce prima solo perché forza `attacking = true` (nessuno lo metteva a vero); il caso «senza squadra» da solo passava anche prima, per questo è unito a quello con il membro.

**4. Misura** (patch `[S24B]` non committata su `attackhst.lua`, tolta con `git checkout`; partita A, 15 minuti, una prima con `attackerbst.lua` di `HEAD~1`, una dopo)

| | `MemberIdle` chiamato | di cui con squadra | `SquadStepComplete` | passo per distanza < 256 (r. 187) | passo per idle (r. 190) |
| --- | --- | --- | --- | --- | --- |
| prima | 0 | 0 | 277 | 48 | 0 |
| dopo | 208 | 208 | 187 | 23 | **0** |

**Perché r. 190 non scatta**: `AttackHST:SquadAdvance` mette `squad.idleCount = 0` (r. 233) e **poi** chiama `SquadStepComplete` (r. 250), che lo legge a r. 190: la condizione diventa `0 > floor(#members * 0.85)`, sempre falsa. Gli incrementi di `MemberIdle` fra un avanzamento e l'altro vengono azzerati prima di essere letti. Stesso schema in `raidhst.lua` (azzerato a r. 248, letto a r. 204 dentro lo step). Non l'ho toccato: fuori dal compito. Per farlo funzionare basterebbe azzerare dopo `SquadStepComplete` (o dopo la lettura): **cambio di gioco** da decidere, in tutti e due i moduli.

Quindi il commit, per ora, **non cambia il gioco** per la via di r. 190; l'unica differenza possibile è la `ElectBehaviour` tolta da `Free` per un'unità con un altro behaviour accanto a `AttackerBST`.

**5. Partite** (`run_engine_game.sh`, 15 minuti, `SHARD_MEM_STATS=1`, uscita 0, 19–21 s, righe `[AI Loader] error`: 0 in tutte)

| | min. 14: unità | fine (SUMMARY): unità, fabbriche, mex | relay: messaggi / ordini / rifiutati | gruppi | `Shard memory record` |
| --- | --- | --- | --- | --- | --- |
| A1 | 96 | **110, 2, 19** | 3598 / 10356 / 6 | 2479 | 15454 |
| A2 | 181 | 200, 2, 38 | 3578 / 16718 / 12 | 2929 | 15549 |
| A3 | 144 | 147, 2, 27 | 3370 / 11855 / 8 | 1734 | 15172 |
| C (S24a: 173, 2, 28 · 137, 2, 22) | 130 · 148 | 141, 2, 24 · 159, 1, 27 | 4242 / 22665 / 33 | 5203 | 16765 |

- Riferimenti A: S26 188–203 unità, 29–38 mex; S25 141–186, 23–35; S24a 172, 27. **A1 è sotto** (110 unità, 19 mex), non crollata secondo il criterio di S26 (2 fabbriche, ma unità poco sopra 100 alla fine, 96 al minuto 14). A2 e A3 dentro. Peggio in una A sola: non ho fatto altro. Visto il punto 4 (r. 190 mai raggiunta, `AttackerBST` mai attivo neanche prima), penso sia varianza del seme come in S25/S26, ma non l'ho provato.
- C dentro i riferimenti (S24a, S25, S23).
- Il primo «prima/dopo» del punto 4 (con la patch) dà anche le fini: prima 201 unità, 30 mex; dopo 156, 27.

**Domanda**: correggo l'ordine azzeramento/lettura di `idleCount` in `AttackHST` (e `RaidHST`)? È il cambio di gioco che S24b voleva ottenere.

### S24a (agente locale, 25 novembre 2026) — verificato dal coordinatore. Le due cose «da decidere» (tetto di unità per messaggio, marcatore 65535) passano all'utente e al coordinatore del framework — `'1-2'` è un solo record, eseguito con `GiveOrderToUnitArray`

**In breve**: fatto. Formato versione 2, tutto in `ordercodec.lua`. Test: 2808 successi, 0 fallimenti; `run_engine_tests.sh` `RESULT: ok`; StyLua pulito; EmmyLua senza avvisi nuovi nei file toccati (`.emmyrc.json` ripristinato). Partite A e C: 0 righe `[AI Loader] error`, gioco nei riferimenti.

**Formato** (commento di testa di `ordercodec.lua`)
- `VERSION = 2`. Un **record** è un ordine o un gruppo; l'intestazione conta i record. Il gruppo è un ordine con `unitID = GROUP_UNIT = 65535` (mai un'unità), poi `U16 k`, poi `k` `unitID U16`: `10 + 4n + 2k` byte. Gli ordini singoli sono come prima.
- Costanti: `GROUP_UNIT`, `MAX_UNITS_PER_GROUP = 255`. `MAX_ORDERS_PER_MESSAGE` (20) ora conta **record**: un gruppo vale 1.
- Funzioni: `PackGroup(cmd, options, params, paramCount, unitIDs, unitCount)`, `UnpackGroupUnits(message, positionDopoIParametri)`; `UnpackOrder` invariata (restituisce `GROUP_UNIT` per un gruppo). Il vecchio `unitID` 65535 non si può più mandare come ordine singolo: `Queue` lo scarta (il motore ne ha al massimo 32000).

**Outbox**: `ShardOutbox:QueueGroup(unitIDs, cmd, params, options)`. Un `unitID` non valido è scartato da solo, con un avviso per chiamata (ritorna `false`); un comando non valido scarta tutta la chiamata. Oltre 255 unità fanno più record, nello stesso gruppo (restano insieme in un messaggio). **Una sola unità valida diventa un ordine singolo** (più corto, percorso già noto). Zero unità: nulla in coda, `true`. `game:GiveOrder '1-2'` la usa.

**Relay**: per un gruppo controlla ogni unità (valida e della squadra), compatta l'array, chiama `Spring.GiveOrderToUnitArray` una volta, ordini dati = unità comandate, un contatore `groups` (riga nuova a `Shutdown`: `Shard relay: N groups given`, separata da quella esistente per non rompere chi la legge). Rifiutati: le unità scartate; gruppo con più di 255 unità rifiutato intero (conta le sue unità) e si legge oltre; gruppo troncato = come un ordine troncato (rifiuta questo e i record dopo). Prima di un gruppo, gli ordini in sospeso della unità corrente vengono dati: l'ordine fra record resta quello del messaggio.

**Test**
- `ordercodec_spec.lua`: codec (gruppo da 0, 1, 255 unità fra ordini; troncato in cinque modi), outbox (`QueueGroup`, 1 unità = ordine, 0 unità, spezzato a 255/256, un gruppo vale 1 su 20, `dropFirst` conserva le liste, nessuna coda residua di un gruppo precedente, unità non valida, `BeginGroup` con gruppi e rollback), `'1-2'` (un record; più di 20 unità in un messaggio; unità non valida).
- `shard_ai_loader_spec.lua` (relay): unità estranee/non valide scartate con `shard_relay_rejected`, una sola chiamata, array senza `n`; 1 unità; senza unità valide nessuna chiamata; ordine fra ordini e gruppi; 256 unità rifiutate e lettura oltre; 255 accettate; gruppo troncato; 20 gruppi in un messaggio e contatori. Versione sbagliata: ora 3.
- `luaui/Tests/shard/test_ordercodec.lua` (in motore, entrambi i lati): gruppo da 0, 1, 2, 255 unità. Conferma che `VFS.UnpackU16(msg, pos, 1)` restituisce una **tabella** (il codice non gestisce il caso numero).
- Mutazioni (16, tutte colte): controllo della squadra nel gruppo, tetto 255 nel relay, scarico degli ordini prima del gruppo, pulizia della coda dell'array, contatori, scambio delle liste in `dropFirst`, copia dei conteggi, dimensione del blocco, declassamento a ordine, pulizia della coda della lista, limiti in `UnpackGroupUnits`, tipo di record in `Flush`, `'1-2'` per unità.

**Partite** (`run_engine_game.sh`, 15 minuti, `SHARD_MEM_STATS=1`, uscita 0, 19 e 21 s)

| | fine (SUMMARY): unità, fabbriche, mex | min. 14: unità | relay: messaggi / ordini / rifiutati | gruppi | memoria per frame (media per minuto; picco) | `Shard memory record` |
| --- | --- | --- | --- | --- | --- | --- |
| A (S26: 200/203/188 unità; 4837/4330/2645 messaggi; 14562/17437/12911 ordini; 4/4/19 rifiutati) | 172, 2, 27 | 152 | 4206 / 14436 / 5 | 2891 | 0,17–0,71 KB; 45,5 KB | 15011 (S26: 15468–15581) |
| C (S25: 5137 / 23354 / 35; S23: 4741 / 26817 / 33) | 173, 2, 28 · 137, 2, 22 | 154 · 133 | 4905 / 28520 / 37 | 5666 | 0,28–0,95 KB; 96,0 KB | 16837 (S23: 17651) |

- Righe `[AI Loader] error`: 0 in entrambe. Nessuna riga `messages rejected (…)`: nessun messaggio rifiutato. I rifiutati (5, 37) sono unità non valide dentro messaggi accettati, come prima.
- **Messaggi**: A 4206 contro 2645–4837 di S26, C 4905 contro 4741–5137: dentro la varianza fra partite. Non c'è un calo visibile, e non c'è da aspettarselo: la STAI manda al più un messaggio per frame e il numero di messaggi lo decide il traffico di ordini, non il numero di record. Il guadagno di `'1-2'` sta nei **record** e nelle chiamate al motore: 2891 e 5666 gruppi eseguiti ciascuno con una sola `GiveOrderToUnitArray` (prima una `GiveOrderToUnit` per unità). Non ho il numero di record «prima» per le stesse partite, quindi il rapporto esatto non lo conosco.
- Il gioco non è cambiato (stessi ordini; unità e mex nei riferimenti di S26 e S23). Una partita per tipo, come da compito.

**Da decidere**
1. **Costo per messaggio**. Il tetto di 20 record era un tetto sul costo del motore (4,2 µs per ordine, su ogni client). Con i gruppi, un messaggio può portare fino a 20 × 255 = 5100 comandi. Se il costo per unità resta quello, il tetto vero andrebbe sulle **unità** per messaggio (o per frame). Non l'ho aggiunto: il compito diceva 1 record = 1 più un tetto di 255 per record. Dimmi se vuoi anche un tetto di unità per messaggio, nel relay e nell'outbox.
2. Il marcatore `65535` nel campo `unitID` è il modo più corto (nessun byte in più per gli ordini singoli). Se il coordinatore del framework preferisce un byte di tipo per record, cambia solo `ordercodec.lua` e le tre chiamate (`PackGroup`, `UnpackOrder`, `UnpackGroupUnits`).

### S19 (agente locale, 25 novembre 2026) — verificato dal coordinatore. Prova fallita, due commit ritirati: `gridSize` resta 256

**In breve**: con `gridSize` 128 le tre partite A sono **tutte peggiori** (fine 90 / 132 / 175 unità, contro 188–203 di S26); la memoria sale e `TopologyFooded` sulla mappa più grande arriva a 15.588 chiamate annidate, il 78% del limite di Lua 5.1. Come da compito ho fatto `git revert` dei due commit: `ba90f2c514` «STAI: grid cell size 128 elmos» (con `gridhst_spec.lua` su una mappa 768×512) e `4664f38be0` «STAI: cell radii for the 128-elmo grid», ritirati da `0f57a6bbc3` e `47fe7ca3b9`. `luarules/` e `spec/` sono identici a `a99cabc2c3`.

**Mappe**: A = Comet Catcher Remake 1.8, 1024×768 quadrati (8192×6144 elmi): 32×24 = 768 celle a 256, 64×48 = 3072 a 128. Più grande disponibile (letta dagli header `.smf` di tutte le mappe in `~/.spring/maps`): 2048×2048, **Jade Empress 1.41** (16384 elmi): 64×64 = 4096 celle a 256, 128×128 = 16.384 a 128. (Special Hotstepper, stessa misura, scartata: STAI crolla anche a 256, mappa con lava.)

**1. Inventario**

| Dove | Oggi (256) in elmi | A 128 | Nella prova |
| --- | --- | --- | --- |
| `commanderbst.lua` r. 25, `getCellsFields(…, 2, …)` `ARMED > 500` | 5×5 celle, quadrato di 1280 (±640) | 4 → 9×9, 1152 (±576) | 4 |
| `nukebst.lua` r. 74, `getCellsFields(…, 2, …)` | 1280 | 4 → 1152 | 4 |
| `scoutbst.lua` r. 204, `areaCells(X, Z, 1, …)` | 3×3, 768 | 2 → 640 | non toccato: `ScoutBST:bestAdjacentPos` **non è chiamato da nessuno** (codice morto) |
| `TargetHST:IsSafeCell` `adjacent` default 0 (`buildingshst.lua` r. 845, `mexupbst.lua` r. 112) | la sola cella, 256 | 0 → 128 (area ¼); 1 → 384 (area 2,25×): non si conserva | lasciato 0 (più permissivo: soglia 0 di `ARMED` su ¼ dell'area) |
| `TargetHST:Blobbing` raggio 1 | vicini immediati (connessione) | resta 1, va bene | 1 |
| `MapHST:TopologyFooded` raggio 1 | vicini immediati | resta 1 | 1 |
| `maphst.lua` r. 29, `SimplifyMetalSpots(gridSize * 2)` | 512 (solo se > 1024 spot) | costante 512 | `512 --elmos, …` |
| `maphst.lua` r. 355, `gridThePath` default `gridSize` | toglie i waypoint a meno di 256 | 128: più waypoint; serve a `UnitMexMoveTest` per contare i passaggi di cella, segue la cella | segue |
| `raidhst.lua` r. 256, `gridSizeDouble` | 512 (distanza blob–bersaglio) | costante 512 | 512; `gridSizeDouble` tolto (nessun altro uso) |
| `gridSizeHalf` (disegni di debug in `damagehst`, `loshst`, `targethst`, `maphst`) | metà cella | segue | segue |
| `attackhst.lua` r. 187 `< 256` | tappa raggiunta: elmi, **non** pensato come cella | resta | resta |
| `attackhst.lua` r. 259 `< 512` | distanza dal centro della cella bersaglio per passare a FIGHT: elmi, non «due celle» | resta | resta |
| `raidhst.lua` r. 201 `< 256` | come `attackhst` r. 187 | resta | resta |
| `ScoutHST.SCOUTED` 3600 frame | segna solo la cella dello scout: 256² per 2 minuti | segna ¼ dell'area: più bersagli «non esplorati» | non toccato |
| `DamageHST` calo ×0,9 di `DAMAGED` | minaccia per cella | il danno si divide in celle più piccole, le celle escono prima dalla lista | non toccato |
| `ENEMY` per cella (`LosHST`) | `ARMED`/`UNARM` per cella | valori per cella ≈ ¼; le somme su un'area uguale (comandante, nuke) non cambiano; le soglie su una cella sola sì | — |
| `ScoutHST:PerimetralCells` | celle del bordo: 108 su A, centro a 128 dal bordo | 220, centro a 64 dal bordo | segue |
| `BuildingsHST:UnitMexMoveTest` / `trampledCells` | celle sopra 1,5× la media dei passaggi | 4× celle: posti più numerosi e più fitti per le difese (`taskshst` r. 653, 1094, 1104) | segue |
| `GridLayer:Unmark` | ricerca lineare in `LIST` («LIST is short») | liste fino a 4× più lunghe | — |
| Ricorsione `TopologyFooded` | vedi misura | profondità ≈ numero di celle della rete più grande | — |

**3. Misura** (strumentazione non committata: `Spring.GetTimer`/`DiffTimers` intorno a `Init`, contatori di profondità; il primo tentativo con `GetTimerMicros` è fallito: nel contesto dei moduli restituisce un userdata). Una partita per mappa e misura, 15 minuti:

| | A 256 | A 128 | Jade 256 | Jade 128 |
| --- | --- | --- | --- | --- |
| `GridHST:Init` | 0 ms | 2 ms | 3 ms | 11 ms |
| `MapHST:Init` | 6 ms | 19 ms | 29 ms | 127 ms |
| profondità max `TopologyFooded` | 738 | 2955 | 3907 | **15.588** (78% di ~20.000) |
| profondità max `Blobbing` | 4 | 7 | 4 | 5 |
| memoria per frame: media / max | 0,37 / 69 KB | 0,47 / 58 KB | 0,54 / 7306 KB | 0,26 / 69 KB |
| heap a fine partita | 14,7 MB | 20,1 MB | 18,3 MB | 34,4 MB |
| `Shard memory record` | 15356 | 20624 | 23494 | 41543 |
| fine: unità, fabbriche, mex | 182, 2, 37 | 144, 2, 27 | 58, 1, 17 | 51, 1, 12 |

La profondità è circa il 95% delle celle: una mappa 40×40 (20480 elmi, 25.600 celle a 128) supererebbe il limite. Il picco di 7306 KB in un frame su Jade a 256 non l'ho indagato (probabilmente `UnitMexMoveTest`, «CAUTION is heavy»).

**4. Partite con il codice finale a 128** (senza strumentazione, `SHARD_MEM_STATS=1`, uscita 0, righe `[AI Loader] error`: 0):

| | min. 10 / 13: unità | fine: unità, fabbriche, mex | relay: messaggi / ordini / rifiutati | `Shard memory record` | heap |
| --- | --- | --- | --- | --- | --- |
| A1 | 58 / 84 | 90, 2, 13 | 2598 / 6584 / 17 | 19023 | 18,2 MB |
| A2 | 70 / 95 | 132, 2, 24 | 3435 / 7083 / 13 | 18550 | 18,0 MB |
| A3 | 73 / 122 | 175, 2, 32 | 3362 / 9057 / 11 | 18403 | 17,8 MB |
| C | t0 65 / 102, t1 68 / 120 | t0 135, 2, 28; t1 153, 2, 30 | 4099 / 13400 / 42 | 27994 | 27,3 MB |

Riferimenti: S26 (A a 256, stesso `HEAD`) fine 188–203 unità, 29–38 mex, memory record 15468–15581; S21 min. 13 147–194, fine 161–217; S1 fine 141–186, 23–35 mex; S25 C 155 e 145. A 128 il minuto 13 è sotto S21 in tutte e tre le A, la fine sotto S26 in tutte e tre. La C è nella norma. Memoria +20% su A, quasi ×2 su Jade.

**Perché peggio**: non indagato (il compito chiede di ritirare e decidere). Candidati dall'inventario: `IsSafeCell` con `adjacent` 0 su ¼ dell'area (mex in posti meno sicuri), `trampledCells` più fitti (più difese), `SCOUTED` su ¼ dell'area, ordini molto meno numerosi (6584–9057 contro 12911–17437 di S26).

**Controlli** (sul commit a 128, prima del revert): `lx --lua-version 5.1 test` 2788 successi, 0 fallimenti (1 pending preesistente); test aggiornati: `gridhst_spec.lua` (10 asserzioni con 256 o elmi derivati, mappa dimezzata, `gridSize` 128; fallisce sul codice a 256). `maphst_spec.lua` r. 103 chiama `SimplifyMetalSpots(256)` direttamente e non dipende da `gridSize`; `loshst_spec.lua` e `targethst_spec.lua` hanno 256 nei loro finti `PosToGrid`, non toccati. StyLua 2.5.2 sulle righe toccate: niente. `.emmyrc.json` ripristinato. EmmyLua e `run_engine_tests.sh` non eseguiti: dopo il revert il codice è identico a `a99cabc2c3`, già controllato in S25.

**Per l'utente / il coordinatore**: tenere 256 (consiglio: la ricorsione da sola rende 128 rischioso sulle mappe grandi senza riscrivere `TopologyFooded` in modo iterativo), oppure riprovare 128 con `IsSafeCell` `adjacent` 1 e un `TopologyFooded` iterativo.

### S26 (agente locale, 25 novembre 2026) — verificato dal coordinatore. Il crollo era varianza; nessuna bisezione

Tre partite A su `HEAD` (`a99cabc2c3`), 15 minuti, `SHARD_MEM_STATS=1`, uscita 0, righe `[AI Loader] error`: 0. Nessuna è crollata (criterio: fabbriche 0 o unità < 100).

| | min. 14: unità | fine (SUMMARY): unità, fabbriche, mex | relay: messaggi / ordini / rifiutati | `Shard memory record` |
| --- | --- | --- | --- | --- |
| A1 | 191 | 200, 2, 38 | 4837 / 14562 / 4 | 15581 |
| A2 | 183 | 203, 2, 37 | 4330 / 17437 / 4 | 15468 |
| A3 | 167 | 188, 2, 29 | 2645 / 12911 / 19 | 15573 |

Come da compito: ferma qui, nessun `Echo`, nessun cambio di codice. Il crollo di S25 (1 unità, 0 fabbriche, 2705 messaggi) resta una partita su quattro non spiegata; non si è ripetuta. S19 si può eseguire.

### S25 (agente locale, 25 novembre 2026) — verificato dal coordinatore; la partita A crollata va in S26. Domande: `GetBestBombardCell` e funzioni matematiche globali restano per ora; `test.lua` da guardare in chiusura — da verificare dal coordinatore

**Punto 1, metodi inesistenti in `Tool`** (commit `1209557466`): `bomberbst.lua:59` (`Deactivate`) e `mexupbst.lua:35` e `:127` usavano `GiveOrderToUnit`, che non esiste. Ora `self.ai.tool:GiveOrder(<id>, …)` con l'id dell'unità (`:ID()`), come le altre chiamate. `mexupbst` non è caricato: la correzione è solo di coerenza.

**Punto 2, ricerca generale.** Scanner (non committato, in `scratchpad`): per ogni `self.ai.<modulo>:<Metodo>(` e `self.ai.tool:<Metodo>(` controlla la definizione nel file del modulo. Risultati:
- **Corretto** (commit `bbfd7a4b4d`): `tool.lua:107`, `Tool:RandomAway`, usava `self.ai.map:MapDimensions()`, che non esiste (crash a ogni chiamata). Ora `self.ai.maphst.mapSize`: `maphst` calcola `elmoMapSizeX = mapSize.x * 8`, lo stesso valore di `maxElmosX`.
- **Non corretto, da decidere:** `nukebst.lua:41` e `:43` chiamano `self.ai.targethst:GetBestBombardCell(…)`, che non esiste in `targethst.lua`. Non esiste nemmeno nel codice vecchio (`git show 3ad8f3fb^:luarules/gadgets/ai/Shard/targethst.lua`): il metodo non è mai stato portato. Serve una decisione: portarlo, o far restituire a `NukeBST` la cella con la sua logica.
- **Falsi positivi o codice commentato:** `loshst.lua:85` (`perceptionhandler:OnRadar`) esiste in `shard_runtime/perceptionhandler.lua`; `damagehst.lua:27` e `:39`, `buildingshst.lua:942` e `:945`, `bootbst.lua:147`, `tool.lua:137` sono in commenti.

**Punto 3, globali accidentali.** Controllo con `luac5.1 -l -p` (`SETGLOBAL` per ogni file di `STAI/`):
- **Corretto** (commit `b322840014`): `JOB` in `buildersbst.lua` `ProgressQueue`, assegnato come globale nel ciclo. Ora `local JOB` prima del `for`. Effetto: la riga di debug `"JOB", JOB` del primo giro stampa `nil` invece del valore residuo di una chiamata precedente. Solo debug.
- **Lasciati, da decidere:** in `tool.lua` le funzioni matematiche (`random`, `pi`, `halfPi`, `twicePi`, `sin`, `cos`, `abs`, `max`, `min`, `sqrt`, `floor`, `ceil`, `atan2`) sono globali. Non sono globali di Lua 5.1, e 11 file di `STAI/` le usano senza definirle (`random` in 10 file, `max` in 8, `min` in 7, `floor` in 5, `ceil` in 6 — conteggi senza `tool.lua`): con un `local` in `tool.lua` si romperebbero. Cambiarle vuol dire far definire le locali in ogni file che le usa: scelta di stile del porting, non un refuso.
- **Lasciati, voluti:** i nomi di classe (`BootBST = class(…)`, `GridLayer`, `GraphAStar`, `PathfinderAStar`, `STAI`, …) e `ai` in `boot.lua`. `ai`, `u` e `dump` in `test.lua` sono globali di un file che non compare fra i moduli caricati (`modules.lua`): non ho verificato se il file viene mai incluso.

**Controlli**
- `luac5.1 -p` sui quattro file: ok.
- StyLua 2.5.2: il file `HEAD` è già fuori formato, con righe vuote da correggere: il gate guarda solo le righe toccate. Le righe toccate (`bomberbst` 59, `mexupbst` 35/127, `tool` 107, `buildersbst` 453) non compaiono nell'output.
- EmmyLua 0.24.0 sull'intera `STAI/`: 6193 righe di output, quasi tutte `undefined-global` su `class`, `CMD`, `game` e simili, che il progetto usa senza `---@` (il rumore non è cambiato in modo visibile). `JOB` non compare più fra i globali indefiniti. Non ho fatto un confronto con la base.
- `lx --lua-version 5.1 test`: **2788 successi, 0 fallimenti, 0 errori**, 1 pending preesistente (`def_invariants_spec.lua:321`). `.emmyrc.json` ripristinato.
- `run_engine_tests.sh`: `RESULT: ok`, sincronizzato e non sincronizzato 3 ok, 0 falliti, controllo negativo rilevato.

**Partite** (`run_engine_game.sh`, 15 minuti, `SHARD_MEM_STATS=1`, uscita 0 in entrambe):

| Partita | Relay: messaggi / ordini / rifiutati | Righe `[AI Loader] error` | Fine partita |
| --- | --- | --- | --- |
| A, STAI vs SimpleAI | 2705 / 6094 / 7 | 0 | STAI: 1 unità, 0 fabbriche (SimpleAI: 96 unità) |
| C, STAI vs STAI | 5137 / 23354 / 35 | 0 | 155 e 145 unità, 2 fabbriche ciascuna |

Negli infolog delle partite ci sono errori di widget (`gui_pip` `CreateShader`, `gui_sensor_ranges_jammer_preview` `sheetShader`) e di shader: sono dell'engine in headless, non di STAI. La partita A finisce con STAI quasi distrutto: da tenere d'occhio, ma con una sola partita non si può attribuirlo a questo compito.

**Domande per il coordinatore**
1. `GetBestBombardCell`: portarlo in `targethst` o riscrivere `NukeBST` (righe 41–43)?
2. Le funzioni matematiche globali di `tool.lua`: lasciarle così per ora, o locali in ogni file che le usa?
3. `test.lua` è ancora incluso da qualche parte? Se no, i suoi globali si possono togliere.

### S23 (agente locale, 25 novembre 2026) — verificato dal coordinatore; commit `540d26c853` accettato

**In breve**: `BootBST` ora riconosce la fabbrica e `ExitFactory` gira davvero. Appena girato è emerso un errore **non previsto dal compito**: `ExitFactory` chiamava `self.ai.tool:GiveOrderToUnit`, che in `Tool` non esiste (107 + 99 errori `[AI Loader]` in una partita C). L'ho corretto in un commit a parte (`GiveOrder`, come `SetMoveState`): senza, le uscite cadevano in errore dopo `u:Move`. Tre partite A senza errori del loader.

**Commit**
- `6d760961b2` «STAI: BootBST finds its factory and is mobile for mobile units» (`bootbst.lua`, `bootbst_spec.lua` nuovo): `self.DebugEnabled`, `mobile = speed > 0`, `self.factory = nil` prima del ciclo, controlli su `lab.behaviour` e `lab.exitRect` (esistono: `labsbst.lua` r. 35, 67–72).
- `540d26c853` «STAI: BootBST orders the exit move with Tool:GiveOrder» (una riga). **Fuori dal compito**, da confermare.
- `315e57fae8` «STAI: ReclaimBST priority is 0» (`Priority` restituisce 0, commento a fine riga). «Nell'indice»: `nuovo-stai.md` non lo tocco, lo aggiorna il coordinatore.
- Più il commit di questi risultati.

**Cosa fa `ExitFactory` ora**: per un'unità mobile che si trova nel `exitRect` di una fabbrica (Init o controllo ogni 300 frame): `Priority` 120, `Activate` → `ExitFactory`: sceglie il lato da `GetFacing` della posizione della fabbrica, calcola un punto a 200 elmi, lo limita ai bordi della mappa, `u:Move(out)` più un ordine MOVE (via `GiveOrder`, un'unità, `"1-1"`), poi `lastOrderFrame` e `lastExitSide`. Se dopo 12 frame l'unità è ancora attiva e dentro il rettangolo, `Update` richiama `ExitFactory` con il lato di `GetFacing` della posizione dell'unità (altro lato o lo stesso). Quando l'unità esce dal rettangolo: `factory = nil`, rielezione.
- Aree dell'ordine MOVE: una volta per unità e per tentativo; 335 chiamate per 221 attivazioni (112 unità con più di un tentativo, 109 con uno solo).

**Test busted** (`bootbst_spec.lua`, 4 casi): `mobile` per unità e edificio; `FindMyFactory` dentro l'`exitRect` (`Priority` 120) e fuori (0, anche dopo essere stata dentro); lab senza `behaviour` o `exitRect` scartata. Sul vecchio `bootbst.lua` due test falliscono (`mobile`, fabbrica trovata).

**Misura, partita C** (patch non committata con `Spring.Echo`, tolta): 

| | prima | dopo (con `GiveOrder`) |
| --- | --- | --- |
| attivazioni di `BootBST` | 0 | 221 |
| `ExitFactory` | 0 | 335 |
| unità uscite dal rettangolo | — (mai dentro per `BootBST`) | 221 (tutte) |
| uscite dopo più di 300 frame | non misurabile (`factory` mai assegnata) | 43 (max 2236, media 232) |
| errori `[AI Loader]` | 0 | 0 (con `GiveOrderToUnit`: 206 attivazioni, 206 errori) |

Fine C dopo: team 0 149 unità, 1 fabbrica, 26 mex; team 1 137, 2, 19.

**Tre partite A** (15 minuti, `SHARD_MEM_STATS=1`, uscita 0, righe `[AI Loader] error`: 0):

| | min. 10 / 13 / 14: unità | fine (SUMMARY): unità, fabbriche, mex | relay: ordini / rifiutati | `Shard memory record` |
| --- | --- | --- | --- | --- |
| A1 | 87 / 155 / 177 | 199, 2, 37 | 17005 / 16 | 16259 |
| A2 | 94 / 151 / 159 | 178, 2, 36 | 14042 / 10 | 15393 |
| A3 | 90 / 135 / 137 | 154, 2, 22 | 14415 / 1 | 15631 |

Riferimenti: S21 min. 13 147–194, fine 161–217, 29–36 mex; S1 fine 141–186, 23–35 mex. Una sola partita (A3) un poco bassa (22 mex, 154 unità): non peggio in più di una, nessun'altra correzione tentata.

**Controlli**: `lx --lua-version 5.1 test` 2788 successi, 0 fallimenti, 1 in sospeso (già prima). StyLua pulito sui tre file. `emmylua_check`: nessun errore nei file toccati (solo avvisi, `self.factory may be nil` in `ExitFactory` era già lì; non ho fatto il confronto con la base). `run_engine_tests.sh`: `RESULT: ok`. `.emmyrc.json` ripristinato.

**Da sapere**: `GiveOrderToUnit` è chiamato anche da `mexupbst.lua` (r. 35, 127; non caricato) e `bomberbst.lua` r. 59 (`Deactivate`, ordini verso casa): stesso errore latente, non toccati.

**Domande**
1. Va bene il commit `540d26c853` (fuori dal compito)? Senza, `BootBST` dà errore a ogni uscita.
2. `bomberbst.lua:59` e `mexupbst.lua`: compito a parte?

### S22 (agente locale, 25 novembre 2026) — verificato dal coordinatore; test di `bomberhst` non serve; i rifiutati delle partite C (21–44) si tengono d'occhio

**In breve**: regola nuova d'elezione (`STAI.legacyElection = false`), `CleanerBST:Priority` a `0`, `labshst.lua` non più indicizza una rete `nil` (il caso di S21 è ora coperto da test), `bomberhst` con contatore. Tre commit di codice più questo. Una partita A e una C, nessuna riga `[AI Loader] error`.

**Commit**
- `1ea1b59fe8` «STAI: elect only a priority above zero; CleanerBST priority 0» (`ai.lua`, `cleanerbst.lua`).
- `2805256c24` «STAI: skip lab spots with no network of their layer» (`labshst.lua`, `spec/luarules/gadgets/ai/STAI/labshst_spec.lua`, nuovo).
- `3cf5f0f6da` «STAI: index bomber command ids from a counter» (`bomberhst.lua`).
- Più il commit di questi risultati.

**Punto 1**: `ai.lua` r. 3 ora `STAI.legacyElection = false` con il commento proposto. `CleanerBST:Priority` restituisce `0`.

**Punto 2**: `PostPositionalFilter` prende `NETWORK = networks[mtype][network]` con i controlli su `network` e sul layer; se manca, il punto è scartato come «area too small». Test busted nuovo con tre casi (rete grande, layer senza reti, rete piccola). Sul codice di base il primo caso senza rete dà errore a `labshst.lua:367` (`attempt to index field '?' (a nil value)`): il test fallisce sulla base e passa dopo la correzione.

**Punto 3**: `BomberHST:SquadsPerformBombing` riempie `squad.cmdUnitId` con un contatore `n`, come in S21. **Senza test** (il compito lo chiedeva solo «se semplice»; non l'ho fatto, lo dico qui). Non cambia il gioco oggi (S16: `bomberhst:163` non è chiamato in partita).

**Controlli**
- `lx --lua-version 5.1 test`: 2784 successi, 0 fallimenti, 0 errori, 1 in sospeso (`def_invariants_spec.lua:321`, già prima). Sulla base con il solo `labshst.lua` originale: 1 errore (il test del nil).
- `stylua --check --respect-ignores` su `ai.lua`, `cleanerbst.lua`, `labshst.lua`, `bomberhst.lua`, `labshst_spec.lua`: pulito.
- `emmylua_check -c .emmyrc.json .`: exit 1 come prima (il repo ha già migliaia di avvisi e hint). Nei file toccati **nessun errore**; avvisi nuovi: `unnecessary-if` e `need-check-nil` nel punto di `labshst.lua`, non ho fatto il confronto con la base riga per riga.
- `run_engine_tests.sh`: `RESULT: ok`; sincrono 3 ok, asincrono 3 ok, controllo negativo rilevato.
- `.emmyrc.json`: `lx test` lo riscrive; ripristinato con `git checkout`, non nei commit.

**Partite** (15 minuti, `SHARD_MEM_STATS=1`, uscita 0, 20–30 s ciascuna; righe `[AI Loader] error`: **0** in tutte e due)

| partita | unità STAI min. 10 / 13 / 14 | fine (SUMMARY): unità, fabbriche, mex | relay: messaggi / ordini / rifiutati | memoria |
| --- | --- | --- | --- | --- |
| A (STAI vs SimpleAI) | 103 / 159 / 174 (min. 9–14 sopra) | 198, 2, 32 (SimpleAI 72) | — | — |
| C (STAI vs STAI) | 90 / 154 / 148 (team 0); 107 / 159 / 149 (team 1) | 146, 2, 25 · 164, 2, 26 | 4298 / 30392 / 44 | record 17425 |

Riferimenti (S21, partite A): min. 13 194 / 152 / 147 / 217; fine 161–217, 2, 29–36. Con la nuova regola la partita A sta dentro il range di S21 (min. 13 159, fine 198). **Una partita sola per tipo**, come da compito: la varianza è quella di sempre, non la misuro qui.

**Da sapere**
- Partita C: 44 ordini rifiutati, sopra i 6–21 di S16 e S21. Non l'ho indagato; è in S22 perché il compito non lo chiedeva. Lo segnalo come dato da tenere d'occhio.
- Prima partita con `legacyElection = false` in gioco: i numeri restano nel range di S13 (sei partite di controllo per tipo). Il giudizio sul passaggio resta dell'utente (domanda 1 di S13).

**Domande**
1. Il test di `bomberhst` (punto 3) lo faccio in un compito a parte, o va bene così?
2. I 44 ordini rifiutati nella partita C: li guardo?

### S13 (agente locale, 25 novembre 2026) — verificato dal coordinatore. Decisione dell'utente: **regola nuova sì** (in S22); `AttackerBST` resta com'è per ora

**In breve**: con STAI le due regole differiscono solo quando la legacy elegge `BootBST` (priorità sempre 0) o `CleanerBST` (`nil`); con la nuova quelle unità restano senza behaviour attivo. Nessuno dei due fa qualcosa quando è attivo, quindi il gioco non dovrebbe cambiare. **Correzioni in STAI: nessuna** (passo 3 saltato). Ma due delle tre partite A con `legacyElection = false` sono sotto S1 in qualche numero: per la regola del compito **non ho tenuto il passaggio**, `ai.lua` resta `true`. Sei partite di controllo con la legacy (codice di base) danno lo stesso quadro (2 su 6 sotto S1): tabella al punto 4. Decide l'utente.

**Commit**: solo quello di questi risultati. Nessun commit di codice (né correzioni né passaggio).

**1. Lettura**

La lista dei behaviour viene sempre da `BehaviourFactory:defaultBehaviours` (`behaviourfactory.lua` r. 38): `behaviours.lua` restituisce `{}`, quindi `self.behaviours[nome]` è sempre `nil`. Ordine: `BootBST` primo per ogni fabbrica e ogni unità mobile (`isFactory or speed > 0`), poi i behaviour delle categorie nell'ordine del file; i doppioni si tolgono tenendo l'ultima occorrenza (ciclo da `#b` a 1).

| Behaviour | `Priority()` | `Activate` / `Deactivate` |
| --- | --- | --- |
| `BootBST` | 120 se `self.factory` o (`repairedBy` e `mobile`), altrimenti 0. **In pratica sempre 0**: `FindMyFactory` (r. 108) mette `self.factory = nil` dopo il ciclo, sempre; `repairedBy` non è mai assegnato | `active`; `SetMoveState`/`ExitFactory` solo con `repairedBy`/`factory` → **niente** |
| `CommanderBST` | 200 con `save` (1, 2 o `true`), altrimenti 0 | `active`; GUARD su `safeBuilder` o `HelpFactory` / `active = false` |
| `BuildersBST` | 100 | GUARD sul progetto in corso o `UnitIdle` (nuovo lavoro) / `ClearMyProjects` |
| `EngineerBST` | 1000 | quelli di `Behaviour` (vuoti); `Init` mette `active = true` |
| `LabsBST` | non definita → `Behaviour:Priority` = `self.priority` = **0** (da `Behaviour.init`, chiamato dal costruttore di `class`) | vuoti |
| `ScoutBST` | 100 | debug / toglie `target`, `evading`, `attacking` |
| `RaidBST` | 200 se `RaiderHaveTarget(squad)`, altrimenti 0 | vuoti |
| `AttackerBST` | 200 se `attacking`, altrimenti 0. **Sempre 0**: `attacking` è assegnato solo a `false`/`nil` (r. 49, 58, 109) | `active` |
| `ReclaimBST` | 101 se `self.act`, altrimenti 0. **Sempre 0**: `self.act` non è mai assegnato (esiste solo il metodo `Act`) | vuoti |
| `CleanerBST` | **`nil`** (corpo vuoto) | solo `EchoDebug` |
| `BomberBST` | 100 | `active` / `active = false` e due ordini MOVE verso casa |
| `AntinukeBST`, `NukeBST` | 100 | `NukeBST`: `active` |
| `MexUpBST` | non caricato (commentato in `behaviours.lua`) | — |

Liste per tipo di unità (le principali):

| Unità | Lista | Vince (legacy) | Vince (nuova) |
| --- | --- | --- | --- |
| fabbrica | Boot, Labs | Boot (0) | nessuno |
| costruttore (`armck`…) | Boot, Builders | Builders | Builders |
| comandante | Boot, Commander, Builders | Builders o Commander | uguale |
| ingegnere | Boot, Engineer | Engineer | Engineer |
| rez (`armrectr`, `cornecro`) | Boot, Reclaim **o** Attacker (50 %) | Boot (0) | nessuno |
| combattenti (`armham`, `corthud`, `armrock`, `corstorm`, `armwar`…) | Boot, Attacker | Boot (0) | nessuno |
| raider | Boot, Raid, Scout | Scout (100) o Raid (200) | uguale |
| bombardiere, antinuke mobile | Boot, Bomber / Antinuke | 100 | uguale |
| mobili senza categoria (AA, caccia, radar…) | Boot | Boot (0) | nessuno |
| nano (`armnanotc`, `cornanotc`) | Cleaner (+ Labs se `isStaticBuilder`) | Cleaner (`nil`) | nessuno |
| silo / antinuke fisso | Nuke / Antinuke | 100 | uguale |

C'è anche un'elezione a lista parziale: `BuildersBST:Init` chiama `ElectBehaviour` prima di essere aggiunto (`t:Init()` poi `unit:AddBehaviour(t)`), quindi un costruttore elegge una volta su `{Boot}` o `{Boot, Commander}` → Boot. Con la nuova: nessuno, poi `UnitBuilt` elegge Builders come prima.

**Unità senza behaviour attivo con la nuova regola: chi dà loro ordini?** Gli stessi di oggi. `Unit:Update` chiama `Update` di **tutti** i behaviour, attivi o no, e nessuno dei behaviour coinvolti dipende da `active` per dare ordini:
- combattenti: gli ordini li dà `AttackHST` alle squadre. `AttackerBST` non è attivo con nessuna delle due regole (priorità sempre 0), quindi `OwnerIdle → MemberIdle` (solo se `active`) non gira mai, oggi come dopo;
- rez: `ReclaimBST:Update` chiama `Act` (RECLAIM) sempre; `AttackerBST` come sopra;
- nano: `CleanerBST:Update` fa `Search`/`Clean` sempre;
- fabbriche: `LabsBST:Update` sempre;
- mobili con solo Boot: nessun behaviour dà loro ordini, né con la legacy (Boot non fa niente) né con la nuova.

**`nil` non primo con la legacy** (`score > 0` con `score == nil` → errore): l'unico `nil` è `CleanerBST`, che è primo nella sua lista (le nano non hanno `BootBST`: velocità 0, non fabbriche). Dopo un primo `nil`, `bestScore` è `nil` e un secondo behaviour con priorità > 0 darebbe errore in `score > bestScore`; il secondo possibile è `LabsBST`, sempre 0, quindi `0 > 0` si ferma prima. **Non succede**: 0 casi misurati (punto 2).

Differenze di codice oltre alla regola (`unit.lua`): la legacy, cambiando behaviour, chiama `Deactivate` ma lascia `activeBehaviour` impostato fino al prossimo `Update`; una seconda elezione prima di quell'`Update` può (a) chiamare di nuovo `Deactivate` sullo stesso behaviour, (b) lasciare in attesa un `nextBehaviour` peggiore se rivince quello attivo. La nuova non ha né (a) né (b). Misurati: 0 casi di tutti e due (punto 2).

**2. Misura nella stessa partita** (patch non committata in `LegacyElection`, tolta con `git checkout`; partita C, 15 minuti, legacy attiva). Due partite (la seconda con il contatore delle doppie `Deactivate`):

| | partita C 1 | partita C 2 |
| --- | --- | --- |
| elezioni | 4991 | 5363 |
| diverse fra le due regole | 206 (4,1 %) | 268 (5,0 %) |
| `nil` dopo il primo | 0 | 0 |
| `nextBehaviour` peggiore lasciato in attesa (b) | 0 | 0 |
| doppia `Deactivate` (a) | — | 0 |
| righe `[AI Loader] error` | 0 | 0 |

Coppie diverse (partita C 2; la 1 ha le stesse coppie, con numeri simili): **solo** `BootBST(0) → nessuno` (252) e `CleanerBST(nil) → nessuno` (16). Per tipo di unità:

| unità | Boot → nessuno | | unità | Boot/Cleaner → nessuno |
| --- | --- | --- | --- | --- |
| `corthud` | 90 | | `corck` / `armck` | 8 / 9 |
| `armham` | 70 | | `corack` / `armack` | 3 / 3 |
| `corstorm` / `armrock` | 20 / 20 | | `armwar` | 4 |
| `cornecro` / `armrectr` | 10 / 9 | | `cornanotc` / `armnanotc` (Cleaner) | 8 / 8 |
| `corlab`, `armlab`, `coralab`, `armalab`, `corcom`, `armcom` | 1 ciascuno | | | |

Nessuna elezione in cui la nuova regola sceglie un altro behaviour: cambia solo «Boot/Cleaner attivo» contro «nessuno attivo». Siccome Boot e Cleaner non fanno niente in `Activate`/`Deactivate` (sopra), il gioco non dovrebbe cambiare.

**3. Correzioni**: nessuna necessaria. `CleanerBST:Priority` con `nil` funziona con la nuova regola (`or 0`); un `return 0` esplicito sarebbe solo pulizia, non l'ho fatto (il compito dice «solo se necessarie»). Dimmi se lo vuoi.

**4. Passaggio** (`STAI.legacyElection = false`, con commento `--only a priority above zero wins: a unit whose behaviours are all at zero has none active`; 15 minuti, `SHARD_MEM_STATS=1`, uscita 0, 19–22 s ciascuna). Partite A 1–3 sono quelle del compito; 4–6 e le sei di controllo (codice di base `da7b012a7a`, `legacyElection = true`) le ho aggiunte per vedere la varianza:

| `false` | unità min. 1 / 5 / 10 / 13 | fine (min. 14): unità, fabbriche, mex | `SUMMARY` | relay: messaggi / ordini / rifiutati | memoria: media per minuto, picco | heap |
| --- | --- | --- | --- | --- | --- | --- |
| A1 | 5 / 39 / 98 / 134 | **136**, 2, **21** | 149, 2, 25 | 3989 / 13309 / 7 | 0,18–0,69 KB, 77,5 KB | 12,8–14,7 |
| A2 | 6 / 37 / 80 / **113** | 137, **1**, **14** | 157, 2, 17 | 4025 / 15241 / 7 | 0,17–0,75 KB, **251,0 KB** | 13,0–15,2 |
| A3 | 5 / 37 / 100 / 173 | 192, 2, 33 | 228, 2, 38 | 3709 / 16068 / 6 | 0,18–0,62 KB, 84,2 KB | 13,0–14,6 |
| A4 | 6 / 35 / 91 / 164 | 183, 2, 31 | 203, 2, 33 | 3942 / 15271 / 7 | 0,17–0,87 KB, 61,2 KB | 13,0–15,3 |
| A5 | 6 / 36 / 100 / 148 | 157, 2, 32 | 171, 2, 35 | 4165 / 14592 / 9 | 0,17–1,04 KB, 89,2 KB | 12,9–14,6 |
| A6 | 6 / 42 / 113 / 181 | 206, 2, 33 | 234, 2, 38 | 4465 / 24486 / 13 | 0,17–0,70 KB, 86,8 KB | 12,9–15,6 |

| `true` (controllo) | unità min. 1 / 5 / 10 / 13 | fine (min. 14): unità, fabbriche, mex | `SUMMARY` | relay: messaggi / ordini / rifiutati | memoria: media per minuto, picco | heap |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | 5 / 35 / 88 / 156 | 184, 2, 31 | 210, 2, 37 | 3384 / 16941 / 6 | 0,18–0,63 KB, 94,7 KB | 12,9–15,2 |
| C2 | 6 / 39 / 98 / 175 | 196, 2, 37 | 202, 2, 42 | 4076 / 16806 / 13 | 0,17–0,79 KB, 114,8 KB | 12,9–14,8 |
| C3 | 6 / 37 / 85 / **107** | **114**, 2, **16** | 133, 2, 19 | 3123 / **9244** / 11 | 0,17–0,79 KB, 95,9 KB | 12,9–14,5 |
| C4 | 5 / 38 / 98 / 154 | 185, 2, 31 | 203, 2, 33 | 4296 / 17017 / 19 | 0,18–0,64 KB, 183,9 KB | 12,9–15,1 |
| C5 | 6 / 40 / 76 / 123 | 143, 2, 23 | 140, 2, 24 | 2977 / 11104 / 9 | 0,17–0,59 KB, 82,2 KB | 13,0–14,5 |
| C6 | 6 / 36 / 82 / 122 | **136**, **1**, **18** | 141, 1, 16 | 3750 / 17082 / 13 | 0,17–0,52 KB, 51,3 KB | 13,0–15,2 |

Riferimenti: S1 6 / 25–41 / 54–101 / 117–159, fine 141–186, 2, 23–35; S21 5–6 / 36–42 / 96–110 / 147–194, fine 161–217, 2, 29–36; S12b (A) 6 / 36–37 / 95–112 / 136–180, fine 155–204, 2, 34–37. In grassetto i valori sotto S1.

- **Sotto S1**: con `false` A1 (136 unità e 21 mex a fine partita) e A2 (113 al minuto 13, 1 fabbrica e 14 mex a fine partita); con `true` C3 (107 al minuto 13, 114 e 16 mex alla fine) e C6 (136, 1 fabbrica, 18 mex). **2 su 6 per parte.**
- **Memoria**: picco di A2 251,0 KB, il più alto visto finora (S21 fino a 130,3; S12a2 fino a 90,2); ma anche il controllo ha 183,9 (C4) e 114,8 (C2). Medie per minuto e heap uguali fra le due parti. Un picco solo per partita: varianza, come in S21.
- Medie su sei partite: `false` 152 unità al minuto 13, 168 a fine partita, 27,3 mex; `true` 140, 160, 26,0.
- Per la regola del compito («sotto i riferimenti in più di una partita»: A1 e A2) **non** ho tenuto il passaggio. Il controllo dice che le partite basse capitano allo stesso modo con la legacy, e la lettura dice che il gioco non cambia. Se l'utente decide di tenerlo, il commit è solo `ai.lua` r. 3–4 come sopra.
- **Partita C** (`false`, 15 minuti, uscita 0, 22 s): team 0 / team 1: unità min. 1 / 5 / 10 / 13 7/36/92/116 · 5/39/103/153; fine 126, 2, 21 · 171, 2, 30; `SUMMARY` 124, 2, 20 · 175, 2, 32; 184 morti; relay 4741 / 26817 / 33 (S16: 4364 / 26954 / 21); memoria 0,27–1,05 KB, picco 135,3 KB, heap 13,3–16,6 MB; `Shard memory record` 17651.
- **Righe `[AI Loader] error`: 0** in tutte le 15 partite (3 + 3 A `false`, 6 A `true`, 1 C `false`, 2 C di misura). Errori del log solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown).

**Controlli**: nessun file di codice nel commit, quindi StyLua, EmmyLua, `lx test` e `run_engine_tests.sh` non sono cambiati rispetto a S21 e non li ho rifatti. `git status` pulito a parte `.ai-notes/`; `unit.lua` e `ai.lua` ripristinati con `git checkout`.

**Da sapere** (non toccati)

1. `BootBST:FindMyFactory` (r. 108–115) mette sempre `self.factory = nil` dopo il ciclo: un'unità non riconosce mai la fabbrica in cui si trova, e l'uscita dalla fabbrica (`ExitFactory`) non gira mai. Inoltre `self.mobile = speed == 0` è al contrario (vero per gli edifici), e `ignoreFactories` ne dipende: per tutte le unità mobili è vero, quindi il ramo della fabbrica in `Update` è comunque saltato.
2. `AttackerBST.attacking` e `ReclaimBST.act` non diventano mai veri: i due behaviour non sono mai attivi. Per `AttackerBST`, `Update` chiama `ElectBehaviour` a ogni turno finché ha `squad` e `target` (elezione inutile: dà sempre lo stesso risultato).
3. Con la nuova regola il commento di `Behaviour:YieldControlOfUnit` («there may be no other behaviours to take control») resta vero; nessun behaviour di STAI usa `YieldControlOfUnit`.

**Domande**

1. Tenere il passaggio a `legacyElection = false` nonostante A1 e A2 (il controllo con la legacy ha lo stesso tasso di partite basse)?
2. `CleanerBST:Priority` con `return 0` esplicito: lo faccio (solo pulizia)?
3. I punti 1 e 2 di «Da sapere» (`FindMyFactory`, `mobile`, `attacking`, `act`): compiti a parte?

### S21 (agente locale, 25 novembre 2026) — verificato dal coordinatore. `labshst.lua:367` (rete `nil`) e `bomberhst.lua:158–160` annotati in `nuovo-stai.md` punto 19

**In breve**: `cmdUnitId` ora si riempie con un contatore (`n`) in `raidhst.lua` (prevent, GUARD, MOVE) e in `attackhst.lua` (FIGHT/MOVE); il GUARD di `raidhst` usa `if n > 0`. Il test nuovo fallisce sul codice di base (nessun ordine emesso: `#` dà 0) e passa dopo la correzione. Il gioco cambia solo dove c'era un buco: nelle tre partite A non è comparso nessun caso in cui la vecchia `#` desse un numero diverso da `n` (vedi sotto).

**Commit**

- `3707375c74` «STAI: fill RaidHST and AttackHST order lists without holes» (`raidhst.lua`, `attackhst.lua`, `spec/luarules/gadgets/ai/STAI/raidhst_spec.lua`, nuovo).
- Più il commit di questi risultati.

**Controllo dei membri**: `squad.members` in `raidhst` e `attackhst` è un array (si riempie con `table.insert`; `table.remove` lo tiene senza buchi). I buchi nascono solo nel GUARD di `raidhst`, dove si salta chi già fa GUARD sul bersaglio. Gli altri cicli riempiono tutti i membri, quindi il contatore dà lo stesso risultato: li ho cambiati per sicurezza, come chiesto.

**Non toccato, da decidere**: `bomberhst.lua:158–160` indicizza `cmdUnitId` con `bomber.id` (chiavi non contigue, come `members`): stesso schema. Non l'ho cambiato (fuori dall'elenco del compito). Non cambia il gioco oggi: `bomberhst:163` non è mai chiamato in partita (S16).

**Test** (`raidhst_spec.lua`): tre membri, il primo già in GUARD sul bersaglio; l'ordine GUARD esce con i due altri, in ordine, `{102, 103}`. Sul codice di base l'ordine non esce (`#` dà 0): il test fallisce.

**Partita A: misura della vecchia `#`** (patch temporanea, non committata, solo su `raidhst.lua`, prima partita): 1506 chiamate al GUARD, **0 casi** in cui `#` della vecchia tabella (stesso ordine di inserimento) diverge da `n`. I casi di buco stavano in coda (es. membri 1–2 dentro, 3 saltato), quindi `#` restava giusto; il caso «primo membro saltato» non è comparso. Patch tolta prima delle tre partite finali.

**Tre partite A** (codice `3707375c74`, 15 minuti, `SHARD_MEM_STATS=1`, uscita 0, circa 20 s ciascuna):

| | partita 1 | partita 2 | partita 3 | S12a2 (tre partite) | S1 (intervallo) |
| --- | --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 5 / 42 / 110 / 194 | 5 / 36 / 96 / 152 | 6 / 39 / 96 / 147 | 6/37/106/176 · 6/33/81/117 · 5/39/94/146 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14): unità, fabbriche, mex | 217, 2, 36 | 166, 2, 29 | 161, 2, 32 | 179/134/163, 2/1/2, 35/25/31 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 236, 2, 41 | 181, 2, 30 | 178, 2, 34 | 188/149/171, 2/1/2, 35/26/35 | — |
| relay: messaggi / ordini / rifiutati | 4052 / 13452 / 1 | 3285 / 14590 / 11 | 3618 / 15019 / 11 | 3117–4138 / 13879–16511 / 9–21 | 3405–3933 / 10445–15948 / 9–16 |
| memoria per frame: media per minuto, picco | 0,16–0,77 KB, 73,3 KB | 0,16–0,70 KB, 68,5 KB | 0,17–0,66 KB, 130,3 KB | 0,17–0,94 KB, 31,9–90,2 KB | picchi 68–74 KB |
| heap | 12,8–15,1 MB | 12,9–14,7 MB | 12,8–14,9 MB | 12,9–15,5 | 13,1–15,5 |
| `Shard memory record` | 15467 | 15292 | 15212 | — | — |
| righe `[AI Loader] error` | 0 | 0 | 2 (1 tipo, vedi sotto) | 0 | 0 |

**Fuori dai riferimenti, da leggere**:
- **Partita 1 sopra S1**: 194 unità al minuto 13 (S1 117–159) e 236 a fine partita (S1 141–186). Non è verso il peggio; è la prima partita del gruppo, con la più alta crescita di energia a fine partita (4586 al min. 13): da vedere se ricapita.
- **Partita 3, memoria**: picco 130,3 KB, sopra S1 (68–74) e S12a2 (fino a 90,2). Media per minuto nei limiti.
- **Partita 3, errore del loader** (1 volta, frame 20630, STAI team 0): `labshst.lua:367`, `attempt to index field '?' (a nil value)`. È in `PostPositionalFilter`: `self.ai.maphst.networks[mtype][network]` è `nil` quando `MobilityNetworkHere` non dà una rete per il punto. Riga non toccata da S21 (la sua unica modifica storica è `e4e18a90d7`, che ha solo avvolto `EchoDebug`). Non l'ho indagata oltre la lettura: va in «Domande».

**Controlli**

- `lx --lua-version 5.1 test`: 2781 successi, 0 fallimenti, 0 errori, 1 in sospeso (`spec/gamedata/def_invariants_spec.lua:321`, già prima).
- `stylua --check --respect-ignores` sui tre file (`raidhst.lua`, `attackhst.lua`, `raidhst_spec.lua`): pulito.
- `emmylua_check -c .emmyrc.json .`, base contro finale, sui file toccati: `raidhst.lua` 35 → 35, `attackhst.lua` 35 → 35 (conteggio di righe con il nome del file); nessun errore nuovo.
- `.ai-notes/tools/run_engine_tests.sh`: `RESULT: ok`; sincrono 3 ok, asincrono 3 ok, controllo negativo rilevato.
- `.emmyrc.json`: `lx test` lo riscrive; ripristinato con `git checkout`, non nei commit.

**Domande**

1. Il `labshst.lua:367` (indice di `networks[mtype][network]` con `network == nil`): lo tratto in un compito a parte, o lo lasci com'è?
2. `bomberhst.lua:158–160` ha lo stesso schema (chiavi = id del bombardiere): lo sistemo in un compito a parte? Oggi non cambia nulla in partita.

### S16 (agente locale, 25 novembre 2026) — verificato dal coordinatore; `#` con buchi confermato in `raidhst.lua` r. 271–280 (difetto vero: ordini GUARD saltati) — punto 10: nessun ordine perso per dimensione, si chiude (con un'osservazione su `#` in `raidhst.lua:280`)

**1. Framework.** Il limite è `MAX_ORDERS_PER_MESSAGE = 20` ordini a messaggio (`ordercodec.lua`), 1 messaggio per frame (max 2 per frame di emissione nel relay).
- `1-2` / `2-2` (molte unità, un ordine ciascuna) non hanno gruppo: ogni ordine è un gruppo a sé, `Flush` ne mette 20 per messaggio e il resto va ai frame dopo. Oltre 20 unità non si perde nulla: costa solo latenza (circa 1 frame ogni 20 unità; 100 unità = 5 frame).
- Si perde solo un **gruppo** con più di 20 ordini, cioè `2-1` (molti comandi a una unità): `Flush` lo manda da solo e il relay lo rifiuta intero con `Reject("count")` (riga «N messages rejected (count)»; non entra nel contatore «orders rejected»).
- «Orders rejected» (contatore del relay e `outbox.rejected`) conta solo: ordini per un'unità non valida o non della squadra (morta fra emissione e arrivo), e ordini dopo un ordine tagliato. Non dipende dalla dimensione.

**2. Punti di STAI con più unità (`1-2`) o più comandi (`2-1`).** Gli altri `GiveOrder` sono `1-1`.

| Punto | Metodo | Max osservato |
|---|---|---|
| `attackhst.lua:239` (prevent, FIGHT) | 1-2 | 14 |
| `attackhst.lua:256` (FIGHT) | 1-2 | 9 |
| `attackhst.lua:258` (MOVE) | 1-2 | 15 |
| `raidhst.lua:266` (FIGHT) | 1-2 | 7 |
| `raidhst.lua:280` (GUARD) | 1-2 | 7 |
| `raidhst.lua:293` (MOVE) | 1-2 | 1 |
| `bomberhst.lua:163` (ATTACK) | 1-2 | mai chiamato in C |
| `labsbst.lua:160` (coda di produzione) | 2-1 | 10 (`wave`: costanti fino a 10, una funzione `engineerNeeded`) |

**3. Misura** (patch non committata su `game:GiveOrder`, tolta; partita C, 15 min, Comet Catcher, STAI vs STAI; rapporto fino al frame 25609 di 27000):

| Punto | Chiamate | Con più di 20 unità | Totale unità |
|---|---|---|---|
| attackhst:239 | 497 | 0 | 2159 |
| attackhst:256 | 77 | 0 | 255 |
| attackhst:258 | 330 | 0 | 2376 |
| raidhst:266 | 54 | 0 | 139 |
| raidhst:280 | 2427 | 0 | 7084 |
| raidhst:293 | 3 | 0 | 3 |
| labsbst:160 | 36 | 0 (max 10 comandi) | 96 |
| bomberhst:163 | 0 | 0 | 0 |

Relay a fine partita: 4364 messaggi, 26954 ordini dati, **21 ordini rifiutati** (unità non più valide, nessuna riga «messages rejected»: zero rifiuti per `count`, `seq`, `frame`, `rate`).

**4. Proposta.** Nessun ordine perso in questa partita: il punto 10 si può chiudere. Il rischio teorico resta un `2-1` con più di 20 comandi (oggi `wave` ≤ 10, ma `engineerNeeded` è una funzione senza tetto) e squadre da molte decine di unità, che nell'osservato arrivano a 15. Se in futuro serve, la correzione più economica è nel framework: `game:GiveOrder '2-1'` spezza un gruppo oltre 20 in gruppi da 20 (pro: nessun cambio in STAI; contro: i gruppi non sono più atomici per la stessa unità, con `shift` va bene perché l'ordine è preservato). In alternativa un `math.min(limit, 20)` in `labsbst.lua:160`.

**Osservazione, non misurata come perdita:** in `raidhst.lua:280` (e simili) `squad.cmdUnitId[i]` è riempito solo per i membri cambiati, con buchi, e `game:GiveOrder '1-2'` usa `#id`: in Lua 5.1 `#` su una tabella con buchi può dare un bordo qualunque e far saltare unità. Nella misura la media è 2,9 unità a chiamata (7084/2427), quindi non l'ho potuto separare; vale la pena un compito a parte (loop con `pairs` o contatore).

Nessun commit di codice; `git status` pulito a parte `.ai-notes/`.

### S15 (agente locale, 25 novembre 2026) — verificato dal coordinatore (caveat sulla prima AI fermata: accettato, raro e solo debug). Il `nil` lo romperebbe: verificato leggendo il widget, non in partita

**In breve**: `map.lua` non passa più `self.ai.game:GetTeamID()` ai disegni, ma `drawTeam(self.ai)`: l'id del team se l'AI è un team AI, altrimenti l'id della prima team AI dell'ambito (`ai.AIs[1].id`), altrimenti `nil`. Nove funzioni attive cambiate (`DrawRectangle`, `EraseRectangle`, `DrawCircle`, `EraseCircle`, `DrawLine`, `EraseLine`, `DrawPoint`, `ErasePoint`, `EraseAll`). Partita: nessuna, come da compito.

**Come usa il team il widget** (`luaui/Widgets/shard_help_draw.lua`): ogni forma va in `aiTeams[teamID][channel]` (`GetShapes`, r. 251), e `AddShape`, `EraseShapes` e `ClearShapes` chiamano `GetShapes(teamID, channel)`. Con `teamID == nil`, `aiTeams[nil] = {}` dà l'errore di Lua 5.1 «table index is nil»: quindi un `nil` lo romperebbe, come previsto dal compito. Il selettore di team (tasti `t` e `0`–`9`) elenca i team con forme: un ally team con due AI compare sotto l'id della prima.

**Commit**

- `71fb3121b2` «Shard runtime: file map drawings under a team in ally and global scopes» — `spring_lua/map.lua` e `spec/.../spring_lua/map_spec.lua`.
- Più il commit di questi risultati.

**Dettagli**

- `drawTeam` è una funzione locale in `map.lua`, prima della sezione «DRAWING FUNCTIONS», con commento in inglese. Nessuna tabella nuova: il percorso non alloca.
- Le righe commentate (`--SendToUnsynced(…)`, `--Script.LuaUI…`) contengono ancora `self.ai.game:GetTeamID()`: non le ho toccate, perché sono codice commentato.
- Il file ha terminazioni CRLF; i due file lo mantengono.

**Test** (`map_spec.lua`, nuovo `describe("map drawings")`; `loadMap` accetta ora la lista delle chiamate a `Script.LuaUI`)

1. Team AI (`id = 3`): `ShardDrawAddPoint` riceve 3 come team.
2. Ally team con due AI (`5`, `7`): `ShardDrawClearShapes` riceve `5` e il canale `2`.
3. Ally team senza AI: `ShardDrawAddRectangle` riceve `nil` come team, senza errori.

Verifica che i test siano veri: con `map.lua` di `HEAD` i tre test danno errore (`2777 successi / 0 fallimenti / 3 errori`); con la modifica `2780 successi / 0 fallimenti`.

**Caveat**: se la prima AI di un ally team viene fermata, i disegni successivi vanno sotto la nuova prima AI. I disegni già fatti restano sotto l'id vecchio, e un `EraseAll` dell'ally team pulisce solo il nuovo. Il compito non copriva questo caso: lo segnalo, non l'ho cambiato.

**Controlli**

- `lx --lua-version 5.1 test`: 2780 successi, 0 fallimenti, 0 errori, 1 in sospeso (`spec/gamedata/def_invariants_spec.lua:321`, già prima).
- `stylua --check --respect-ignores` sui due file: pulito.
- `emmylua_check -c .emmyrc.json` sulla cartella `spring_lua`, base contro finale: `map.lua` 56 errori, 10 avvisi, 25 suggerimenti in entrambi; conteggi per file identici. Nessuna segnalazione sul file di spec.
- `.ai-notes/tools/run_engine_tests.sh`: `RESULT: ok`; sincrono 3 ok, asincrono 3 ok, controllo negativo rilevato.
- `.emmyrc.json`: `lx test` lo riscrive; l'ho ripristinato con `git checkout`, non è nei commit.

**Domande**

1. Il caveat sopra (prima AI fermata) va bene così, o vuoi che il team dell'ally team resti fisso (per esempio il primo id visto)?

### S14 (agente locale, 25 novembre 2026) — verificato dal coordinatore. `buildersbst.lua:112` resta così (errore possibile solo con il debug acceso; da sapere)

**In breve**: 84 chiamate `EchoDebug` con argomenti che lavorano (chiamate, `..`, `#`, tabelle, `tostring`) avvolte in `if self.DebugEnabled then … end`, in 16 file, una volta per blocco. Gli argomenti semplici (variabili, campi, costanti, letterali) sono rimasti com'erano. La stampa non cambia. Partita A: uscita 0, nessuna riga `[AI Loader] error`. Busted, StyLua, EmmyLua e test in motore: come sotto.

**Commit** (tre, uno per gruppo; in inglese)

- `e4e18a90d7` «STAI: guard costly EchoDebug arguments in the modules» — `attackhst`, `bomberhst`, `buildingshst`, `cleanhst`, `gridhst`, `labshst`, `maphst`, `raidhst`.
- `0600d4a4d1` «STAI: guard costly EchoDebug arguments in the behaviours» — `bootbst`, `buildersbst`, `cleanerbst`, `labsbst`, `mexupbst`, `nukebst`, `scoutbst`.
- `5e0df48657` «STAI: guard costly EchoDebug arguments in tool» — `tool.lua`.
- Più il commit di questi risultati.

**Elenco** (chiamate avvolte per file; un blocco per chiamata: nessuna chiamata costosa era vicina a un'altra, quindi nessun gruppo)

| file | chiamate | file | chiamate |
| --- | --- | --- | --- |
| `attackhst.lua` | 6 | `labsbst.lua` | 1 |
| `bomberhst.lua` | 2 | `labshst.lua` | 11 |
| `bootbst.lua` | 4 | `maphst.lua` | 6 |
| `buildersbst.lua` | 14 | `mexupbst.lua` | 6 |
| `buildingshst.lua` | 13 | `nukebst.lua` | 1 |
| `cleanerbst.lua` | 2 | `raidhst.lua` | 6 |
| `cleanhst.lua` | 1 | `scoutbst.lua` | 5 |
| `gridhst.lua` | 3 | `tool.lua` | 3 |

Totale: 84 avvolte su 361 chiamate attive (le altre 277 restano com'erano). Le chiamate commentate (`--self:EchoDebug(…)`) non sono toccate.

**Casi dubbi**

- Lasciati, perché sono argomenti semplici (regola del compito): variabili, campi (`self.id`, `squad.squadID`, `self.role`), letterali e costanti. Avvolte: le chiamate (anche `unit:ID()`) e le concatenazioni `..`.
- `bomberhst.lua:122` e `149`: gli argomenti chiamano `SquadTargetExist` e `IsBombing`. Sono letture senza effetti sul gioco (il loro unico effetto è `EchoDebug`), quindi avvolte come le altre.
- **`buildersbst.lua:112`** (`game:GetUnitByID(self.assistant):GetPosition()` e `:Name()` dentro l'argomento): se l'assistente è morto, `GetUnitByID` dà `nil` e la chiamata va in errore. Nel codice di prima l'errore era sempre valutato, ora succede solo con `DebugEnabled`. Quindi nel gioco normale l'errore sparisce, e questo è un cambio di comportamento (una volta non è più un errore, ma nessuno l'ha verificato). Da decidere: lasciare così (il caso è solo in debug) o scrivere un controllo esplicito dentro il blocco o fuori.
- `taskshst.lua` non è stato toccato (non ha chiamate costose; già non era pulito in StyLua prima di questo lavoro).

**Controlli**

- `lx --lua-version 5.1 test`: 2777 successi, 0 fallimenti, 0 errori, 1 in sospeso (`spec/gamedata/def_invariants_spec.lua:321`, già prima).
- `stylua --check --respect-ignores` sui 16 file: pulito dopo `stylua` (la correzione ha toccato due righe di `bomberhst.lua` e `buildersbst.lua`, dove la chiamata è più lunga di 120 colonne).
- `emmylua_check -c .emmyrc.json` sulla cartella STAI, base (`HEAD` prima del lavoro) contro finale: errori 367 → 367 (`undefined-global`, tutti già presenti); avvisi `unnecessary-if` 24 → 26: due nuovi, in `mexupbst.lua` (r. 16) e `buildersbst.lua`, dove EmmyLua deduce `self.DebugEnabled` da `= false` e dà la condizione come sempre falsa o sempre vera. Sono 2 su circa 437 righe cambiate: sotto il budget di 15 nuovi ogni 1000 righe. Nessun errore nuovo.
- `.emmyrc.json`: `lx test` lo riscrive; l'ho ripristinato con `git checkout` (non è nei commit).
- `.ai-notes/tools/run_engine_tests.sh`: `RESULT: ok`; sincrono 3 ok, asincrono 3 ok, controllo negativo rilevato.

**Partita A** (`a_stai_vs_simpleai.txt`, 15 minuti, `SHARD_MEM_STATS=1`, codice `e4e18a90d7`…`5e0df48657`, uscita 0, circa 20 s, una partita)

| | STAI (team 0) | SimpleAI (team 1) |
| --- | --- | --- |
| unità min. 1 / 5 / 10 / 13 | 6 / 37 / 95 / 143 | — |
| fine partita (min. 14): unità, fabbriche, mex | 172, 2, 30 | 65, 1, 10 |
| `SUMMARY` (fine) | 192, 2, 34 | 76, 1, 9 |
| relay: messaggi / ordini / rifiutati | 4705 / 18639 / 13 | — |
| memoria per frame: media per minuto, picco | 0,58–0,94 KB, 69 KB | — |
| heap | 14,4–15,7 MB | — |
| righe `[AI Loader] error` | 0 | — |

Il minuto 13 (143 unità) sta nell'intervallo di S1 (117–159). Una partita sola: riferimento di massima. Nel log ci sono errori del motore (`gui_pip` su `CreateShader`, shader di `AoE Napalm` e `Reclaim Field`, `groundFX`, `AdvSky`): sono di rendering e widget in headless, non vengono da STAI.

**Domande**

1. `buildersbst.lua:112`: quale delle tre soluzioni vuoi (vedi sopra)?
2. Le due nuove `unnecessary-if` le lascio così o le tolgo con una dichiarazione esplicita del tipo del campo? (Non le ho toccate.)

### S12b (agente locale, 25 novembre 2026) — verificato dal coordinatore. Commento «a design choice» va bene

**In breve**: `DamageHST` registra i danni di tutta l'alleanza (test con mutazioni); i tre moduli sono in ambito `"ally"` cambiando solo `Scope()`: nei tre file non c'era niente di squadra da togliere, e i lettori di squadra li raggiungono come prima. Partita B: **una** istanza per alleanza di ciascuno, nessun errore del loader, nessuna delle due STAI gioca molto peggio. Tre partite A: nessun numero sotto i riferimenti. Il framework non serve toccarlo.

**Commit**

- `558479f83d` «STAI DamageHST: record the damages to every unit of the ally team» (`damagehst.lua`, `damagehst_spec.lua`).
- `cbb8cb7a95` «STAI LosHST, TargetHST, DamageHST: one instance per ally team» (`loshst.lua`, `targethst.lua`, `damagehst.lua`: solo `Scope()`).
- Un commit per questi risultati.

**0. Partita B di riferimento** (`b_2stai_vs_2simpleai.txt`, 15 minuti, `SHARD_MEM_STATS=1`, codice `65c0228d`, uscita 0, 22 s): numeri nella tabella del punto 4. Una partita sola: riferimento di massima. Lo script **non** dà il tempo per frame delle AI (il timer per AI dell'engine c'è solo con `/debug`), quindi non c'è.

**1. `Scope()`**: `"ally"` in `loshst.lua` r. 12, `targethst.lua` r. 14, `damagehst.lua` r. 12. Nient'altro da cambiare (punto 3).

**2. `DamageHST:UnitDamaged`**: r. 21 `if defender:AllyTeam() ~= self.ai.allyId then --the damages of the whole ally team, human allies too: a design choice`; tolta la `local teamID`. Nel commento ho scritto «a design choice» e non «user decision», perché le regole sui commenti (`agents.md`) chiedono di non citare il compito o la conversazione: dimmi se lo vuoi alla lettera.

- `damagehst_spec.lua`: il finto `ai` è uno `ShardAlly` (solo `allyId`, niente `id`). Test nuovo «records the hits to a unit of a human ally, not to a unit of another ally team»: un'unità di una squadra umana alleata (team 3, alleanza 0) colpita da una torre nemica → `losEnemy` e una posizione registrate; un'unità dell'alleanza 1 colpita da una torre di una terza alleanza → niente. Ho messo i due casi in un test solo perché il secondo, da solo, passa anche sulla base (la base esce per ogni difensore non della squadra).
- Mutazioni (3 test): base `65c0228d` → 3 falliti; niente filtro (`if false then`) → 1; filtro sulla squadra (`defender:Team() ~= 0`) → 1.

**3. Controlli sui tre moduli**

- Grep `self.ai.id`, `GetTeamID`, `self.ai.tool`/`ai.tool`, `self.ai.<campo> =`: **nessuno**. I `self.ai.*` rimasti: `allyId`, `drawDebug` (su `ShardAlly`, da `ShardAI:Init` → `DrawDisplay(false)`), `armyhst`, `gridhst` (globali), `loshst`, `perceptionhandler` (ally). Nessun modulo di squadra.
- Scritture dall'esterno nei tre moduli (grep `loshst|targethst|damagehst` seguito da campo o indice e `=`): solo `damagehst.lua` r. 37–38 su `self.ai.loshst.losEnemy`/`radarEnemy`, che ora è il `LosHST` della stessa alleanza.
- Eventi ricevuti come ally (dal loader):
  - `LosHST:UnitEnteredLos`/`LeftLos`/`EnteredRadar`/`LeftRadar`: `DeliverSight` li dà solo agli `ShardAlly` dell'alleanza che vede, una volta. Il filtro `allyTeam ~= self.ai.allyId` ora non scarta niente; l'ho lasciato. `UnitLeftLos` legge `self.ai.perceptionhandler:OnRadar`: `PerceptionHandler` viene prima in `modules.lua` e prima era già ally, quindi l'ordine resta.
  - `LosHST:UnitDead`: arriva per **tutte** le unità della partita (`DeliverToAll`, anche da `UnitTaken`), come prima arrivava a ogni squadra. `cleanEnemy` su un'unità che non conosce mette a `nil` tre chiavi già `nil`: niente effetti.
  - `DamageHST:UnitDamaged`: tutte le unità della partita (`DeliverToAll`), filtrate per alleanza del difensore (punto 2).
  - `Update` dei tre: dallo scheduler (`MScheduler` di STAI), che dà a un modulo ally **un turno per giro** per l'oggetto che lo tiene (`scheduler.lua`, `Holder`/`RebuildModules`). Con una STAI per alleanza (partita A) il giro ha gli stessi turni di prima; con due (B) i tre moduli girano una volta per giro invece di due.
  - Nessuno dei tre ha `UnitCreated`, `UnitBuilt`, `UnitIdle`, `GameEnd`. `LosHST:Draw` non è un evento e nessuno la chiama.
  - Ordine: ogni evento arriva prima agli ally e poi alle squadre, quindi `LosHST:UnitDead` e `DamageHST:UnitDamaged` girano prima di quelli dei moduli di squadra. Nessun modulo di squadra legge `losEnemy`/`DAMAGED` nei suoi `UnitDead`/`UnitDamaged` (l'unico altro `UnitDamaged` è `UnitHST`, che non li legge).
- Lettori di squadra: `self.ai.loshst`/`targethst`/`damagehst` da un modulo o behaviour di squadra è il campo che `ShardAI:LoadModule` fa puntare all'istanza dell'alleanza (scope più largo → `self.ally[internalName]`). Lettori: `attackhst`, `raidhst` (anche con `local loshst`/`targethst`), `bomberhst`, `scouthst` (`damagehst.DAMAGED`), `buildingshst`, e i behaviour `buildersbst`, `labsbst`, `commanderbst`, `scoutbst`, `mexupbst`, `nukebst`. Leggono soltanto; nessuno scrive.
- `game` e `map` globali: `ShardAI:Prepare` mette quelli dell'`api` dello `ShardAlly`, con `game.ai`/`map.ai` = lo `ShardAlly`. Usati: `game:GetUnitByID` (`Shard:shardify_unit`, non dipende dalla squadra), `game:Frame`, `game:GetUnitLos` (usa `self.ai.allyId`: giusto), `map:GetGroundHeight`. **Dipende dalla squadra** solo il disegno: `map:DrawRectangle`, `DrawPoint`, `DrawCircle`, `EraseAll` passano `self.ai.game:GetTeamID()`, cioè `self.ai.id`, che sullo `ShardAlly` è `nil`. Gira solo con `drawDebug` vero, e nessuno chiama `DrawDisplay(true)`: oggi non succede niente, ma se si accendono i disegni di debug dei tre moduli bisognerà dare a `map` un'altra chiave (per esempio l'alleanza). `Spring.GetGroundHeight`/`GetUnitVelocity` diretti (in `loshst.lua` e nel disegno di `damagehst.lua`) non dipendono dalla squadra.

**4. Prove**

Partita B (`b_2stai_vs_2simpleai.txt`, 15 minuti, `SHARD_MEM_STATS=1`, uscita 0, 22 s): righe del loader `ally 0, ShardAlly, Info: , adding PerceptionHandler module`, poi `… adding LosHST module`, `… TargetHST …`, `… DamageHST …`, **una** volta ciascuna (prima: `0, STAI` e `2, STAI` per ciascuno). Nessuna riga `[AI Loader] error`, nessun avviso di STAI; errori del log quelli di sempre, uguali riga per riga al riferimento.

| | riferimento (`65c0228d`): team 0 / team 2 | finale (`cbb8cb7a95`): team 0 / team 2 |
| --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6/31/77/130 · 6/25/62/92 | 6/34/87/88 · 6/37/68/131 |
| fine partita (min. 14): unità, fabbriche, mex | 134, 1, 14 · 109, 1, 23 | 106, 2, 14 · 138, 2, 20 |
| `SUMMARY` (fine) | 150, 2, 16 · 120, 1, 22 | 124, 2, 16 · 122, 2, 17 |
| somma delle due STAI al min. 14 | 243 | 244 |
| SimpleAI al min. 14 (team 1 / 3) | 60 / 60 | 57 / 38 |
| relay: messaggi / ordini / rifiutati | 4484 / 22230 / 30 | 5526 / 24591 / 45 |
| memoria per frame: media per minuto, picco | 0,30–0,90 KB, 88,8 KB | 0,29–0,87 KB, 59,7 KB |
| heap | 13,4–18,2 MB | 13,2–17,7 MB |
| `Shard memory record` | 19267 | 18082 |
| morti nella partita | 207 | 247 |
| righe `[AI Loader] error` | 0 | 0 |

- Nessuna delle due STAI gioca molto peggio: la somma a fine partita è la stessa. Il team 0 si ferma fra il minuto 11 e il 13 (98 → 88 unità, con una seconda fabbrica dal minuto 12) mentre il team 2 cresce (69 → 131): perdite in combattimento (247 morti contro 207), non un blocco. Con una partita sola non dice altro.
- Memoria: media per minuto e heap circa uguali, picco più basso (59,7 contro 88,8 KB). Una partita sola per parte: i picchi variano molto anche a codice invariato (S12a2: 31,9–90,2 KB), quindi non ne ricavo un risparmio.

Tre partite A (`a_stai_vs_simpleai.txt`, `SHARD_MEM_STATS=1`, 15 minuti, codice `cbb8cb7a95`, uscita 0, 18–22 s). In tutte e tre le righe dei tre moduli sono `ally 0, ShardAlly`.

| | partita 1 | partita 2 | partita 3 | S12a2 (tre partite) | S1 (intervallo) |
| --- | --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6 / 36 / 101 / 168 | 6 / 37 / 112 / 180 | 6 / 37 / 95 / 136 | 6/37/106/176 · 6/33/81/117 · 5/39/94/146 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14): unità, fabbriche, mex | 192, 2, 35 | 204, 2, 37 | 155, 2, 34 | 179/134/163, 2/1/2, 35/25/31 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 215, 2, 37 | 200, 2, 40 | 157, 2, 35 | 188/149/171, 2/1/2, 35/26/35 | — |
| relay: messaggi / ordini / rifiutati | 3900 / 15479 / 5 | 2935 / 16179 / 11 | 3537 / 14371 / 12 | 3117–4138 / 13879–16511 / 9–21 | 3405–3933 / 10445–15948 / 9–16 |
| memoria per frame: media per minuto, picco | 0,17–0,84 KB, 74,8 KB | 0,17–0,82 KB, 85,0 KB | 0,17–0,71 KB, 53,0 KB | 0,17–0,94 KB, 31,9–90,2 KB | picchi 68–74 KB |
| heap | 12,9–15,0 MB | 12,9–15,0 MB | 12,9–14,5 MB | 12,9–15,5 | 13,1–15,5 |
| righe `[AI Loader] error` | 0 | 0 | 0 | 0 | 0 |

- **Niente sotto i riferimenti.** Sopra S1: unità al minuto 13 delle partite 1 e 2 (168, 180) e al minuto 10 della 2 (112), unità e mex a fine partita delle partite 1 e 2 (192, 204; mex 37 della 2), ordini della partita 2 (16179). Fuori da S1 ma non verso il peggio: rifiutati della partita 1 (5, S11 1–10), messaggi della 2 (2935, S11 da 2724).
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown), uguali alla partita B di riferimento.

**Controlli**

- `lx --lua-version 5.1 test`: 2777 successi, 0 falliti, 1 pending (2776 + 1 test nuovo). `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 su `loshst.lua`, `targethst.lua`, `damagehst.lua`, `damagehst_spec.lua`: ok.
- EmmyLua 0.24.0, base `65c0228d` (stash) → finale: errori 19 → 19; per file (avvisi / hint) `loshst.lua` 3/18 → 3/18, `targethst.lua` 43/6 → 43/6, `damagehst.lua` 4/5 → 4/5; `damagehst_spec.lua` senza diagnostiche in entrambi. I **totali** di avvisi non sono confrontabili: due esecuzioni sullo stesso codice finale danno 22927 e 23414 avvisi (342 righe di file diverse, tutti file non toccati: `common/wav.lua`, `gamedata/…`), quindi il controllore varia da un'esecuzione all'altra.
- `.emmyrc.json` ripristinato; `git status` pulito a parte `.ai-notes/`.

**Da sapere**

- I disegni di debug dei tre moduli (`map:Draw*`, `EraseAll`) passerebbero squadra `nil` (punto 3). Oggi spenti.
- `nukebst.lua` r. 41 e 43 chiamano `self.ai.targethst:GetBestBombardCell`, che non esiste in `TargetHST` e non esisteva neanche nello STAI tolto (`3ad8f3fb^`): con un'unità nucleare quel ramo darebbe errore. C'era già; non toccato.
- `.ai-notes/drafts/README.md`, «Scopes», dice ancora «the other modules declare "team" for now, and LosHST will move to "ally" when it is ported»: ora sono ally anche `TargetHST` e `DamageHST`. Non l'ho toccato (lo aggiorna il coordinatore?).
- `DamageHST` ora segna anche i colpi alle unità degli alleati umani: `ScoutHST:TargetAvailable` (r. 79) scarta quelle celle per gli scout anche se nessuna unità STAI ci è stata colpita.

### S12a2 (agente locale, 25 novembre 2026) — verificato dal coordinatore. Partita 2 sotto S1 (134 unità, una fabbrica): come la partita 1 di S10 a codice invariato, varianza; le altre due dentro. `GetCenter` può dare `nil` prima del primo edificio (nessuno la chiama prima: da sapere)

**In breve**: `CENTER` è la media degli edifici, o la posizione attuale del comandante senza edifici, o l'ultimo `CENTER` senza comandante vivo, tramite `BuildingsHST:GetCenter()`; `GetBlobs` e `drawDBG` scorrono `blob.cells` con un ciclo numerico. Test busted con mutazioni. Partita C: blob uguali a quelli con `pairs` tranne `metal` nelle ultime cifre (25 volte, scarto massimo 0,00049); `CENTER` sempre la media degli edifici dal frame 180. Tre partite A: la **partita 2 va sotto i riferimenti a fine partita** (134 unità al minuto 14, S1 141–186); nessuna correzione tentata.

**Commit**

- `07469c52c4` «STAI BuildingsHST: CENTER is the mean of the own buildings, or the commander position without them» (`buildingshst.lua`, `commanderbst.lua`, `attackhst.lua`, `raidhst.lua`, `buildingshst_spec.lua`).
- `ddc812ace2` «STAI TargetHST: walk the cells of the blobs with a numeric loop» (`targethst.lua`).
- Un commit per questi risultati.

**1. `CENTER`**: la proposta, con due scelte mie.

- `BuildingsHST:GetCenter()`: se `self.buildingsCenter`, restituisce `CENTER` (la media che tiene `getCenter`); se no `game:GetUnitByID(self.commanderID)` e `GetRawPos()`, e con una posizione copia `x, y, z` in `CENTER` (`self.CENTER = self.CENTER or {}`, campo per campo); senza, `CENTER` resta com'è. `getCenter` scrive `self.buildingsCenter = count > 0` e per il resto è quella di prima.
- Ho usato `GetRawPos` e non `GetPosition`: non tocca la tabella di posizione del comandante (`ShardUnit:GetPosition` la riscrive a ogni chiamata, era la causa di S12a). Comandante morto: `Spring.GetUnitPosition` dà `nil`, quindi `x` è `nil` (stesso criterio di `GetPosition`). `game:GetUnitByID(nil)` restituisce `nil` (`Shard:shardify_unit` esce subito), quindi senza comandante registrato non serve un controllo a parte.
- `CommanderBST:Init`: `self.ai.buildingshst.commanderID = self.id --CENTER without buildings; the last registered commander wins`. Con più comandanti vale l'**ultimo registrato** (l'ultimo `CommanderBST:Init`); se muore, senza edifici `CENTER` resta fermo anche se ce n'è un altro vivo. `self.position` di `CommanderBST` resta (lo legge `UnitMexMoveTest`), ma non va più in `CENTER`.
- Lettori: `attackhst.lua` (`SquadsTargetPrevent2`: `local center = self.ai.buildingshst:GetCenter()` prima del ciclo dei blob, non a ogni giro), `raidhst.lua` r. 398, `BuildingsHST:VisualDBG` (`map:DrawPoint(self:GetCenter(), …)`).
- Grep `CENTER` in `luarules/gadgets/ai/STAI/`: lo scrivono solo `GetCenter` e `getCenter`, sempre campo per campo; nessuna tabella di posizione di un'unità dentro `CENTER`. `TargetHST` usa la parola «CENTER» solo come etichetta del disegno di `enemyCenter`.
- `buildingsCenter` **non** è inizializzato in `Init`: con `self.buildingsCenter = false` in `Init` EmmyLua dava un avviso nuovo (`unnecessary-if`: deduce il tipo `false` dalla prima assegnazione e dice che `if self.buildingsCenter` è sempre falso). Senza, `nil` fino al primo `getCenter`, stesso effetto. Allo stesso modo `game:GetUnitByID(self.commanderID)` al posto di `self.commanderID and …` (stesso avviso su `if commander`).
- Test (`buildingshst_spec.lua`, sostituiscono quello di S12a; unità finte con posizione modificabile, `GetPosition` che riscrive una sola tabella come `ShardUnit`):
  - «gives as center the current commander position without buildings, in a table of its own»: posizione del comandante, poi il comandante si muove e `GetCenter` lo segue; `CENTER` ≠ la tabella di `GetPosition`;
  - «gives as center the mean of the buildings, even when the commander moves»;
  - «goes back to the commander when all the buildings are lost»;
  - «keeps the last center with no buildings and the commander dead».
- Mutazioni (4 test): M1 niente ramo del comandante → 3 falliti; M2 il comandante vince sugli edifici → 2; M3 `buildingsCenter` mai scritto → 2; M4 `buildingsCenter` mai rimesso a falso → 1; M5 `CENTER = commander:GetPosition()` → 1; M6 comandante morto azzera `CENTER` → 1. Codice di S12a (`349eafe8b3`) con i test nuovi: 4 errori (manca `GetCenter`).

**2. Ciclo numerico**: `GetBlobs` r. 53 `for n = 1, #blob.cells do --numeric loop keeps the order of the cells` + `local v = blob.cells[n]`; uguale nei due cicli di `drawDBG` (r. 189 e 202, `local cell = blob.cells[n]`). Il test dei blob di S12a resta verde. (`drawDBG` legge ancora `cell.POS` sulle `cellCoord`, che non ce l'hanno: c'era già, non toccato.)

**3. Partita C** (`c_stai_vs_stai.txt`, 15 minuti, codice di prova non committato e tolto con `git checkout`, uscita 0, 21 s). `TargetHST:cmpBlobPairs`: dopo il riempimento di ogni blob, la stessa somma con `pairs(blob.cells)` sulle stesse celle, confrontata con il blob (`position` x, y, z; `targetCell`; insieme di `units`; `metal`).

| | ally 0 | ally 1 |
| --- | --- | --- |
| blob confrontati | 4166 | 1601 |
| `position`, `targetCell`, `units` diversi | 0 | 0 |
| `metal` diverso | 21 | 4 |
| scarto massimo di `metal` | 0,000488 | 0,000244 |
| blob dove `pairs` non va in ordine numerico | 1457 | 636 |

`CENTER` (contato in `GetCenter` e a ogni `getCenter`, frame passati in ciascun modo):

| | squadra 0 | squadra 1 |
| --- | --- | --- |
| posizione del comandante: chiamate / frame | 0 / 0 | 0 / 0 |
| media degli edifici: chiamate / frame | 856 / 26829 | 2064 / 26828 |
| nessuno dei due (`CENTER` ancora `nil`): frame | 181 | 180 |

Il primo edificio nasce al frame 180–181; prima nessuno chiama `GetCenter`, e la `getCenter` del `UnitCreated` del comandante gira prima di `CommanderBST:Init`, quindi in quei frame `CENTER` è `nil` (prima era la tabella del comandante, ma nessuno la leggeva). In questa partita nessuna squadra ha perso tutti gli edifici: il ramo del comandante non è mai servito.

**4. Tre partite A** (`a_stai_vs_simpleai.txt`, `SHARD_MEM_STATS=1`, 15 minuti, codice finale `ddc812ace2`, uscita 0, 18–20 s)

| | partita 1 | partita 2 | partita 3 | S11 (tre partite) | S1 (intervallo) |
| --- | --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6 / 37 / 106 / 176 | 6 / 33 / 81 / 117 | 5 / 39 / 94 / 146 | 6/36/104/146 · 5/37/103/179 · 5/33/100/160 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14): unità, fabbriche, mex | 179, 2, 35 | **134**, **1**, 25 | 163, 2, 31 | 172/203/168, 2/2/2, 27/31/34 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 188, 2, 35 | 149, 1, 26 | 171, 2, 35 | 196/230/177, 2/2/2, 30/36/38 | — |
| relay: messaggi / ordini / rifiutati | 4138 / 16511 / 9 | 4030 / 14603 / 11 | 3117 / 13879 / 21 | 2724–3691 / 12797–16921 / 1–10 | 3405–3933 / 10445–15948 / 9–16 |
| memoria per frame: media per minuto, picco | 0,18–0,94 KB, 72,9 KB | 0,17–0,51 KB, 31,9 KB | 0,18–0,74 KB, 90,2 KB | 0,18–0,59 KB, 50–93 KB | picchi 68–74 KB |
| heap | 12,9–14,8 MB | 12,9–15,5 MB | 13,0–14,7 MB | 12,9–15,1 | 13,1–15,5 |
| righe `[AI Loader] error` | 0 | 0 | 0 | 0 | 0 |

- **Sotto i riferimenti**: la partita 2 a fine partita (134 unità al minuto 14, S1 141–186; una sola fabbrica, come una partita di S10), e al minuto 13 è al bordo basso (117). Le partite 1 e 3 stanno dentro S1 (la 1 al minuto 10 e 13 appena sopra, come S11). Con il seme che cambia a ogni avvio non so dire se sia il cambio di `CENTER`; non ho tentato correzioni.
- Fuori dagli intervalli anche: messaggi del relay delle partite 1 e 2 (4138, 4030, sopra S1 e S11), ordini della partita 1 (16511, sopra S1), rifiutati della partita 3 (21, sopra S1 e S11), media di memoria per minuto della partita 1 fino a 0,94 KB (S11 fino a 0,59, S10 fino a 0,76) e picco della partita 3 a 90,2 KB (S11 92,9).
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown).

**Controlli**

- `lx --lua-version 5.1 test`: 2776 successi, 0 falliti, 1 pending (2773 − 1 test di S12a + 4 nuovi). `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 sui file toccati: ok.
- EmmyLua 0.24.0, confronto con la base `042550bd50` (stash): per file (avvisi / hint, base → finale) `buildingshst.lua` 26/35 → 26/35; `targethst.lua` 43/9 → 43/6; `commanderbst.lua` 4/4, `attackhst.lua` 7/23, `raidhst.lua` 6/24 uguali; `buildingshst_spec.lua` senza diagnostiche.
- `.emmyrc.json` ripristinato; `git status` pulito a parte `.ai-notes/`.

**Da sapere**

- Il comandante che riprende `CENTER` senza edifici è quello di `CommanderBST`, cioè di questa squadra; se ne nasce un secondo (per esempio regalato), diventa lui il riferimento.
- `attackhst.lua` chiama `GetCenter` una volta prima del ciclo; senza edifici, `CENTER` è la posizione del comandante in quel momento.

### S12a (agente locale, 25 novembre 2026) — verificato dal coordinatore: punti 1–5 accettati; `CENTER` e il ciclo dei blob si completano in S12a2 (decisioni dell'utente). — **fermato alla prova in partita**: due differenze, una vera (`CENTER`) e una di arrotondamento (`metal` dei blob)

**In breve**: punti 1–5 fatti, un commit ciascuno, test busted per `getCenter` e per il ritorno dei blob (falliscono sulla base). La prova nella stessa partita C trova differenze, quindi mi sono fermato: **niente partita A**. La causa principale: nella base `CENTER` **non** era la posizione del comandante all'avvio, ma la **tabella che `ShardUnit:GetPosition` riscrive a ogni chiamata**. Il punto 1 (copia) cambia il gioco. Servono due decisioni (sotto, «Domande»).

**Commit**

- `d60cadd582` «STAI BuildingsHST: hold CENTER and the own buildings, moved from LosHST» (`buildingshst.lua`, `loshst.lua`, `commanderbst.lua`, `attackhst.lua`, `raidhst.lua`, `buildingshst_spec.lua` nuovo, `loshst_spec.lua`).
- `9f43d6cf20` «STAI LosHST: keep needAntiAir in LosHST instead of on the AI» (`loshst.lua`, `buildersbst.lua`, `labsbst.lua`).
- `c3bd380549` «STAI DamageHST: remove friendlyTeamID, never filled, and compare the team with ai.id» (`loshst.lua`, `damagehst.lua`, `damagehst_spec.lua`).
- `f5d2aecafc` «STAI DamageHST: remove isDamaged, read only by the debug drawing» (`damagehst.lua`).
- `133689a252` «STAI TargetHST, DamageHST: no more use of Tool» (`tool.lua`, `toolbox.lua`, `targethst.lua`, `damagehst.lua`, `targethst_spec.lua` nuovo).
- Un commit per l'indice (`codice-tolto.md`, sezioni S12a) e questi risultati.

**1. `CENTER`, `ownImmobile`**: `ownImmobile` in `BuildingsHST:Init`; in testa a `BuildingsHST:UnitCreated` (stesso controllo `teamId == self.ai.id` e `UnitDefs[...].speed == 0`) e a `UnitDead`, poi `getCenter` (copiata com'era dopo S11). `LosHST:UnitCreated` tolta (restava vuota). `CommanderBST:Init`: `self.ai.buildingshst.CENTER = { x = …, y = …, z = … } --a copy: getCenter writes in CENTER`. Lettori `attackhst.lua` r. 327 e `raidhst.lua` r. 398 su `self.ai.buildingshst.CENTER`. Il punto «BASE» di `LosHST:Draw` è passato in `BuildingsHST:VisualDBG` (nessuna delle due è chiamata da nessuno). Test «keeps the center on a copy of the commander position without buildings, on their mean with them» (`buildingshst_spec.lua`): `BuildingsHST` vero e `CommanderBST:Init` vero (con `UnitMexMoveTest` finta); `CENTER` ≠ `commander.position` ma con gli stessi valori, `getCenter` senza edifici non tocca né la tabella né i valori, con due edifici la media, e `commander.position` resta com'era. Il test vecchio di `loshst_spec.lua` è tolto.

**2. `needAntiAir`**: `self.needAntiAir = false` in `LosHST:Init` (commento a fine riga), `setPosLayer2` scrive `self.needAntiAir = true` (tolto il `TODO need to move from here`); lettori su `self.ai.loshst.needAntiAir`. `false` al posto di `nil` non cambia niente: i lettori fanno solo `if check` e `not …`.

**3. `friendlyTeamID`**: via da `LosHST:Init`; `DamageHST:UnitDamaged` → `if teamID ~= self.ai.id then`. Il `game` globale è quello dell'oggetto (`ShardAI:Prepare` lo imposta prima di ogni chiamata), e `game:GetTeamID()` restituisce `self.ai.id`: stesso effetto. Nello spec di `DamageHST` il finto `game.GetTeamID` diventa `ai.id`.

**4. `isDamaged`**: grep in `luarules/` e `spec/`: solo `damagehst.lua`. Tolti il campo, la `local defenderID` (serviva solo a lui), `UpdateDamagedUnits` con la sua chiamata, `DamageHST:UnitDead` (restava vuota), la parte di `VisualDBG`. `UpdateDamagedUnits` leggeva solo la salute: niente effetti sul gioco.

**5. `TargetHST` senza `Tool`**

- `Toolbox.COLOURS` (la tabella com'era; commento di testa di `toolbox.lua`: «math and table helpers, and the debug colours»); `Tool.COLOURS = Toolbox.COLOURS --the same table`. Il ciclo di `tool.lua` che avvolge i metodi di `Toolbox` ora avvolge solo le funzioni (`type(func) == "function"`), altrimenti avrebbe fatto di `COLOURS` una funzione. `targethst.lua` e `damagehst.lua` leggono `Toolbox.COLOURS`.
- `local TablePool = shard_include("tablepool")` in testa a `targethst.lua`, `self.blobPool = TablePool.New()` in `Init`, `Get` al posto di `RezTable`. `TargetHST:releaseBlobs(blobs)` rende le `cellCoord`, `cells`, `position`, `units`, `targetCell` e il blob, e toglie la chiave. `MOBILE_BLOBS`/`IMMOBILE_BLOBS` restano le stesse tabelle, come prima: anche `ResetTable` le rimetteva nella riserva e `RezTable` le riprendeva subito, buttando il risultato. Test «gives back to the pool the old blobs with the tables in them» (`targethst_spec.lua`): un blob di due celle, poi un giro senza celle. Risultato: blob vuoti, `freeCount == 7`, le 7 tabelle tutte nella riserva e vuote.
- Tolto anche il blocco commentato di `DamageHST:Update` con `game:GetTeamID()` (codice morto; nell'indice).
- Grep nei tre file dopo i commit: nessun `self.ai.tool`, `game:GetTeamID()` o `self.ai.<campo> =`. Resta **un** `self.ai.id`: `damagehst.lua` r. 22, voluto dal punto 3. Gli altri `self.ai.*` sono `gridhst`, `armyhst` (globali), `loshst`, `perceptionhandler` (ally), `allyId`, `drawDebug`.
- `self.ai.drawDebug` **c'è** su `ShardAlly`: `ShardAlly` eredita `ShardAI:Init`, che chiama `self.game:DrawDisplay(false)`, e lì `game.ai` è lo `ShardAlly`. Nel repository nessuno chiama `DrawDisplay(true)`, quindi i disegni di debug non girano mai.

**6. Prova nella stessa partita** (partita C, `c_stai_vs_stai.txt`, 15 minuti, `Echo` non committati, codice tolto con `git checkout`). Accanto al codice nuovo girava quello della base:

- **blob**: `GetBlobs`/`Blobbing` della base, alla lettera (`Tool:RezTable`/`ResetTable`), su `REF_MOBILE_BLOBS`/`REF_IMMOBILE_BLOBS`, confrontati per `blobref` a ogni `Update`: chiavi, `metal`, `position`, `targetCell`, celle in ordine, insiemi di `units`;
- **`CENTER`**: `ownImmobile`, `UnitCreated`, `UnitDead`, `getCenter` della base in `LosHST`, e `CommanderBST:Init` che scrive anche `self.ai.loshst.CENTER = self.position` come prima. Confronto dopo ogni `getCenter` della base (gira dopo quella di `BuildingsHST` nello stesso evento: `LosHST` viene dopo nell'elenco dei moduli) e anche a ogni `Update` di `TargetHST`.

| | partita 1, squadra 0 / 1 | partita 2 (diagnosi), squadra 0 / 1 |
| --- | --- | --- |
| `Update` confrontati | 1501 / 1501 | 1501 / 1501 |
| blob confrontati (max per giro) | 7948 (16) / 3983 (14) | 2614 (9) / 4270 (11) |
| blob diversi | **14 / 63** | **4 / 7** |
| blob mancanti o in più | 0 | 0 |
| `getCenter` confrontate / diverse | 393 / 0 · 400 / 0 | 390 / 0 · 355 / 0 |
| `CENTER` diverso a un `Update` | **1027 / 1362** | **1320 / 1357** |

**Differenza A, `CENTER` (vera, cambia il gioco)**. `ShardUnit:GetPosition` (`shard_runtime/spring_lua/unit.lua` r. 461) tiene una sola tabella per unità (`self.position`) e la riscrive a ogni chiamata. Nella base, quindi:

- `CENTER` era la tabella di posizione del comandante, e chiunque chiede la posizione del comandante la riscrive: `CommanderBST:Update` r. 25 (finché non c'è il laboratorio T2 e il comandante è sano) e il codice che lo usa come costruttore;
- finché il comandante vive, `CENTER` segue la sua posizione viva; `getCenter` (a ogni `UnitCreated`/`UnitDead`) ci scrive la media degli edifici, ma solo fino alla `GetPosition` successiva sul comandante;
- quando il comandante muore nessuno riscrive più la tabella, e `CENTER` resta la media degli edifici;
- in più `getCenter` sporcava la posizione del comandante per chi teneva quella tabella fra due chiamate.

Con la copia del punto 1 `CENTER` è la media degli edifici, sempre. Per questo il confronto a ogni `getCenter` dà 0 (in quel momento entrambi hanno la media) e quello a ogni `Update` dà diverso quasi sempre. Il test di S11 e quello di questo compito descrivono «posizione del comandante finché non ci sono edifici», che non era il comportamento vero.

**Differenza B, `metal` dei blob (arrotondamento, c'era già)**. Seconda partita con una diagnosi a ogni differenza; tutte le 11 sono così:

- solo `metal` diverso, nelle ultime cifre (es. 863,733398 contro 863,733337: precisione dei numeri Lua dell'engine);
- posizione, `targetCell`, celle e unità uguali; sommando le celle in ordine numerico i due valori sono uguali;
- in ogni caso **uno** dei due lati scorre `blob.cells` con `pairs` in un ordine non numerico, perché la tabella riciclata ha già una parte hash e `table.insert` ci mette le chiavi in ordine sparso: 8 volte il lato nuovo, **3 volte la base**.

Il ciclo di riempimento di `GetBlobs` (`for i, v in pairs(blob.cells)`) somma quindi in un ordine che dipende da quale tabella torna dalla riserva. Prima era la riserva di `Tool`, condivisa con `AttackHST`, `RaidHST` e `BomberHST`; ora è quella dei blob.

**Domande**

1. `CENTER`: (a) tenere il comportamento della base: `CommanderBST:Init` scrive `self.ai.buildingshst.CENTER = self.position` (la tabella viva), e il test cambia (copia no, stessa tabella); il gioco non cambia. (b) Tenere la copia: `CENTER` è sempre la media degli edifici (o la posizione iniziale del comandante senza edifici), ed è un cambio di gioco da misurare. (c) Rendere esplicito il comportamento vero, per esempio `CENTER` = posizione del comandante finché vive, media degli edifici dopo. Senza (a) il gioco cambia: per questo non ho fatto la partita A.
2. Blob: proposta, ciclo numerico in `GetBlobs` (`for n = 1, #blob.cells do`, come gli altri cicli «numeric loop keeps the order»). Così la somma non dipende più dalla riserva; rispetto alla base cambierebbe solo il `metal` nelle ultime cifre dei casi in cui la base sommava in ordine sparso. In alternativa si accetta la differenza come arrotondamento.

**Controlli**

- `lx --lua-version 5.1 test`: 2773 successi, 0 falliti, 1 pending (2772 − 1 test di `getCenter` tolto da `loshst_spec` + 1 di `BuildingsHST` + 1 di `TargetHST`). Sulla base `451be31e89` (codice di STAI della base, spec nuovi): errori in `buildingshst_spec` (manca `getCenter` di `BuildingsHST`), `targethst_spec` (manca `blobPool`) e nei due test di `damagehst_spec` (lo spec non ha più il finto `game.GetTeamID`). `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 su tutti i file toccati: ok.
- EmmyLua 0.24.0, confronto con un worktree della base: errori 19 → 19. Per file (avvisi / hint, base → finale): `targethst.lua` 63/9 → 43/9; `damagehst.lua` 8/6 → 4/5; `buildingshst.lua` 26/37 → 26/35; `raidhst.lua` 5/24 → **6**/24 (`Undefined field ENEMY` su `loshst.ENEMY` r. 400, lo stesso che c'era a r. 424: la `local loshst` ha perso l'uso di `CENTER` da cui il controllore ricavava il tipo); `tool.lua` 1/15 → **2**/15 (`assign-type-mismatch` r. 20: il controllore pensa che `Tool[name]` possa essere `COLOURS`); gli altri uguali; spec nuovi senza diagnostiche.
- `.emmyrc.json` ripristinato; `git status` pulito a parte `.ai-notes/`.

**Da sapere**

- La riserva di `Tool` (`Tool._TABLES` è un campo della classe, quindi condivisa da tutte le AI STAI del client) non riceve più le tabelle dei blob: `AttackHST`, `RaidHST`, `BomberHST` avranno più spesso tabelle nuove da `RezTable`. I valori non cambiano; l'ordine di `pairs` su quelle tabelle può cambiare, come in B.
- `TargetHST:drawDBG` legge `cell.POS` sulle `cellCoord` dei blob, che hanno solo `X` e `Z`: se `drawDebug` fosse vero darebbe errore. C'era già; non l'ho toccato.
- Le due partite C hanno girato con il codice di confronto, che usa la riserva di `Tool` anche per i blob della base: non valgono come partite di misura.

### S11 (agente locale, 25 novembre 2026) — verificato dal coordinatore. Il `git commit -a` del punto 4 senza la skill `submodule-pointer` è controllato (solo `loshst.lua`): la prossima volta passare dalla skill

**In breve**: i quattro difetti corretti (un commit ciascuno, un test per i punti 1–3, ogni test nuovo fallisce sul codice di base) e il codice morto tolto in un commit, con l'indice aggiornato. Le tre partite A, con il codice finale, stanno tutte dentro i riferimenti di S1 e vicino a S8b; nessun errore del loader.

**Commit**

- `b3dd879373` «STAI LosHST: clear the factory of an ENEMY cell when the cell is cleared» (`loshst.lua`, `loshst_spec.lua`).
- `bdb27d2c82` «STAI LosHST: keep CENTER where it is when there are no own buildings, instead of dividing by zero» (`loshst.lua`, `loshst_spec.lua`).
- `7a180ee4ab` «STAI DamageHST: give the attacker its own defId in the los, and accept an attacker out of unitTable» (`damagehst.lua`, `damagehst_spec.lua` nuovo).
- `821b9ecae7` «STAI LosHST: make the draw positions of LosHST:Draw local» (`loshst.lua`).
- `c59c12a597` «STAI AttackHST, TargetHST: remove SquadAttackbackup, the commented SquadAttack, NearbyVulnerable and GetPathModifierFunc» (`attackhst.lua`, `targethst.lua`).
- Un commit per l'indice e questi risultati.

**1. `CELL.base`**: in `resetCell`, dopo `unitsCount`, `CELL.base = nil --the name of the last factory seen in this round`. Test «forgets the factory of a cell when the cell is cleared and used again» (nel finto `unitTable` un tipo `factory` con `isFactory`): fabbrica → `base == "factory"`; `resetCell` (quello che fa `ENEMY:Clear` sulle celle della lista), poi un edificio → `BUILDINGS` 100 e `base` nil. Codice di base: fallisce.

**2. `getCenter`**: somme in `x, y, z` locali; con `count == 0` `return` senza toccare `CENTER`; con `count > 0` `self.CENTER = self.CENTER or {}` e i tre campi come prima. Commento a fine riga sulla funzione. Test «keeps the center where it is without own buildings, and puts it in their mean position with them»: `CENTER` = una tabella del comandante, `ownImmobile` vuoto → stessa tabella e stessi valori; due edifici (100, 300) e (300, 500) → `{ x = 200, y = 0, z = 400 }`. Codice di base: fallisce (NaN).

**3. `DamageHST:UnitDamaged`**: `attackerThreat = attackerut and attackerut.metalCost or damage or 100` (commento a fine riga), così il resto non cambia; r. 41 `attackerut.defId`. Test nuovi in `damagehst_spec.lua` (stesso schema di `loshst_spec.lua`, `AddBadPosition` finta che registra gli argomenti): «puts a building that hits our unit in the los with the type of the building» (`losEnemy[30] == 22`, tolto da `radarEnemy`, `AddBadPosition` con minaccia 300/50 e durata 900); «counts an attacker out of unitTable as its damage» (nessun errore, `losEnemy` vuota, `AddBadPosition` con minaccia 40 = `damage`). Codice di base: 1 fallito e 1 errore.

**4. `LosHST:Draw`**: `local` per `posG`, `posS`, `posB`, `posA`. Grep: nessun altro uso in `luarules/gadgets/ai/`. EmmyLua: `loshst.lua` da 10 a 3 avvisi (resta un hint: `posB` mai usata, c'era già).

**5. Codice morto**: grep in `luarules/` e `spec/` su `SquadAttackbackup`, `NearbyVulnerable`, `GetPathModifierFunc`, `pathModifierFuncs`, `pathModParam`: solo le definizioni e i due campi di `Init`. Tolti, con la vecchia `SquadAttack` commentata in fondo a `attackhst.lua` (115 righe in tutto). Indice in `codice-tolto.md` (sezione S11).

**Tre partite A** (`a_stai_vs_simpleai.txt`, `SHARD_MEM_STATS=1`, 15 minuti, codice finale `c59c12a597`, uscita 0, 19–23 s)

| | partita 1 | partita 2 | partita 3 | S10 (tre partite) | S9 | S1 (intervallo) |
| --- | --- | --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6 / 36 / 104 / 146 | 5 / 37 / 103 / 179 | 5 / 33 / 100 / 160 | 6/36/83/124 · 5/39/97/154 · 6/40/92/114 | 6 / 38 / 84 / 142 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14): unità, fabbriche, mex | 172, 2, 27 | 203, 2, 31 | 168, 2, 34 | 145/175/132, 1/2/2, 19/32/28 | 161, 2, 32 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 196, 2, 30 | 230, 2, 36 | 177, 2, 38 | 173/203/153, 1/2/2, 20/34/30 | 169, 2, 34 | — |
| relay: messaggi / ordini / rifiutati | 2724 / 12797 / 9 | 3460 / 16921 / 1 | 3691 / 13962 / 10 | 2733–4005 / 10860–15659 / 6–35 | 2912 / 11906 / 7 | 3405–3933 / 10445–15948 / 9–16 |
| memoria per frame: media per minuto, picco | 0,18–0,59 KB, 68,6 KB | 0,18–0,57 KB, 50,4 KB | 0,18–0,57 KB, 92,9 KB | 0,18–0,76 KB, fino a 35 KB | — | picchi 68–74 KB |
| heap | 12,9–14,7 MB | 12,9–15,1 MB | 12,9–14,8 MB | 12,8–15,3 | 13,0–14,9 | 13,1–15,5 |
| righe `[AI Loader] error` | 0 | 0 | 0 | 0 | 0 | 0 |

- Nessuna partita sotto i riferimenti. Le unità al minuto 10 (100–104) e la partita 2 al minuto 13–14 (179, 203) stanno appena sopra l'intervallo di S1, come S8b; con il seme che cambia a ogni avvio non lo attribuisco alle correzioni.
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown).

**Controlli**

- `lx --lua-version 5.1 test`: 2772 successi, 0 falliti, 1 pending (2768 + 2 di `LosHST` + 2 di `DamageHST`). `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 su tutti i file toccati: ok.
- EmmyLua 0.24.0, confronto con un worktree della base `46e2f73cc1`: errori 19 → 19. Per file (base → finale, avvisi / hint): `loshst.lua` 10 / 17 → 3 / 18; `damagehst.lua` 7 / 6 → **8** / 6; `attackhst.lua` 7 / 24 → 7 / 23; `targethst.lua` 63 / 15 → 63 / 9; `damagehst_spec.lua` senza diagnostiche. L'avviso in più di `damagehst.lua` è `Undefined field defId` su `attackerut`, lo stesso tipo dei due che c'erano già (`metalCost`, `isBuilding` sullo stesso `attackerut`: `unitTable` non ha tipo).
- `.emmyrc.json` ripristinato; `git status` pulito a parte `.ai-notes/`.

**Da sapere**

- Punto 3: il `defId` scritto in `losEnemy` oggi non cambia niente di quello che `LosHST` scrive nelle celle (`setCellLos` usa `unit:Name()`), e `UnitLeftLos` usa il `unitDefID` dell'engine, non questo valore: ora è giusto per chi lo leggerà come tipo.
- Il commit del punto 4 l'ho fatto con `git commit -a` senza passare dalla skill `submodule-pointer`: ho controllato, contiene solo `loshst.lua`.

### S10 (agente locale, 25 novembre 2026) — verificato dal coordinatore. Il gioco non cambia su Comet Catcher (nessun lettore di `unarm*` fuori da `LosHST`, 0 spot senza cella, `SimplifyMetalSpots` non entra): le partite 1 e 3 sotto S1 sono varianza del seme

**In breve**: i cinque difetti corretti, un commit e un test per ciascuno (il punto 5 è una riga tolta, senza test); ogni test nuovo fallisce sul codice di base. **Il gioco non cambia su Comet Catcher, nemmeno per il punto 1**: fuori da `LosHST` nessuno legge `unarm*`, `A`/`S`/`G` o `*_balance` (solo `LosHST:Draw`, con `drawDebug`). Delle tre partite A, **la 1 va sotto S1** (19 mex e 1 fabbrica al minuto 14) e **la 3 va sotto S1 per unità ai minuti 13–14** e ha 35 ordini rifiutati: non ho tentato correzioni; visto che il codice gioca come in S9, lo attribuisco al seme, ma decide l'utente.

**Commit**

- `11e6b95039` «STAI LosHST: add up the unarmed immobile units of a cell instead of copying the mobile ones» (`loshst.lua`, `loshst_spec.lua`).
- `34e9bda055` «STAI MapHST: skip only the metal or geo spot without a cell, not the rest of the scan» (`maphst.lua`, `maphst_spec.lua`).
- `082004516b` «STAI MapHST: simplify the metal spots up to the Z size of the map» (`maphst.lua`, `maphst_spec.lua`).
- `de54d3bc9a` «STAI GridHST: tell the bad raw position with its own x and z in the debug» (`gridhst.lua`, `gridhst_spec.lua`).
- `5bb29fbb13` «STAI ArmyHST: remove the unused UWMetalSpotCheckUnit» (`armyhst.lua`).
- Un commit per l'indice e questi risultati.

**1. `LosHST`, immobile disarmato** (`setCellRadar` r. 313–315, `setCellLos` r. 401, 403, 405)

- **Chi legge i campi** (grep su `unarm`, `armed[AGS]`, `_balance`, `.A`/`.S`/`.G`, e sui campi passati a `getCellsFields`/`sumCellsFields` e a `TargetHST:Blobbing`): solo `LosHST` stesso. `unarmA/S/G` → `A`, `S`, `G`, `*_balance` dentro `setCellLos`/`setCellRadar`; `A`, `S`, `G` letti solo da `LosHST:Draw` (esce subito senza `drawDebug`). I lettori fuori: `getCellsFields` con `ARMED`, `UNARM`, `ENEMY` (`commanderbst.lua`, `targethst.lua`, `nukebst.lua`); `Blobbing` con `SPEED`, `IMMOBILE`. Nessuno di questi cambia. Quindi, contrariamente al compito, **il gioco non cambia**.
- Corretti tutti e sei i punti (`AI`, `SI`, `GI` in tutte e due le funzioni).
- Test (`loshst_spec.lua`; `newLosHST` ha in più `game:Frame`, `Spring.GetUnitVelocity` finto e `armyhst.unitTable`; `getEnemyCell` e `setPosLayer2` sostituiti sull'istanza): «adds up the unarmed buildings of a cell in los, layer G/A/S» (tre test: due edifici da 100 → `unarm?I` 200, `unarm?M` 0; con un mobile da 50 prima → 200 e 50); «adds up the immobile units of a cell on radar, on every layer» (due immobili da 30 → 60 su `G`, `A`, `S`; con un mobile prima → 60 e 30).
- Mutazioni: codice di base 4 falliti su 10; una sola riga riportata alla base (r. 313, 315, 401, 403, 405) → 1 fallito ciascuna.

**2. `metalScan` / `geoScan`**: `if not index then EchoDebug(...) --skip only this spot else ... end`. Test: «skips only the metal spot out of the map, and puts the ones after it in their cells and networks» e lo stesso per i geo (spot fuori in mezzo a due spot; celle, rete `ground` con tutte e due le celle, rete `air` con una). Codice di base: 2 falliti su 3.

**3. `SimplifyMetalSpots`**: `z` fino a `elmoMapSizeZ`; commento a fine riga sul `table.remove` («safe inside pairs: break right after»). Test «simplifies the metal spots over the whole of a map that is not square»: mappa 1024 × 2048, 1000 spot sul bordo (mai presi) più uno al centro di ciascuno dei 32 quadrati da 256; tornano 32 spot, 16 con `z` oltre 1024. Codice di base: fallisce (ne tornano 16).

**4. `RawPosIsInMap`**: `x .. ", " .. z`. Test «tells a raw position out of the map in the debug, and gives it back when in the map» (griglia propria con `DebugEnabled`, `SendToConsole` che registra le righe): riga «bad position: 1537, 100» e `nil`; dentro la mappa restituisce `x, y, z`. Codice di base: errore (`pos` nil).

**5. `UWMetalSpotCheckUnit`**: grep in tutto il repository (fuori da `.ai-notes/`, `.lux/`, `.git/`): solo la riga tolta. Tolta col commento sopra; nell'indice `codice-tolto.md` (sezione S10).

**Il codice di S10 gioca come S9 su Comet Catcher**: misura con una patch temporanea (`[S10-CHECK]`, non committata) in `metalScan`: 80 metal spot, 0 geo, **0 spot senza cella**; con 80 spot `SimplifyMetalSpots` esce subito (≤ 1024); il punto 4 è solo debug, il 5 una costante non letta.

**Tre partite A** (`a_stai_vs_simpleai.txt`, `SHARD_MEM_STATS=1`, 15 minuti, codice finale `5bb29fbb13`, uscita 0, 18–21 s)

| | partita 1 | partita 2 | partita 3 | S9 | S8b (tre partite) | S1 (intervallo) |
| --- | --- | --- | --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6 / 36 / 83 / 124 | 5 / 39 / 97 / 154 | 6 / 40 / 92 / **114** | 6 / 38 / 84 / 142 | 5/38/108/152 · 5/38/86/149 · 6/37/101/171 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14): unità, fabbriche, mex | 145, **1**, **19** | 175, 2, 32 | **132**, 2, 28 | 161, 2, 32 | 168/166/198, 2, 33/29/39 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 173, 1, 20 | 203, 2, 34 | 153, 2, 30 | 169, 2, 34 | 190/197/212, 2, 34/34/43 | — |
| relay: messaggi / ordini / rifiutati | 4005 / 15659 / 6 | 3598 / 15423 / 7 | 2733 / 10860 / **35** | 2912 / 11906 / 7 | 3301–3891 / 13383–19508 / 8–16 | 3405–3933 / 10445–15948 / 9–16 |
| heap | 12,9–15,3 MB | 12,8–14,6 MB | 12,9–14,6 MB | 13,0–14,9 | 12,9–15,1 | 13,1–15,5 |
| righe `[AI Loader] error` | 0 | 0 | 0 | 0 | 0 | 0 |

- **Sotto i riferimenti**: partita 1, mex al minuto 14 (19 contro 23–35 di S1) e una fabbrica sola per tutta la partita; partita 3, unità al minuto 13 (114 contro 117) e 14 (132 contro 141), 35 ordini rifiutati (S1 9–16). Non ho tentato correzioni. Per quanto sopra il codice gioca come S9, quindi lo leggo come varianza del seme, ma non l'ho provato con una prova nella stessa partita.
- La memoria per frame non l'ho riportata in medie: lo script nuovo la stampa per minuto (`avg 0.18–0.76 KB`, picco per minuto fino a 35 KB nella partita 1), in linea con le partite di prima.
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown).

**Controlli**

- `lx --lua-version 5.1 test`: 2768 successi, 0 falliti, 1 pending (2760 + 4 di `LosHST` + 3 di `MapHST` + 1 di `GridHST`). `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 (dalla radice) su tutti i file toccati: ok.
- EmmyLua 0.24.0, confronto con un worktree della base `663698e4d6`: errori 19 → 19. Per file (base → finale): `loshst.lua` 10 avvisi / 17 hint → uguale; `maphst.lua` 11 / 15 → uguale; `gridhst.lua` 0 / 9 → uguale; `armyhst.lua` 40 / 17 → 39 / 17; i tre spec senza diagnostiche. I totali degli avvisi dei due alberi differiscono di centinaia (23405 / 23059) per file che non ho toccato, come nelle volte prima.
- `.emmyrc.json` ripristinato; `git status` pulito a parte `.ai-notes/`.

**Da sapere**

- Il compito dava il punto 1 come l'unico che cambia il gioco: non lo cambia (sopra). Diventa visibile solo se un modulo legge `unarm*`, `A`/`S`/`G` o i `*_balance`.

### S9 (agente locale, 25 novembre 2026) — verificato dal coordinatore. `POS` di `DAMAGED` da `GridToPos` accettato (previsto dal compito); uscita sulle celle fuori griglia accettata (0 casi)

**In breve**: `GridLayer:Unmark(i)` c'è, con test e mutazioni; `DAMAGED` è uno strato di `DamageHST`, `SCOUTED` uno strato di `ScoutHST` scritto solo dal padrone (`ScoutHST:Scouted(X, Z)`); via `areaGridCells` e `getGridCellsFields`. **Prova nella stessa partita: 0 differenze** in tutta la partita C, per tutti e due gli strati, cella per cella, con lo stesso numero di celle e le stesse somme di `defenderThreat` a ogni `Update`. **`POS` di `DAMAGED` resta da `GridToPos`**: con il `POS` della cella di `GridHST` la prova ha trovato una cella con `y` diverso (terreno deformato dopo `Init`). La partita A non sta sotto i riferimenti.

**Commit**

- `d23cc49eff` «STAI GridHST: take one cell out of a layer, keeping the order of the list»: `GridLayer:Unmark` e i test.
- `f03fb8edf0` «STAI DamageHST: keep the damaged cells in a DAMAGED layer of GridHST»: `DamageHST`, i lettori (`targethst.lua`, `scouthst.lua` r. 79), via le due sorelle di `GridHST` e il loro test.
- `1432104f6c` «STAI ScoutHST: keep the scouted cells in a SCOUTED layer of GridHST»: `ScoutHST`, `ScoutBST`.
- Un commit per l'indice e questi risultati.

**1. `GridLayer:Unmark(i)`** (`gridhst.lua`)

- Su una cella non segnata esce subito. Se no: ricerca di `i` in `LIST` con un ciclo numerico e `table.remove` (commento «LIST is short»), `marked[i] = nil`, `resetCell` sulla cella se c'è la funzione e la cella; la tabella resta in `CELLS`.
- Chi scorre la lista e intanto chiama `Unmark`: **ciclo numerico all'indietro** (`for n = #LIST, 1, -1 do --backward: Unmark takes the cell out of LIST`), in `DamageHST:UpdateBadPositions` e in `ScoutHST:Update`. `table.remove` sposta solo le celle dopo `n`, già viste. Mi è sembrato più leggibile di raccogliere e poi togliere.
- Test (`gridhst_spec.lua`): «takes one cell out of the list keeping the order of the others, and resets it» (ordine, stessa tabella `LIST`, `GetMarked` nil, `resetCell` chiamata una volta sulla cella giusta, le altre intatte); «does nothing on a cell that is not in the list» (cella con dati ma non segnata, e cella mai fatta); «marks a cell again after it was taken out, at the end of the list» (stessa tabella); «takes cells out while a backward loop runs over the list» (vede tutte le celle una volta, restano le dispari in ordine).
- Mutazioni, ognuna fa fallire almeno un test: `gridhst.lua` della base (4 in errore); `table.remove` sostituito con «l'ultima al posto della tolta» (2); senza `table.remove` (3); `marked` non tolto (2); senza `resetCell` (1); senza l'uscita sulle celle non segnate (1).

**2. `DAMAGED`** (`damagehst.lua`)

- `Init`: `self.DAMAGED = self.ai.gridhst:NewLayer(self.resetCell)`. `DamageHST.resetCell(CELL)` azzera `frame`, `attackerThreat`, `defenderThreat`, `duration` (funzione con il punto, come `LosHST.resetCell`).
- `AddBadPosition`: `PosToGrid`, `IsCellInGrid` (fuori: `Warn` «damage out of the grid» e uscita), indice, `Get`. Cella non segnata: si scrivono i campi del vecchio `newRecord` (`X`, `Z`, `POS`, `nodeCostIndex = i`, `frame`, minacce, `duration`); segnata: `frame` e somme come prima. Poi `Mark`. Via `groundAirSubmerged` (globale mai definito); il parametro `mtype` resta (non usato, come prima).
- **`POS`**: il compito chiedeva `POS` da `gridhst.CELLS[i].POS`, scritto una volta. Nella prima prova (sotto) l'unica differenza è stata `POS.y`: cella 15, 10 del team 1, 237,12 (altezza a `Init`) contro 237,44 (`GridToPos` al primo colpo), 204 confronti su 1501 `Update`. Il terreno cambia in partita (crateri), quindi **ho lasciato `GridToPos`**, chiamato quando la cella entra nella lista, come faceva `newRecord`; commento a fine riga («not the POS of the GridHST cell: the ground can change after Init»). Lo legge solo `VisualDBG` (disegno). Con questo `X`, `Z`, `nodeCostIndex` li scrivo anch'essi all'entrata (sono sempre gli stessi numeri), così l'entrata è il vecchio `newRecord` campo per campo e non serve una `getDamagedCell`.
- `UpdateBadPositions`: ciclo all'indietro sulla lista, `Unmark(i)` dove prima `DAMAGED[X][Z] = nil`; `EchoDebug(cell.defenderThreat)`.
- Lettori: `targethst.lua` r. 170 `getGridCellsFields` → `getCellsFields` (da sapere: `GetPathModifierFunc` non la chiama nessuno, grep in tutto `luarules/`); `scouthst.lua` r. 79 → `GetCell(X, Z, self.ai.damagehst.DAMAGED)`; `VisualDBG` → ciclo numerico sulla lista (corpo uguale).
- `GridHST`: via `areaGridCells`, `getGridCellsFields` e il loro test.

**3. `SCOUTED`** (`scouthst.lua`, `scoutbst.lua`)

- `Init`: `self.SCOUTED = self.ai.gridhst:NewLayer()`; la cella tiene `frame`.
- `ScoutHST:Scouted(X, Z)` (scelto `X, Z`: `ScoutBST` li calcola già e li usa nel suo `EchoDebug`): `IsCellInGrid` (fuori: uscita, senza avviso), indice, `Get(i).frame = game:Frame()`, `Mark`. `ScoutBST:Update` chiama solo quello.
- `ScoutHST:Update`: ciclo all'indietro, `Unmark` delle celle con `frame > CELLS[i].frame + 3600`. `TargetAvailable` r. 75 → `GetCell(X, Z, self.SCOUTED)`.

**Differenza possibile, mai vista**: una posizione con `x` o `z` uguale a 0 dà `X` o `Z` 0. Prima `DAMAGED` e `SCOUTED` scrivevano lo stesso una cella fuori griglia (e `GridToPos` avvisava «is not in map»); ora `AddBadPosition` e `Scouted` escono. Nella partita C: 0 casi su 3267 colpi e 4047 passaggi di esploratori.

**4. Prova nella stessa partita** (`[S9-PROOF]`, non committata; `c_stai_vs_stai.txt`, 15 minuti)

- `DamageHST`: `AddBadPosition` e `UpdateBadPositions` della base copiate (`shadowAdd`, `shadowUpdate`) su `shadowDAMAGED[X][Z]`, chiamate sugli stessi eventi; dopo ogni `Update` confronto: `marked` contato = `#LIST`; ogni cella della lista nella griglia vecchia con `frame`, `attackerThreat`, `defenderThreat`, `duration`, `nodeCostIndex`, `X`, `Z`, `POS.x`, `POS.y`, `POS.z` uguali; ogni cella della griglia vecchia segnata nello strato; stesso numero di celle; stessa somma di `defenderThreat` (strato in ordine di lista, griglia vecchia con `pairs`).
- `ScoutHST`: in `Scouted` anche `shadowSCOUTED[X][Z] = frame` (la riga della base); in `Update` la scadenza della base, poi lo stesso confronto (presenza nei due versi, `frame`, numero di celle). In più, a ogni `TargetAvailable`, le risposte vecchia e nuova per `SCOUTED` e per `DAMAGED`.

| codice | team | `Update` | celle confrontate | colpi (`AddBadPosition`) | uscite (`Unmark`) | celle insieme, max | somma di `defenderThreat` su tutti gli `Update` (strato = vecchia) | differenze |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `DAMAGED`, `POS` da `GridHST` (prima prova) | 0 / 1 | 1501 / 1501 | 27406 / 21402 | 1207 / 2329 | 21 / 6 | 57 / 60 | 19.630.884 / 34.802.016 | 0 / 0, più `POS.y` 0 / 204 |
| `DAMAGED`, codice finale | 0 / 1 | 1501 / 1501 | 26136 / 18442 | 1866 / 1401 | 17 / 9 | 50 / 46 | 22.815.968 / 19.390.070 | **0 / 0** (`POS.y` compreso) |

| codice finale | team | `Update` | celle confrontate | `Scouted` | uscite | celle insieme, max | risposte di `TargetAvailable` confrontate | differenze |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `SCOUTED` | 0 / 1 | 1501 / 1501 | 68751 / 75340 | 1688 / 2359 | 269 / 306 | 149 / 161 | 1824 / 2499 | **0 / 0** |

- La prova vede gli errori: con `defenderThreat < 2` al posto di `< 1` nel codice nuovo, 464 / 247 differenze (la prima al frame 15901: «cell only in shadow, 18, 8», celle 15 contro 16, somma 9128 contro 9129); con `+ 3000` al posto di `+ 3600` nella scadenza di `SCOUTED`, 12733 / 14483 differenze e 46 / 9 risposte di `TargetAvailable` diverse.
- Partita C del codice finale: relay 4370 messaggi, 28408 ordini, 48 rifiutati (S8b: 5204 / 29055 / 40); nessuna riga `[AI Loader] error`.
- Quindi gli strati contengono esattamente le griglie di prima; il gioco cambia solo per l'ordine (lista al posto di `pairs`), e qui l'ordine non conta: i lettori fanno somme di interi o domande sì/no.

**Partita A** (`a_stai_vs_simpleai.txt`, `SHARD_MEM_STATS=1`, 15 minuti, codice finale senza il `---@type` sotto, che non cambia il gioco; uscita 0, 20 s)

| | S9 | S8b (tre partite) | S1 (intervallo) |
| --- | --- | --- | --- |
| unità STAI min. 1 / 5 / 10 / 13 | 6 / 38 / 84 / 142 | 5/38/108/152 · 5/38/86/149 · 6/37/101/171 | 6 / 25–41 / 54–101 / 117–159 |
| fine partita (min. 14) | 161 unità, 2 fabbriche, 32 mex | 168/166/198, 2, 33/29/39 | 141–186, 2, 23–35 |
| `SUMMARY` (fine) | 169, 2, 34 | 190/197/212, 2, 34/34/43 | — |
| relay: messaggi / ordini / rifiutati | 2912 / 11906 / 7 | 3301–3891 / 13383–19508 / 8–16 | 3405–3933 / 10445–15948 / 9–16 |
| messaggi rifiutati | nessuno | nessuno | nessuno |
| memoria per frame, medie per minuto | 0,19–0,63 (media 0,38) | 0,37–0,40 di media | 0,37–0,45 |
| memoria per frame, picco | 73,0 KB (min. 13) | 64,2–127,8 | 67,9–73,5 |
| heap | 13,0–14,9 MB | 12,9–15,1 | 13,1–15,5 |
| righe `[AI Loader] error` | 0 | 0 | 0 |

- **Non sta sotto i riferimenti**: 161 unità e 32 mex al minuto 14, dentro S1; al minuto 13 142, dentro S1. Messaggi del relay (2912) e rifiutati (7) sotto S1 e S8b: una partita sola con il seme diverso, non lo attribuisco al cambio (la prova dice che gli strati sono uguali alle griglie).
- Errori nel log: solo quelli di sempre (`AdvSky`, `ceg_test_projectile`, atlas groundFX, `gui_pip` `CreateShader`, shader AoE Napalm/Reclaim Field, `gui_sensor_ranges_jammer_preview` in Shutdown). Nessuno cita Shard, STAI o i moduli toccati.

**Controlli**

- `lx --lua-version 5.1 test`: 2760 successi, 0 falliti, 1 pending (2757 + 4 di `Unmark` − 1 di `getGridCellsFields`). `run_engine_tests.sh`: `RESULT: ok`.
- StyLua 2.5.2 (dalla radice) su tutti i file toccati: ok.
- EmmyLua 0.24.0, confronto con un worktree della base `5f103a2c51`: errori 20 → **19** (tolto `undefined global groundAirSubmerged` in `damagehst.lua`). Per file (base → finale): `damagehst.lua` 1 errore / 7 avvisi / 8 hint → 0 / 7 / 6; `gridhst.lua` 0/0/9 → 0/0/9; `scouthst.lua` 0/0/5 → 0/0/5; `scoutbst.lua` 0/9/7 → 0/9/7; `targethst.lua` 0/63/15 → 0/63/15; `gridhst_spec.lua` senza diagnostiche. Da sapere: come in S8a per `LosHST`, il ciclo nuovo di `VisualDBG` faceva comparire 4 avvisi `cellElmosHalf value may be nil` (il ciclo su `[X][Z]` faceva saltare l'analisi); risolti con `---@type number` sulla riga di `cellElmosHalf`, dentro il commit di `DAMAGED` prima del push.
- `.emmyrc.json` ripristinato; `git status` pulito a parte i file di `.ai-notes/`.
- `codice-tolto.md`: sezione S9 (`groundAirSubmerged`, `newRecord`, le due sorelle di `GridHST` e il loro test, la riga commentata `-- cell = nil` di `ScoutHST:Update`).

**Difetti visti, non toccati**

- `TargetHST:GetPathModifierFunc` (e `pathModifierFuncs`) non la chiama nessuno: codice morto, oppure aspetta il servizio percorsi (rinviato).
- `DamageHST:AddBadPosition` riceve `mtype` e `duration` ma nessuno legge `duration` né distingue per `mtype`: la scadenza è sempre il calo del 10 % ogni 300 frame.

### S8b (agente locale, 25 novembre 2026) — verificato dal coordinatore

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


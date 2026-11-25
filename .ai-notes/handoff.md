# Handoff fra il coordinatore (claude.ai) e l'agente locale

## Protocollo

- Branch condiviso: `shard/fase1` su `pandaro/Beyond-All-Reason`. Il coordinatore scrive qui il compito; l'agente locale lo esegue e scrive qui i risultati.
- Quando l'utente scrive «vai»:
  1. `git pull` su `shard/fase1`;
  2. leggi «Compito attuale» ed eseguilo, rispettando `CLAUDE.local.md` e `.github/agents.md`;
  3. scrivi i risultati sotto «Risultati» (cosa hai fatto, file toccati, numeri, problemi, domande);
  4. commit e push su `shard/fase1`, poi fermati e di' all'utente «fatto».
- «vai» autorizza i commit e il push su `shard/fase1` previsti dal compito. Mai push su `master`, mai PR, mai force push.
- `.ai-notes/` è escluso da git sulla macchina locale: per questi file usa `git add -f` (`.ai-notes/handoff.md`, e altri file di `.ai-notes/` solo se il compito lo dice). Prima di `git add -A` o `git commit -a` segui la skill `submodule-pointer`.
- `.ai-notes/proposta-architettura.md` è l'export aggiornato della proposta: la aggiorna il coordinatore, non modificarla.
- Prima di una PR verso BAR, `.ai-notes/` va tolta dal branch.
- Tutto ciò che va nel repository è in inglese: messaggi di commit (anche «Handoff: …»), commenti, nomi, messaggi di log, test. Solo `.ai-notes/` resta in italiano.
- Test con l'engine vero: `.ai-notes/tools/run_engine_tests.sh`; il `PASS` del test runner di BAR non conta.
- Strumenti fissati: StyLua 2.5.2 ed EmmyLua 0.24.0 (`emmylua_check`) in `~/.local/bin` (release ufficiali su GitHub); `~/.local/bin` può non essere nel `PATH` della shell dell'agente: chiamali con il percorso intero. `lx` è in `/usr/local/bin`.

## Compito attuale

### T18: memoria nella riga `[Shard timer]`

**Impegno: basso.** Branch di lavoro: **`shardST1`** (unione di `shard/fase1` e `stai/porting`; push `git -c push.negotiate=true push origin shardST1`).

**Perché.** Un utente ha mandato questa riga da una partita lunga (74 minuti, heap 80 MB, picco per frame 4,9 MB): `module=UnitHandler behaviour=BuildersBST call=Update ms=1553.5`. Non si capisce se il secondo e mezzo è un calcolo pesante di STAI o il garbage collector che parte dentro quella chiamata.

**Lavoro**

1. In `loader/timers.lua`, in `BeginModule`/`BeginBehaviour` si legge la memoria in uso (`collectgarbage("count")`, KB) insieme al tempo, in `EndModule`/`EndBehaviour` di nuovo. Niente tabelle nuove nel percorso: le letture si tengono nelle stesse variabili locali del tempo.
2. La riga sopra soglia riceve un campo `kb=<fine - inizio>` (con segno, un decimale), subito dopo `ms=`: `... call=Update ms=1553.5 kb=-48210.3`. Un valore molto negativo = è passato il garbage collector durante la chiamata; positivo e grande = la chiamata alloca molto.
3. Il riepilogo a fine partita non cambia.
4. Guida («How to debug», `.ai-notes/drafts/README.md`): aggiorna il formato della riga e spiega in due righe come si legge `kb`.
5. Se la lettura di `collectgarbage("count")` rallenta in modo visibile, dillo e non toglierla.

**Test busted**: la riga contiene `kb=` con il segno giusto (memoria che scende e che sale; usa una `collectgarbage` finta); sotto soglia nessuna riga. Mutazione: `kb` con segno invertito, `kb` letto solo all'inizio.

**Partita**: una partita A di 15 minuti; riporta le righe `[Shard timer]` che compaiono (se ce ne sono) con il nuovo campo. Nessuna riga `[AI Loader] error`.

**Controlli**: StyLua 2.5.2, EmmyLua 0.24.0, `lx --lua-version 5.1 test`, `run_engine_tests.sh`.

**Commit**, in inglese: uno per il codice, uno per la guida.

## Risultati

### T17 (agente locale, 25 novembre 2026) — verificato dal coordinatore (`ShardTimers` è un globale del gadget: scostamento accettato, serve a `shardai.lua` e `unit.lua`)

**Commit**: `b204166b0a` (tempi), `f5745cb437` (`ShardMemStats` da codice), `202eddbf18` (guida e strumenti).

**1. Tempi** — `shard_runtime/loader/timers.lua`, unsynced, incluso da `ShardAILoader.lua` e reso visibile al runtime come globale del gadget `ShardTimers` (lo leggono `shardai.lua` e `unit.lua`; senza loader, come negli spec del runtime, le funzioni diventano vuote).
- In cima: `TIMERS_ON = true`, `SPIKE_MS = 10`.
- Quattro funzioni piccole: `BeginModule`/`EndModule` attorno a ogni chiamata a un modulo in `shardai.lua` (Init, Update, ScheduledUpdate, GameMessage e tutti i gestori degli eventi: 16 punti), `BeginBehaviour`/`EndBehaviour` attorno a ogni chiamata a un behaviour in `unit.lua` (Update nei due rami, PreActivate+Activate come `call=Activate`, Owner*/Unit* degli eventi, GameEnd). `delivery.lua` e `scheduler.lua` non toccati; le righe commentate (`game:StartTimer`, tracy) restano, e il codice dei timer di `game.lua` e del widget pure.
- Riga sopra soglia (strettamente > 10 ms), tutti i campi presenti:
  `[Shard timer] frame=5 ai=STAI team=0 ally=0 scope=team module=UnitHandler behaviour=BuildersBST call=Update ms=12.3`
  `team=-` per ally e global, `ally=-` per global, `behaviour=-` per i moduli. Il modulo di un behaviour è quello la cui chiamata è in corso quando il behaviour è chiamato (quello che tiene l'unità); `BeginModule` restituisce il modulo esterno e `EndModule` lo rimette, senza tabelle. Il tempo di un modulo include i behaviour che chiama: un behaviour lento dà due righe.
- Riepilogo a `GameOver`, o a `Shutdown` se la partita non è finita (una volta sola): `[Shard timer summary] names=N spike_ms=10`, poi per nome, somma più alta prima: `name= kind= calls= min= max= avg= sum= spikes=` (ms).
- **Risoluzione**: `Spring.DiffTimers(Spring.GetTimerMicros(), t0, true, true)` (quarto argomento `fromMicroSecs`), letti nel loader e non nell'ambiente dei moduli. In partita il riepilogo mostra `min=0.001`: risoluzione sotto il ms confermata. Il passo di `GetTimerMicros` cresce con l'uptime (memoria: 256 µs dopo 45 minuti), sempre sotto i decimi di ms richiesti fino a lì.
- Un errore dentro un modulo (preso da `xpcall` in `delivery.lua`) salta `EndModule`: quella chiamata non viene contata e il «modulo corrente» resta quello fino alla prossima `BeginModule`.

**3. `ShardMemStats`** — `memstats.lua`: `SHARD_MEM_STATS = true` in cima; tolti `Spring.GetConfigInt` e la rilettura ogni minuto. `SetMeasuring`/`SetEnabled` esistono solo per gli spec.

**Strumenti e guida**: `run_engine_game.sh` non usa più `SHARD_MEM_STATS` (toglie solo un eventuale `ShardMemStats` vecchio dallo springsettings temporaneo), stampa le righe `Shard timer summary` e il numero di righe `[Shard timer]`. `.ai-notes/drafts/README.md`: sezione «How to debug» (i due interruttori, la soglia, i due formati, un comando per i picchi più alti), voce 12 dell'indice.

**Test busted** (spec del loader unsynced, 7 nuovi in «with the timers»): riga sopra soglia con tutti i campi per behaviour e modulo; nessuna riga a 10 ms e sotto; ally e global con il loro scope; `call=UnitCreated`; riepilogo con conteggi, min, max, media, somma, spikes, scritto a GameOver e una volta sola; spento → nessuna lettura del timer e nessuna riga; acceso dalla costante. Memstats: i test usano lo switch al posto di springsettings; «riprende a misurare dopo /set» sostituito da «misura con springsettings vuoto: lo switch è nel codice». Gli spec sovrascrivono gli switch (`world.timers`, `world.memStats`; `"code"` lascia il valore del file).
Mutazioni, ognuna rilevata: `TIMERS_ON = false`, `<` al posto di `<=` sulla soglia, `SetEnabled` ignorato, riepilogo scritto più volte, modulo corrente non registrato, `spikes` non contato, `max` sbagliato, `SHARD_MEM_STATS = false`, tolta la misura di UnitCreated in `shardai.lua`, tolta quella di Update in `unit.lua` (3 falliti), tolto il riepilogo da GameOver (1 fallito dopo aver rafforzato il test: prima `Shutdown` lo copriva).

**Partita A** (STAI contro SimpleAI, 15 minuti, `run_engine_game.sh`; uscita 0 in 21 s): STAI 122 unità, 2 fabbriche, 15 mex; SimpleAI 85/1/11. Relay 3268 messaggi, 10255 ordini, 9 rifiutati. Nessuna riga `[AI Loader] error`. Memoria per frame: media 0,4-0,6 KB, massimo 35,7 KB; picco heap 15374 KB.
- Righe `[Shard timer]`: **2**, tutte e due a `Init` (frame 0), nessuna durante il gioco:

| frame | modulo | call | ms |
|---|---|---|---|
| 0 | ArmyHST | Init | 20,6 |
| 0 | MapHST | Init | 18,2 |

- Riepilogo (29 nomi; i primi per somma, ms):

| nome | tipo | chiamate | max | media | somma |
|---|---|---|---|---|---|
| UnitHandler | modulo | 31672 | 4,1 | 0,050 | 1583,4 |
| LabsHST | modulo | 27032 | 0,3 | 0,011 | 307,9 |
| ScoutBST | behaviour | 302838 | 0,9 | 0,000 | 130,2 |
| EcoHST | modulo | 27032 | 0,7 | 0,004 | 117,7 |
| AttackHST | modulo | 27032 | 0,3 | 0,004 | 102,8 |
| TargetHST | modulo | 27032 | 0,1 | 0,004 | 100,1 |
| BuildersBST | behaviour | 145254 | 1,6 | 0,001 | 84,1 |
| BootBST | behaviour | 587629 | 0,1 | 0,000 | 83,5 |
| RaidHST | modulo | 27032 | 0,1 | 0,003 | 70,7 |
| LosHST | modulo | 32294 | 0,2 | 0,002 | 69,4 |

  Il massimo di una chiamata durante il gioco è 4,1 ms (UnitHandler, che include i behaviour delle unità).
- Lettura: in headless, con una sola STAI e questo STAI di `shard/fase1`, nessuna chiamata supera 10 ms dopo l'avvio. I picchi gravi che l'utente vede vanno cercati in una partita vera con lo stesso codice (le righe e il riepilogo ci sono già): se lì non compaiono righe, i picchi non stanno dentro moduli o behaviour (garbage collector, engine, widget). Nota: `TaskQueueBST` dell'esempio del compito non esiste in questo STAI.

**Controlli**: `lx --lua-version 5.1 test` 2735 successi, 0 falliti, 1 pending di sempre. StyLua 2.5.2 pulito sui file toccati. EmmyLua 0.24.0: 20 errori, gli stessi; `timers.lua` e `memstats.lua` 0 diagnostiche, warning di `unit.lua` da 9 a 6. `run_engine_tests.sh`: `RESULT: ok`. `.emmyrc.json` ripristinato.

### T16 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Commit**: `05f3c46453` (`maxInstances` per partita), `a816f926b9` (20 ordini per messaggio). Dopo il rebase: `39382534`, `cee1aca2`.

**1. `maxInstances` per partita**

- File nuovo `shard_runtime/loader/admission.lua`, puro (nessuna chiamata `Spring.*`), includibile dal synced: `Admission.MAX_INSTANCES_PER_AI_TYPE = 2` (unico posto da cambiare) e `Admission.Admitted(aiTeams, maxInstances?)` → `teamID -> true`. Ordina per ID i team di `aiTeams` (la stessa tabella da cui `SetupAI` legge il tipo, costruita da `Spring.GetTeamLuaAI` identica su tutti i client) e ammette i primi N di ogni tipo. Il synced non serve: l'input è lo stesso ovunque e non cambia durante la partita, quindi nessun messaggio né rules param.
- `types.lua`: tolta la costante locale; `Setup` calcola `admitted` una volta; `AtInstanceLimit` guarda solo `admitted[id]`. Il cambio di host passa da `LoadAI` → stessa tabella, quindi chi è escluso resta escluso e chi è ammesso resta ammesso. Riga di log: `[AI Loader] AI team 2 not started: 2 SpecAI AIs already in this game, the most one AI type may have`.
- `relay.lua`: `Setup(hostOf, admitted)`; in `CheckHeader`, dopo il controllo `sender`, un team non ammesso dà `Reject("excluded")` (compare nella riga di chiusura come gli altri motivi). `ShardAILoader.lua` synced: `Relay.Setup(Hosts.HostOf, Admission.Admitted(aiTeams))`.
- Il registro degli host non cambia: anche un team escluso riceve `aiHostPlayer`, ma non parte e i suoi messaggi sono rifiutati.

**Test** (nuovi): unsynced — conta la partita e non il client (client che ospita solo il team 2: non parte); ammessi i primi per ID anche con tipi misti (team 0 PercAI, 1-3 SpecAI → 1 e 2 sì, 3 no); escluso resta escluso quando l'host arriva qui; ammesso resta ammesso quando arriva qui (team 0 arriva su un client che ha già 1; con la vecchia regola il client faceva girare 1 e 2 e rifiutava lo 0). Synced — il relay rifiuta il team 2 escluso anche dal suo host (`excluded = 1`); tipi diversi contano separati anche nel relay.
Mutazioni: codice vecchio → 4 falliti; relay senza controllo → 1; senza ordinamento → 6; un conteggio unico per tutti i tipi → 2. Il test «escluso resta escluso» passa anche col codice vecchio (lì il client aveva già 2 AI): lo tengo perché fissa il requisito 2.

**2. 20 ordini per messaggio**: `MAX_ORDERS_PER_MESSAGE = 20`. Test aggiornati: 21 ordini → 20 + 1; gruppo di 6 dopo 15 → 15 poi 7; gruppo di 21 da solo; relay accetta 20 e rifiuta 21 (`count`); '2-1' dopo 19 ordini va nel messaggio dopo. Con la costante a 10 falliscono 4 test.

**Controlli**: `lx --lua-version 5.1 test` 2728 successi, 0 falliti, 1 pending di sempre. StyLua 2.5.2 pulito sui file toccati. EmmyLua 0.24.0: 20 errori, gli stessi; `admission.lua`, `relay.lua`, `types.lua` 0 diagnostiche. `run_engine_tests.sh`: `RESULT: ok`. `.emmyrc.json` ripristinato. Nessuna partita (il codice di gioco è cambiato come previsto).

### T15 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Commit**: `45b8a1529f` (collect d'avvio), `00e5c38bae` (10 ordini per messaggio), `bcb1cd83be` (tablepool).

**1. `collect` d'avvio**

- Vecchia, `AILoader.lua` r. 276, in `gadget:Initialize` dopo il catch-up, senza condizione: `collectgarbage('collect')`.
- Nuova, `loader/lifecycle.lua` `CatchUpAfterReload`, dopo l'`if spGetGameFrame() > 0`, quindi senza condizione come la vecchia: `-- clean start, as in the old loader` / `collectgarbage("collect")`. Gira solo sui client che ospitano AI (`Initialize` esce prima negli altri), come la vecchia nel suo ramo.
- Test: una sola `collect` in `Initialize` dopo un reload, chiamata quando le AI sono già partite. Il test della rete di sicurezza «solo su frame divisibili per 121» ora svuota il log dopo l'avvio (contava anche questa).

**2. Ordini per messaggio**

- Costante unica `MAX_ORDERS_PER_MESSAGE = 10` in `shard_runtime/ordercodec.lua`, nella tabella `OrderCodec`. Motivo: è già il file del formato incluso da entrambi i lati (outbox unsynced e relay synced), puro e includibile dal synced; nessun file nuovo, nessun `GG`/globale. `outbox.lua` e `relay.lua` fanno `local MAX_ORDERS_PER_MESSAGE = OrderCodec.MAX_ORDERS_PER_MESSAGE`. Il relay prima accettava fino a 4000.
- **Regola tenuta**: un gruppo (gli ordini di una chiamata `GiveOrder` '2-1' o '1-2') non si spezza. Con più di 10 ordini va da solo in un messaggio, e il relay lo **rifiuta intero** (`count`): per esempio un ordine '1-2' a 11+ unità, o una coda di 11+ comandi a una unità, si perde tutto. Prima succedeva solo oltre 4000. Nella partita sotto i rifiutati sono 10 (T14: 13), ma il conteggio per motivo non esce nella riga di chiusura: non so quanti siano `count`. Da decidere: spezzare i gruppi grandi o scartarli nell'outbox con un `Warn`.
- Test: 11 ordini → due messaggi (10 + 1); gruppo di 6 dopo 5 ordini → 5 poi 7; gruppo di 11 inviato da solo; il relay accetta 10 e rifiuta 11 (`count`). Senza la modifica: 5 falliti + 1 errore.

**3. `tablepool`**

- `shard_runtime/tablepool.lua`: `TablePool.New()`, `pool:Get()` (una tabella vuota, riusata o nuova), `pool:Release(t)` (svuota con `pairs` e la tiene). Niente limiti né misure. Commento in testa: conviene con centinaia di tabelle brevi per frame, non per poche o per tabelle che vivono a lungo.
- Accesso: `local TablePool = shard_include("tablepool")`. Motivo: la `shard_include` di ogni AI cerca già in `shard_runtime/` dopo la cartella dell'AI, quindi funziona da moduli e behaviour senza toccare il boot né aggiungere globali; con l'ambiente per tipo il file gira una volta per tipo di AI.
- Test: tabella vuota, riuso svuotato (array e hash), ogni tabella data una volta sola, nessuna allocazione dopo il riscaldamento (`collectgarbage("count")` uguale su 5000 Get/Release). Mutazioni: Get sempre nuova → 3 falliti; Release senza svuotare → 1 fallito. Nessun modulo lo usa.

**Controlli**: `lx --lua-version 5.1 test` 2722 successi, 0 falliti, 1 pending di sempre. StyLua 2.5.2 pulito sui file toccati. EmmyLua 0.24.0: 20 errori, gli stessi; `tablepool.lua` 0 diagnostiche (aggiunto `---@class TablePool`), gli altri file toccati come prima; il totale dei warning nel resto dell'albero oscilla fra due esecuzioni sullo stesso codice. `run_engine_tests.sh`: `RESULT: ok`. `.emmyrc.json` ripristinato.

**Partita A** (STAI contro SimpleAI, `SHARD_MEM_STATS=1`, 15 minuti, uscita 0; nessuna riga `[AI Loader] error`, solo gli errori di sempre)

| | T15 | T14 |
| --- | --- | --- |
| unità STAI min. 1/5/10/13 | 6 / 36 / 74 / 123 | 6 / 31 / 90 / 134 |
| a fine partita (min. 14) | 145 unità, 2 fabbriche, 25 mex | 185, 2, 28 |
| relay: messaggi | **4071** | 2658 |
| relay: ordini dati | 15062 | 15057 |
| relay: ordini rifiutati | 10 | 13 |
| ordini per messaggio, media | 3,7 | 5,7 |
| memoria per frame, medie | 0,18–0,55 KB | 0,18–0,70 KB |
| memoria per frame, massimo | 74 KB (min. 13) | 159 KB (min. 11) |
| heap | 13,1–14,9 MB | |

Lettura: stessi ordini, +53 % di messaggi (i picchi oltre 10 ora vanno sui frame dopo). Unità a fine partita più basse, ma è una partita sola: le differenze di gioco sono nel rumore fra due partite, non ho modo di attribuirle al limite.

### T1 (agente locale, 23 novembre 2026) — verificato dal coordinatore: 95 file identici a `3ad8f3fb^`, nessun file fuori posto

**Fatto**

1. `CLAUDE.local.md` locale: fase «fase 1, runtime», riga che rimanda a questo protocollo. Non committato.
2. Commit 1 `5799277142` «Recupero di Shard e STAI com'erano a 3ad8f3fb^»: 95 file, 19.059 righe, identici a `3ad8f3fb^`.

   | Percorso | File | Righe |
   | --- | --- | --- |
   | `luarules/gadgets/ai/shard_runtime/` | 31 | 4.247 |
   | `luarules/gadgets/ai/STAI/` | 43 | 11.700 |
   | `luarules/gadgets/ai/Shard/` | 18 | 1.850 |
   | `luaui/Widgets/shard_help_draw.lua` | 1 | 1.164 |
   | `common/stai_factory_rect.lua` | 1 | 50 |
   | `luaui/Tests/ai_stai_factory_rect.lua` | 1 | 48 |

   File chiesti che a `3ad8f3fb^` non esistono: nessuno. Non recuperati, come chiesto: `luarules/gadgets/AILoader.lua`, `luaai.lua`.
3. Commit 2 `44c70d3557` «Shard: tolti backend nativo, hooks e scansione dei metal spot»: 9 file, 2 righe aggiunte e 713 tolte.
   - Tolti `shard_runtime/spring_cpp/` (5 file), `shard_runtime/hooks.lua` e `shard_runtime/spring_lua/metal.lua`.
   - `spring_lua/boot.lua`: tolto `"hooks"` da `runtime_includes`.
   - `spring_lua/map.lua`: `map.metalSpots = {}` con un commento che rimanda ai game rules param di BAR (`api_resource_spot_finder`: `mex_count`, `mex_x<i>`…). Ho lasciato una tabella vuota invece di niente perché `map:SpotCount()` e `map:GetSpot()` la leggono; da rivedere quando si collegano i game rules param.
4. Verifica: partita headless (`tools/headless_testing/startscript.txt`, engine 2026.07.04, cartella dati separata per non toccare il gioco aperto), confrontata con la stessa partita sul commit `a3676418d8` prima di T1.
   - Il gioco si avvia e si chiude da solo, codice d'uscita 0, nessun crash.
   - Unico errore nuovo che cita STAI: `[Test Runner] ERROR: ai_stai_factory_rect.lua | LuaUI/Tests/ai_stai_factory_rect.lua did not return a test table { skip, setup, test, cleanup }` (2 volte). Il file recuperato definisce funzioni globali e non restituisce nulla; il test runner di oggi vuole `return { test = … }`, come `luaui/Tests/selftests/test_assertions.lua`. Esce solo nelle partite di test, non in una partita normale.
   - Nessun errore che citi `shard`. `shard_help_draw.lua` ha `enabled = false` e non viene caricato; le cartelle sotto `luarules/gadgets/ai/` non vengono caricate dal gestore dei gadget.
   - Gli altri errori (`setfenv: cannot change this environment` ×16, `gui_pip` `CreateShader`, `gui_sensor_ranges_jammer_preview`, groundFX atlas) c'erano già prima di T1.

**Problemi e domande**

- `luaui/Tests/ai_stai_factory_rect.lua`: lo adeguo al formato del test runner (`return { test = test }`) o lo tolgo finché non serve? Ora genera l'errore sopra in ogni partita di test.
- Riferimenti rimasti a file tolti, non chiesti dal compito e quindi non toccati:
  - `shard_runtime/api.lua` righe 26-27 e `STAI/boot.lua`, `Shard/boot.lua` riga 6: `spring_cpp/...` nel ramo `elseif game_engine` (solo AI native, ora morto);
  - `shard_runtime/shard_null/boot.lua` riga 11: `require "shard_runtime/hooks"`.
- `CLAUDE.local.md` dice ancora che il codice rimosso «non va ripristinato» e «non committare `.ai-notes/`»: contraddicono T1 e questo protocollo. Al primo tentativo il recupero è stato bloccato dal sistema di permessi; è passato quando l'utente ha ridato «vai».
- La copia locale della vecchia proposta (fase 0) è in `.ai-notes/proposta-architettura.fase0-locale.md`, ignorata da git.

### T1b (agente locale, 23 novembre 2026) — verificato dal coordinatore

1. Commit `11c678127f`: `luaui/Tests/ai_stai_factory_rect.lua`, aggiunto `return { test = test }` in fondo (+2 righe, verifiche invariate). Partita headless come in T1: `PASS: ai_stai_factory_rect.lua` (2 volte), l'errore `did not return a test table` non c'è più, codice d'uscita 0, nessun errore che citi `shard` o `STAI`.
2. Commit `c54881ed25`: tolti i rami `elseif game_engine` con `spring_cpp` da `shard_runtime/api.lua` (−4 righe), `STAI/boot.lua` e `Shard/boot.lua` (−2 righe ciascuno), e `require "shard_runtime/hooks"` da `shard_runtime/shard_null/boot.lua` (−1). Nessun riferimento a `spring_cpp` o `hooks` rimasto sotto `luarules/gadgets/ai/`. Rimangono in `STAI/boot.lua` e `Shard/boot.lua` i secondi rami `elseif game_engine` (`ai = STAI()` e simili), che non citano file tolti: non toccati.
3. `CLAUDE.local.md` locale aggiornato come chiesto (contesto, `.ai-notes/` tracciati, impegno). Non committato.

### T2 (agente locale, 23 novembre 2026) — verificato dal coordinatore

**Commit**

- `a6331fda33` «Shard: include per tipo di AI, con ambiente e cache» (punti 2 e 3): `shard_runtime/spring_lua/boot.lua` +30 −2; spec nuova `spec/luarules/gadgets/ai/shard_runtime/spring_lua/boot_spec.lua`, 152 righe.
- `1fe993dddb` «Shard e STAI: tolti i rami game_engine da boot.lua» (punto 4): `STAI/boot.lua` −2, `Shard/boot.lua` −2. Restano `if ShardSpringLua … return` e il ramo `else` di `shard_null`.

**Cosa fa `shard_generate_include_func(runtime_path, ai_path, env)`**

- Senza `env`: stesse righe di prima (`return VFS.Include(file)`, nessuna cache).
- Con `env`: una cache per funzione generata, chiave `string.lower` del percorso del candidato trovato; `VFS.Include(file, env)` solo alla prima richiesta. Un risultato `nil` si memorizza come sentinella `CACHED_NIL` (tabella locale del file); `false` si memorizza così com'è. File inesistente: stessi messaggi di prima, niente in cache. Un file che va in errore non entra in cache: l'errore risale e la richiesta successiva lo riesegue.
- La logica della cache sta in una funzione locale `cachedInclude`, sopra il commento `---` della funzione pubblica, che ha la riga `@param env`.

**Test** (busted, vedi la nota sugli strumenti sotto)

- Spec da sola: 6 successi.
- Suite completa: `2550 successes / 0 failures / 0 errors / 1 pending`, uguale anche con `SPEC_ORDER=reverse`. Prima del compito: 2544 / 0 / 0 / 1 (il pending è `spec/gamedata/def_invariants_spec.lua:321`, già presente).
- Contro il `boot.lua` di prima del compito: falliscono i primi 5 casi (classi separate e fuori dall'ambiente globale, file incluso due volte, maiuscole diverse, `nil`/`false`, file del runtime una volta per tipo). Il sesto («senza ambiente, rieseguito a ogni include nell'ambiente del chiamante») passa con entrambe le versioni: fissa il comportamento che il compito chiede di non cambiare.

**Controlli**

- StyLua 2.5.2: la spec è pulita. Nei sorgenti nessuna riga scritta da me cade in una differenza di StyLua; le differenze più vicine sono righe vecchie accanto (`return function( file )`, righe 46-47). I file recuperati non sono formattati con StyLua: rispetto a `master`, in una PR verso BAR, il controllo di formato li segnalerebbe per intero.
- EmmyLua 0.24.0: 25 errori prima e dopo, nessuno nei file toccati. Warning nei file toccati: `STAI/boot.lua` e `Shard/boot.lua` da 5 a 4, `spring_lua/boot.lua` 0, spec 0. Il totale dei warning cambia di qualche decina fra due esecuzioni sullo stesso albero (in file estranei come `common/constants.lua`), quindi non lo uso come confronto.
- Headless come in T1: codice d'uscita 0, nessun errore nuovo rispetto al commit prima di T1, `PASS: ai_stai_factory_rect.lua`. Nota: la partita non esegue `spring_lua/boot.lua`, perché nessun loader lo include ancora; la prova del comportamento è solo la spec.

**Dubbi**

- Posizione della spec: `spec/luarules/gadgets/ai/shard_runtime/spring_lua/boot_spec.lua`, cioè dentro la cartella chiesta ma rispecchiando il sorgente (`spring_lua/boot.lua`). Se la vuoi direttamente in `shard_runtime/`, è uno spostamento.
- Formato della spec: `loadfile` + `setfenv` con un ambiente costruito a mano, come `spec/luarules/gadgets/api_game_pause_spec.lua`, non `spec/support/spec_env.lua`: serve un VFS finto che conti le esecuzioni, ignori le maiuscole e non cada mai sui file veri. La spec è circa 5 volte il codice che copre (152 contro 30 righe): ogni caso ha bisogno della sua coppia di file finti, e `.github/spec-instructions.md` chiede una frase che lo giustifichi in una PR.
- Firma: la chiave di cache è il percorso del candidato trovato, quindi `"foo"` della cartella dell'AI e `"foo"` del runtime sono due voci diverse, ed è giusto così. Un file che include sé stesso, direttamente o tramite altri, mentre gira non è ancora in cache e si riesegue come prima: nessuna protezione dai cicli, non chiesta.
- Restano riferimenti a `game_engine` in `shard_runtime/shard_null/map.lua:65` (codice vivo nel ramo `shard_null`) e in commenti di `shard_null/game.lua` e `spring_lua/game.lua`: non toccati (punto 5).
- `CLAUDE.local.md` locale: decisione 1 aggiornata con `Scope()` obbligatorio. Non committato.

**Strumenti**

- `lx --lua-version 5.1 test` su questa macchina non parte: l'interprete Lua che lux compila non esporta i simboli `lua_*`, e penlight si ferma su `pl.path requires LuaFileSystem` (`lfs.so: undefined symbol: lua_gettop`). Ho eseguito lo stesso busted di `.lux/` con un Lua 5.1.5 compilato nello scratchpad con `-Wl,-E` (sorgente ufficiale, sha256 `2640fc56…5333`) e gli stessi percorsi delle dipendenze. Il CI, che usa il suo lx, non dovrebbe esserne toccato.
- `lx` riscrive anche `.emmyrc.json` (percorsi `lib/` delle dipendenze compilate): l'ho riportato com'era, non è nei commit.

### T2b (agente locale, 23 novembre 2026) — verificato dal coordinatore

**Commit**

- `9918a93bbf` «gen(stylua): formattazione di Shard e STAI recuperati»: 79 file, +5310 −4459.
- `30d88b9246`: hash aggiunto a `.git-blame-ignore-revs`, stesso formato delle righe esistenti.

**File**

- 87 file `.lua` nei percorsi del compito; StyLua 2.5.2 (`--respect-ignores`, `.stylua.toml`) ne ha cambiati 79, gli altri 8 erano già formattati. Nessuno escluso.
- Fine riga: tutti CRLF. `shard_runtime/spring_lua/unit.lua` era LF nel blob; ora è CRLF come gli altri.

**Confronto del bytecode**

- `luac5.1 -s -o` prima/dopo: **identico solo per 28 file su 87**. Gli altri differiscono anche senza modifiche di codice, perché `-s` toglie le righe delle istruzioni ma non `linedefined`/`lastlinedefined` nell'intestazione di ogni funzione: basta che StyLua sposti una funzione di una riga (es. `class.lua`, funzione 3–45 → 3–47) e il file binario cambia.
- Confronto usato al suo posto: `luac5.1 -l -l -p` (istruzioni, costanti, locali, upvalue di ogni funzione), tolti solo indirizzi di memoria, intervalli di righe delle funzioni e colonna `[riga]`. **87 file su 87 identici.** Quindi nemmeno `sort_requires` ha riordinato nulla (`shard_null/boot.lua` incluso).

**Test**

- `lx --lua-version 5.1 test` (lux e Lua 5.1 di sistema): `2550 successes / 0 failures / 0 errors / 1 pending`, come T2. `lx` ha riscritto `.emmyrc.json`: rimesso com'era, non nei commit.
- Headless come in T2: codice d'uscita 0, insieme delle righe d'errore identico a T2, `PASS: ai_stai_factory_rect.lua` (2 volte).

### T3 (agente locale, 23 novembre 2026) — verificato dal coordinatore

**Commit**

1. `04e219c0f3` «Shard e STAI: Scope() "team" in tutti i moduli»: 26 file, +4 righe ciascuno (`Scope()` subito dopo `internalName()`), nient'altro.
2. `b28f1d888c` «Shard: ambiti team, ally e global nel caricamento dei moduli»:

   | File | + | − |
   | --- | --- | --- |
   | `shard_runtime/shardai.lua` | 92 | 25 |
   | `shard_runtime/module.lua` | 18 | 2 |
   | `shard_runtime/aibase.lua` | 15 | 3 |
   | `shard_runtime/shardally.lua` (nuovo) | 22 | 0 |
   | `shard_runtime/shardglobal.lua` (nuovo) | 20 | 0 |
   | `shard_runtime/spring_lua/boot.lua` | 2 | 0 |
   | `spec/luarules/gadgets/ai/shard_runtime/shardai_spec.lua` (nuovo) | 259 | 0 |

**Cosa fa**

- `Module:Scope()` restituisce `"error"`, con il commento `---` nello stile di `internalName()`.
- `ShardAI:Scope()` `"team"`; `ShardAI:Init` passa ogni classe di `modules.lua` a un nuovo `ShardAI:LoadModule(moduleClass)`, che legge `Name()`, `Scope()` e `internalName()` sulla classe, prima di creare l'istanza:
  - `Scope()` mancante (la classe non ha il metodo) o fuori dai tre valori: `Warn` con nome e valori validi, una volta per classe (tabella locale a chiavi deboli `warnedScopes`), modulo non caricato;
  - ambito più stretto del contenitore: saltato senza avvisi;
  - poi i controlli di prima su `internalName` `"error"` e sui duplicati, con gli stessi messaggi;
  - ambito più largo: `self[internalName]` = l'istanza tenuta da `self.ally` (per `"ally"`) o `self.global` (per `"global"`), solo se sta nei suoi `modules`; altrimenti `Warn` «no ally/global object holds it». Non entra in `self.modules`;
  - stesso ambito: istanza, `Info` «adding», `self[internalName]`, `self.modules`, `SetAI`, come prima; `newmodule` è `local`.
- `Init` include `behaviourfactory` e `unit` solo se `self:Scope() == "team"`.
- `AddModule`: se `Scope()` del modulo differisce da quello del contenitore, `Warn` e niente.
- Callback invariati: scorrono solo `self.modules`.
- `ShardAlly = class(ShardAI)` e `ShardGlobal = class(ShardAI)`, con `Name()` `"ShardAlly"`/`"ShardGlobal"`, `internalName()` `"shardally"`/`"shardglobal"`, `Scope()`, e il commento `---` sui campi impostati dal loader. Aggiunti a `runtime_includes` di `spring_lua/boot.lua` dopo `"shardai"`.

**Punto 4: dove e perché**

Un metodo `AIBase:ConsoleOwner()`: guarda l'ambito di `self.ai or self` (il contenitore per moduli e behaviour, l'oggetto stesso per un contenitore) e restituisce `"ally <allyId>"`, `"global"` o, per un team, `self.game:GetTeamID()` come prima. Le cinque chiamate `SendToConsole(self.game:GetTeamID(), …)` di `AIBase:Warn/Info/EchoDebug` e `Module:Warn/EchoDebug` passano a `self:ConsoleOwner()`. È il punto più piccolo che copre tutto: `AIBase` è la base di `Module`, `ShardAI` (e quindi di `ShardAlly`/`ShardGlobal`) e `Behaviour`. Non ho toccato `game:GetTeamID()` perché i moduli usano il suo valore per decidere (unità mie, scheduler): lì un ambito al posto di un team sarebbe un errore silenzioso, mentre `nil` resta il valore onesto. Nota: oggi `Spring.Echo(nil, …)` non va in errore; senza la modifica la riga diceva `nil`.

**Test**

- Spec nuova, 9 casi: Scope mancante e sconosciuto (un solo `Warn` per classe con 2 ally e 3 team); istanze condivise e separate; raggiungibilità dei tre ambiti verso l'alto e non verso il basso; `Init` una volta per modulo condiviso e un `Update` a ogni modulo una volta; `behaviourfactory`/`unit` solo per i team; `AddModule` di un modulo d'altro ambito; senza `ally`/`global` (due casi); `Warn` da moduli `"ally"`, `"global"` e `"team"` con il proprietario giusto.
- Contro `shardai.lua`/`module.lua`/`aibase.lua`/`boot.lua` di prima (con i due file nuovi presenti): 8 falliscono; passa solo «loads and runs team modules as before», che fissa il comportamento da non cambiare.
- `lx --lua-version 5.1 test`: `2559 successes / 0 failures / 0 errors / 1 pending` (T2b: 2550). `.emmyrc.json` riscritto da `lx`, rimesso com'era.

**Controlli**

- StyLua pulito su tutti i file toccati e sulle righe aggiunte del commit 1. Su `STAI/taskshst.lua` `--check` segnala due tabelle che non ho toccato: StyLua non è idempotente su quel file (le riformatta al secondo passaggio). Fuori dalle righe del commit, quindi fuori dal gate.
- EmmyLua, confrontato con un'esecuzione sullo stato di prima: nei file toccati stessi conteggi (`shardai.lua` 27 warning, `aibase.lua` 1 errore `fname` nel blocco `tracy` e 4 warning, già presenti); nessun warning nei file nuovi. Per la spec ho aggiunto `need-check-nil, inject-field` alla riga `---@diagnostic disable` (accessi a tabelle costruite nel test); in `shardai.lua` un `---@type table<string, integer>` su `SCOPE_RANKS` toglie un falso «impossible if». Totale del repository: 23 errori ora, 25 nell'esecuzione di base; il conteggio oscilla fra esecuzioni come già visto in T2.
- Headless come in T2: codice d'uscita 0, righe d'errore identiche a T2, `PASS: ai_stai_factory_rect.lua` ×2.

**Scostamenti dal compito**

- I moduli di STAI con `class(Module)` sono 20, non 21: `STAI/overviewhst.lua` è tutto commentato. Non toccato.
- `shard_null/boot.lua` non carica `shardai` (richiede solo `class`, `aibase`, `module`): il ramo `shard_null` oggi non ha `ShardAI` e `STAI/boot.lua` vi fallirebbe su `class(ShardAI)`. Non ho aggiunto `shardally`/`shardglobal` lì: senza `shardai` diventerebbero `class(nil)`. Se serve, il compito è aggiungere tutti e tre.
- `Init` salta anche `unit`, non solo `behaviourfactory`, per gli ambiti condivisi: `unit.lua` è la `ShardUnit` con i behaviour.
- `Name()` di `ShardAlly`/`ShardGlobal` sono `"ShardAlly"`/`"ShardGlobal"`, non `"Shard"`: compaiono nelle righe di console accanto al proprietario e distinguono l'oggetto. Se «come in ShardAI» voleva dire lo stesso valore, è una riga per file.

**Dubbi**

- Difetto trovato, non corretto: `shard_runtime/behaviour.lua` riga 7 definisce `function Module:internalName() return "unknown behaviour" end` (dovrebbe essere `Behaviour:`). Poiché `Init` include `behaviourfactory` prima di `modules`, ogni classe di modulo creata dopo eredita `"unknown behaviour"`: il controllo su `internalName` `"error"` non scatta mai, e lo stesso varrebbe per un default di `Scope()` se fosse definito lì. Correzione di una parola; la lascio a un compito.
- `ShardAI:UnitCreated` avvisa «No modules found in AI» se `self.modules` è vuoto: un `ShardAlly` o `ShardGlobal` senza moduli propri lo direbbe a ogni unità, se il loader gli passa gli eventi. Da decidere con la consegna mirata.
- `warnedScopes` è per classe: con l'ambiente per tipo (T2) la classe è una sola per tutte le AI del tipo. Senza ambiente (include rieseguito) ogni contenitore ha classi nuove e l'avviso uscirebbe una volta per contenitore.
- Un modulo condiviso è cercato in `self.ally`/`self.global` solo se quel contenitore ha già fatto `Init`: l'ordine globale → ally → team della bozza del loader è quindi necessario, non solo comodo.

### T3b (agente locale, 23 novembre 2026) — verificato dal coordinatore

**Commit**

1. `9b5a27a61e` «Shard: internalName() di Behaviour, non di Module»: `shard_runtime/behaviour.lua` +1 −1 (riga 7); `shardai_spec.lua` +32 −4: `loadRuntime(extraFiles)` accetta file del runtime in più, e un `describe("behaviour.lua")` con due casi: `Module:internalName()` resta `"error"` dopo `behaviour.lua`; un modulo creato dopo, senza `internalName()`, non si carica (`team.modules` vuoto) e produce una volta «The module with the name noname module has no internal name!». Con la riga vecchia falliscono tutti e due (`9 successes / 2 failures`); con la nuova `11 successes`.
2. `273148b918` «Shard: shard_null carica shardai, shardally e shardglobal»: `shard_runtime/shard_null/boot.lua` +3, tre `require("shard_runtime/…")` subito dopo `module`, nell'ordine `shardai`, `shardally`, `shardglobal`. StyLua (`sort_requires`) non li riordina.

**Punto 2: cosa serve a `shardai.lua`**

Niente in più: al caricamento usa solo `class`, `AIBase` e `setmetatable` (`Spring.Echo` solo se esiste `tracy`). Provato con `lua5.1` da `luarules/gadgets/ai/`: `require("shard_runtime/shard_null/boot")` definisce `ShardAI`, `ShardAlly`, `ShardGlobal` (`Scope()` `"ally"`, `"global"`). Il ramo resta comunque non avviabile così com'è, per un motivo che non tocca questo compito: `require("STAI/boot")` si ferma prima, su `shard_include("ai")` (riga 6 di `shard_null/boot.lua` usa `require(file)`, che cerca `ai.lua` su `package.path`, non nella cartella dell'AI). Non l'ho cambiato.

**Controlli**

- StyLua pulito sui tre file toccati.
- `lx --lua-version 5.1 test`: `2561 successes / 0 failures / 0 errors / 1 pending` (T3: 2559). `.emmyrc.json` rimesso com'era.
- Headless come in T3: codice d'uscita 0, righe d'errore identiche a T3, `PASS: ai_stai_factory_rect.lua` ×2.

### T4 (agente locale, 23 novembre 2026) — verificato dal coordinatore

**Commit** (messaggi in inglese, su richiesta dell'utente)

1. `66cdb93a7f` «Shard: binary order encoding and per-AI outbox»: `shard_runtime/ordercodec.lua` (nuovo, 118 righe), `shard_runtime/spring_lua/outbox.lua` (nuovo, 296), `spring_lua/boot.lua` +1 (`"spring_lua/outbox"` in `runtime_includes`), `spec/luarules/gadgets/ai/shard_runtime/ordercodec_spec.lua` (nuovo, 499).
2. `adda135d9e` «Shard and STAI: GiveOrder and SyncOrder go through the outbox»: `spring_lua/game.lua` +77 −6, `spring_lua/unit.lua` +2 −2, `STAI/tool.lua` +1 −2, spec +85 −1 (i casi di `game:GiveOrder`, che con il `game.lua` di prima falliscono: 7 errori su 20).
3. `5f31cd0ccd` «Shard: headless test of the order encoding with the engine VFS»: `luaui/Tests/shard/test_ordercodec.lua` (nuovo, 67).

**`ordercodec.lua`**: restituisce una tabella (`VFS.Include` dal synced in T5) con le costanti (`MAGIC`, `VERSION`, `HEADER_SIZE`, `ORDER_FIXED_SIZE`, `PARAM_SIZE`, `MAX_PARAMS`), `IsOrderMessage`, `PackHeader`, `PackOrder`, `UnpackHeader` (versione, team, seq, frame, count, posizione del primo ordine; `nil` sotto i 16 byte), `UnpackOrder` (unità, comando, opzioni, n, posizione dei parametri, posizione dell'ordine dopo; `nil` se l'ordine o i suoi parametri escono dal messaggio). Versione+team e opzioni+n si leggono come U16. Nessuna tabella creata, nessuna chiamata unsynced. I parametri li legge chi chiama, come nella bozza (`VFS.UnpackF32(msg, pos, n)`).

**`outbox.lua`**: `ShardOutbox(teamID)` con array paralleli riusati (unità, comando, opzioni, n, gruppo) e una tabella di parametri per posizione della coda, riusata. `Queue` valida e accoda; `BeginGroup`/`EndGroup` tengono insieme gli ordini di una chiamata (se uno è scartato, cade tutto il gruppo); `Flush(frame, send)` prende i gruppi interi dalla testa finché stanno in 25 ordini (`MAX_ORDERS_PER_MESSAGE`; un gruppo più grande parte da solo), costruisce il messaggio con un buffer riusato e `table.concat`, sposta in testa il resto scambiando le tabelle dei parametri, poi chiama `send`. `Reset` svuota e riparte da seq 1. Le uniche tabelle nuove sono quelle dei parametri quando la coda cresce oltre il massimo raggiunto.
- `params`: `nil`, numero, array (≤ 255, altrimenti `Warn` e scartato) o tabella posizione `{x, y, z}`, appiattita in `x, y, z` più `[1]` se c'è, come faceva `Tool:TableToString` (STAI passa posizioni così in decine di punti, es. `scoutbst.lua:106`, `ShardUnit:Patrol`). Posizione senza `y`: scartato, come l'avviso «incomplete position» di STAI.
- `options`: maschera U8, oppure array di nomi (`"shift"`, `"alt"`, `"ctrl"`, `"meta"`, `"right"` → `CMD.OPT_*`, OR senza libreria di bit) e di maschere: `ShardUnit:Build` passa `{ 0 }` per default.

**I quattro metodi** (forma del vecchio loader, `git show 3ad8f3fb^:luarules/gadgets/AILoader.lua`):

| Metodo | Vecchio loader | Ora | Esempio da STAI |
| --- | --- | --- | --- |
| `'1-1'` | `GiveOrderToUnit(id, cmd, params, options)` | un ordine | `GiveOrder(self.id, CMD.GUARD, bossTarget, 0, "1-1")` (`buildersbst.lua:547`) |
| `'2-1'` | `GiveOrderArrayToUnit(id, {{cmd[i], params[i], options[i]}…})` | un ordine per comando, stessa unità, un gruppo | `GiveOrder(self.id, unitList, unitParams, unitOptions, "2-1")`, ondata di costruzione di una fabbrica (`labsbst.lua:163`: comandi `-unitDefID`, parametri e opzioni `0`) |
| `'1-2'` | `GiveOrderToUnitArray(ids, cmd, params, options)` | un ordine per unità, ognuno gruppo a sé | `GiveOrder(squad.cmdUnitId, CMD.MOVE, squad.path[squad.step], 0, "1-2")` (`attackhst.lua:250`) |
| `'2-2'` | `GiveOrderArrayToUnitArray(ids, cmds, true)`: **pairwise**, all'unità `i` il comando `i`, fino al più corto dei due | un ordine per unità, `id[i]` ← `cmd[i]`, `params[i]`, `options[i]` | nessun uso in STAI |

Nota su `'2-2'`: il compito lo descrive come «un array di comandi a un array di unità»; il vecchio loader passava `pairwise = true`, quindi ho seguito il vecchio loader (un comando per unità, non tutti a tutte).

Forme sbagliate: `Warn` e niente in coda (`'2-1'` e `'2-2'` vogliono array di comandi e, se presenti, di parametri e opzioni; `'1-2'` vuole un array di unità e **un** comando; metodo sconosciuto). Senza `self.ai.outbox`: un solo `Warn` per oggetto `game`, poi `false`. Tolti `game:GiveOrder(message)` e `game:SendLuaRulesMessage` (nessun altro uso). `ShardUnit:SyncOrder` restituisce `game:GiveOrder(id, cmd, params, opts, "1-1")`; `Tool:GiveOrder` restituisce `game:GiveOrder(...)` dopo il controllo sugli argomenti che c'era già; `SerializeOrder`/`DeserializeOrder` restano.

**Test**

- Spec, 20 casi: il `VFS` finto (byte noti di F32 1 e −2, S32 −1, U16 258, `PackF32({})` nil, `UnpackU8` all'ultimo byte nil); codec (andata e ritorno con negativi, decimali, limiti U16 e S32; STOP in ultima posizione; header corto e ordine tagliato); outbox (opzioni, parametri e limiti, 60 ordini in tre `Flush` con seq 1-2-3 e frame, gruppo non spezzato, gruppo da 30 da solo, gruppo scartato intero, `Reset`, coda vuota); `game:GiveOrder` (i quattro metodi, `'1-2'` con array di comandi, metodo sconosciuto, nessun outbox).
- Prova delle mutazioni: leggendo `n` come U8 senza ripiego falliscono 7 casi su 20; togliendo il vincolo dei gruppi falliscono 3.
- `lx --lua-version 5.1 test`: `2581 successes / 0 failures / 0 errors / 1 pending` (T3b: 2561). `.emmyrc.json` rimesso com'era.

**Test headless e byte order**: vedi il primo problema sotto. Il nuovo test risulta `PASS` nel runner ma il runner non lo esegue. L'ho quindi fatto girare con il `VFS` vero da un gadget temporaneo (non committato, tolto dopo ogni partita) che carica `luaui/Tests/shard/test_ordercodec.lua` e chiama `test()`, in synced e in unsynced, più una copia con un byte atteso sbagliato come controllo negativo. Risultato sulla versione committata: `synced test_ordercodec: ok`, `unsynced test_ordercodec: ok`, entrambe le copie sbagliate `FAILED … F32 1`. Il `VFS` vero scrive little-endian (F32 1 = `00 00 80 3F`, −2 = `00 00 00 C0`, S32 −1 = `FF FF FF FF`, U16 258 = `02 01`), `UnpackU8` all'ultimo byte restituisce nil, e codec e finto leggono gli stessi byte.

**Controlli**

- StyLua pulito su tutti i file toccati.
- EmmyLua: nessun errore nuovo (l'unico errore nei file toccati è `team` non definito in `game.lua:65`, già presente). Warning: 0 nei file nuovi; `game.lua` da 10 a 2, grazie a `---@class ShardGame` con il campo `ai`; `unit.lua` e `tool.lua` invariati (2 e 6). `---@class ShardOutbox` con i campi; nella spec ho aggiunto alla riga `---@diagnostic disable` le categorie che nascono dal caricare le classi via `env`.
- Headless finale: codice d'uscita 0, righe d'errore identiche a T3b.

**Problemi trovati**

1. **I test headless passano tutti senza girare.** Ogni test in `luaui/Tests/` risulta `PASS … [0 frames] [0 ms]` anche con un `error()` esplicito in `test()` (provato). Causa: `luaui/barwidgets.lua:1754-1758` (`widget.setfenv`, commit upstream #9658/#9660 «owned envs») rifiuta di cambiare l'ambiente se non è posseduto dal widget, scrive `setfenv: cannot change this environment` e restituisce la funzione invariata; `dbg_test_runner.lua:1079` e `:1100` usano proprio `setfenv` per mettere il file di test e `__runTestInternal` nell'ambiente del test, quindi `runTestInternal` non vede `test` e chiude con `PASS`. È l'errore «già presente» `setfenv ×16` che abbiamo ignorato da T1: i `PASS: ai_stai_factory_rect.lua` riportati in T1b–T3b non provano nulla. Non toccato (fuori compito, codice di BAR); probabilmente il runner dovrebbe costruire l'ambiente con `widget.newfenv()`. Da verificare se succede anche nel CI di BAR.
2. **I numeri Lua dell'engine sono float a precisione singola**, in synced e unsynced (verificato in gioco: `2^24 + 1 == 2^24`, `2147483647 == 2^31`, `0.1` con `%.17g` = `0.100000001490116`). Conseguenze:
   - interi esatti solo fino a 2^24: seq e frame di emissione restano esatti per 16.777.216 messaggi o frame, circa 155 ore a 30 frame al secondo con un messaggio per frame; oltre, `seq + 1 == seq` e il relay rifiuterebbe tutto;
   - `2147483647` non esiste: il primo test headless con `seq = 4294967295` lo scriveva come 2^32 e lo rileggeva 0. Corretto prima del commit: i limiti dell'outbox sono potenze di due con estremo superiore escluso (`value < 2^31`), esatte anche in float; il test headless usa valori esatti in float (`2147483520`, `4294967040`, `16777216`);
   - i parametri F32 non perdono precisione: sono già float;
   - la spec gira in doppia precisione, quindi questi casi li copre solo il test con il `VFS` vero.
3. **`attackhst.lua` righe 560, 583, 612, 631** chiamano `'1-2'` con array di comandi, parametri e opzioni (uno per unità): è la forma di `'2-2'`. Con il vecchio loader non funzionava (`GiveOrderToUnitArray` con una tabella come comando); ora danno un `Warn` e nessun ordine. Correzione proposta per il porting di STAI: `'1-2'` → `'2-2'` in quelle quattro righe.

**Dubbi e proposte**

- Gruppi oltre 25 ordini: `'2-1'` in `labsbst.lua:163` manda un'ondata di costruzione; le ondate fisse arrivano a 10, quelle calcolate (`engineerhst.engineerNeeded`) non hanno un limite nel codice. Un gruppo più grande di 25 parte da solo; uno oltre 4.000 ordini sarebbe rifiutato dal relay della bozza (`MAX_ORDERS_PER_MESSAGE`).
- Il tetto di 64 KB del pacchetto non è controllato: 25 ordini restano sotto i 26 KB anche con 255 parametri ciascuno, ma un gruppo grande con molti parametri potrebbe superarlo.
- Non implementati, perché non chiesti: l'accorpamento per unità della proposta (un ordine senza `shift` sostituisce quelli in coda per la stessa unità), le priorità della coda e i controlli locali (unità propria e viva).
- `ShardUnit:SyncOrder` usa il `game` globale, cioè l'AI dell'ultimo `Prepare()`, non necessariamente la proprietaria dell'unità. Proposta, non applicata: risalire alla coda con `Shard.AIsByTeamID[Spring.GetUnitTeam(id)].outbox` (o un `ShardUnit.team` letto alla creazione), che dà sempre l'AI proprietaria.
- Ho aggiunto `"spring_lua/outbox"` ai `runtime_includes` di `spring_lua/boot.lua`, perché la bozza del loader usa `ShardOutbox` come globale; il ramo `shard_null` non lo carica (lì `game:GiveOrder` è quello di `shard_null/game.lua`).

### T5a (agente locale, 23 novembre 2026) — verificato dal coordinatore

**Commit**

1. `31f7694763` «Notes: engine test tool for luaui/Tests/shard, synced and unsynced»: `.ai-notes/tools/engine_tests_gadget.lua` (114 righe), `.ai-notes/tools/run_engine_tests.sh` (69), una riga nel protocollo di questo file.
2. `609e15ad1b` «Shard: move the byte-faithful fake VFS into spec/support»: `spec/support/fake_vfs.lua` (nuovo, 174; restituisce `newVFS(env)`), `ordercodec_spec.lua` +1 −166 (`require("spec/support/fake_vfs")`).
3. `4f122f12b1` «Shard: ShardAILoader synced side, host registry and order relay»: `luarules/gadgets/ShardAILoader.lua` (nuovo, 294), `spec/luarules/gadgets/shard_ai_loader_spec.lua` (nuovo, 367).

**Strumento (punto 0)**

- `run_engine_tests.sh [file…]` copia il gadget in `luarules/gadgets/dbg_shard_engine_tests.lua` (se ci sono file indicati, li scrive nella copia al posto di `REQUESTED_FILES`), lancia `spring-headless` con `tools/headless_testing/startscript.txt`, toglie il gadget con `trap … EXIT INT TERM` e anche subito dopo la partita, stampa le righe `[SHARD-ENGINE-TESTS]` e chiude con `RESULT: ok` (uscita 0) o `RESULT: FAILED` (uscita 1). Se il gadget c'è già, si ferma senza toccarlo.
- Il gadget esegue ogni file (`skip`, `setup`, `test`, `cleanup` come il runner di BAR) in synced e in unsynced, scrive `ok`, `skipped` o `FAILED <file>: <errore>`, poi un controllo negativo (un test che chiama `error`) e la riga `SUMMARY <lato>: N ok, M failed, K skipped; negative control detected`. Restituisce `false`, quindi non resta caricato.
- Provato: senza argomenti `test_ordercodec.lua` passa nei due lati (`RESULT: ok`); con un file inesistente fra quelli indicati, `FAILED … file not found` nei due lati e `RESULT: FAILED`, uscita 1; dopo entrambe le esecuzioni il gadget non c'è più in `luarules/gadgets/`.
- Scostamento: per default lo script **non** usa `~/.spring` come cartella dati ma `${TMPDIR:-/tmp}/shard-engine-tests`, con link a `games`, `maps`, `packages`, `pool`, `rapid` di `~/.spring` e una copia di `tools/headless_testing/springsettings.cfg`. Altrimenti riscriverebbe `~/.spring/infolog.txt` mentre l'utente gioca. `WRITE_DIR=~/.spring` lo fa girare come in `CLAUDE.local.md`; `ENGINE_DIR` sceglie l'engine (default: il più recente in `~/.spring/engine`).

**`ShardAILoader.lua`**

- Dalla bozza: `GetInfo`, localizzazioni, rilevamento dei team con `ai/<NomeAI>/boot.lua`, `return false` senza AI Shard o con `Game.maxUnits > 65536`; lato synced con `IsActive`, `ChooseSuccessor`, `RegisterHosts`, `AddOrder`, `GiveOrders`, `Reject`, `Initialize`, `GameStart`, `PlayerRemoved`, `RecvLuaMsg`, `Shutdown` e gli stessi limiti (`MAX_ORDERS_PER_MESSAGE` 4000, `MAX_MESSAGES_PER_FRAME` 2, `MAX_FRAME_AGE` 900). Lato unsynced: `else` vuoto con un commento che rimanda a T5b.
- Controlli nello stesso ordine della bozza: magic (`false` se manca), dimensione dell'intestazione, versione, mittente, seq, frame di emissione, messaggi per frame di emissione, numero di ordini; poi ordini troncati e, per ogni cambio d'unità, `ValidUnitID` e team. Ogni rifiuto restituisce `true`.

**Scostamenti dalla bozza**

1. Lettura con `ordercodec.lua` (`IsOrderMessage`, `UnpackHeader`, `UnpackOrder`, `OrderCodec.VERSION`): spariti dal loader `ORDER_MAGIC`, `ORDER_VERSION`, `HEADER_SIZE`, gli offset e i `VFS.Unpack*` dell'intestazione. Restano solo i limiti del relay, che non sono del formato. Un'intestazione corta è `UnpackHeader` → `nil` → `Reject("size")`; un ordine troncato è `UnpackOrder` → `nil`, contato come prima (quell'ordine e i seguenti).
2. `params.n = nil` sulla tabella di `VFS.UnpackF32(msg, pos, n)`: l'engine aggiunge il campo `n` (anche il `VFS` finto, come l'engine), e la bozza stessa dice che l'engine legge le tabelle degli ordini con `next()`; tolto, nella tabella restano solo i valori. Senza questa riga due casi della spec falliscono.
3. `spGetPlayerList(-1, true) or {}` al posto di `spGetPlayerList(true)`: la firma documentata è `(teamID, active)`. L'uso con `true` come primo argomento c'è anche in `game_replace_afk_players.lua`, quindi l'engine lo accetta; ho scritto la forma documentata. `ChooseSuccessor` filtra comunque gli attivi da sé.
4. Il lungo commento «DRAFT …» in testa è diventato tre righe che descrivono il file com'è.
5. Annotazioni per EmmyLua (`---@type` su `lastSeq`, `lastFrame`, `cmdArray`, `cmdPool`, `host`; due cast), nessun cambio di logica.

**Test busted** (`shard_ai_loader_spec.lua`, 14 casi; engine finto con team 0 e 1 di STAI nell'ally team 0, team 2 di STAI nell'ally team 1, team 3 umano; host del lobby: giocatore 0 per i team 0 e 1, giocatore 1 per il team 2)

- relay: ordini dell'host con unità, comando, parametri e opzioni giusti; ordini consecutivi della stessa unità in una `GiveOrderArrayToUnit`, con l'array vuoto dopo la chiamata (`next(array) == nil`), e un ordine singolo con `GiveOrderToUnit`; STOP senza parametri in fondo; mittente che non è l'host, host di un altro ally team, team umano; unità di un altro team e unità non valida scartate da sole, con `SendToUnsynced("shard_relay_rejected", 0, 3)`; seq uguale e minore; frame nel futuro e più vecchio di 900, con il limite esatto (900) accettato; terzo messaggio con lo stesso frame di emissione rifiutato, e uno con un frame nuovo nello stesso frame di gioco accettato; versione sbagliata, intestazione di 15 byte, 4001 ordini; ordine troncato (passa quello prima, 2 rifiutati riportati); messaggio senza magic → `false`. I motivi dei rifiuti si leggono dalle righe di `Shutdown`.
- host: all'avvio `aiHostPlayer` pubblico = host del lobby per ogni ally team, nessun `shard_host`; con `PlayerRemoved` dell'host passa al giocatore attivo più basso dello stesso ally team, con `SendToUnsynced("shard_host", …)` per ogni team, il vecchio host viene rifiutato e il nuovo passa con seq 1; senza giocatori dell'ally team passa al giocatore attivo più basso di un altro ally team, e senza giocatori attivi allo spettatore più basso.
- avvio: senza AI Shard il file restituisce `false`.
- Suite completa: `2595 successes / 0 failures / 0 errors / 1 pending` (T4: 2581).

**Prova delle mutazioni** (un controllo tolto alla volta, spec del loader):

| Mutazione | Esito |
| --- | --- |
| mittente, seq, frame nel futuro, frame troppo vecchio, limite per frame di emissione, team dell'unità, numero di ordini, versione, intestazione corta, svuotamento dell'array, campo `n`, `return true` dei rifiuti, `shard_relay_rejected`, `shard_host`, rango del successore, ID più basso | 1 o 2 casi falliscono |
| seq che riparte con il nuovo host | 1 caso in errore |
| `ValidUnitID` tolto (resta il controllo del team) | **nessun caso fallisce** |

L'ultima è una mutazione equivalente: per un'unità che non esiste `GetUnitTeam` restituisce `nil`, nell'engine come nel finto, quindi il controllo del team la scarta comunque. Per farla fallire servirebbe un finto in cui un'unità non valida ha un team, cosa che l'engine non fa; non l'ho aggiunto.

**Controlli**

- StyLua pulito sui file toccati.
- EmmyLua: 0 warning e 0 errori nei file nuovi e in `fake_vfs.lua` (per la spec e per `fake_vfs.lua` ho aggiunto le categorie alla riga `---@diagnostic disable`, come nelle altre spec). Totale invariato: 22 errori. Nota: l'analisi include anche `.ai-notes/drafts/ShardAILoader.lua` (2 errori, 21 warning: `ShardScheduler` e `ShardPerception` non definiti), che non va in una PR.
- Headless con lo strumento: `RESULT: ok` (`test_ordercodec.lua` ok in synced e unsynced, controllo negativo visto); `[AI Loader] ShardLua bot Deactivated!` due volte (synced e unsynced), nessun errore che citi il loader; righe d'errore identiche a T4.

**Dubbi**

- Il commento del lato unsynced rimanda a «T5b», come chiesto; `.github/agents.md` vieta nei commenti i riferimenti ai compiti, quindi va riscritto entro T5b, comunque prima di una PR.
- Dalla bozza, non cambiato: un messaggio rifiutato per numero di ordini consuma lo stesso il posto nel limite per frame di emissione (il contatore sale prima del controllo `count`); e il contatore riparte a ogni cambio di frame di emissione, quindi frame che si alternano (999, 1000, 999…) non incontrano mai il limite. Solo l'host può farlo, e la seq deve comunque crescere; da decidere se basta.
- Il lato synced non verifica che il messaggio arrivi con un frame di emissione non più vecchio di quello del messaggio precedente: un host potrebbe mandare frame decrescenti entro la finestra di 900. Anche questo dalla bozza.

### T5b (agente locale, 23 novembre 2026) — verificato dal coordinatore

**Commit**

1. `ab1c26f58b` «Shard relay: emission frames never go back, size check before the frame limit»: `ShardAILoader.lua` +10 −4, `shard_ai_loader_spec.lua` +22 (due casi).
2. `cd1c46fdd9` «Shard: ShardAILoader unsynced side, the AIs run again on their host»: `ShardAILoader.lua` +689 −1, `spring_lua/unit.lua` +7 −1, `spec/luarules/gadgets/shard_ai_loader_unsynced_spec.lua` (nuovo, 492), tipo di AI finto in `spec/fixtures/shard_ai/` (`boot.lua` 5, `ai.lua` 9, `modules.lua` 3, `specmodules.lua` 45, `behaviourfactory.lua` 1).
3. `3ef3a56aeb` «STAI and Shard back in luaai.lua; STAI squads order with '2-2'»: `luaai.lua` +8 (STAI e Shard fra ScavengersAI e RaptorsAI, come a `3ad8f3fb^`, stessi testi), `STAI/attackhst.lua` +4 −4.

**Punto 1, relay**: dopo il controllo della finestra, `frame < lastFrame[teamID]` → `Reject("frame")`; poi `count`; poi il contatore per frame. Casi nuovi: frame che scende (999 dopo 1000) rifiutato e il 1000 successivo accettato; un messaggio da 4001 ordini fra due messaggi validi con lo stesso frame non consuma il posto (il terzo passa). Mutazioni: senza il controllo del frame che scende fallisce 1 caso; con `count` di nuovo dopo il contatore, 1 caso in errore.

**Punto 2, lato unsynced** (cosa fa, nell'ordine del file)

- `LoadRuntime` come la bozza senza `ShardScheduler` e senza `Shard.perceptions`; il runtime si carica solo in `AddAI`, cioè solo se il giocatore locale è `aiHostPlayer` di un team AI (`Initialize`) o lo diventa (`shard_host`).
- `gadget:HashGameID(gameID)`: `hash = (hash * 31 + byte) % 65521` (primo più grande sotto 2^16; il passaggio massimo è 65520 · 31 + 255 = 2.031.375 < 2^24); `TeamSeed`: `(hash * 31 + teamID + 1) % 65521`. È un metodo del gadget per poterlo provare nella spec.
- `Call(target, name, …)`: `target:Prepare()` e `target[name](…)` dentro `xpcall` con `debug.traceback`; gli argomenti passano per upvalue salvati e ripristinati (rientrante, nessuna closure per chiamata). `ReportError` scrive `[AI Loader] error in <AI> team|ally team|global <id>, <call-in>: <traceback>` una volta per coppia oggetto + call-in ogni 900 frame (tabella a chiavi deboli). L'avvio usa `Call(target, "Prepare")`, quindi anche un errore in `Init` è contenuto e scritto come `Prepare`.
- `LoadAIType`, `GetAlly`, `SetupAI`, `AddAI`, `StartObject`, `StartAIs`, `Ready`, `CatchUp`, `RelayRejected`, `Initialize`, `GameStart`, `FeatureDestroyed`, `GameID`, `Shutdown` come la bozza, tolte percezione e registro.
- `HostChanged`: se il giocatore locale diventa host, `AddAI` e `CatchUp(StartAIs())` (solo gli oggetti nuovi sentono le unità esistenti); se smette di esserlo, `StopAI`: `outbox:Reset()`, l'AI esce da `Shard.AIsByTeamID`, `Shard.AIs` (indici rinumerati), `ally.AIs`, `global.AIs`, e `hosting` torna `false` se non resta nessuna AI.
- `GameOver` → `GameEnd()` con `Call` su team, ally, global (ordine della bozza).
- `UnitDestroyed` → dopo `UnitDead`, `Shard:unshardify_unit(unitId)`.

**Punto 3**: `ShardUnit:SyncOrder` usa `Shard.AIsByTeamID[Spring.GetUnitTeam(id)]` e passa per `owner.game:GiveOrder(…, "1-1")`; se l'unità non è di un'AI ospitata qui: `Spring.Echo("Shard Warning: unit <id> is not of an AI hosted here, order dropped")` e `false`. `ShardUnit` non ha un metodo `Warn` (il vecchio `self:Warn` di `SyncOrder` sarebbe andato in errore), quindi `Spring.Echo`.

**Punto 4**: le quattro righe ora usano `"2-2"`. Le righe 612 e 631 stanno dentro un `--[[ … ]]` (righe 588–634, una seconda `AttackHST:SquadAttack` commentata): cambiate lo stesso, come chiesto, ma non girano.

**Parti provvisorie, esattamente dove sono** (tutte in `ShardAILoader.lua`, lato unsynced)

| Parte | Dove | Come funziona oggi |
| --- | --- | --- |
| Update | `gadget:GameFrame` → `UpdateObject` | a ogni frame `Call(obj, "Update")` su global, poi ally, poi team; poi `outbox:Flush(n, Spring.SendLuaRulesMsg)` di ogni AI di team |
| Consegna eventi | `Deliver`, `DeliverToShared`, `DeliverToAIs`, `DeliverToAll`, `DeliverSight` e i call-in `Unit*` | vedi tabella sotto; il blocco ha il commento «Provisional, as the old loader did» |
| Tabelle di unità | `AddToUnitTables`, `RemoveFromUnitTables`, i cinque campi creati in `SetupAI` | onniscienti; lette da `game:GetUnits()`, `GetFriendlies()`, `GetEnemies()` in `spring_lua/game.lua` |
| Errori | `ReportError`, `Call` | per oggetto + call-in, nessuna quarantena per modulo |
| Oggetti senza moduli | `HasModules` | un `ShardAlly`/`ShardGlobal` senza moduli del suo ambito non riceve né `Update` né eventi |

| Call-in | Chi lo riceve | Tabelle |
| --- | --- | --- |
| `UnitCreated` | global e ally tutti; fra le AI di team **solo la proprietaria** | aggiunge |
| `UnitFinished` → `UnitBuilt` | tutti | — |
| `UnitDestroyed` → `UnitDead` | tutti, poi `unshardify_unit` | toglie |
| `UnitDamaged` | tutti (`unit`, `attacker`, oggetto danno) | — |
| `UnitIdle` | tutti | — |
| `UnitTaken` → `UnitDead` | tutti | toglie |
| `UnitGiven` → `UnitCreated` | tutti | aggiunge col nuovo team |
| `UnitEntered/LeftLos/Radar` | gli ally di quell'`allyTeam` e tutte le AI di team | — |

**Scostamenti dal compito, dalla bozza e dal vecchio loader**

1. **`UnitCreated` solo all'AI proprietaria** (il compito dice «a tutti gli oggetti»): il vecchio loader lo dava solo alla proprietaria, e i moduli di STAI lo trattano come un'unità propria: `BuildingsHST:UnitCreated` blocca il terreno di ogni struttura non pianificata di cui sente parlare (`DontBuildRectangle`). Darlo a tutte le AI cambierebbe il comportamento di STAI in T5c. Global e ally lo ricevono tutti (oggi STAI non ha moduli lì). `UnitGiven` invece va a tutti, come nel vecchio loader.
2. **Oggetti senza moduli saltati** (`HasModules`): con STAI tutti i moduli sono `"team"`, quindi `ShardGlobal` e `ShardAlly` hanno `modules` vuoto, e `ShardAI:UnitCreated` scriverebbe «No modules found in AI» a ogni unità (dubbio di T3).
3. **`Wants`, `AllyTeamWants`, `Sees`, `DeliverToObservers` tolte**, non lasciate inutilizzate: la consegna mirata le riscriverà comunque sopra gli handler per modulo, e codice morto in un gadget non passa le regole di BAR (`CONTRIBUTING.md`: no dead code). Restano nella bozza.
4. **Gaia**: il vecchio loader confrontava l'ally team dell'unità con l'ID del **team** Gaia (`unitAllyTeam == spGetGaiaTeamID`), vero solo quando i due numeri coincidono; ora `teamID == gaiaTeamID`. In una 1v1 i numeri coincidono (stesso risultato di prima); in una 2v2 le unità Gaia (le critter di BAR) prima erano nemiche, ora neutrali.
5. **Tabelle in `UnitTaken`/`UnitGiven`**: il vecchio loader non le aggiornava (le aggiornava solo `UnitCreated`/`UnitDestroyed`); il compito lo chiede: `UnitTaken` toglie l'unità, `UnitGiven` la classifica col nuovo team.
6. **`Shard:RegisterUnit`/`UnregisterUnit` della bozza tolti**: `spring_lua/shard.lua` non li ha; con le tabelle provvisorie non servono.
7. **LOS e radar**: niente `shardify_unit` (il vecchio loader creava l'oggetto e poi passava solo gli ID).
8. **`StopAI`** non esiste nella bozza: la bozza ignorava la perdita dell'host. Gli oggetti ally e global restano anche se restano senza AI.

**Test** (`shard_ai_loader_unsynced_spec.lua`, 14 casi): il runtime vero (`boot.lua`, classi, `game.lua`, `outbox.lua`, codec) sopra un engine finto; l'AI finta `SpecAI` ha un modulo per ambito che scrive ogni chiamata in `SpecLog`, con ganci `SpecHooks` per dare ordini o andare in errore.

- client non host: `Shard` resta `nil`, nessun log, nessun messaggio; client host solo dei team 0 e 1: niente oggetti per il team 2 né per l'ally team 1;
- avvio: 1 global, 1 ally per ally team, 3 team; `Init` nell'ordine global, ally, ally, team ×3; moduli condivisi raggiungibili dai team; `startPos`;
- `UnitFinished` arriva una volta a ognuno dei 6 oggetti; `UnitCreated` a global, ai due ally e alla sola proprietaria; `UnitEnteredLos` all'ally che vede, non all'altro, e alle 3 AI;
- tabelle dopo `UnitCreated` (propria, alleata, nemica, Gaia neutrale), `UnitTaken` + `UnitGiven`, `UnitDestroyed`; `unitsByID` senza l'unità morta;
- un ordine in `Update` esce in `SendLuaRulesMsg` nello stesso `GameFrame` con team, frame e unità giusti; `ShardUnit:Move` su un'unità del team 2 finisce nel messaggio del team 2 anche col `game` globale del team 0; un'unità di un umano: avviso e nessun ordine;
- errore in `Update` del team 1: scritto una volta in due frame, gli altri oggetti girano, il team 1 viene richiamato; 900 frame dopo è scritto di nuovo;
- cambio di host verso questo client (solo i nuovi `ShardAlly` e team sentono le unità esistenti) e via da questo client (AI fuori dalle liste, outbox vuota, niente più `Update` né eventi);
- `GameOver` → `GameEnd` una volta a ogni oggetto;
- seme: stesso `GameID` → stesso valore, ogni passaggio di un riferimento calcolato nel test sotto 2^24, semi diversi per team.

Suite completa: `2611 successes / 0 failures / 0 errors / 1 pending` (T5a: 2595).

**Mutazioni del lato unsynced** (una alla volta, spec unsynced): senza `xpcall` (1 errore); errore scritto a ogni frame; senza filtro del catch-up; `UnitCreated` a tutte le AI; vista a tutti gli ally; senza `Reset()` dell'outbox; AI fermata lasciata in `Shard.AIs`; senza `unshardify_unit`; team avviati prima dei condivisi; modulo del seme `2147483647`; `UnitTaken` senza togliere dalle tabelle; Gaia come nemico; senza `Flush` (2 casi); senza il controllo dell'host in `Initialize` (3 casi); `GameOver` senza i team; `SyncOrder` con il `game` globale. **Tutte e 16 fanno fallire almeno un caso.**

**Controlli**

- StyLua pulito sui file toccati.
- EmmyLua: 0 warning e 0 errori in `ShardAILoader.lua`, nella spec e nelle fixture; `unit.lua` invariato (2 warning). Totale del repository 22 errori, come prima. Annotazioni aggiunte: cast su `gameHash`, `unitDefID`, `teamID`; `---@type any` sulle variabili della chiamata in corso; `disable-next-line` su `ShardGlobal()`, `ShardAlly()`, `ShardOutbox()` (le classi di `class()` non sono chiamabili per l'analizzatore), su `self:UnitCreated`/`UnitFinished` in `CatchUp`, sul controllo di `traceback` e sulle due globali dell'ambiente del gadget (`ShardSpringLua`, `Shard`).
- Strumento: `RESULT: ok` (`test_ordercodec.lua` ok nei due lati, controllo negativo visto); `[AI Loader] ShardLua bot Deactivated!` in synced e unsynced (nessuna AI Shard nella partita); righe d'errore identiche a T4. Il lato unsynced con un'AI vera non è ancora girato nell'engine: è T5c.

**Dubbi**

- `ShardAI:Init` mette `loaded = true` prima di caricare i moduli: se `Init` va in errore a metà, l'oggetto resta caricato con una parte dei moduli e non riprova. L'errore è scritto (come `Prepare`).
- Un `ShardGlobal` che esisteva già non risente le unità del nuovo ally team quando un team arriva per cambio di host (nota della bozza, invariata).
- Gli eventi di vista vanno a tutte le AI di team per ogni ally team, come nel vecchio loader: con molte AI e molte unità è il costo maggiore; la consegna mirata lo toglierà.
- `debug.traceback` nel LuaRules unsynced: usato se c'è, altrimenti il solo messaggio. Da confermare in T5c leggendo una riga d'errore vera.
- Il seme ha solo 65.521 valori possibili: basta per la casualità di un'AI; se serve di più, due hash con moduli diversi.

### T5c (agente locale, 23-24 novembre 2026) — verificato dal coordinatore

**Commit**

1. `4519d047b7` «Shard runtime: no tail call to VFS.Include, the runtime files ran in the global environment»: `spring_lua/boot.lua` +7 −2, `luaui/Tests/shard/test_runtime_environment.lua` (nuovo, 28).
2. `7234ffcd3d` «Shard runtime: metal spots from the game rules params of api_resource_spot_finder»: `spring_lua/map.lua` +27 −5, `spec/luarules/gadgets/ai/shard_runtime/spring_lua/map_spec.lua` (nuovo, 52); `b25ea794cd` +2 −2 (cast per EmmyLua).
3. `84a583fb51` «Shard loader: write the random seed of each AI team»: `ShardAILoader.lua` +3 −1.
4. `4397010419` «Notes: headless games with AI teams, control gadget and three startscripts»: `.ai-notes/tools/engine_game_gadget.lua`, `run_engine_game.sh`, `startscripts/{a_stai_vs_simpleai,b_2stai_vs_2simpleai,c_stai_vs_stai}.txt`.

**Strumento** (`run_engine_game.sh <startscript> <minuti>`): cartella dati in `${TMPDIR:-/tmp}/shard-engine-game` con link a `~/.spring`; copia il gadget di controllo in `luarules/gadgets/dbg_shard_engine_game.lua` e lo toglie sempre (`trap`, e l'engine viene ucciso se lo script è interrotto); sostituisce `@QUIT_FRAME@` (fine + 30 frame) nello startscript; lancia l'engine con `stdbuf -oL` e stampa righe `[SHARD-GAME]`, `[AI Loader]`, `Shard relay`, errori. Il gadget (synced) scrive ogni minuto per ogni team unità, fabbriche, mex, metallo, energia, `aiHostPlayer`, e le righe `SUMMARY`; la sua parte unsynced manda `luarules setTestReadyPlayers` finché la partita non parte.

Tre cose scoperte per far partire una partita headless con AI:
- il giocatore deve essere **spettatore** e qualcuno deve dichiararlo pronto (`setTestReadyPlayers` di `dbg_test_env_helper.lua`, come fa il test runner); con il giocatore nello stesso team di STAI la partita resta al frame -1 e la memoria di LuaUI sale (881 MB in 100 s); anche `startscript_barb_smoke.txt` di BAR resta al frame -1 su questa macchina;
- `setmaxspeed 100`/`setminspeed 100` nei `debugcommands`: 15 minuti di gioco in 21–28 s;
- l'infolog e lo stdout rediretto sono scritti a blocchi: se l'engine viene ucciso, le ultime righe si perdono e sembra fermo prima di quanto sia (`stdbuf -oL` per lo stdout).

**Mappa**: Comet Catcher Remake 1.8 (`comet_catcher_remake_1.8.sd7`), `StartPosType=0`, 15 minuti (frame 27000), velocità 100x.

**Correzioni**

1. **Runtime in `_G`** (nostra, T2): `shard_include` del runtime in `spring_lua/boot.lua` faceva `return VFS.Include(runtime_file)`. In una tail call il chiamante sparisce e `VFS.Include` senza ambiente ripiega sull'ambiente globale: tutti i file del runtime (`class`, `ShardAI`, `ShardOutbox`, `game.lua`, `map.lua`…) finivano nel `_G` del LuaRules, mentre il loader e gli ambienti dei tipi di AI li cercano nella tabella `gadget`. Effetto in partita: `STAI/ai.lua:1: attempt to call global 'class' (a nil value)` in `Initialize`, che faceva cadere tutto il LuaRules unsynced (l'errore di `Initialize` non è contenuto da `Call`). Correzione: `local result = VFS.Include(...) return result`, anche nel ramo senza ambiente di `shard_generate_include_func`. Test con lo strumento `test_runtime_environment.lua`: carica `boot.lua` e `api.lua` in un ambiente nuovo e controlla che `class`, `ShardAI`, `ShardOutbox`, `ShardUnit` e le funzioni di `game.lua`/`map.lua` stiano lì; prima: `FAILED … class: expected function, got nil` in synced e unsynced; dopo: `ok` in entrambi. La spec busted non poteva vederlo: il `VFS` finto non riproduce la regola dell'engine sulle tail call.
2. **Metal spot vuoti** (nostra, T1): `map.metalSpots = {}` lasciato in T1 faceva `LabsHST:factoriesRating` dividere 0 per 0 (`topRatingSpots`) → `labshst.lua:96: table index is NaN` in `Init`; i moduli dopo `LabsHST` non facevano `Init`, e a catena `loshst.lua:182 ownMobile nil`, `unithst.lua:117 units nil`, `unithst.lua:22` in ogni `Update` (visto nella partita in locale dell'utente). Correzione: `map:GetMetalSpots()`, `SpotCount()`, `GetSpot()` leggono `mex_count`, `mex_x<i>`, `mex_y<i>`, `mex_z<i>` di `api_resource_spot_finder` alla prima richiesta (non al caricamento di `map.lua`, che avviene prima che siano sicuramente impostati) e li tengono quando `mex_count` esiste; `mex_count = -1` (mappa di metallo) → nessuno spot. Spec busted, 3 casi: i primi 2 falliscono sul codice di prima, il terzo (mappa di metallo) passa con entrambi e fissa il comportamento.
3. **Seme casuale**: una riga `[AI Loader] AI team <id> random seed <seme>` in `TeamSeed`, lasciata perché serve a riprodurre una partita.

**Partita A — STAI (team 0) contro SimpleAI (team 1)**

| Minuto | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| STAI unità | 6 | 13 | 17 | 25 | 34 | 35 | 47 | 60 | 69 | 84 | 93 | 106 | 125 | 152 | 175 |
| STAI mex | 2 | 3 | 3 | 5 | 6 | 7 | 11 | 13 | 15 | 18 | 19 | 22 | 25 | 30 | 32 |
| SimpleAI unità | 5 | 13 | 20 | 24 | 30 | 38 | 43 | 45 | 50 | 60 | 58 | 56 | 58 | 63 | 60 |

STAI: 1 fabbrica fino al minuto 11, 2 dal 12. Relay: `3741 messages, 14309 orders given, 24 orders rejected`, nessun messaggio rifiutato. Nessuna riga `[AI Loader] error`. Ripetuta 5 volte: in 4 STAI cresce come sopra; in una resta senza metallo dal minuto 3, si ferma a ~38 unità e viene distrutta da SimpleAI al minuto 11 (nessun errore nel log: comportamento di gioco).

**Partita B — STAI (team 0, 2) contro SimpleAI (team 1, 3)**: semi 7325 e 7327.

| Minuto | 1 | 3 | 5 | 7 | 9 | 11 | 13 | 15 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| STAI team 0 unità / mex | 6 / 2 | 15 / 3 | 32 / 6 | 48 / 11 | 61 / 13 | 87 / 16 | 101 / 15 | 134 / 17 |
| STAI team 2 unità / mex | 6 / 2 | 18 / 3 | 32 / 5 | 45 / 9 | 60 / 10 | 78 / 14 | 115 / 20 | 165 / 24 |
| SimpleAI team 1 / 3 unità | 5 / 5 | 19 / 16 | 30 / 26 | 36 / 40 | 41 / 47 | 54 / 57 | 69 / 52 | 63 / 54 |

Relay: `4543 messages, 20802 orders given, 12 orders rejected`. Nessun errore. Un solo `ShardAlly` e un solo `ShardGlobal` per i due STAI: non c'è una riga di log che lo mostri; lo garantiscono `GetAlly`/`LoadAIType` e la spec unsynced («one global per AI type, one ally per ally team and type»).

**Partita C — STAI contro STAI**: semi 44929 e 44930.

| Minuto | 1 | 3 | 5 | 7 | 9 | 11 | 13 | 15 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| team 0 unità / mex | 6 / 2 | 12 / 3 | 31 / 6 | 41 / 7 | 69 / 11 | 103 / 16 | 116 / 19 | 146 / 23 |
| team 1 unità / mex | 6 / 2 | 17 / 3 | 35 / 5 | 55 / 7 | 82 / 11 | 111 / 17 | 143 / 24 | 153 / 24 |

Relay: `3886 messages, 23906 orders given, 14 orders rejected`. Nessun errore.

**Ordini rifiutati** (12–27 per partita, circa 0,1%): con una sonda temporanea nel relay (non committata) tutti risultano `valid false`, cioè unità morte fra l'invio e l'arrivo dell'ordine, con un ritardo di 28–30 frame fra emissione e arrivo. Il ritardo è gonfiato dalla velocità 100x (latenza in tempo reale del server locale contata in frame); a velocità normale la finestra è di pochi frame. Nessun messaggio rifiutato in nessuna partita. Nota per chi scrive sonde: per un'unità che non esiste `Spring.GetUnitTeam` non restituisce nessun valore, e `tostring(Spring.GetUnitTeam(id))` va in errore; la prima versione della sonda faceva fallire `RecvLuaMsg` e nascondeva i rifiuti.

**`debug.traceback`**: esiste nel LuaRules unsynced; confermato dalle righe d'errore vere della partita dell'utente (traceback completi), senza bisogno di un errore voluto.

**Confronto con il vecchio STAI**: 145–175 unità, 2 fabbriche e 20–30 mex a 15 minuti su Comet Catcher, sempre sopra SimpleAI: mi sembra normale per STAI. Si vede spesso energia a 0 nei primi minuti (stallo di energia) e metallo a 0 a tratti; non so dire se il vecchio STAI facesse lo stesso.

**Errori vecchi di STAI**: nessuno nelle tre partite dopo le due correzioni.

**Dubbi**

- Un errore in `gadget:Initialize` del loader (per esempio in `LoadAIType` o in `boot.lua` di un tipo di AI) fa ancora cadere tutto il LuaRules unsynced: `AddAI` non passa da `Call`. È il motivo per cui il primo difetto bloccava la partita invece di scrivere un errore. Proposta: proteggere `AddAI` con `xpcall`, scrivere l'errore e lasciare l'AI non caricata.
- Il blocco con il giocatore nello stesso team di STAI (frame -1, memoria LuaUI in crescita) non l'ho indagato: in una partita normale il giocatore non sta nel team di un bot, ma da capire.
- La partita A persa da STAI per mancanza di metallo: un caso su cinque.

**Prova dell'utente in SkyLobby**

1. In SkyLobby crea una partita (singleplayer o stanza locale) con il gioco «Beyond All Reason $VERSION», cioè la copia di sviluppo `~/.spring/games/BAR.sdd`; mappa: Comet Catcher Remake 1.8 (o un'altra piccola).
2. Aggiungi un bot STAI in un **team diverso dal tuo** (con «Add bot» / «Aggiungi bot», scegliendo STAI). Avversario consigliato: un bot SimpleAI nell'altro ally team, con te spettatore; oppure STAI contro di te.
3. Avvia e lascia giocare 10–15 minuti: il commander di STAI deve costruire subito mex e una fabbrica, poi unità.
4. Chiudi il gioco (l'infolog viene scritto per intero solo alla chiusura) e cerca in `~/.spring/infolog.txt`:
   - `[AI Loader] AI team <n> hosted by player <tu>` e `[AI Loader] AI team <n> random seed …`;
   - righe `<team>, STAI, Info: , adding … module` (tutti i moduli caricati);
   - **nessuna** riga `[AI Loader] error in …`;
   - alla fine `Shard relay:, <messaggi>, messages,, <ordini>, orders given,, <rifiutati>, orders rejected` con messaggi e ordini > 0 e rifiutati pochi.

### T6 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Commit**

1. `5faa0dad2a` «Shard loader: an AI that fails to load or initialise is dropped, LuaRules goes on»: `ShardAILoader.lua` +107 −18, spec unsynced +99 −7, `spec/fixtures/shard_ai_broken/boot.lua` (nuovo, 6), `luaui/Tests/shard/test_contained_load_error.lua` (nuovo, 20).
2. `19311ddb75` «Shard loader: a dead unit's ShardUnit stays 900 frames before it leaves the cache»: `ShardAILoader.lua` +53 −3, spec unsynced +73 −4, `spec/fixtures/shard_ai/specmodules.lua` +4 −1 (`SpecQuiet`).
3. `45ec9599a3` «Shard loader: ShardMemStats writes the Lua memory allocated per frame once a minute»: `ShardAILoader.lua` +35, spec unsynced +93.
4. `45d5cf2bb1` (strumento): `SHARD_MEM_STATS=1` in `run_engine_game.sh` scrive `ShardMemStats = 1` nel `springsettings.cfg` della cartella dati temporanea (mai in `~/.spring`).
5. `5893143262`: annotazioni per EmmyLua (`newAllies`, contatori della memoria).

**Punto 1 — caricamento protetto**

- `AddAI` esegue `LoadRuntime` e `SetupAI` (quindi `LoadAIType`, `boot.lua` e i file inclusi, `NewAPI`, `GetAlly`, `ShardOutbox`…) dentro `xpcall` con traceback. Se fallisce: `[AI Loader] error loading <AI> for team <id>: <traceback>`, l'AI non entra in `Shard.AIs`/`AIsByTeamID`, e i `ShardAlly` creati durante quel tentativo e rimasti senza AI vengono tolti (`newAllies`, `RemoveNewAllies`). `Shard.types[nome]` e `Shard.globals` si riempiono solo alla fine di `LoadAIType`, quindi un tipo fallito non lascia oggetti.
- Un tipo fallito è ricordato in `failedTypes`: gli altri team di quel tipo scrivono la loro riga con lo stesso errore, senza rieseguire `boot.lua`. Lo stesso per il runtime (`runtimeFailure`). Vale in `Initialize` e nel cambio di host (`HostChanged` → `AddAI`).
- Anche `Init` (primo `Prepare()` in `StartAIs`) fa cadere l'AI: `Call` ora restituisce l'esito; un oggetto il cui `Init` fallisce va in una lista e, alla fine della sua fase (global, ally, team), `DropFailed` lo toglie: un team con `StopAI(id, "failed to initialise")`; un ally o un global con tutte le sue AI (`"lost its ally object, which failed to initialise"`), poi l'ally esce da `alliesByAllyID`, il global da `Shard.globals` e il suo tipo va in `failedTypes`. Motivo: con `Init` interrotto a metà, l'AI sbaglia a ogni chiamata (è quello che si è visto con `LabsHST` in T5c). `StopAI` prende il motivo come argomento.
- Test busted (5 casi nuovi): tipo `BrokenAI` (il cui `boot.lua` va in errore) per due team → nessuna loro AI, nessun ally per l'ally team 1, una riga per team, `boot.lua` eseguito una volta, la terza AI gira; modulo di team in errore in `Init` → solo quel team cade, gli altri fanno `Update`; modulo d'ally in errore in `Init` → cade l'ally e la sua AI; `SetupAI` che fallisce dopo `GetAlly` (con `AreTeamsAllied` finto in errore) → l'ally nuovo viene tolto; cambio di host verso un team `BrokenAI` → riga d'errore e nessuna AI. Contro il loader di prima: 2 fallimenti e 2 errori.
- Mutazioni: senza `xpcall` in `AddAI` 2 errori; senza memoria dei tipi falliti 1 fallimento; senza rimozione degli ally vuoti 1 fallimento; `Init` fallito tenuto 2 fallimenti; oggetto condiviso fallito che tiene le AI 1 fallimento.
- Strumento: `test_contained_load_error.lua` include `spec/fixtures/shard_ai_broken/boot.lua` dentro `xpcall` con `debug.traceback`, controlla che l'errore arrivi con `broken boot` e che dopo il LuaRules includa ancora file: `ok` in synced e unsynced. Limite: non passa dal loader (la partita di test non ha team AI); il percorso del loader è coperto dalle spec.

**Punto 2 — unità morte**

- `UnitDestroyed`: dopo `UnitDead` il `ShardUnit` resta in `Shard.unitsByID`, segnato `destroyed = true`, e va in un anello di tre array paralleli (ID, oggetto, frame di scadenza = frame + 900). L'anello raddoppia solo quando è pieno (prima volta 64 posti); `ExpireDeadUnits(n)` in `GameFrame` toglie dalla testa le voci scadute, e solo se in cache c'è ancora lo stesso oggetto.
- `UnitCreated` di un ID il cui oggetto in cache è `destroyed` lo sostituisce con uno nuovo; la scadenza vecchia trova un oggetto diverso e non tocca il nuovo.
- Test busted (3 casi nuovi): `GetUnitByID(id):Name()` nello stesso frame della morte e 899 frame dopo → nome giusto, dopo 901 frame l'ID non è più in cache (sul loader di prima: errore, l'errore della partita dell'utente riprodotto); ID riusato prima della scadenza → oggetto nuovo col suo nome, ancora in cache dopo la scadenza vecchia; 300 unità morte in coda, 1450 `GameFrame` con le scadenze in mezzo, GC ferma: `collectgarbage("count")` identico prima e dopo (nessuna allocazione; per misurarlo i moduli finti tacciono con `SpecQuiet`). Il caso esistente sulle tabelle di unità ora si aspetta l'unità morta ancora in `unitsByID`. Mutazioni: sostituzione dell'ID riusato tolta, scadenza che toglie anche l'oggetto nuovo, anello ricostruito a ogni frame → 1 fallimento ciascuna.
- `shardify_unit` di un ID che non esiste e non è in cache (invariato): crea un `ShardUnit` con `UnitDefID` nil e `type.def` nil, lo mette in cache **per sempre** (nessun `UnitDestroyed` lo toglierà) e ogni metodo che legge la definizione va in errore (`Name`, `CanMove`…). Proposta: in `shardify_unit`, se l'ID non è in cache e `Spring.ValidUnitID(id)` è falso, restituire `nil` senza mettere niente in cache; il chiamante di STAI che fa `game:GetUnitByID(id):Name()` andrebbe comunque in errore (indice di `nil`), ma senza oggetti fantasma. Da decidere insieme alla correzione di STAI.

**Punto 3 — memoria per frame**

- Commento in testa al lato unsynced con l'opzione. `memoryStats` si legge da `Spring.GetConfigInt("ShardMemStats", 0)` al caricamento e di nuovo ogni 1800 frame (così `/set ShardMemStats 1` vale dal minuto dopo). Spenta: un solo `local memoryBefore = memoryStats and …` per frame. Accesa: `collectgarbage("count")` dopo `Ready()` e alla fine di `GameFrame`; somma, massimo e frame in tre numeri; ogni 1800 frame (non al frame 0) la riga `[AI Loader] memory per frame: avg … KB max … KB over N frames, heap … MB` e i contatori ripartono. Nessuna tabella.
- `Shard memory record:` di `Shutdown` resta, con un commento: è l'unico dato di memoria (picco di `gcinfo()` ogni 300 frame) quando l'opzione è spenta.
- Test busted (3 casi): media, massimo, numero di frame e heap esatti su due minuti, con un heap finto e un modulo che alloca 6 o 2 KB a frame alterni e poi 10; spenta → nessuna riga e nessuna chiamata a `collectgarbage("count")`; accesa a metà del primo minuto → una sola riga, nel secondo. Mutazioni: misura sempre accesa (2 fallimenti), contatori non azzerati, configurazione mai riletta, massimo non tenuto (1 ciascuna); senza il salto del frame 0, 1 fallimento.

**Partita A di T5c, 15 minuti, `SHARD_MEM_STATS=1`** (Comet Catcher Remake 1.8, seme 54414): nessuna riga `[AI Loader] error`; relay `2964 messages, 7725 orders given, 3 orders rejected`; STAI 146 unità, 2 fabbriche, 26 mex; SimpleAI 56 unità. Tutte le righe della memoria:

```
[AI Loader] memory per frame: avg 0.18 KB max 25.82 KB over 1801 frames, heap 13.1 MB
[AI Loader] memory per frame: avg 0.19 KB max 11.69 KB over 1800 frames, heap 13.1 MB
[AI Loader] memory per frame: avg 0.27 KB max 29.73 KB over 1800 frames, heap 13.2 MB
[AI Loader] memory per frame: avg 0.25 KB max 17.17 KB over 1800 frames, heap 13.6 MB
[AI Loader] memory per frame: avg 0.26 KB max 15.07 KB over 1800 frames, heap 13.4 MB
[AI Loader] memory per frame: avg 0.29 KB max 14.33 KB over 1800 frames, heap 13.5 MB
[AI Loader] memory per frame: avg 0.30 KB max 15.96 KB over 1800 frames, heap 13.8 MB
[AI Loader] memory per frame: avg 0.35 KB max 16.79 KB over 1800 frames, heap 13.8 MB
[AI Loader] memory per frame: avg 0.35 KB max 22.86 KB over 1800 frames, heap 13.9 MB
[AI Loader] memory per frame: avg 0.38 KB max 29.79 KB over 1800 frames, heap 13.9 MB
[AI Loader] memory per frame: avg 0.46 KB max 56.52 KB over 1800 frames, heap 14.3 MB
[AI Loader] memory per frame: avg 0.46 KB max 32.70 KB over 1800 frames, heap 14.0 MB
[AI Loader] memory per frame: avg 0.56 KB max 42.14 KB over 1800 frames, heap 14.1 MB
[AI Loader] memory per frame: avg 0.73 KB max 49.75 KB over 1800 frames, heap 14.6 MB
[AI Loader] memory per frame: avg 0.82 KB max 45.50 KB over 1800 frames, heap 14.3 MB
Shard memory record:, 15004
```

**Controlli**: StyLua pulito; EmmyLua 0 warning nei file toccati (22 errori nel repository, come prima); `lx --lua-version 5.1 test`: `2625 successes / 0 failures / 0 errors / 1 pending` (T5c: 2614); `run_engine_tests.sh`: `RESULT: ok`, 3 test per lato.

**Errori di STAI annotati, non corretti**

- `STAI/buildersbst.lua:122` e `STAI/bomberhst.lua:192`: `game:GetUnitByID(id):Name()` su ID di unità che possono essere morte (con il tempo di grazia ora funziona per 30 s; oltre, o per ID mai esistiti, resta l'errore).
- `STAI/buildersbst.lua:122`: gli argomenti di `EchoDebug` (anche `:Name()`) si calcolano a ogni chiamata, anche col debug spento: lavoro e allocazioni inutili.
- `STAI/loshst.lua` (celle) tiene ID di unità senza toglierli alla morte.

**Dubbi**

- La media per frame (0,2–0,8 KB) è probabilmente sottostimata: `collectgarbage("count")` misura tutto lo stato LuaRules unsynced e i passi della GC incrementale dentro il frame la abbassano (il limite è scritto nel commento). Per una misura netta servirebbe fermare la GC durante il frame, che però cambierebbe il comportamento: non l'ho fatto.
- La media cresce nel corso della partita (0,18 → 0,82 KB) insieme al numero di unità: atteso con STAI, che alloca per unità.
- `DropFailed` di un global segna il tipo come fallito per tutta la partita: un cambio di host verso un team di quel tipo non riprova.

### T6b (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Commit**

1. `a282312226` «Shard loader: errors told apart by message, counted, and listed once at the end»: `ShardAILoader.lua`, spec unsynced (+5 casi, uno aggiornato).
2. `912dfb290c` «Shard runtime: a recycled unit ID gets a new ShardUnit, an ID that never existed gets none» (punti 2 e 3): `spring_lua/shard.lua` +11 −4, `ShardAILoader.lua` −5 (il blocco di T6 in `UnitCreated` non serve più), spec unsynced +29.
3. `8e690cf374` (strumento): il gadget di controllo misura dopo quanto un ID morto torna in `UnitCreated`.
4. `33ef1e96da`: annotazioni per EmmyLua (`errorList`, cache delle unità).

**Punto 1**: `ReportError` ha una chiave `"<oggetto>|<call-in>|<prima riga dell'errore>"` (la prima riga contiene file, riga e testo). La prima volta: la riga di sempre con il traceback, subito; poi solo `count` e `last`. Niente più finestra di 900 frame (`ERROR_REPORT_FRAMES` e la tabella per oggetto tolti). Allocazioni solo quando c'è un errore (una stringa chiave a ogni errore, un record al primo). `WriteErrorSummary`, chiamata alla fine di `GameOver` e in `Shutdown`, scrive una volta sola, solo se ci sono stati errori: `[AI Loader] errors in this game, N different:` e poi `[AI Loader] <oggetto>, <call-in>: <n> times, frames <primo> to <ultimo>: <messaggio>`, nell'ordine della prima volta (l'ordine di inserimento). La chiave include il call-in, oltre a oggetto e messaggio: lo stesso messaggio in due call-in diversi conta due volte, come le due righe del riepilogo mostrano. Test (5): due errori diversi in `Update` a 2 frame di distanza → due righe col traceback; lo stesso errore 50 volte → una riga, poi `50 times, frames 1 to 50` una volta sola anche con `GameOver` e `Shutdown`; ordine della prima volta; riepilogo in `GameOver` da solo; nessun riepilogo senza errori. Il caso di T5b ora si aspetta una sola riga anche 900 frame dopo. Contro il loader di prima: 4 fallimenti. Mutazioni (chiave senza messaggio, contatore non incrementato, riepilogo due volte, niente riepilogo in `GameOver`, errore ripetuto scritto, intestazione senza errori): ognuna fa fallire 1–3 casi.

**Punti 2 e 3**: `Shard:shardify_unit(id)`: oggetto in cache e non `destroyed` → quello; altrimenti, se `Spring.ValidUnitID(id)` è falso → quello in cache (l'unità morta nel tempo di grazia) o `nil` (ID mai esistito, nulla in cache); se è vero → `ShardUnit` nuovo al posto del vecchio. `ValidUnitID` si chiama solo per ID non in cache o `destroyed`. La scadenza di T6 toglie solo se in cache c'è ancora lo stesso oggetto, quindi non tocca quello nuovo. Test (2): unità distrutta, ID dato a un'unità di altro tipo prima di `UnitCreated` → `GetUnitByID` restituisce la nuova col suo nome, `UnitCreated` non ne crea un terzo, e dopo la scadenza vecchia è ancora lì; `GetUnitByID(4242)` → `nil` e cache vuota. Contro il codice di prima: 2 fallimenti. Mutazioni: senza `ValidUnitID` 1 fallimento + 1 errore; oggetto `destroyed` sempre tenuto 2 fallimenti. L'engine finto ora ha `ValidUnitID`.

**Punto 4 — riciclo degli ID**: nessun riuso osservato. Partita A di 15 minuti: 128 unità morte, 0 ID riusati. Partita C di 60 minuti di gioco (STAI contro STAI, 265 s reali): 1495 unità morte, 0 ID riusati. In queste partite l'engine non ha mai ridato un ID di un'unità morta entro un'ora di gioco; il caso resta coperto dalle spec.

**Partita A di T5c, 15 minuti, `SHARD_MEM_STATS=1`** (seme 47596): nessun errore, quindi nessun riepilogo; relay `3393 messages, 11492 orders given, 9 orders rejected`; STAI 154 unità, 2 fabbriche, 23 mex; 15 righe di memoria.

**Partita C di 60 minuti**: il riepilogo vero, con due errori di STAI:

```
[AI Loader] errors in this game, 2 different:
[AI Loader] STAI team 0, Update: 51 times, frames 74332 to 75532: [string "luarules/gadgets/ai/STAI/buildersbst.lua"]:121: attempt to index a nil value
[AI Loader] STAI team 1, Update: 1671 times, frames 77955 to 108015: [string "luarules/gadgets/ai/STAI/bomberhst.lua"]:132: attempt to index a nil value
```

Sono gli ID vecchi di STAI annotati in T6 (`game:GetUnitByID(id)` su unità morte da più di 30 s, ora `nil` invece di un oggetto senza definizione). Relay `18781 messages, 142544 orders given, 45 orders rejected`. Il team 0 è stato distrutto (0 unità a fine partita), il team 1 ha 1335 unità.

**Controlli**: StyLua pulito; EmmyLua 0 warning in `ShardAILoader.lua`, 2 in `spring_lua/shard.lua` su righe non toccate (63 e 73, `ShardSpringDamage()`/`ShardSpringFeature()`, c'erano già); 22 errori nel repository come prima; `lx --lua-version 5.1 test`: `2632 successes / 0 failures / 0 errors / 1 pending` (T6: 2625); `run_engine_tests.sh`: `RESULT: ok`.

**Note**

- Lo scratchpad era stato svuotato fra i compiti: StyLua 2.5.2 ed EmmyLua 0.24.0 riscaricati dalle release di GitHub.
- Con 1671 ripetizioni in mezz'ora, l'errore di `bomberhst` ora costa una concatenazione di stringhe (la chiave) a ogni ripetizione: accettabile perché gli errori sono rari, ma STAI che sbaglia a ogni frame lo rende un costo per frame.

### T7 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Commit** (suite verde dopo ognuno)

1. `2b1fb6e7e7` «memory measure moved to loader/memstats.lua»
2. `277f814414` «unit tables and dead unit ring moved to loader/unitregistry.lua»
3. `a44bb61fe6` «protected calls, error list and event delivery moved to loader/delivery.lua»
4. `4b5fa9bdc4` «loading, start, stop and change of host moved to loader/loader.lua» (con la riscrittura dei call-in unsynced)
5. `ddb57b7e44` «host registry and order relay moved to loader/hosts.lua and loader/relay.lua»: un solo commit per i due file synced, perché si chiamano a vicenda (`Hosts.Setup(…, Relay.ForgetTeam)`, `Relay.Setup(Hosts.HostOf)`); separarli avrebbe chiesto un gadget intermedio scritto solo per il commit.
6. `7012d523b1` test nuovi: nessuna funzione del loader nell'ambiente del gadget, dei tipi di AI, di `_G`.
7. `e35b1955bd` riordino finale: tolto `spGetTeamInfo` non più usato dal gadget, tipi delle funzioni che `loader.lua` riceve da `Setup`.

**Righe**: prima `ShardAILoader.lua` 1194. Dopo:

| File | Lato | Righe |
| --- | --- | --- |
| `luarules/gadgets/ShardAILoader.lua` | entrambi | 285 |
| `shard_runtime/loader/hosts.lua` | synced | 105 |
| `shard_runtime/loader/relay.lua` | synced | 202 |
| `shard_runtime/loader/loader.lua` | unsynced | 498 |
| `shard_runtime/loader/delivery.lua` | unsynced | 230 |
| `shard_runtime/loader/unitregistry.lua` | unsynced | 100 |
| `shard_runtime/loader/memstats.lua` | unsynced | 74 |

Totale 1494: le righe in più sono commenti in testa ai file, le tabelle restituite, `Setup` e i `local` delle funzioni usate a ogni frame.

**Come sono legati**: ogni file restituisce una tabella; nessun globale. Il gadget include i file (`local X = VFS.Include(LOADER_PATH .. "x.lua")`, mai come tail call: vedi T5c) e passa le dipendenze con `Setup`: synced `Hosts.Setup(aiTeams, teamList, Relay.ForgetTeam)` e `Relay.Setup(Hosts.HostOf)`; unsynced `Loader.Setup({ gadget, aiTeams, teamList, aiPath, runtimePath, Delivery, UnitRegistry })`. `memstats`, `unitregistry`, `delivery` non hanno dipendenze e leggono `Shard` (globale dell'ambiente del gadget, come prima). I globali scritti restano quelli di sempre e solo in `loader.lua` (`ShardSpringLua`, `Shard`, `shard_include`). Il gadget mette in `local` le funzioni usate a ogni frame e a ogni evento.

**`Ready()` diviso** in `Loader.IsHosting()` e `Loader.StartAIsOnce()`, chiamate una dopo l'altra in ogni call-in che prima chiamava `Ready()`; `FeatureDestroyed`, `GameOver` e `GameStart` usano solo `IsHosting()`, come prima.

**`GameFrame` e un call-in di unità, ora:**

```lua
function gadget:GameFrame(n)
	if not IsHosting() then
		return
	end
	StartAIsOnce()
	BeginMemoryFrame()
	UpdateAll()
	FlushOrders(n)
	ExpireDeadUnits(n)
	EndMemoryFrame(n)
end

function gadget:UnitDestroyed(unitId, unitDefId, teamId, attackerId, attackerDefId, attackerTeamId)
	if not IsHosting() then
		return
	end
	StartAIsOnce()
	local unit = Shard:shardify_unit(unitId)
	DeliverToAll("UnitDead", unit)
	RemoveFromUnitTables(unitId)
	-- kept a while, with its type and name, then dropped: the old loader kept every dead unit forever
	KeepDeadUnit(unitId, unit, spGetGameFrame())
end
```

**Cose spostate con una piccola forma nuova** (stesso comportamento, verificato dalle spec e dalle mutazioni):
- `UnitCreated`: il blocco «tra le AI solo la proprietaria» è diventato `Delivery.DeliverToOwner(teamID, name, …)`, con il suo commento.
- `KeepDeadUnit` mette anche `unit.destroyed = true` (prima lo faceva `UnitDestroyed` subito prima).
- `RecvLuaMsg` è `Relay.Receive`, diviso in `CheckHeader` (tutti i controlli, nello stesso ordine) e `GiveMessageOrders` (il ciclo sugli ordini); `ReadParams` per i parametri; `Reject` non restituisce più `true`, perché è `Receive` a restituire `true` per ogni messaggio col magic.
- `RegisterHosts` è `Hosts.Register`, diviso in `ChooseHost` e `SetHost`; l'azzeramento di seq e frame del relay quando cambia l'host passa da `onHostChanged` (`Relay.ForgetTeam`), nello stesso punto di prima (dopo `aiHostPlayer`, prima del rules param).
- `GameOver`: `Delivery.EndGameAll()` e `Delivery.WriteErrorSummary()`; `GameID`: `Loader.SetGameID(gameID)`; `Initialize` unsynced: `Loader.AddHostedAIs()` e `Loader.CatchUpAfterReload()`; `FlushOrders` è in `loader.lua`.

**Modifiche alle spec**

1. `shard_ai_loader_unsynced_spec.lua`, caso del seme: `loader.gadget:HashGameID(gameID)` → `HashGameID` preso da `loader/loader.lua` incluso con il `VFS` della spec, perché non è più un metodo del gadget. Le asserzioni sono le stesse.
2. Nuovo, unsynced: «leaves no function of the loader in the environment of an AI type, nor in _G»: i nomi esportati dai quattro file unsynced, i nomi delle tabelle (`Loader`, `Delivery`…) e i vecchi metodi del gadget (`AddAI`, `StartAIs`…); nessuno in `rawget(env)`, nell'ambiente di `SpecAI`, in `_G`. Con il gadget di prima di T7 fallisce (i metodi `gadget:AddAI` ecc. erano visibili alle AI); ora passa.
3. Nuovo, synced: lo stesso per `relay.lua` e `hosts.lua` (nel gadget, nel suo ambiente, in `_G`); la spec ora tiene anche `recorded.env`.
4. Nuovi, synced: «rejects a first message from the future» e «rejects a first message older than 900 frames». Motivo: la prova delle mutazioni sul nuovo `relay.lua` ha mostrato che **togliendo del tutto il controllo della finestra dei frame nessun test falliva**: dal rinforzo di T5b, nel caso esistente il frame futuro arrivava per primo, veniva accettato, e i due messaggi dopo cadevano per «frame che scende» con gli stessi conteggi. Non dipende dallo spostamento. Con i due casi nuovi la rimozione completa fa fallire 2 casi, le due metà 1 e 2.

Nessuna asserzione tolta o allentata. Suite: `2636 successes / 0 failures / 0 errors / 1 pending` (T6b: 2632 + 4 casi nuovi).

**Mutazioni sui file synced dopo lo spostamento**: mittente, seq, finestra dei frame, frame che scende, limite per frame, numero di ordini, team dell'unità, svuotamento dell'array, magic che non è nostro, azzeramento di seq al cambio di host, rango del successore, `shard_host`: tutte fanno fallire almeno un caso.

**Controlli**: StyLua pulito; EmmyLua 0 warning nei file del loader e nel gadget (22 errori nel repository come prima); `run_engine_tests.sh`: `RESULT: ok`. Partita A di T5c, 15 minuti, `SHARD_MEM_STATS=1`, seme 62732: nessuna riga `[AI Loader] error`, relay `3395 messages, 16896 orders given, 9 orders rejected`, STAI 201 unità, 2 fabbriche, 38 mex. Memoria:

```
avg 0.17 KB max 26.79 KB over 1801 frames, heap 13.1 MB
avg 0.20 KB max 22.27 KB over 1800 frames, heap 13.2 MB
avg 0.28 KB max 29.36 KB over 1800 frames, heap 13.2 MB
avg 0.27 KB max 24.69 KB over 1800 frames, heap 13.4 MB
avg 0.29 KB max 17.18 KB over 1800 frames, heap 13.6 MB
avg 0.39 KB max 15.84 KB over 1800 frames, heap 14.0 MB
avg 0.36 KB max 20.09 KB over 1800 frames, heap 13.8 MB
avg 0.37 KB max 24.60 KB over 1800 frames, heap 14.1 MB
avg 0.38 KB max 22.15 KB over 1800 frames, heap 14.3 MB
avg 0.38 KB max 27.50 KB over 1800 frames, heap 14.1 MB
avg 0.38 KB max 27.10 KB over 1800 frames, heap 14.3 MB
avg 0.53 KB max 199.27 KB over 1800 frames, heap 14.3 MB
avg 0.52 KB max 37.83 KB over 1800 frames, heap 15.0 MB
avg 0.49 KB max 27.66 KB over 1800 frames, heap 14.5 MB
avg 0.51 KB max 28.46 KB over 1800 frames, heap 14.7 MB
Shard memory record:, 15577
```

Simili a T6b (medie 0,17–0,53 KB contro 0,18–0,82; heap 13–15 MB). Il massimo di 199 KB al minuto 12 è un frame isolato; in T6b il massimo era 94 KB. Con una sola partita non so dire se sia STAI o il loader.

**Nomi che cambierei** (non cambiati):
- `loader/loader.lua` → `loader/lifecycle.lua`: «loader/loader» non dice nulla, e il file è caricamento + avvio + arresto + cambio di host.
- `loader.lua` è il file più lungo (498 righe): si potrebbe dividere in `types.lua` (runtime, tipi, oggetti, seme, fallimenti) e `lifecycle.lua` (avvio, arresto, catch-up, host).
- `AI_PATH`/`RUNTIME_PATH` in `loader.lua` sono in maiuscolo come costanti ma arrivano da `Setup`; li lascerei così o li passerei come costanti del file.
- `KeepDeadUnit` ora segna anche l'unità morta: `ForgetDeadUnit` o `UnitDied` direbbe meglio cosa fa.

**Difetti visti spostando il codice** (annotati, non corretti):
- `EndGameAll` chiama `GameEnd` anche sugli oggetti senza moduli (non passa da `HasModules`, a differenza di `UpdateAll` e `Deliver`): oggi innocuo, `ShardAI:GameEnd` scorre i moduli.
- `CatchUp` passa dai call-in del gadget: ogni unità rigenera anche `AddToUnitTables` per tutte le AI, non solo per gli oggetti nuovi (idempotente, ma lavoro inutile in un cambio di host).
- La lacuna della spec sulla finestra dei frame (sopra), chiusa con due casi.

### T7b (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Commit**, uno per punto, suite verde dopo ognuno:

1. `920848e188` «loader/loader.lua split into loader/types.lua and loader/lifecycle.lua»
2. `bd9e7bbd11` «KeepDeadUnit renamed UnitDied» (gadget e `unitregistry.lua`; le spec non lo nominavano)
3. `0a763c8aa5` «GameEnd only to the objects that have modules, as Update and the events»
4. `3f804b6f83` «a catch-up writes the unit tables of the AIs it catches up only»

**Punto 1**: `types.lua` (runtime, tipi e loro ambiente, `NewAPI`, `LoadAIType`, `GetAlly`, `SetupAI`, seme, fallimenti del caricamento) e `lifecycle.lua` (`AddAI`, `StopAI`, `StartObject`, `DropFailed`, `StartAIs`, `IsHosting`, `StartAIsOnce`, `CatchUp`, `HostChanged`, `RelayRejected`, `AddHostedAIs`, `CatchUpAfterReload`, `FlushOrders`, `SetGameID`). Scelte dove il posto non era chiaro:
- il vecchio `AddAI` è diviso: il caricamento con `xpcall` e la gestione dei fallimenti sono `Types.LoadAI(id)`; la registrazione in `Shard.AIs`/`AIsByTeamID` e `hosting = true` sono `AddAI` in `lifecycle.lua`, che possiede `hosting`;
- `SetGameID` è in `lifecycle.lua` perché dipende da `hosting`; chiama `Types.SetGameHash` (sempre) e `Types.SeedAIs` (solo se ospita), come prima;
- `RemoveValue` e `RemoveAlly` stanno in `types.lua` (li usa la pulizia dei fallimenti) e sono esportati per `StopAI` e `DropFailed`;
- `DropFailed` segna un tipo fallito con `Types.MarkTypeFailed`, perché `failedTypes` è di `types.lua`.
Gadget: `Types.Setup(...)` e `Lifecycle.Setup(...)` al posto di `Loader.Setup`; i call-in usano `Lifecycle.*`. Spec: `HashGameID` preso da `loader/types.lua`; il test «nessuna funzione del loader visibile» scorre `types` e `lifecycle` al posto di `loader`, e controlla anche i nomi `Types`, `Lifecycle`, `LoadAI`. Righe: `types.lua` 294, `lifecycle.lua` 270; il gadget 294.

**Punto 3**: `EndGameAll` passa da `EndGameObject`, che controlla `HasModules`. Test: un ally con `modules` vuoto e `GameEnd` sostituito non viene chiamato a `GameOver`, l'altro ally sì; fallisce sul codice di prima.

**Punto 4**: `UnitRegistry.SetUnitTableTargets(targets)`, chiamata da `CatchUp` insieme a `SetCatchUpTargets` e azzerata alla fine: durante il catch-up `AddToUnitTables` salta le AI che non sono fra le nuove. Test: AI del team 0 attiva con unità propria e alleata, cambio di host che porta qui il team 2; le cinque tabelle del team 0 sono sostituite da tabelle che contano le scritture: 0 scritture, e il team 2 ha l'unità 100 fra le nemiche e la 300 fra le alleate. Sul codice di prima: 1 fallimento.

**Controlli**: StyLua pulito; EmmyLua 0 warning nei file del loader e nel gadget, 22 errori nel repository come prima; `lx --lua-version 5.1 test`: `2638 successes / 0 failures / 0 errors / 1 pending` (T7: 2636 + 2 casi nuovi); `run_engine_tests.sh`: `RESULT: ok`; partita A di 5 minuti: nessuna riga `[AI Loader] error`, relay `362 messages, 757 orders given, 0 orders rejected`, STAI 37 unità, 1 fabbrica, 6 mex.

**Nota di metodo**: ho scritto i quattro punti insieme e poi li ho separati nei commit, ricostruendo lo stato del solo punto 1 prima del primo commit; ogni commit è stato provato con la suite completa.

### T8 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Nome della classe: `ShardBasic`** (proposta del coordinatore, da confermare con l'utente). Nessun file di `Shard/` usa il globale `Shard` del runtime, quindi il nome non rompe nulla.

**Commit**

1. `76a55e269c` struttura: `Shard/ai.lua` (nuovo, 11 righe: `ShardBasic = class(ShardAI)`, `Name()` "Shard", `internalName()` "shard"); `Shard/boot.lua` +3 −2 (`shard_include("ai")`, restituisce `ShardBasic()`; ramo `shard_null` invariato).
2. `b69a510a6d` `Shard/behaviours.lua` +4 −1: definisce `behaviours = {}` e lo restituisce. `BehaviourFactory:AddBehaviours` legge il globale `behaviours[nome dell'unità]`, che **nessun file ha mai definito** (nemmeno a `3ad8f3fb^`): con l'ambiente separato per tipo, alla prima unità `attempt to index global 'behaviours'` e Shard non dava ordini. Vuota: ogni unità riceve `defaultBehaviours`. Spec `spec/luarules/gadgets/ai/Shard/behaviours_spec.lua` (fallisce prima).
3. `a8685480d5` `Shard/behaviour.lua` +2: `Behaviour:OwnerCreated`, che `shard_runtime/unit.lua:105` chiama e che il `Behaviour` di Shard (che per Shard prende il posto di quello del runtime) non aveva. Spec `behaviour_spec.lua`: tutti i callback `Owner*` che `Unit` chiama esistono (fallisce prima).
4. `bc25bb59c7` `Shard/placementhandler.lua` +1 −1: `NewJob` passava a `snap_to_grid` un `start_position` inesistente invece di `details.start_position` (`placementhandler.lua:20: attempt to index local 'pos'`); nessuna costruzione partiva. Spec `placementhandler_spec.lua` (stesso errore prima).
5. `fc35147be7` `Shard/placementhandler.lua`: le 19 chiamate `SendToUnsynced("shard_debug_position", …)` (solo nel codice synced: le AI girano nell'unsynced; in partita 27.020 errori in 15 minuti) passano da una `DebugPosition` locale che chiama `Script.LuaUI.shard_debug_position` se il widget c'è, come faceva il vecchio loader. Spec: `CanBuildAt` in un ambiente senza `SendToUnsynced` (fallisce prima).
6. `eee670beae` `Shard/taskqueuebehaviour.lua` +4 −1: stesso difetto in `TaskQueueBehaviour:DebugPoint` (10.253 errori in 15 minuti). Spec `taskqueuebehaviour_spec.lua` (fallisce prima).
7. `c469ee72b0` startscript `d_shard_vs_simpleai.txt` e `e_shard_vs_stai.txt`.

Tutti i difetti 2–6 c'erano già nel vecchio Shard; li ha resi visibili l'ambiente separato per tipo (2), il `Behaviour` del runtime (3) e il fatto che l'AI gira nell'unsynced (5, 6).

**Partita D, Shard contro SimpleAI, 15 minuti, `SHARD_MEM_STATS=1`, dopo tutte le correzioni**: nessuna riga `[AI Loader] error`, nessun riepilogo; relay `879 messages, 881 orders given, 0 orders rejected`.

| Minuto | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Shard unità | 6 | 10 | 11 | 11 | 12 | 12 | 14 | 15 | 3 | 0 |
| fabbriche / mex | 1 / 0 | 1 / 0 | 1 / 0 | 1 / 0 | 1 / 0 | 1 / 0 | 3 / 0 | 3 / 0 | 0 / 0 | 0 / 0 |

Distrutta da SimpleAI al minuto 10 (SimpleAI a fine partita: 32 unità). Memoria: medie da 0,06 a 20 KB per frame, **massimi di circa 5.950 KB in un frame** quasi ogni minuto in cui Shard costruisce, heap da 9,5 a 23,4 MB; dopo la distruzione 0,06 KB.

Prima dell'ultima correzione (con `DebugPoint` ancora in errore) Shard aveva costruito fino a 5 mex e 2 fabbriche, 19 unità, 53 ordini: con `DebugPoint` corretto ne costruisce 0. Non ho indagato (vedi sotto).

**Partita E, Shard contro STAI, 5 minuti**: i due tipi girano insieme, semi 61969 e 61970, nessun errore, relay `724 messages, 898 orders given, 0 orders rejected`. A 5 minuti Shard 14 unità, 1 fabbrica, 0 mex; STAI 39 unità, 1 fabbrica, 7 mex.

**Controlli**: StyLua pulito sui file toccati; EmmyLua: nessun errore o warning nuovo nei file di `Shard/` (confrontato con il codice prima del compito: `taskqueuebehaviour.lua` aveva già 1 errore, `value` non definito, e 44 warning, ora 42; `boot.lua` e `behaviours.lua` invariati); `lx --lua-version 5.1 test`: `2643 successes / 0 failures / 0 errors / 1 pending` (T7b: 2638 + 5 spec di Shard); `run_engine_tests.sh`: `RESULT: ok`.

**Non corretto, da elencare**

- Shard non costruisce mex (0 in due partite dopo le correzioni) e resta senza metallo dal minuto 2: da capire in `TaskQueueBehaviour:BuildExtractor` / `MetalSpotHandler:ClosestFreeSpot` (i metal spot ora vengono dai game rules param). Che con `DebugPoint` in errore ne costruisse è un indizio: l'errore interrompeva `Update` in un punto che forse cambia il flusso della coda.
- Allocazioni di circa 6 MB in un frame: con buona probabilità `PlacementHandler:GenerateSpiral` (raggio 1500, passo 16: una spirale di circa 190 × 190 posizioni a ogni nuovo lavoro di piazzamento).
- `shard_runtime/unit.lua:155` (`Unit:UnitDamaged`, `unit` nil), visto una volta in una partita: da T6b `shardify_unit` restituisce `nil` per un ID non valido e non in cache, e il loader consegna l'evento lo stesso. È del runtime/loader, non di Shard: proposta di non consegnare `UnitDamaged` quando l'unità è `nil`, da decidere.
- `taskqueuebehaviour.lua`: `value` non definito (errore EmmyLua già presente).

### T10 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Commit**

1. `a571c66fec` runtime e spec: consegna mirata in `shardai.lua`.
2. `28395e3ade` loader e spec: un oggetto senza moduli interessati non viene chiamato.
3. `b26bc57697` unità `nil`.
4. `96f2dcef82` `shard_null`.
5. `393f0ba29e` annotazioni per EmmyLua.

In tutto 9 file, +449 −34. `shardai.lua` 530 righe, `shard_null/boot.lua` 63.

**Runtime**: `EVENTS` (i 14 callback, compreso `UnitGiven`) ed `EVENTS_CALLED` (`UnitBuilt` → `My/Friendly/Enemy/NeutralUnitBuilt`; `UnitGiven` → `UnitCreated`, `UnitBuilt`, quindi per ricorsione anche i quattro `*UnitBuilt`). `WantsEvent(module, event)`: `module[event] ~= AIBase[event]`, letto sull'istanza, oppure uno degli eventi chiamati. Gli altri metodi di `AIBase` che ne chiamano altri: solo questi due (gli altri sono vuoti o di servizio). `ShardAI:BuildHandlers()` costruisce `self.handlers[evento]` alla fine di `Init` (dopo l'`Init` dei moduli, così vale anche un metodo assegnato lì) e in `AddModule`; i callback scorrono `self.handlers.<evento>`. `ShardAI:WantsEvent(event)` (vero anche prima di `Init`). Aggiunto `ShardAI:UnitGiven`, che scorre la sua lista: il loader oggi non lo usa, perché consegna `UnitGiven` dell'engine come `UnitCreated` (come il vecchio loader).

**Loader**: `HasModules` sostituito da `Wants(target, name)` = `target:WantsEvent(name)` in `Deliver`, `UpdateObject` (`Update`) ed `EndGameObject` (`GameEnd`). Ordine verificato call-in per call-in: `DeliverToShared` (global, poi ally) e poi le AI per `UnitCreated` (solo l'owner fra le AI), `UnitBuilt`, `UnitDead`, `UnitDamaged`, `UnitIdle`, `UnitTaken`, `UnitGiven`; `Update` e `GameEnd` uguale (`GameEnd` va team → ally → global, come da T5b); `DeliverSight` va agli ally di quell'ally team e alle AI, mai ai global (scelta di T5b, non cambiata). Commento in testa a `delivery.lua` aggiornato.

**Unità `nil`**: nei call-in `UnitCreated`, `UnitFinished`, `UnitDestroyed`, `UnitDamaged`, `UnitIdle`, `UnitTaken`, `UnitGiven`, se `Shard:shardify_unit(unitId)` è `nil` l'evento non si consegna; le tabelle di unità si aggiornano lo stesso; `UnitDestroyed` consegna `UnitDead` prima di toglierle, come prima. L'attaccante di `UnitDamaged` può restare `nil`.

**`shard_null`**: `shard_null/boot.lua` ha un `shard_include` che cerca prima nella cartella dell'AI e poi in `shard_runtime/` (leggendo `package.path` senza eseguire nulla), e restituisce `{ SetAIFolder, Start }`; `Start(ai, nome)` imposta `api` (quella di `shard_null` da `api.lua`), `fullname`, `id`, `allyId` e chiama `Prepare()`. `shard_null/game.lua`: `DrawDisplay`, che `ShardAI:Init` chiama. `Shard/boot.lua` (come esempio): nel ramo `shard_null`, `SetAIFolder("Shard")` e `Start(ai, "Shard")`. Il `require` in `shard_include` non è una tail call: lo `spec_helper` di BAR lo rifiuta, come l'engine con `VFS.Include` (T5c).

**Test**

- Runtime (6 casi in `shardai_spec.lua`): un modulo senza l'evento non lo riceve, gli altri sì, nell'ordine di `modules.lua`; `MyUnitBuilt` da solo → `UnitBuilt`; `UnitGiven` → chi vuole `UnitCreated`/`UnitBuilt`/`EnemyUnitBuilt`, nessun altro; metodo ereditato da una classe intermedia e metodo assegnato in `Init`; `AddModule` dopo `Init`; 1000 `UnitDead` senza allocazioni. Sul runtime di prima: 4 errori. Mutazioni (`UnitBuilt` senza smistamento, `UnitGiven` senza chiamati, tutti vogliono tutto, metodo letto sulla classe, `AddModule` senza ricostruire): tutte prese.
- Loader (3 casi): un ally i cui moduli non vogliono `UnitIdle` non viene chiamato (`Prepare` contato: 0) mentre gli altri sì (fallisce con il `delivery.lua` di prima); ordine global, ally, ally, team ×3; 500 `UnitIdle` a tutti gli oggetti senza allocazioni.
- Unità `nil` (1 caso): `UnitDamaged`, `UnitIdle`, `UnitFinished`, `UnitDestroyed` per un ID mai esistito → nessun evento; `UnitDamaged` con attaccante inesistente → consegnato con attaccante `nil`. Prima: errore.
- `shard_null` (1 caso): `require("Shard/boot")` con `package.path` su `luarules/gadgets/ai/`, `Init` con 5 moduli, 5 `Update` senza errori. Prima: errore.
- **Modifica a una spec esistente**: «ends the game only for the objects that have modules» (T7b) svuota `modules` a mano dopo `Init`; ora chiama anche `o.ally1:BuildHandlers()`, come fanno `Init` e `AddModule`. Asserzioni invariate. La spec unsynced ha anche `WeaponDefs` finto (serve a `shardify_damage`).
- Suite: `2654 successes / 0 failures / 0 errors / 1 pending`. `run_engine_tests.sh`: `RESULT: ok`.

**Chi riceve cosa** (Shard: liste vere sotto `shard_null`; STAI: dai metodi definiti nelle 20 classi `class(Module)`, comprese quelle che `modules.lua` non carica)

| Evento | Shard | STAI |
| --- | --- | --- |
| Update | 4 (unithandler, attackhandler, placementhandler, sleep) | 13 |
| GameMessage | 0 | 0 |
| UnitCreated | 1 (unithandler) | 3 (BuildingsHST, LosHST, UnitHST) |
| UnitBuilt | 1 | 2 (BuildingsHST, UnitHST) |
| UnitGiven | 1 | 3 |
| UnitDead | 3 | 5 (BuildingsHST, CleanHST, DamageHST, LosHST, UnitHST) |
| UnitIdle | 1 | 1 (UnitHST) |
| UnitDamaged | 1 | 3 (DamageHST, LosHST, UnitHST) |
| UnitEntered/LeftLos, UnitEntered/LeftRadar | 0 | 1 (LosHST) |
| UnitMoveFailed | 0 | 0 |
| GameEnd | 1 | 1 (UnitHST) |

**Partite** (`SHARD_MEM_STATS=1`, 15 minuti, Comet Catcher): nessuna riga `[AI Loader] error` in nessuna delle due.

| | T10 | T7 / T5c |
| --- | --- | --- |
| A, STAI a fine partita | 182 unità, 2 fabbriche, 32 mex | 201 / 2 / 38 (T7) |
| A, unità ai minuti 1/5/10/13 | 6 / 40 / 86 / 142 | 6 / 34 / 84 / 125 (T5c) |
| A, relay | 3638 messaggi, 12169 ordini, 10 rifiutati | 3395 / 16896 / 9 (T7) |
| A, memoria media per frame | 0,18–0,62 KB, max fino a 172 KB, heap 13–14,4 MB | 0,17–0,53, max 199, heap 13–15 (T7) |
| C, STAI a fine partita | 159 e 156 unità, 24 e 25 mex | 146 e 153 (T5c) |
| C, relay | 4255 / 24662 / 34 | 3886 / 23906 / 14 (T5c) |
| C, memoria media per frame | 0,28–1,01 KB, heap 18,7–22,7 MB | — |

Le partite stanno nella variabilità vista in T5c (fra 146 e 201 unità a fine partita); nessun segno di eventi persi. La memoria per frame non cala in modo visibile: gli eventi che STAI non ascolta erano chiamate vuote, senza allocazioni.

**Cosa servirebbe a STAI per girare sotto `shard_null`** (non fatto, STAI non si tocca):
1. `STAI/boot.lua` come `Shard/boot.lua`: `ShardNull.SetAIFolder("STAI")` e `ShardNull.Start(ai, "STAI")`; oggi l'AI parte senza `api` (`shardai.lua:173: attempt to index field 'api'`).
2. Nomi dei file e degli include con le stesse maiuscole: `modules.lua` include `schedulerhst`, il file è `schedulerHST.lua` (il VFS dell'engine non distingue, il file system sì).
3. `Spring`, `UnitDefs`, `Game` finti: 14 file di STAI li usano direttamente.

**Note**: EmmyLua senza errori nuovi; in `shardai.lua` un warning in più (28 contro 27), dello stesso tipo di quelli già presenti nei callback.

### T9 (agente locale, 24 novembre 2026) — verificato dal coordinatore (EmmyLua e StyLua 2.5.2 da rifare)

**Commit**

1. `4d59f1fca8` scheduler e spec (11 file, +568 −11).
2. `2059d084fb` esempio in Shard (3 file).

Nessuno startscript nuovo: `d_shard_vs_simpleai.txt` e `a_stai_vs_simpleai.txt` bastano.

**Righe per file**

| File | Cambio |
| --- | --- |
| `shard_runtime/loader/scheduler.lua` | nuovo, 143 |
| `shard_runtime/shardai.lua` | +31 −1 (`BuildHandlers`, `ScheduledUpdate`) |
| `shard_runtime/loader/types.lua` | +15 −1 (`SetSchedule`) |
| `shard_runtime/loader/lifecycle.lua` | +5 −1 (`Changed()` in `AddAI` e `StopAI`) |
| `shard_runtime/loader/delivery.lua` | commento in testa |
| `ShardAILoader.lua` | +6 (include, `Setup`, `RunScheduledTurn()` dopo `UpdateAll()`) |
| `Shard/ai.lua` | +4; `Shard/attackhandler.lua` +2 −5 |
| spec unsynced | +11 casi; fixture `spec/fixtures/shard_ai_scheduled/` (3 file), `specmodules.lua` +2 moduli |
| `shard_null_spec.lua` | +1 caso |

**Come funziona**

- `ShardAI:BuildHandlers` (alla fine di `Init` e in `AddModule`): se `self.MScheduler` c'è, i moduli di questo oggetto il cui `Name()` è nella lista vanno in `self.scheduledModules` (posizione nella lista → modulo) e **non** entrano in `handlers.Update`. Un oggetto la cui lista `Update` resta vuota non viene chiamato a ogni frame (`WantsEvent`, come T10). Senza `MScheduler` il codice fa esattamente quello di prima (`scheduledModules` vuota).
- `ShardAI:ScheduledUpdate(position)`: `Update` del modulo in quella posizione, se l'oggetto non è a fine partita. Lo scheduler lo chiama con `Delivery.Call` (quindi `Prepare` e `xpcall` come ogni altra chiamata).
- `types.lua` copia la lista della classe dell'AI (`aiType.class.MScheduler`) anche sugli oggetti ally e global del tipo, che sono `ShardAlly`/`ShardGlobal` e non la vedrebbero.
- `scheduler.lua`: una rotazione piatta di record `{ target, position, team, name }`, costruita solo quando `Changed()` è stato chiamato (`AddAI`, `StopAI`), al turno successivo. Ordine: per ogni posizione, le AI in `Shard.AIs` che la dichiarano; il modulo condiviso va all'oggetto che lo tiene (ally o global) una volta per posizione. I record sono riusati fra una ricostruzione e l'altra, quindi il cursore riparte dal record che stava per girare, o dal primo successivo rimasto. Per frame: avanza fino al primo record il cui oggetto ha davvero il modulo (un nome elencato e non tenuto da nessuno non consuma il frame; diventa un turno quando `AddModule` lo aggiunge), un solo turno, nessuna tabella nuova.
- Tipi diversi con liste diverse: la posizione `i` di ciascuno, in un unico giro lungo quanto la lista più lunga.
- `BScheduler`: non letto, scritto nel commento in testa a `scheduler.lua` e in `BuildHandlers`.

**Campi di compatibilità**: `self.ai.scheduler.moduleTeam` e `.moduleUpdate`. `scheduler` è **una sola tabella per client** (`Scheduler.state`), messa da `types.lua` su ogni oggetto (team, ally, global) dei tipi che dichiarano `MScheduler`; i tipi senza lista non hanno il campo (STAI invariato). Perché lì: un modulo raggiunge già il proprio oggetto con `self.ai`, anche se è un modulo condiviso (il suo `ai` è l'ally o il global); il nome ricalca `self.ai.schedulerhst` di STAI, così una condizione come quella dei moduli di STAI si traduce cambiando solo il campo. Per un turno di un modulo ally o global `moduleTeam` è `nil` (non è il turno di un team). Con lo scheduler che chiama solo il modulo di turno, il controllo nei moduli non serve più: i campi sono per chi vuole sapere a chi tocca.

**Shard**: `ShardBasic.MScheduler = { "AttackHandler", "PlacementHandler" }`, con il commento sulla regola. Fuori: `UnitHandler` (fa girare i behaviour) e `Sleep` (conta i frame: a turni le attese si allungherebbero); `MetalSpotHandler` non ha `Update`. `AttackHandler:Update` aveva `if (frame + team) % 15 == 0`: chiamato a turni scatterebbe a caso (con un giro di 2 frame, solo nei frame pari o dispari), quindi ora chiama `DoTargetting` a ogni turno; lo sfasamento fra AI lo fa lo scheduler. Con una sola AI Shard il giro è di 2 frame: la mira passa da ogni 15 frame a ogni 2, il piazzamento da ogni frame a ogni 2.

**Test** (`2666 successes / 0 failures / 0 errors / 1 pending`; T10: 2654, +12)

Fixture `SchedAI`: classe con `MScheduler = { SpecTeamModule, SpecAllyModule, SpecGlobalModule, SpecTeamModuleB }`, `SpecTeamModuleC` non elencato, `BScheduler` dichiarato; i moduli sono quelli di `SpecAI` (la spec mappa `specmodules.lua` e `behaviourfactory.lua` sui file di `shard_ai/`; `realPath` ora sceglie il prefisso più lungo).

1. senza liste: ogni modulo `Update` a ogni frame, nessun campo `scheduler`;
2. con liste: 4 `Update` per frame (3 `specteamc` + 1 elencato), 18 frame = due giri esatti di `t0,t1,t2 / a0,a1 / global / t0,t1,t2`;
3. ally con tutti i moduli a turni: nessun `Prepare` nei frame non suoi, `handlers.Update` vuota; team: solo `specteamc`;
4. modulo condiviso: un turno per giro per contenitore (3 su 3 giri);
5. AI fermata quando era la prossima: il turno passa alla successiva, nessun salto né ripetizione per 14 frame;
6. AI fermata che non era la prossima: si riparte dallo stesso turno;
7. nome elencato non tenuto da nessuno: saltato senza consumare il frame; dopo `AddModule` ha il suo turno (frame 10 e 20);
8. AI presa da un altro host: entra nella rotazione, il cursore resta dov'era;
9. due tipi (SchedAI e SpecAI): SpecAI riceve tutto a ogni frame come prima; SchedAI gira a turni;
10. `moduleTeam`/`moduleUpdate` letti dal modulo durante il turno; la stessa tabella su team, ally, global;
11. 500 frame senza allocazioni (stesso metodo di T6: `collectgarbage("stop")` e confronto di `count`);
12. (`shard_null_spec`) Shard: `handlers.Update` = `UnitHandler`, `Sleep`; `scheduledModules` = `AttackHandler`, `PlacementHandler`.

Sul codice di prima: 7 casi falliscono, 1 errore (il test dei nomi esportati non trova `scheduler.lua`). Passano anche prima il caso 1 (è il «come oggi» chiesto) e il caso 11 (prima non c'erano turni): la mutazione che alloca una tabella per frame in `RunScheduledTurn` lo fa fallire.

**Mutazioni** (tutte prese): elencati lasciati in `Update` (7 fallimenti); condiviso una volta per AI (5); cursore a 1 dopo la ricostruzione (2); cursore che salta un record (2); `StopAI` senza `Changed` (2); `AddAI` senza `Changed` (1); AI in ordine inverso (6); un'allocazione per frame (2); tutti i turni in un frame (6); `moduleUpdate` o `moduleTeam` non scritti (1 ciascuna); nome non tenuto dato all'ally (1); nessun salto dei turni senza modulo (1). Un `Changed()` in `StartAIs` che avevo messo non era coperto: era ridondante (ogni `StartAIs` che crea oggetti segue un `AddAI`, e la ricostruzione avviene al frame dopo) e l'ho tolto.

**Partite** (`SHARD_MEM_STATS=1`, 15 minuti, nessuna riga `[AI Loader] error` in nessuna delle due)

D, Shard contro SimpleAI:

| Minuto | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Shard unità T9 | 6 | 10 | 12 | 15 | 18 | 19 | 14 | 13 | 11 | 0 |
| Shard unità T8 | 6 | 10 | 11 | 11 | 12 | 12 | 14 | 15 | 3 | 0 |
| fabbriche / mex T9 | 0 / 1 | 0 / 1 | 0 / 1 | 1 / 1 | 1 / 1 | 2 / 1 | 0 / 1 | 0 / 1 | 0 / 1 | 0 / 0 |

Distrutto al minuto 10 come in T8 (SimpleAI a fine partita 74 unità). Relay `357 messages, 357 orders given, 1 orders rejected` (T8: 879 / 881 / 0). Memoria: medie 3,5–20 KB per frame, massimi di circa 5.950 KB quasi ogni minuto (la spirale di `PlacementHandler`, come in T8), heap 10–19 MB; dopo la distruzione 0,06 KB. Gli ordini sono meno della metà di T8: con una partita sola non so dire se dipenda dal piazzamento ogni 2 frame o dalla variabilità; Shard costruisce 1 mex (in T8 0).

A, STAI contro SimpleAI:

| | T9 | T10 |
| --- | --- | --- |
| STAI a fine partita | 188 unità, 2 fabbriche, 37 mex | 182 / 2 / 32 |
| unità ai minuti 1/5/10/13 | 6 / 35 / 107 / 164 | 6 / 40 / 86 / 142 |
| relay | 4031 messaggi, 15539 ordini, 6 rifiutati | 3638 / 12169 / 10 |
| memoria media per frame | 0,18–0,83 KB, max fino a 73 KB, heap 13,2–15 MB | 0,18–0,62, max 172, heap 13–14,4 |

Nella variabilità vista fino a T10: per STAI non cambia niente (nessun campo nuovo sui suoi oggetti, `handlers` identiche).

**Controlli**: `run_engine_tests.sh`: `RESULT: ok`. StyLua pulito sui file toccati, ma con **StyLua 2.6.0** (l'estensione di VSCodium): su questa macchina non trovo né StyLua 2.5.2 né `emmylua_check` (non sono nel `PATH` né altrove sul disco), quindi **EmmyLua non l'ho eseguito**. Da controllare con gli strumenti fissati.

**Note**
- `lx test` riscrive `.emmyrc.json` (percorsi `lib`/`src` delle dipendenze); l'ho ripristinato a ogni esecuzione, non è nei commit.
- Un modulo condiviso aggiunto con `AddModule` a un ally dopo l'avvio non entra nella rotazione finché le AI ospitate non cambiano (il caso del team invece sì, test 7). Non l'ho gestito: nessuno lo usa.

### T11 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Commit**

1. `dca5222bd3` strumenti e controlli di T9: annotazioni in `scheduler.lua` e `shardai.lua`; riga sugli strumenti nel protocollo.
2. `e9e379fafc` elezione, `legacyElection`, riga di STAI, spec.
3. `bbb25cbe57` `BScheduler` e spec.
4. `885f668c6f` esempio in Shard.

**0. Strumenti**: `~/.local/bin/stylua` (2.5.2) e `~/.local/bin/emmylua_check` (0.24.0), dalle release di GitHub (sha256 degli archivi: `bcb0d855…d5ab` StyLua, `f75c6981…7564` EmmyLua). `~/.local/bin` non è nel `PATH` della shell dell'agente: si chiamano col percorso intero (scritto nel protocollo).

**Controlli di T9 rifatti**
- StyLua 2.5.2 sui 14 file `.lua` toccati da T9: puliti.
- EmmyLua 0.24.0 su tutto, contro `50218e25bf` (prima di T9) in un worktree: 20 errori in entrambi, negli stessi punti. Warning nuovi di T9: 6 in `scheduler.lua` (`record may be nil` ×5 e `never` → `integer`) e 1 in `ShardAI:ScheduledUpdate` (`Update` non definito). Corretti con una classe `ShardSchedulerTurn` e tre annotazioni locali: `scheduler.lua` ora ha 0 warning. Gli altri scostamenti per file (per esempio `global-in-non-module` in `ShardAI:Prepare`, codice non toccato) cambiano fra due esecuzioni sullo stesso albero, come già visto in T2.

**Righe per file** (codice; spec a parte)

| File | Cambio |
| --- | --- |
| `shard_runtime/unit.lua` | elezione +50 −16; `Unit:Update` +24 −7 (ora 319 righe) |
| `STAI/ai.lua` | +3 (la riga e il commento) |
| `shard_runtime/loader/scheduler.lua` | +12 −3 (annotazioni), +78 −36 (`BScheduler`); ora 203 righe |
| `shard_runtime/loader/types.lua` | +6 −2 |
| `shard_runtime/shardai.lua` | +1 −1 (annotazione), +10 −1 |
| `ShardAILoader.lua` | +2 |
| `Shard/ai.lua` | +4; `Shard/taskqueuebehaviour.lua` +6 −3 |
| spec | `unit_spec.lua` nuova (373 righe), loader +269, `shard_null_spec.lua` +41; fixture `shard_ai_behaviours/boot.lua` (16), `shard_ai_scheduled/ai.lua` +2 −1 |

**Elezione** (`Unit:ElectBehaviour`): scorre i behaviour in ordine, `Priority() or 0`, vince solo `score > bestScore` partendo da 0 (quindi > 0, e a parità il primo). Poi `nextBehaviour = nil`; se il vincitore è l'attivo (o nessuno vince e non c'è un attivo) finisce lì; altrimenti `nextBehaviour = vincitore` (anche `nil`), e l'attivo, se c'è, esce subito: `activeBehaviour = nil`, `PreDeactivate`, `Deactivate`. Il commento è aggiornato ed è esatto.
- Un cambio in più, motivato: un behaviour disattivato **non resta** `activeBehaviour` fino all'`Update` successivo. Con la regola di oggi resta, e ne seguono due difetti: due elezioni prima di un `Update` lo disattivano due volte; e se rivince prima dell'`Update`, «non cambia niente» ma il `nextBehaviour` già scelto entra lo stesso (c'è un test legacy che fissa proprio questo). Con l'attivo azzerato, `activeBehaviour` e `nextBehaviour` non sono mai impostati insieme. Fuori da `unit.lua` nessuno legge `activeBehaviour`/`ActiveBehaviour()` (grep su `luarules/gadgets/ai` e `shard_help_draw.lua`).
- **`legacyElection`**: `local function LegacyElection(self)` in `unit.lua`, con il corpo di oggi copiato identico; la sceglie `self.ai.legacyElection == true`. `STAI.legacyElection = true` in `STAI/ai.lua`, col commento chiesto. Con la regola di oggi una priorità `nil` dopo il primo behaviour è un errore (`nil > 0`): resta così, e c'è un test.
- `Shard/behaviour.lua`: funziona con la regola nuova. Le sottoclassi hanno `priority = 0` da `init` e `Priority()` restituisce quello; un `Behaviour()` creato direttamente ha `priority` `nil`, che ora vale zero invece di un errore.

**`BScheduler`**
- `scheduler.lua`: una seconda rotazione, di record `{ target = AI, position, team, name }`, costruita come quella dei moduli (per ogni posizione di `BScheduler`, le AI di `Shard.AIs` che la dichiarano) e ricostruita con lei quando c'è `Changed()`. Il cursore riparte come per i moduli: la logica comune è passata in `ResumeAt`, e `Rebuild` ora chiama `RebuildModules` e `RebuildBehaviours`. `NextBehaviourTurn()` fa un turno per frame: scrive `behaviourTeam` e `behaviourUpdate` in `state` (la stessa tabella di `moduleTeam`/`moduleUpdate`), o `nil` se la rotazione è vuota. Non chiama niente.
- `ShardAILoader.lua`: `NextBehaviourTurn()` **prima** di `UpdateAll()`, perché i behaviour girano dentro l'`Update` di ogni frame di `UnitHandler`. Chiamato dopo, come `RunScheduledTurn`, il turno varrebbe per il frame successivo (c'è una mutazione che lo controlla).
- `types.lua`: `scheduler` va agli oggetti dei tipi con `MScheduler` **o** `BScheduler`. Agli ally e ai global va solo la tabella `scheduler`, non `BScheduler`.
- `ShardAI:BuildHandlers`: se c'è `BScheduler`, `self.scheduledBehaviours = { [nome] = true }`.
- `Unit:Update`: l'attivazione del `nextBehaviour` resta in testa, a ogni chiamata. Senza `scheduledBehaviours` o senza `scheduler` (per esempio sotto `shard_null`) c'è il ciclo di prima, identico. Altrimenti il nome di turno è `behaviourUpdate`, se `behaviourTeam == ai.id`, e `behaviour:Update()` va a chi ha quel `Name()` o non è in lista. Nessuna allocazione.
- Una scelta diversa dai moduli: un turno di behaviour **non si salta** quando l'AI non ha unità con quel behaviour. Saperlo costerebbe una scansione delle unità; STAI fa lo stesso. È scritto in testa a `scheduler.lua`.

**Shard**
- `ShardBasic.BScheduler = { "TaskQueueBehaviour" }`: è l'unico behaviour di Shard con lavoro periodico (fa avanzare le code dei costruttori). `AttackerBehaviour` non ha `Update` (quella ereditata è vuota): elencarlo non cambierebbe niente. `BootBehaviour` conta i frame per liberare un'unità nuova e resta fuori, come `Sleep` fra i moduli.
- `TaskQueueBehaviour:Update`: il `countdown` contava le chiamate (15 prima di `ProgressQueue`). Ora somma i frame passati dall'`Update` precedente, quindi a turni l'attesa resta di 15 frame; chiamato a ogni frame conta esattamente come prima. Il controllo viene prima dell'incremento, come prima: a turni si avanza al primo turno dopo i 15 frame. Con una sola AI Shard la rotazione ha un solo turno, quindi in partita non cambia niente.
- **Cosa cambia per Shard con la regola nuova.** Priorità: `BootBehaviour` vale 500 mentre aspetta (solo unità mobili, dopo il frame 10), altrimenti 0. `TaskQueueBehaviour` vale sempre 50. `AttackerBehaviour` vale 100 quando attacca, altrimenti 0.
  - Costruttori (Boot + TaskQueue) e fabbriche: nessun cambio, TaskQueue (50) comanda dopo l'attesa di Boot.
  - Unità d'attacco (Boot + Attacker) e unità con solo Boot: dopo l'attesa, oggi restava attivo Boot (che da attivo non fa niente); ora **nessun behaviour è attivo** finché `AttackCell` non chiede l'elezione, e allora vince Attacker (100) come prima.
  - Effetto pratico nullo, quindi le priorità di Shard non vanno corrette.

**Test** (suite `2694 successes / 0 failures / 0 errors / 1 pending`, uguale con `SPEC_ORDER=reverse`; prima del compito 2666, +28)
- `unit_spec.lua`, elezione, regola nuova (9 casi): vince la più alta > 0; `nil` vale zero (e un attivo con `nil` esce); tutte ≤ 0 → nessuno attivo; l'attivo esce subito quando non resta niente > 0; a parità il primo; vince l'attivo → nessuna chiamata; il perdente esce subito e il nuovo entra all'`Update`; un `nextBehaviour` in attesa che perde si annulla (anche quando nessuno vince); due elezioni prima di un `Update` → una sola disattivazione.
- `legacyElection` (7 casi): più alta > 0; tutte ≤ 0 → il primo; l'attivo resta se nessuno è > 0; parità; `nil` del primo vince, `nil` dopo il primo è un errore; uscita subito e ingresso all'`Update`; l'attivo disattivato resta `ActiveBehaviour()` fino all'`Update` e il `nextBehaviour` entra anche se l'attivo rivince.
- Sul `unit.lua` di prima: falliscono i 6 casi della regola nuova che la cambiano (`nil`, nessuno attivo, uscita senza nulla > 0, perdente e vincitore, attesa annullata, doppia disattivazione). Passano anche prima i 3 casi che la regola nuova lascia uguali (più alta, parità, vince l'attivo) e tutti i casi legacy, che sono la regola di oggi.
- `Unit:Update` (4 casi in `unit_spec.lua`): elencati solo nel turno del loro nome per la loro AI (team diverso, nome di nessuno, turno vuoto), non elencati sempre; senza lista o senza `scheduler`, tutti sempre; l'attivazione del nuovo avviene anche fuori turno; 1000 `Update` senza allocazioni.
- Loader (5 casi, fixture `BehavAI` con solo `BScheduler`): tre AI, giro `SpecBehaviour@t0,t1,t2, SpecBehaviourB@t0,t1,t2` un turno per frame, `SpecBehaviourFree` ogni frame per tutte e tre; due AI che alternano, accanto a una AI `SpecAI` senza lista i cui behaviour girano tutti a ogni frame (né `scheduler` né `scheduledBehaviours`); `behaviourTeam`/`behaviourUpdate` letti da un modulo durante l'`Update` del frame, già sul turno di quel frame; AI fermata → il giro continua senza salti; tipo con solo `BScheduler`, più lungo di `MScheduler`: moduli tutti a ogni frame, behaviour a turni, `scheduler` condiviso; 500 frame senza allocazioni.
- Sul codice senza `BScheduler`: falliscono 5 casi. Passano anche prima «senza lista come oggi», l'attivazione a ogni `Update` e le due prove di allocazione (prima non c'erano turni); le mutazioni con allocazioni le fanno fallire.
- `shard_null_spec.lua` (2 casi): `scheduledBehaviours = { TaskQueueBehaviour = true }`; `countdown` a frame: con `Update` a ogni frame avanza al frame 16 (come prima), ogni 3 frame al 21. Ciascuno fallisce senza la sua modifica.

**Mutazioni** (tutte prese; fra parentesi i fallimenti)
- Elezione: parità all'ultimo (5); ≤ 0 può vincere (4); `nil` non zero (2 errori); attesa non annullata (1); attivo non azzerato (5); vincitore attivato subito (3); l'attivo che rivince rientra (1); perdente non disattivato (4); legacy ignorata (4); legacy sempre (6); legacy senza «primo di default» (2); legacy che azzera l'attivo (1).
- `BScheduler`: elencati sempre (4); turno senza controllo del team (4); non elencati solo nel turno (3); allocazione in `Unit:Update` (2); turno che non avanza (4); AI in ordine inverso (4); cursore a 1 dopo la ricostruzione (1); behaviour non ricostruiti (4); rotazione che legge `MScheduler` (1); `NextBehaviourTurn` dopo `UpdateAll` (4); niente `scheduler` senza `MScheduler` (1); niente `scheduledBehaviours` (4); allocazione nella rotazione (2).
- Una mutazione sopravvissuta ha mostrato un controllo inutile: `self:Scope() == "team"` in `BuildHandlers`. Ally e global non ricevono mai `BScheduler`, quindi l'ho tolto.

**Partite** (`SHARD_MEM_STATS=1`, 15 minuti; nessuna riga `[AI Loader] error`; solo gli errori di sempre: `gui_pip`, `sensor_ranges_jammer_preview`, groundFX, shader, `AdvSky`, `ceg_test_projectile`)

D, Shard contro SimpleAI: la prima partita moriva al minuto 7 (T9: 10). Per capire se fosse la regola nuova ho fatto altre 3 partite con T11 e 3 con il codice di prima del compito (`c706feaca9`, solo `luarules/` rimesso com'era e poi ripristinato).

| Partita | unità Shard ai minuti 1–10 | distrutto | mex | relay (messaggi / ordini / rifiutati) |
| --- | --- | --- | --- | --- |
| T11 #0 | 5 10 11 11 14 10 0 | min. 7 | 1 solo al min. 1 | 557 / 556 / 1 |
| T11 #1 | 5 10 11 11 14 14 10 0 | min. 8 | idem | 700 / 702 / 0 |
| T11 #2 | 5 10 11 11 14 14 10 8 6 0 | min. 10 | idem | 679 / 680 / 1 |
| T11 #3 | 5 10 11 11 13 14 11 9 8 9 … 4 a fine partita | vivo | 1 (min. 1 e 8) | 1252 / 1252 / 0 |
| prima #1 | 5 10 11 11 14 11 7 8 0 | min. 9 | 1 solo al min. 1 | 565 / 566 / 0 |
| prima #2 | 5 10 11 11 14 9 0 | min. 7 | idem | 546 / 549 / 0 |
| prima #3 | 5 10 11 11 13 12 10 0 | min. 8 | idem | 673 / 674 / 0 |
| T9 | 6 10 12 15 18 19 14 13 11 0 | min. 10 | 1 | 357 / 357 / 1 |

Stessa distribuzione prima e dopo il compito: nessun segno che la regola nuova peggiori Shard. Memoria nella partita #0: medie 3,4–13,5 KB per frame con Shard vivo e massimi di circa 5.950 KB (la spirale di `PlacementHandler`, come in T8 e T9), heap 9–13 MB; dopo la distruzione 0,06 KB.

A, STAI contro SimpleAI:

| | T11 | T9 | T10 |
| --- | --- | --- | --- |
| STAI a fine partita | 147 unità, 2 fabbriche, 15 mex | 188 / 2 / 37 | 182 / 2 / 32 |
| unità ai minuti 1/5/10/13 | 6 / 32 / 75 / 125 | 6 / 35 / 107 / 164 | 6 / 40 / 86 / 142 |
| relay | 3052 messaggi, 15253 ordini, 15 rifiutati | 4031 / 15539 / 6 | 3638 / 12169 / 10 |
| memoria media per frame | 0,18–0,65 KB, max 63 KB, heap 13,1–15,4 MB | 0,18–0,83, max 73, heap 13,2–15 | 0,18–0,62, max 172, heap 13–14,4 |

147 unità sta nella variabilità vista in T5c (146–201). Per STAI il codice è lo stesso: `legacyElection` ha il corpo di prima, la classe non dichiara `BScheduler` (quindi niente `scheduledBehaviours` né `scheduler`, e `Unit:Update` prende il ciclo di prima). Ho fatto una sola partita A.

**Controlli**: StyLua 2.5.2 pulito su tutti i file toccati. EmmyLua 0.24.0: 20 errori, gli stessi di prima. Nei file toccati nessun warning nuovo: `scheduler.lua` 0, `shardai.lua` 27, `unit.lua` da 10 a 8, spec solo hint; in `taskqueuebehaviour.lua` restano i 2 `unnecessary-if` di prima, a righe spostate. `run_engine_tests.sh`: `RESULT: ok`.

**Note**
- StyLua 2.5.2 a volte stabilizza una tabella in un `assert.same(...)` solo alla seconda o terza passata: conviene ricontrollare con `--check` dopo aver formattato.
- `lx test` riscrive ancora `.emmyrc.json`: l'ho ripristinato ogni volta, non è nei commit.
- `types.SchedAI.class` è la classe, ma `SetSchedule` copia `MScheduler` sulle istanze già a `Initialize`: per provare un tipo con solo `BScheduler` è servita una fixture (`BehavAI`) invece di cambiare la classe nel test.

### T12 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Fatto**

1. `shard_runtime/perceptionhandler.lua` (52 righe), classe `PerceptionHandler` (`Module`, `Scope()` `"ally"`): `los` e `radar` `[unitID] = true`, i quattro eventi di vista, `UnitDead` che toglie da tutte e due, `Sees` e `OnRadar` (restituiscono sempre un booleano). Commento in testa di tre righe. Nient'altro.
2. Tolti `Perception()` e `omniscient` da `loader/types.lua` (4 righe: tipo, globale, ally, team); non comparivano altrove fuori da `.ai-notes/drafts/`. In `unitregistry.lua` il commento in testa ora dice che le tabelle tengono tutte le unità, che la percezione è dell'AI e che il loader le passa gli eventi di vista; tolto anche «(provisional)» dal titolo della sezione.
3. Shard: `shard_include("perceptionhandler")` e `PerceptionHandler` in testa alla lista di `Shard/modules.lua`. `AttackHandler:DoTargetting` filtra con `Sees`: `if e ~= nil and perception:Sees(e:ID()) then`, più un commento di una riga (radar no, perché `ScoreUnit` legge il tipo). **Perché `Sees` e non lo scorrere di `los`**: `los` contiene anche unità Gaia (il catch-up e l'engine le mandano per ogni ally team diverso), quindi scorrendo `los` servirebbe comunque un controllo «è nemico» sulle tabelle del loader; con `Sees` la definizione di nemico resta una sola (`GetEnemies`) e la modifica è di due righe. Costo: `GetEnemies` crea uno `ShardUnit` per ogni nemico, ma solo quando le reclute superano `counter`, cioè raramente.

**Consegna degli eventi** (già nel loader, verificato con i test): gli oggetti team tengono solo un riferimento ai moduli d'ambito più largo, non li mettono in `self.modules` né in `handlers`, quindi un evento di vista arriva al `PerceptionHandler` una volta sola, tramite l'oggetto ally dell'ally team che vede (`DeliverSight`), anche con due AI Shard nello stesso ally team. Il catch-up (ricarica e cambio di host) rigenera `UnitEnteredRadar`/`UnitEnteredLos` dallo stato `GetUnitLosState` per ogni ally team con AI diverso da quello dell'unità, e solo verso gli oggetti nuovi.

**Righe per file**

| File | Righe |
| --- | --- |
| `shard_runtime/perceptionhandler.lua` | +52 (nuovo) |
| `shard_runtime/loader/types.lua` | −4 |
| `shard_runtime/loader/unitregistry.lua` | +4 −3 |
| `Shard/modules.lua` | +2 −1 |
| `Shard/attackhandler.lua` | +3 −1 |
| `spec/.../shard_runtime/perceptionhandler_spec.lua` | +91 (nuovo) |
| `spec/.../Shard/attackhandler_spec.lua` | +94 (nuovo) |
| `spec/luarules/gadgets/shard_ai_loader_unsynced_spec.lua` | +118 −2 |
| `spec/fixtures/shard_ai_perception/modules.lua` | +4 (nuovo) |

**Test busted** (`lx --lua-version 5.1 test`: 2707 successi, 0 fallimenti, 1 pending di sempre)

- Modulo (6): ambito e nome; entra/esce da LOS; entra/esce da radar; in LOS e radar, esce da LOS → resta su radar; `UnitDead` pulisce tutte e due e solo quell'unità; ID mai visti → `false`.
- Loader (5), con un tipo `PercAI` (la fixture `SpecAI` più il `PerceptionHandler` vero del runtime): un modulo per ally team, lo stesso per le due AI dell'ally team 0, diverso per l'ally team 1; ogni evento di vista arriva una volta al modulo dell'ally team che vede e zero volte all'altro; un'unità distrutta in vista sparisce; dopo una ricarica a partita in corso il catch-up riempie `los` e `radar` secondo `GetUnitLosState` (il finto engine ora legge `world.losStates`); al cambio di host l'ally team preso in carico ha le unità che vede, l'altro resta com'era.
- `AttackHandler` (2), caricato da solo con il `PerceptionHandler` vero: un nemico solo su radar non è attaccato e le reclute restano; con due nemici visti nella stessa cella e uno non visto da solo (che sarebbe il bersaglio più debole) attacca la cella dei visti.

**Mutazioni** (13, tutte prese; numero di test falliti sui tre file di spec)

| Mutazione | falliti |
| --- | --- |
| `AttackHandler` senza `Sees` | 2 |
| `AttackHandler` con `OnRadar` al posto di `Sees` | 2 |
| `UnitLeftLos` non toglie | 3 |
| `UnitLeftRadar` non toglie | 1 |
| `UnitDead` pulisce solo `los` / solo `radar` | 2 / 2 |
| `UnitLeftLos` toglie anche dal radar | 2 |
| `Sees` / `OnRadar` restituiscono `nil` per ID ignoti | 6 / 4 |
| `Scope()` `"team"` | 2 + 4 errori |
| catch-up senza `UnitEnteredRadar` / senza `UnitEnteredLos` | 2 / 2 |
| `DeliverSight` a tutti gli ally team | 3 |

**Controlli**: StyLua 2.5.2 pulito su tutti i file toccati (il modulo nuovo in CRLF come gli altri). EmmyLua 0.24.0: 20 errori, gli stessi di prima. Nei file toccati un solo warning nuovo: `attackhandler.lua` da 12 a 13, `undefined-field Sees` su `self.ai.perceptionhandler` (il campo non ha tipo); il modulo nuovo ha 3 hint (`self` non usato in `Name`, `internalName`, `Scope`, come gli altri moduli), le spec nessun warning. `run_engine_tests.sh`: `RESULT: ok`, 3 + 3 file. `lx` ha riscritto ancora `.emmyrc.json`: ripristinato, non è nei commit.

**Partite** (`SHARD_MEM_STATS=1`, 15 minuti; nessuna riga `[AI Loader] error`; solo gli errori di sempre: `gui_pip`, `sensor_ranges_jammer_preview`, groundFX, shader, `AdvSky`, `ceg_test_projectile`)

D, Shard contro SimpleAI, due partite, con un contatore temporaneo in `AttackHandler` (tolto, mai committato) che ogni minuto scriveva le ricerche di bersaglio e, in quel momento, nemici totali, `los`, `radar`, reclute:

| Partita | unità Shard ai minuti 1–10 | distrutto | mex | relay (messaggi / ordini / rifiutati) |
| --- | --- | --- | --- | --- |
| T12 #1 | 5 10 11 11 14 12 12 11 0 | min. 9 | 1 solo al min. 1 | 745 / 744 / 1 |
| T12 #2 | 5 10 11 11 13 14 14 15 13 8 0 | min. 11 | idem | 927 / 926 / 1 |
| T11 (7 partite) | — | min. 7–9, una viva | idem | 546–1252 |

| Minuto (partita #2) | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11+ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nemici totali | 5 | 11 | 19 | 24 | 35 | 40 | 41 | 45 | 49 | 56 | 58 → 108 |
| in `los` | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 1 | 3 | 5 | 0 |
| su `radar` | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 3 | 4 | 9 | 0 |

In tutte e due le partite **`AttackHandler` non ha mai cercato un bersaglio**: reclute sempre 0, `counter` sempre 8, ricerche 0. Shard in queste partite non arriva ad avere unità d'attacco reclutate, quindi il filtro non cambia niente nel suo gioco attuale; la percezione però lavora: `los` e `radar` seguono le poche unità nemiche che Shard incontra e tornano a 0 quando Shard non ha più unità. Memoria (partita #2) come T11: medie 0,06–13,5 KB per frame, massimi circa 5.950 KB (la spirale di `PlacementHandler`), heap 9–13,6 MB; dopo la distruzione 0,06 KB.

A, STAI contro SimpleAI (controllo per `types.lua`): unità ai minuti 1/5/10/13: 5 / 36 / 100 / 161; a fine partita 194 unità, 2 fabbriche, 36 mex (contro 147–188 e 15 mex di T11); relay 2309 messaggi, 14421 ordini, 8 rifiutati; memoria media 0,17–0,72 KB per frame, massimo 81 KB, heap 13,1–15,1 MB. Nessun segno di cambiamento: STAI non dichiarava `Perception()`, quindi `omniscient` era già `false`.

**Cosa cambia nel gioco di Shard**: quando avrà reclute, attaccherà solo celle con nemici in LOS dell'ally team; se nessun nemico è in vista non attacca e le reclute aspettano (prima andavano verso la cella più debole di tutta la mappa, anche mai vista). Con il gioco attuale di Shard il cambiamento non si vede nelle partite.

**Problemi e domande**

- **`UnitTaken` arriva come `UnitDead`** (il loader fa così da sempre). Un nemico in LOS che passa a un'altra squadra nemica sparisce da `los` e `radar`; se l'engine non manda un nuovo `UnitEnteredLos` dopo il cambio di squadra (non l'ho verificato), resta fuori finché non esce e rientra in vista. Proposta, non fatta: `UnitDead` del modulo toglie l'unità solo se `engineunit.destroyed` o se l'ID non è più valido; oppure il loader distingue `UnitTaken` da `UnitDead`. Da decidere.
- **`shard_null` non ha oggetti ally**: sotto `shard_null` Shard avvisa «Skipping the loading of PerceptionHandler: no ally object holds it» e `self.ai.perceptionhandler` è `nil`. Non dà errori solo perché il `game` di `shard_null` restituisce `GetEnemies() = {}`. Se `shard_null` deve far girare moduli ally, `ShardNull.Start` dovrebbe creare anche uno `ShardAlly`: non l'ho fatto, fuori dal compito.
- Nessun test prova che `Shard/modules.lua` includa il modulo: la spec del loader usa la fixture, e sotto `shard_null` il modulo non si carica (punto sopra). Le partite D lo provano (le righe del contatore leggevano `self.ai.perceptionhandler`).
- Il warning EmmyLua in `attackhandler.lua` si toglierebbe con un `---@type` sul locale, ma `PerceptionHandler = class(Module)` non produce un tipo; lasciato.

**Commit**

1. `21507320d0` Shard runtime: PerceptionHandler, an ally team module with the units its ally team sees in LOS and on radar
2. `55bd31fb9e` Shard loader: no Perception() nor omniscient field; the unit tables hold every unit
3. `a9cf6d542f` Shard example: AttackHandler targets only the enemies its ally team sees in LOS

### T13 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Fatto**

1. `shard_null/boot.lua`: quattro funzioni locali (`NewAPI`, `NewGlobal`, `NewAlly`, `SetupTeam`) composte in `ShardNull.Start`, che si legge come passi: crea il globale, l'ally (ally team 0), collega il team, poi `Prepare()` di global, ally, team. Commento di due righe in testa a `Start`. I campi sono quelli del loader (`LoadAIType`, `GetAlly`, `SetupAI`): `loaded`, `fullname`, `api`, `AIs`, `allyId` (ally e team), `ally.global`, `ai.global`, `ai.ally`, l'AI dentro `AIs` di tutti e due. Nessuna funzione nuova esportata: i test chiamano `ai.global`, `ai.ally`, `ai` nell'ordine.
2. **`api` propria per ogni oggetto** (`NewAPI`): prima `Start` faceva un solo `require("shard_runtime/api")`, che sotto `shard_null` è in cache, quindi i tre oggetti avrebbero condiviso `game` e `map`; e `ShardAI:Init` scrive `self.game.ai = self`, così `game.ai` di tutti sarebbe stato il team. `NewAPI` toglie da `package.loaded` `api`, `game` e `map` di `shard_null` e li ricarica, come `NewAPI` del loader rilegge `api.lua` per ogni oggetto.
3. `Shard/boot.lua`, Shard, STAI, loader: non toccati. (STAI sotto `shard_null` non usa `ShardNull.Start`: chiama `ai:Init()` da sé, come prima.)

**Lasciato fuori dal loader, e perché**

- `SetSchedule` (`MScheduler`/`scheduler` sugli oggetti ally e global): lo scheduler condiviso non esiste sotto `shard_null`. Effetto: i moduli dell'ally girano tutti nell'`Update` di ogni frame (oggi solo `PerceptionHandler`, che non ha `Update`). Il team mantiene `MScheduler` dalla sua classe, come prima.
- `outbox`, host, semi (`randomseed`), `side`, `alliedTeamIds`/`enemyTeamIds`, tabelle delle unità (`NewUnitTables`), `Shard.alliesByAllyID`/`Shard.globals`: servono solo al loader; nessun modulo di Shard li legge sotto `shard_null`. Niente si è rotto senza di loro.

**Righe per file**

| File | Righe |
| --- | --- |
| `shard_runtime/shard_null/boot.lua` | +48 −4 |
| `spec/.../shard_runtime/shard_null_spec.lua` | +61 |

**Test busted** (`lx --lua-version 5.1 test`: 2710 successi, 0 fallimenti, 1 pending di sempre; i 4 test di prima invariati)

- Oggetti e modulo: nessuna riga «Skipping the loading»; `ai.ally`/`ai.global` con `Scope()` giusto, `ai.ally.global == ai.global`, `allyId` 0, `AIs` = `{ ai }` per tutti e due, tutti e due `loaded`; `ai.perceptionhandler` esiste ed è `ai.ally.perceptionhandler`; `ai.ally.modules` = `{ PerceptionHandler }`, `ai.global.modules` vuoto; `ai.modules` 5, tutti di ambito team; `game` dell'ally diverso da quello del team e `ai.ally.game.ai == ai.ally`.
- Ordine di `Init`: dalle righe `Info` «… - playing: …» stampate da ogni `Init` (catturate sostituendo `_G.print`), proprietari `"global"`, `"ally 0"`, `0`.
- Vista: `ai.ally:UnitEnteredLos(42, …)` → `Sees(42)` vero; `UnitLeftLos` → falso.

**Mutazioni** (11, tutte prese; falliti + errori nella spec di `shard_null`, 7 test)

| Mutazione | falliti |
| --- | --- |
| `ally:Prepare()` tolto (ally mai inizializzato) | 2 + 1 errore |
| `global:Prepare()` tolto | 2 |
| ordine `Prepare` invertito (team, ally, global) | 5 + 1 errore |
| ally prima di global | 1 |
| `ai.ally` non collegato | 1 + 1 errore |
| `ai.global` non collegato | 1 errore |
| `ally.global` non collegato | 1 |
| AI non in `ally.AIs` / non in `global.AIs` | 1 / 1 |
| `api` condivisa (cache di `package.loaded` non tolta) | 1 |
| ally team 1 al posto di 0 | 2 |

**Controlli**: StyLua 2.5.2 pulito sui due file. EmmyLua 0.24.0: 20 errori, gli stessi; `boot.lua` senza diagnostiche; la spec ha solo l'hint di prima (`self` non usato in `ProgressQueue`). Un warning nuovo (`pcall(require, …)`, `param-type-mismatch`) l'ho tolto passando una closure a `pcall`. `run_engine_tests.sh`: `RESULT: ok`, 3 + 3 file. `lx` ha riscritto ancora `.emmyrc.json`: ripristinato, non è nel commit.

**Problemi e domande**

- `Prepare()` assegna i globali `ai`, `game`, `map`: nell'ordine global → ally → team l'ultimo è il team, come si aspetta `Shard/boot.lua` (con l'ordine invertito `ai` diventa lo `ShardGlobal`, ed è così che la mutazione fa fallire 5 test).
- Nessun aiuto aggiunto per consegnare eventi o `Update`: per ora chiamare `ai.global`, `ai.ally`, `ai` a mano basta (lo fa il test di vista in tre righe).

**Commit**

1. `9cc285d311` Shard null: Start builds a ShardGlobal and a ShardAlly and prepares global, ally, team as the loader does

### T14 (agente locale, 24 novembre 2026) — verificato dal coordinatore

**Dove stava la `collect` e dove sta ora**

Il vecchio `luarules/gadgets/AILoader.lua` (`git show 3ad8f3fb^:luarules/gadgets/AILoader.lua`) ne ha **due**:

- r. 276, in `gadget:Initialize`, dopo il catch-up delle unità: `collectgarbage('collect')` senza condizione. **Non l'ho rimessa**: non ha soglia né valori, gira una volta al caricamento e non è la rete di sicurezza descritta nel compito. Se va rimessa anche questa, il punto corrispondente è la fine di `Lifecycle.CatchUpAfterReload`. Da decidere.
- r. 357–369, la rete di sicurezza, in `gadget:GameFrame`, dentro il ciclo sulle AI, dopo `thisAI:Update()` della **prima** AI (`if i == 1 and n % 121 == 0`): `ramuse = gcinfo()`, se `ramuse > garbagelimit` → `collectgarbage("collect")`, poi `newgarbagelimit = math_min(1000000, gcinfo() + basememlimit + pershardmemlimit * numShards)` e una riga di log. I valori (r. 324–328): `basememlimit = 200000`, `pershardmemlimit = 50000`, `garbagelimit` parte da `basememlimit`. A ogni AI caricata (r. 340–342, in `SetupAI`): `garbagelimit = math_min(1000000, garbagelimit + pershardmemlimit)`, riga di log, `numShards + 1`.

Ora:

| Vecchio | Nuovo |
| --- | --- |
| r. 324–328, locali del gadget | `loader/memstats.lua` r. 26–32, stessi nomi e valori |
| r. 340–342, in `SetupAI` dopo `Prepare` | `memstats.lua` `AIAdded` (r. 76), chiamata da `lifecycle.lua` `AddAI` (r. 65) quando l'AI è caricata; stessa riga di log |
| r. 357–369, `GameFrame`, dopo l'`Update` della prima AI | `memstats.lua` `SafetyNet` (r. 91, la `collect` a r. 96), chiamata in `ShardAILoader.lua` `GameFrame` r. 164, dopo `UpdateAll()` e `RunScheduledTurn()`, prima di `FlushOrders`; stessa condizione (`n % 121 == 0`, `ramuse > garbagelimit`), stesso calcolo, stessa riga di log |

Differenze inevitabili: oggi l'`Update` di tutte le AI è in `UpdateAll` (più i turni dello scheduler), quindi la rete scatta dopo l'`Update` di **tutte** le AI del frame, non fra la prima e le altre; `if i == 1` diventa «una volta per frame, se il client ospita AI» (`GameFrame` esce prima se non ne ospita). La riga di log dice ancora «STAIs», identica alla vecchia. `memoryRecord` non l'ho rimesso: c'è già il picco di `MemStats` («Shard memory record»). `AddAI` è chiamata anche al cambio di host, come la vecchia `SetupAI`; `StopAI` non abbassa il limite, come prima.

**`maxInstances`**: `MAX_INSTANCES_PER_AI_TYPE = 2` in testa a `loader/types.lua` (r. 17). `AtInstanceLimit` (r. 192) conta le AI di quel tipo in `Shard.AIs`, cioè quelle che **questo client** fa girare; `SetupAI` la chiama subito dopo la riga «AI Player … is a …» (r. 217) e, al limite, restituisce `nil` prima di caricare il tipo o creare oggetti ally: nessun errore, le altre AI vanno avanti. Riga: `[AI Loader] AI team 2 not started: 2 SpecAI AIs already run on this client, the most one AI type may have`. Una AI fermata (`StopAI`) libera il posto.

- **Da notare**: il limite è per client host, non per partita; con due host (un ally team ciascuno) le AI di un tipo possono essere 2 per host. Se lo volete per partita va contato nel synced. Da decidere.
- **Per la spec**: `Types.Setup` accetta un campo facoltativo `maxInstancesPerAIType` che sostituisce la costante. Il loader non lo passa mai; la spec lo mette a 3 per i test di sempre (il mondo di prova ha tre team SpecAI, 42 righe dipendono dal team 2) e a `nil` (la costante vera) per i test del limite.

**Righe per file**

| File | Commit GC | Commit limite |
| --- | --- | --- |
| `luarules/gadgets/ShardAILoader.lua` | +3 | |
| `loader/lifecycle.lua` | +4 −1 | |
| `loader/memstats.lua` | +49 | |
| `loader/types.lua` | | +33 −1 |
| `spec/.../shard_ai_loader_unsynced_spec.lua` | +87 −1 | +46 −1 |

**Test busted** (2716 successi, 0 fallimenti, 1 pending di sempre; ognuno dei due commit passa da solo: il primo dà 2714). Il finto engine: `gcinfo()` e `collectgarbage("count")` leggono `world.heap`; `collectgarbage("collect")` va in `SpecLog` e mette `world.heap = world.heapAfterCollect`.

- Limite (2): tre team SpecAI → partono 0 e 1, il 2 no, niente ally per l'ally team 1, una riga di log per il team 2 e nessuna per 0 e 1; due SpecAI e un PercAI → partono tutti e tre.
- GC (4): righe «AI 0/1/2 (SpecAI) using 200 MB RAM, adjusting limit to 250/300/350 MB»; nessuna `collect` con heap uguale al limite o su frame non multipli di 121, una con heap sopra a frame 242; la `collect` viene dopo l'ultimo `Update` del frame in `SpecLog`, riga «3 STAIs using 350 MB RAM > 350 MB limit, … adjusting limit to 450 MB», poi 450000 non raccoglie e 450001 sì; tetto a 1000 MB.

**Mutazioni** (16, tutte prese; falliti + errori nella spec del loader, 67 test)

| Mutazione | falliti |
| --- | --- |
| nessun limite | 1 |
| limite uno in meno | 18 + 26 errori |
| conta tutti i tipi | 1 |
| costante 3 | 1 |
| senza riga di log | 1 |
| `SafetyNet` non chiamata | 2 + 1 errore |
| `SafetyNet` prima di `UpdateAll` | 1 |
| ogni 120 frame | 2 + 1 errore |
| `>=` al posto di `>` | 2 |
| limite non aggiornato dopo la `collect` | 1 |
| base 250 MB / per AI 60 MB | 2 + 1 errore / 2 + 1 errore |
| senza tetto di 1 GB | 1 |
| `AIAdded` non chiamata | 3 |
| `numShards` non contato | 1 |
| nessuna `collect` | 1 + 1 errore |

**Controlli**: StyLua 2.5.2 pulito sui 5 file. EmmyLua 0.24.0: 20 errori, gli stessi; nei file toccati le stesse diagnostiche di prima (solo hint). `run_engine_tests.sh`: `RESULT: ok`. `.emmyrc.json` riscritto da `lx`, ripristinato.

**Partita A** (STAI contro SimpleAI, `SHARD_MEM_STATS=1`, 15 minuti; nessuna riga `[AI Loader] error`, solo gli errori di sempre: `gui_pip`, `sensor_ranges_jammer_preview`, groundFX, shader, `AdvSky`, `ceg_test_projectile`)

| | T14 | T12 |
| --- | --- | --- |
| unità STAI min. 1/5/10/13 | 6 / 31 / 90 / 134 | 5 / 36 / 100 / 161 |
| a fine partita | 185 unità, 2 fabbriche, 28 mex | 194, 2, 36 |
| relay (messaggi / ordini / rifiutati) | 2658 / 15057 / 13 | 2309 / 14421 / 8 |
| memoria per frame, medie | 0,18–0,70 KB | 0,17–0,72 KB |
| memoria per frame, massimo | 159 KB (min. 11) | 81 KB |
| heap | 13,2–14,8 MB | 13,1–15,1 MB |
| picco («Shard memory record») | 15.582 KB | — |

La rete di sicurezza ha scritto una sola riga, «AI 0 (STAI) using 200 MB RAM, adjusting limit to 250 MB»: con l'heap sotto i 16 MB non scatta mai, come atteso; nessuna `collect` nella partita. Le differenze nei numeri di STAI sono nella variabilità fra partite già vista in T11/T12; il massimo di 159 KB in un frame è un picco isolato (gli altri minuti 15–62 KB).

**Commit**

1. `ba961659f0` Shard loader: the old loader's garbage collection safety net, with the same limits, every 121 frames after the AIs' Update
2. `7d7a0b0d5f` Shard loader: at most 2 AIs of one type per client; the teams beyond stay without AI and the log says why

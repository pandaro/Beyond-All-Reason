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

## Compito attuale

### T7: riordino di `ShardAILoader.lua` in più file, senza cambiare il comportamento

**Impegno: alto.** Tocca tutto il loader e il risultato deve fare esattamente quello che fa oggi; la difficoltà è tenere ogni dettaglio (ordine delle chiamate, chi riceve cosa, errori contenuti, nessuna allocazione per frame) mentre si sposta il codice. È anche un compito di stile: l'utente vuole il codice ordinato, non solo funzionante.

**Prima di tutto** leggi `.ai-notes/drafts/mappa-shardailoader.md`: la mappa del file com'è, i sette punti di disordine e le decisioni (sezione «Decisioni» in fondo).

**Decisioni**

- Si divide in più file, uno per compito (utente). **Non si riscrive da capo**: si sposta e si riordina il codice che c'è.
- Stile dell'utente: funzioni piccole e riutilizzabili, con nomi che dicono cosa fanno, composte in funzioni più grandi («macro») che si leggono come una sequenza di passi.
- I file stanno in `luarules/gadgets/ai/shard_runtime/loader/`. Ognuno **restituisce una tabella** con le sue funzioni (`local Relay = VFS.Include(LOADER_PATH .. "relay.lua")`); **nessun globale**: l'ambiente delle AI ricade sul gadget, quindi un globale del loader sarebbe visibile a STAI.
- Dentro i file solo `local function`; `gadget:Metodo` solo per i call-in dell'engine. I metodi di oggi che non sono call-in (`NewAPI`, `LoadAIType`, `GetAlly`, `SetupAI`, `AddAI`, `StartAIs`, `CatchUp`, `HashGameID`) diventano funzioni dei file; se le spec li chiamano come `gadget:…`, aggiorna solo il modo di raggiungerli nelle spec e scrivilo nei risultati.
- I file synced non includono niente di unsynced e restano deterministici.

**File** (nomi proposti; se uno non torna, proponi un nome migliore nei risultati, non cambiarlo da solo):

| File | Lato | Contenuto |
| --- | --- | --- |
| `ShardAILoader.lua` | entrambi | ricerca dei team AI, controlli iniziali, i call-in dell'engine: ognuno una macro di poche righe |
| `loader/hosts.lua` | synced | `IsActive`, `ChooseSuccessor`, `RegisterHosts`, `aiHostPlayer` |
| `loader/relay.lua` | synced | stato e controlli del relay, `AddOrder`, `GiveOrders`, `Reject`, contatori, riga di `Shutdown` |
| `loader/loader.lua` | unsynced | runtime, tipi, oggetti, seme, fallimenti del caricamento, avvio (`StartAIs`), arresto (`StopAI`), `CatchUp`, cambio di host |
| `loader/delivery.lua` | unsynced | `Call`, errori (`ReportError`, elenco e riepilogo), consegna degli eventi |
| `loader/unitregistry.lua` | unsynced | tabelle di unità per AI e anello delle unità morte |
| `loader/memstats.lua` | unsynced | misura della memoria per frame e picco di `gcinfo()` |

**Ordine dentro ogni file**: un commento in testa (scopo del file, lato, cosa è provvisorio), costanti, stato, funzioni piccole, funzioni composte, la tabella restituita. Stesso ordine nei due lati.

**Punti precisi**

1. `GameFrame` si deve leggere come una sequenza di passi, per esempio: avvio la prima volta, `Update` di tutti, invio degli ordini, scadenza delle unità morte, misura della memoria.
2. `Ready()` oggi fa due cose (controlla e avvia le AI): separale, con un nome per ciascuna, e chiamale esplicitamente dove serve.
3. Le parti provvisorie (eventi a tutti, tabelle di unità onniscienti, `Update` a ogni frame) stanno in `delivery.lua` e `unitregistry.lua` e sono elencate nel commento in testa a quei file, senza nomi di compiti.
4. Lo stato sparso (le variabili della memoria, dell'anello dei morti, dei fallimenti) va nel file del suo compito.
5. Nessuna allocazione nuova nei percorsi per frame: passare per una tabella di funzioni (`Delivery.Call`) è ammesso, ma metti in `local` all'inizio del file le funzioni usate a ogni frame, come fa oggi il loader con le funzioni `Spring.*`.

**Rete di sicurezza**

- **Tutte le spec di oggi devono passare.** Si cambiano solo dove raggiungono funzioni che prima erano `gadget:…` o dove caricano file nuovi; ogni modifica alle spec va elencata e motivata. Nessuna asserzione tolta o allentata.
- Un test nuovo: dopo il caricamento, nessuna funzione del loader è visibile nell'ambiente di un tipo di AI né in `_G` (controlla i nomi delle funzioni dei file nuovi).
- Un commit per file estratto, nell'ordine che preferisci, con la suite verde a ogni commit (`lx --lua-version 5.1 test`).
- Alla fine: `run_engine_tests.sh` e la partita A di T5c con `SHARD_MEM_STATS=1`, nessuna riga `[AI Loader] error`, righe della memoria simili a quelle di T6b.

**Fuori dal compito**: qualunque cambio di comportamento, anche piccolo e anche se migliora qualcosa. Annotalo e basta. Non toccare STAI.

**Commit**, in inglese: uno per file estratto, poi uno per il riordino finale del gadget se serve.

**Nei risultati**: righe per file prima e dopo, l'elenco delle modifiche alle spec con il motivo, `GameFrame` e un call-in di unità come sono ora (incollati), i nomi che cambieresti, ogni punto dove spostare il codice ti ha fatto vedere un difetto (annotato, non corretto).

## Risultati

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

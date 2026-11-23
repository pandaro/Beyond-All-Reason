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

### T6: errori di caricamento contenuti, unità morte, misura della memoria per frame

**Impegno: medio.** Tre correzioni circoscritte, con le cause già individuate; serve cura nei test (uno riproduce un errore visto in partita) e nel non allocare a ogni frame.

**Contesto**: nella partita dell'utente (STAI contro SimpleAI, circa 30 minuti di gioco a velocità 10, vinta da STAI; relay 8626 messaggi, 47217 ordini, 1 rifiutato) sono uscite due righe:
- `[AI Loader] error in STAI team 1, Update: unittype.lua:12: attempt to index field 'def' (a nil value)`, da `STAI/buildersbst.lua:122` (argomenti di un `EchoDebug`, calcolati anche con il debug spento) via `game:GetUnitByID(self.assistant):Name()`;
- lo stesso errore da `STAI/bomberhst.lua:192` (`game:GetUnitByID(id):Name()` sulle unità delle celle di `LosHST`).
Causa: da T5b `UnitDestroyed` chiama `Shard:unshardify_unit`; STAI tiene ancora ID di unità morte, e `shardify_unit` crea un `ShardUnit` nuovo per un ID che non esiste più, con `UnitDefs[nil]` come definizione. Il vecchio loader non toglieva mai gli oggetti, e il difetto restava nascosto. Regola dell'utente: **un errore deve far cadere l'AI, mai la battle**.

**Lavoro**

1. **`AddAI` protetto.** Il caricamento di un tipo di AI e di un'AI (`LoadAIType`, `SetupAI`, `boot.lua`, i file inclusi) passa da `xpcall` con traceback. Se fallisce: una riga `[AI Loader] error loading <AI> for team <id>: <traceback>`, quell'AI non viene caricata (nessun oggetto lasciato a metà nelle liste di `Shard`), le altre AI e il resto del LuaRules continuano. Se fallisce il tipo, tutte le AI di quel tipo restano non caricate, con una riga per team. Vale sia in `Initialize` sia nel cambio di host.
   Test: busted (un tipo di AI finto il cui `boot.lua` va in errore; uno il cui modulo va in errore in `Init`) e con lo strumento (`run_engine_tests.sh`, un test in `luaui/Tests/shard/` che carica un tipo rotto e verifica che il LuaRules sia vivo dopo).
2. **Unità morte: tempo di grazia.** In `UnitDestroyed` il `ShardUnit` non si toglie subito: va in una coda di rimozione e viene tolto da `Shard.unitsByID` dopo 900 frame (30 secondi di gioco). Nel frattempo `game:GetUnitByID(id)` restituisce l'oggetto vecchio, con il suo tipo e il suo nome, come faceva il vecchio loader.
   - La coda non alloca a ogni frame: array circolare o due array paralleli riusati (ID e frame di scadenza), svuotati in `GameFrame` dalla testa finché scadono.
   - Se lo stesso ID viene riusato dall'engine per un'unità nuova prima della scadenza, `UnitCreated` deve sostituire l'oggetto vecchio con uno nuovo (e la scadenza vecchia non deve togliere quello nuovo).
   - `shardify_unit` di un ID che non esiste e non è in cache: invariato per ora, ma scrivi nei risultati cosa succede e proponi cosa fare.
   Test busted: l'errore della partita riprodotto (unità creata, distrutta, poi `GetUnitByID(id):Name()` nello stesso frame e 899 frame dopo → nome giusto; 901 frame dopo → l'oggetto è uscito dalla cache); ID riusato prima della scadenza; nessuna tabella nuova in `GameFrame` con la coda piena (conta le tabelle con un `setmetatable` strumentato o con `collectgarbage("count")` stabile su molti frame).
3. **Misura della memoria per frame** (idea dell'utente). In `gadget:GameFrame` del lato unsynced: `collectgarbage("count")` all'inizio e alla fine; il delta è la memoria allocata dal loader e dalle AI in quel frame (con il limite noto: un passo della GC incrementale in mezzo lo riduce, anche sotto zero).
   - Attivata solo se `Spring.GetConfigInt("ShardMemStats", 0) == 1` (impostabile dall'utente in `springsettings.cfg` o con `/set ShardMemStats 1`); spenta non costa nulla oltre a un controllo per frame.
   - Ogni 1800 frame (un minuto di gioco) una riga `[AI Loader] memory per frame: avg <KB> max <KB> over <N> frames, heap <MB>`, poi i contatori ripartono. Niente tabelle nuove.
   - Togli la riga `Shard memory record:` di `Shutdown` se non è più utile, o tienila e spiega perché.
   - Documenta l'opzione in un commento in testa al lato unsynced.
   Test: busted per il calcolo di media e massimo e per lo spegnimento; con lo strumento, una partita breve con l'opzione accesa che scriva almeno una riga.

**Fuori dal compito**: correggere STAI (gli ID vecchi in `buildersbst`, `bomberhst`, `LosHST`, l'`EchoDebug` con argomenti costosi): annotali soltanto.

**Controlli**: StyLua, EmmyLua, `lx --lua-version 5.1 test`, `run_engine_tests.sh`, e una partita A di T5c con `run_engine_game.sh` (15 minuti) con l'opzione della memoria accesa: nessuna riga `[AI Loader] error`, e le righe della memoria nel log.

**Commit**, in inglese: uno per punto.

**Nei risultati**: righe per file, test e mutazioni, le righe della memoria della partita A (tutte), dubbi.

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

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

## Compito attuale

### T3b: due difetti vecchi del runtime

**Impegno: basso.** Due correzioni piccole, già individuate in T3; nessuna decisione da prendere.

1. `shard_runtime/behaviour.lua`, riga 7: `function Module:internalName()` diventa `function Behaviour:internalName()`, stesso valore restituito. Oggi, quando il file viene incluso, cambia il default di tutti i moduli da `"error"` a `"unknown behaviour"`, e il controllo di `ShardAI:LoadModule` sui moduli senza `internalName()` non scatta mai.
   - Test in `shardai_spec.lua` (o in una spec accanto, se più pulito): con `behaviour.lua` caricato, un modulo senza `internalName()` non si carica e produce il `Warn` «has no internal name»; e `Module.internalName` resta `"error"` dopo il caricamento di `behaviour.lua`. Verifica che il test fallisca sul codice di prima.
2. `shard_runtime/shard_null/boot.lua`: carica anche `shardai`, `shardally` e `shardglobal`, nello stesso modo e nello stesso ordine dei file che carica già (dopo `module`), così il ramo `shard_null` ha le classi che `STAI/boot.lua` e `Shard/boot.lua` usano. Se per caricare `shardai.lua` in quel ramo serve altro (globali o file mancanti), non inventarlo: fermati e scrivilo nei risultati.

Controlli: StyLua sui file toccati, `lx --lua-version 5.1 test`, partita headless come in T3.

Commit: uno per punto. Nei risultati: righe toccate, output dei test, eventuali problemi del punto 2.

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

### T3b (agente locale, 23 novembre 2026)

**Commit**

1. `9b5a27a61e` «Shard: internalName() di Behaviour, non di Module»: `shard_runtime/behaviour.lua` +1 −1 (riga 7); `shardai_spec.lua` +32 −4: `loadRuntime(extraFiles)` accetta file del runtime in più, e un `describe("behaviour.lua")` con due casi: `Module:internalName()` resta `"error"` dopo `behaviour.lua`; un modulo creato dopo, senza `internalName()`, non si carica (`team.modules` vuoto) e produce una volta «The module with the name noname module has no internal name!». Con la riga vecchia falliscono tutti e due (`9 successes / 2 failures`); con la nuova `11 successes`.
2. `273148b918` «Shard: shard_null carica shardai, shardally e shardglobal»: `shard_runtime/shard_null/boot.lua` +3, tre `require("shard_runtime/…")` subito dopo `module`, nell'ordine `shardai`, `shardally`, `shardglobal`. StyLua (`sort_requires`) non li riordina.

**Punto 2: cosa serve a `shardai.lua`**

Niente in più: al caricamento usa solo `class`, `AIBase` e `setmetatable` (`Spring.Echo` solo se esiste `tracy`). Provato con `lua5.1` da `luarules/gadgets/ai/`: `require("shard_runtime/shard_null/boot")` definisce `ShardAI`, `ShardAlly`, `ShardGlobal` (`Scope()` `"ally"`, `"global"`). Il ramo resta comunque non avviabile così com'è, per un motivo che non tocca questo compito: `require("STAI/boot")` si ferma prima, su `shard_include("ai")` (riga 6 di `shard_null/boot.lua` usa `require(file)`, che cerca `ai.lua` su `package.path`, non nella cartella dell'AI). Non l'ho cambiato.

**Controlli**

- StyLua pulito sui tre file toccati.
- `lx --lua-version 5.1 test`: `2561 successes / 0 failures / 0 errors / 1 pending` (T3: 2559). `.emmyrc.json` rimesso com'era.
- Headless come in T3: codice d'uscita 0, righe d'errore identiche a T3, `PASS: ai_stai_factory_rect.lua` ×2.

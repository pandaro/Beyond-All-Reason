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

### T3: gli ambiti nel runtime (`Scope()`, `ShardAlly`, `ShardGlobal`)

**Impegno: alto.** Cambia come `ShardAI:Init` carica i moduli e introduce due classi nuove; da qui dipendono il loader, lo scheduler e la consegna dei callback. Gli errori possibili (un modulo istanziato due volte, un evento ricevuto due volte, una dipendenza verso il basso) non si vedono in partita finché non c'è il loader: li devono prendere i test.

**Prima di tutto** leggi in `.ai-notes/proposta-architettura.md` i paragrafi «Tre ambiti: globale, ally team, team» e «Gli oggetti di ogni ambito», e in `.ai-notes/drafts/AILoader.lua` le funzioni `LoadAIType`, `GetAlly`, `SetupAI` e `StartAIs`: mostrano chi crea gli oggetti, con quali campi e in che ordine (globale → ally → team).

**Decisioni già prese dall'utente**

- `Scope()` è obbligatorio, senza default.
- Anche i contenitori dichiarano il proprio ambito con lo stesso metodo `Scope()` (non con un campo).
- In questo compito **tutti i moduli esistenti dichiarano `"team"`**, MapHST e LosHST comprese: oggi usano `self.ai.id`, `game:GetTeamID()` e `self.ai.schedulerhst`, quindi cambiano ambito solo quando verranno adattate, nella fase di porting di STAI. Il comportamento in partita resta identico.

**Lavoro**

1. `shard_runtime/module.lua`: `Module:Scope()` che restituisce `"error"`, con un commento `---` nello stile di `internalName()` («overriding this is *mandatory*»), che elenca i tre valori validi e cosa significano.
2. `shard_runtime/shardai.lua`:
   - `ShardAI:Scope()` restituisce `"team"`.
   - `ShardAI:Init` scorre `modules.lua` come oggi. Per ogni classe di modulo legge `Scope()` (sulla classe, prima di creare l'istanza) e:
     - ambito uguale a quello del contenitore: crea l'istanza, `SetAI`, la mette in `self[internalName]` e in `self.modules`, poi `Init` come oggi;
     - ambito più largo (`"ally"` o `"global"` visti dal team, `"global"` visto dall'ally): mette in `self[internalName]` l'istanza che sta in `self.ally` o `self.global`, **senza** aggiungerla a `self.modules`; se il contenitore di sopra manca, o non ha quel modulo, il modulo non si carica e c'è un `Warn`;
     - ambito più stretto (un modulo `"team"` visto da `ShardAlly` o `ShardGlobal`): lo salta senza avvisi;
     - valore mancante o sconosciuto: non si carica, con un `Warn` che dice il nome del modulo e i valori validi. L'avviso esce una volta per classe di modulo, non una volta per contenitore o per AI.
   - Restano i controlli di oggi su `internalName` `"error"` e sui nomi duplicati.
   - `AddModule` accetta solo moduli dell'ambito del contenitore; altrimenti `Warn` e niente.
   - Difetto da correggere: `newmodule = m()` crea una variabile globale; diventa `local`.
   - I callback (`Update`, `UnitCreated`, `UnitBuilt`, …, `GameEnd`) continuano a scorrere solo `self.modules`: così un modulo condiviso riceve un evento una volta sola, dal suo contenitore. Non cambiare ora chi riceve cosa: la consegna mirata è un compito successivo.
3. `shard_runtime/shardally.lua` e `shard_runtime/shardglobal.lua`, nuovi, nello stile di `shardai.lua`:
   - `ShardAlly = class(ShardAI)`, `Scope()` `"ally"`, campi `allyId`, `AIs`, `global`; `ShardGlobal = class(ShardAI)`, `Scope()` `"global"`, campo `AIs`. Li riempie il loader (come nella bozza); un commento `---` in testa a ogni file elenca i campi e chi li imposta.
   - Non caricano behaviour né `behaviourfactory`: i behaviour sono sempre di team.
   - `Name()` e `internalName()` come in `ShardAI`.
   - Aggiungili ai file del runtime caricati all'avvio, subito dopo `shardai`, sia in `spring_lua/boot.lua` sia dove li carica `shard_null`.
4. `Warn`, `Info`, `EchoDebug` di `AIBase` e `Module` non devono andare in errore in un modulo condiviso, dove `game:GetTeamID()` non ha un team: al posto del team mostrano l'ambito (`ally <allyId>` o `global`). Scegli tu dove farlo con la modifica più piccola; motiva la scelta nei risultati.
5. `Scope()` che restituisce `"team"` in tutti i moduli di STAI e Shard (le classi con `class(Module)`: 21 in `STAI/`, 6 in `Shard/`, comprese le `nullmodule.lua`), subito dopo `internalName()`, senza toccare altro.
6. Test busted in `spec/luarules/gadgets/ai/shard_runtime/` (stessa impostazione della spec di T2), con classi di modulo finte e contenitori costruiti a mano come fa la bozza del loader:
   - modulo senza `Scope()` e modulo con valore sconosciuto: non caricati, un solo `Warn` per classe anche con più AI;
   - due AI nello stesso ally team condividono la stessa istanza del modulo `"ally"`; AI di ally team diversi hanno istanze diverse; tutte condividono l'istanza del modulo `"global"`; ogni AI ha la propria istanza del modulo `"team"`;
   - da un team `self.ai.<internalName>` raggiunge i moduli dei tre ambiti; da un modulo `"ally"` non si raggiungono moduli `"team"`; da un modulo `"global"` non si raggiungono moduli `"ally"` né `"team"`;
   - `Init` di ogni modulo condiviso gira una volta sola; un evento passato a team, ally e global arriva una volta a ogni modulo;
   - senza `ally` e `global` (come nel ramo `shard_null`), un'AI con soli moduli `"team"` si comporta come prima; un modulo `"ally"` non si carica, con `Warn`;
   - `Warn` da un modulo `"ally"` e da uno `"global"` non va in errore e mostra l'ambito.

**Commit**, in quest'ordine, così nessuno lascia il branch rotto:

1. punto 5 (`Scope()` `"team"` in tutti i moduli): da solo non cambia nulla;
2. punti 1–4 e 6 (runtime e test).

**Controlli**: StyLua sui file toccati, EmmyLua senza errori nuovi, `lx --lua-version 5.1 test`, partita headless come in T2 (in partita il codice nuovo non gira ancora: serve solo a vedere che non si rompa nulla).

**Nei risultati**: righe toccate per file, output dei test, dove hai messo la gestione del punto 4 e perché, qualunque punto in cui il codice di Shard ti ha costretto a scostarti da questo compito, dubbi.

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

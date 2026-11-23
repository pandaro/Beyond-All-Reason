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

### T2: include per tipo di AI, con ambiente e cache

**Impegno: alto.** È il primo pezzo del runtime che cambia comportamento: tocca come ogni file di ogni AI viene eseguito, e gli errori qui (classi che si sovrascrivono, file eseguiti due volte, percorsi che non combaciano) si vedono solo più avanti e lontano dalla causa.

**Perché.** Oggi ogni istanza di STAI riesegue tutti i suoi file: con 3 STAI, `maphst.lua` gira 3 volte e la classe `MapHST` viene ridefinita 3 volte nello stesso ambiente globale; due tipi di AI diversi con una classe dallo stesso nome si sovrascrivono. Con questo compito ogni tipo di AI ha il proprio ambiente e ogni suo file gira una volta sola. Le istanze dei moduli restano una per AI: gli ambiti (`Scope()`) sono un compito successivo.

1. Prima di tutto leggi `git show 3ad8f3fb^:luarules/gadgets/ai/shard_runtime/spring_lua/boot.lua` e `.ai-notes/drafts/AILoader.lua` (funzione `LoadAIType`), che è chi chiamerà la nuova firma.
2. `shard_runtime/spring_lua/boot.lua`: `shard_generate_include_func(runtime_path, ai_path, env)`, con `env` facoltativo.
   - Senza `env`: comportamento identico a oggi, riga per riga (nessuna cache, `VFS.Include(file)`).
   - Con `env`:
     - esegue il file con `VFS.Include(file, env)`;
     - tiene una cache per funzione generata (cioè per tipo di AI), con chiave il percorso risolto in minuscolo (i percorsi VFS non distinguono maiuscole e minuscole);
     - alla seconda richiesta dello stesso file restituisce il valore memorizzato senza rieseguirlo; memorizza anche un risultato `nil` o `false` (usa un valore sentinella, non `cache[k] or ...`);
     - se il file non esiste: stessi messaggi di oggi, niente in cache.
   - Resta nello stile del file (commento `---` con `@param env`, stessi nomi). Nessuna allocazione nei percorsi eseguiti a ogni frame: questa funzione gira solo al caricamento.
3. Test busted in `spec/luarules/gadgets/ai/shard_runtime/` (segui la disposizione e lo stile di `spec/luarules/gadgets/`, con i builder di `spec/builders/` se servono; `VFS.FileExists` e `VFS.Include` simulati sopra una tabella di file finti):
   - due tipi di AI, ognuno con un file che definisce una classe globale `Foo`: le due `Foo` restano distinte nei due ambienti, e nessuna finisce nell'ambiente globale;
   - un file incluso due volte dallo stesso tipo gira una volta e restituisce entrambe le volte lo stesso valore;
   - lo stesso file chiesto con maiuscole diverse non viene rieseguito;
   - un file che restituisce `nil` non viene rieseguito;
   - lo stesso file in due tipi di AI diversi gira una volta per tipo;
   - senza `env`, due chiamate eseguono il file due volte (comportamento di oggi).
   Comando: `lx --lua-version 5.1 test`.
4. `STAI/boot.lua` e `Shard/boot.lua`: togli i rami `elseif game_engine` rimasti (erano della vecchia struttura). Restano `if ShardSpringLua` con il `return` e il ramo `else` di `shard_null`.
5. Non toccare `AILoader.lua`, i moduli di STAI né altri file del runtime.
6. Aggiorna il tuo `CLAUDE.local.md` (locale, non committarlo), «Decisioni da rispettare», punto 1: `Scope()` è **obbligatorio**, senza default. Un modulo senza `Scope()`, o con un valore diverso da `"team"`, `"ally"`, `"global"`, non si carica e il runtime lo segnala con `Warn`. Decisione dell'utente del 23 novembre 2026: preferisce le cose esplicite ai default. Non serve ancora nel codice: vale dal compito sugli ambiti.

Controlli: `stylua --check --respect-ignores` sui file toccati, `emmylua_check -c .emmyrc.json .` senza errori nuovi, e la partita headless di T1 (gioco che parte e si chiude, nessun errore nuovo che citi `shard` o `STAI`).

Commit: uno per i punti 2 e 3, uno per il punto 4. Nei risultati: output dei test, righe toccate, esito di headless e controlli, dubbi sul formato delle spec o sulla firma.

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

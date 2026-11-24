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
- Un cambio al framework (`shard_runtime/`, `ShardAILoader.lua`) solo se il compito lo chiede, in un commit a parte che inizia con «Shard …».
- Test con l'engine vero: `.ai-notes/tools/run_engine_tests.sh`; il `PASS` del test runner di BAR non conta. Partite: `.ai-notes/tools/run_engine_game.sh`.
- Strumenti fissati: StyLua 2.5.2 ed EmmyLua 0.24.0 (`emmylua_check`) in `~/.local/bin`, da chiamare con il percorso intero; `lx` è in `/usr/local/bin`. `lx test` riscrive `.emmyrc.json`: ripristinalo, non committarlo.

## Compito attuale

### S2: scheduler — le liste nella classe, via `SchedulerHST`

**Impegno: medio.** Punto 1 di `nuovo-stai.md` (deciso). STAI passa allo scheduler del framework (`shard_runtime/loader/scheduler.lua`, guida §Scheduler) **senza cambiare cosa gira e quando**.

**Lavoro**

1. **Liste nella classe**: `STAI.MScheduler` e `STAI.BScheduler` in `STAI/ai.lua`, con gli stessi nomi e lo stesso ordine di `SchedulerHST.MScheduler` / `BScheduler` (anche le righe commentate, `OverviewHST` e `BomberBST`, restano commentate come oggi).
2. **Via `SchedulerHST`**: `git rm` di `STAI/schedulerHST.lua`; tolti `shard_include("schedulerhst")` e `SchedulerHST` da `STAI/modules.lua`.
3. **Via i controlli di turno** in testa agli `Update` dei moduli e dei behaviour elencati (`self.ai.schedulerhst.moduleTeam ~= self.ai.id ...`, `behaviourTeam ~= ...`): il runtime chiama solo nel turno. Prima di toglierne uno, guarda se **prima del controllo** c'è codice che gira ogni frame (contatori, timer): se c'è, scrivilo nei risultati e decidi in modo che il comportamento resti uguale (per esempio un contatore che contava i frame deve continuare a contare i frame).
4. **Casi speciali, da non cambiare nel comportamento**:
   - `BomberBST` e `ScoutBST:Draw`: **restano come sono** (decisione dell'utente). `BomberBST:Update` è tutto commentato; `Draw` dei behaviour non lo chiama nessuno.
   - `MexUpBST` non è creato da nessuno: lascia il file com'è, salvo sostituire `self.ai.schedulerhst` con `self.ai.scheduler` perché non resti un riferimento a un modulo che non esiste.
   - `overviewhst.lua` r. 18: riga commentata, lasciala.
5. Alla fine `grep -rn schedulerhst luarules/gadgets/ai/STAI` deve trovare solo i commenti e `ScoutBST:Draw`.

**Test**: se ci sono test di STAI che usano `SchedulerHST`, aggiornali; altrimenti niente test nuovi (il comportamento dello scheduler è già coperto dai test del framework). `lx --lua-version 5.1 test`, `run_engine_tests.sh`.

**Partite**:
- tre partite A come in S1; tabella con le stesse righe di S1, più una colonna con l'intervallo di S1 per confronto;
- una partita C (`c_stai_vs_stai.txt`, 15 minuti): due STAI sullo stesso host, per vedere che la rotazione fra due team funzioni (unità e mex di **tutte e due** le STAI a fine partita, errori).
- Se le partite A vanno chiaramente peggio di S1 (tutte e tre sotto il minimo di S1 in unità o mex) **fermati** e scrivi cosa vedi, senza correggere.

**Controlli**: StyLua 2.5.2 e EmmyLua 0.24.0 sui file toccati (EmmyLua: nessun errore nuovo rispetto ai 20 di sempre). `.emmyrc.json` ripristinato.

**Commit**, in inglese: uno per il codice di STAI («STAI: …»), uno per i risultati.

## Risultati

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


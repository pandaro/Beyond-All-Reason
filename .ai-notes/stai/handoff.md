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

### S1: partenza — istruzioni locali e partite di riferimento

**Impegno: basso.** Nessun cambio al codice del gioco. Serve un punto di riferimento nuovo: i numeri di `nuovo-stai.md` §6 sono di prima di T15–T16 (ordini per messaggio 25 → 10 → 20, `maxInstances` per partita).

**Lavoro**

1. **Istruzioni locali**: aggiorna `CLAUDE.local.md` (e la copia in `~/.spring/games/BAR.sdd/CLAUDE.local.md` se è un file distinto) perché, per «esegui», puntino a questo file (`.ai-notes/stai/handoff.md`) e al branch `stai/porting`, con le stesse regole di prima (compiti S<n>, risultati qui, `git add -f` per `.ai-notes/`, commit di framework a parte con «Shard …»). Le decisioni tecniche numerate restano come sono. Non committare `CLAUDE.local.md`; nei risultati scrivi in poche righe cosa hai cambiato.
2. **Controllo di partenza**: `git log -1` uguale a `origin/stai/porting`; `lx --lua-version 5.1 test` e `.ai-notes/tools/run_engine_tests.sh` passano come alla fine di T16 (2728 successi, `RESULT: ok`). Ripristina `.emmyrc.json`.
3. **Tre partite A**: `SHARD_MEM_STATS=1 .ai-notes/tools/run_engine_game.sh .ai-notes/tools/startscripts/a_stai_vs_simpleai.txt 15`, tre volte. Per ogni partita, in una tabella (una colonna per partita):
   - unità STAI ai minuti 1, 5, 10, 13 e a fine partita; fabbriche e mex a fine partita;
   - relay: messaggi, ordini, rifiutati **per motivo** (atteso `excluded = 0`; quanti `count`, cioè gruppi oltre 20 ordini);
   - memoria media per frame, picco, heap;
   - righe `[AI Loader] error` (numero e testo distinto, una volta ciascuno);
   - tempo reale della partita.
4. Se una partita va molto fuori dai valori di §6 (meno di 140 unità, meno di 15 mex, errori nuovi) **non correggere niente**: scrivilo e fermati dopo le tre partite.

**Controlli**: nessun file di gioco toccato (`git status` pulito a parte `.ai-notes/stai/handoff.md`).

**Commit**, in inglese: uno solo, con i risultati in questo file.

## Risultati

### S1 (agente locale, 24 novembre 2026)

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


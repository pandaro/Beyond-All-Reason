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

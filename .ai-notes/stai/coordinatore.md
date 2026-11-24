# Passaggio di chat del coordinatore del porting di STAI

Questo file serve ad avviare (e riprendere) il lavoro di porting di STAI in una chat di claude.ai. Va letto per intero prima di fare qualunque cosa. Stato al 25 novembre 2026.

Messaggio d'avvio per la chat:

> Sei il coordinatore del porting di STAI sul nuovo framework Shard per BAR. Leggi `.ai-notes/stai/coordinatore.md` nel branch `stai/porting` di `pandaro/Beyond-All-Reason` e riprendi da lì.

## 1. Da leggere, in quest'ordine

1. Questo file.
2. `.ai-notes/stai/nuovo-stai.md`: cosa si sa del porting, decisioni aperte, ordine di lavoro.
3. `.ai-notes/coordinatore.md` (il coordinatore del framework): §1 (metodo), §2 (regole dell'utente), §6 (cose imparate). Valgono anche qui.
4. `.ai-notes/drafts/README.md`: la guida del framework.
5. `.ai-notes/stai/handoff.md`: compito attuale e risultati.

## 2. Metodo (lo stesso del framework)

- **Utente**: pandaro, autore di STAI. Scrive in italiano; si risponde in italiano, semplice e preciso.
- **Coordinatore** (questa chat): legge, verifica, riassume, scrive i compiti, tiene aggiornati `nuovo-stai.md` e questo file. Non scrive codice del gioco.
- **Esecutore** (Claude Code in VSCodium sulla macchina dell'utente, Ubuntu 24.04): esegue compiti, test e partite headless.
- **Canale**: git, branch `stai/porting`. Il compito sta in `.ai-notes/stai/handoff.md` («Compito attuale»); l'esecutore scrive i risultati lì («Risultati», intestazione `### S<n> (agente locale, <data>)`). I compiti del porting si chiamano **S1, S2, …** per non confonderli con i T del framework.

**Ciclo di ogni compito**

1. Il coordinatore propone il compito in chat, in breve, con l'impegno (basso, medio, alto, extra) e il motivo.
2. L'utente approva o corregge. **Niente compito scritto, commit, push o cambio di decisioni senza il suo ok.** Leggere, verificare, riassumere e registrare risultati misurati si può senza chiedere.
3. Il coordinatore scrive il compito in `handoff.md`, committa e fa push.
4. L'utente dà all'esecutore `/clear`, l'impegno, e «esegui»: l'esecutore sa cosa leggere (le sue istruzioni locali vanno aggiornate perché puntino a `.ai-notes/stai/handoff.md`; lo fa l'esecutore nel primo compito).
5. L'utente dice «fatto»; il coordinatore fa `git pull`, legge i risultati, controlla a campione i diff, segna `— verificato dal coordinatore` (commit e push), riassume e propone il passo dopo.

**Formule fisse (richiesta dell'utente, 24 novembre 2026)**: a ogni compito il coordinatore dice sempre, con queste parole:
- quando il compito è scritto e pushato: «S<n> pronto, assegna impegno <x>»;
- quando i risultati sono verificati: «concluso»;
- quando propone il compito successivo: «go next».

**Commit del coordinatore**: messaggio in inglese, chiuso dalle righe di attribuzione che il sistema indica nella chat. Push con `git -c push.negotiate=true push origin stai/porting`. Mai push su master, niente PR, niente force push.

## 3. Regole in più per il porting

- **STAI deve restare forte**: ogni compito che cambia il gioco si confronta con le partite di riferimento (almeno tre partite quando si vuole dire che qualcosa peggiora o migliora).
- **Il framework si tocca solo se serve a tutte le AI**, con l'ok dell'utente, in commit separati che iniziano con «Shard …». Se il framework ha un difetto, si segnala all'utente prima di correggerlo.
- **Le decisioni aperte** (`nuovo-stai.md` §4) le prende l'utente: il coordinatore presenta le opzioni in modo semplice, con un consiglio motivato, e aspetta.
- **La griglia** (punto 5) non si tocca prima di averne parlato con l'utente. Decisa il 25 novembre 2026: una geometria (`GridHST`), tanti strati.
- **Stile di STAI** (`nuovo-stai.md` §7): ogni compito lo richiama; il codice nuovo o spostato deve sembrare scritto dall'utente.
- Una decisione cambiata si scrive come «Decisione del <data> (utente)» accanto al testo vecchio, che resta come storia.

## 4. Dove sta ogni cosa

| Cosa | Dove |
| --- | --- |
| Repository | fork `pandaro/Beyond-All-Reason`, branch `stai/porting` (creato da `shard/fase1`) |
| Documento del porting | `.ai-notes/stai/nuovo-stai.md` |
| Compiti e risultati del porting | `.ai-notes/stai/handoff.md` |
| Storia del framework (T1–T16) | `.ai-notes/handoff.md`, `.ai-notes/coordinatore.md` |
| Proposta del framework (export) | `.ai-notes/proposta-architettura.md` |
| Guida del framework | `.ai-notes/drafts/README.md` |
| Strumenti di prova | `.ai-notes/tools/` (`run_engine_tests.sh`, `run_engine_game.sh`, `startscripts/`) |
| Codice STAI | `luarules/gadgets/ai/STAI/` |
| STAI com'era prima della rimozione da BAR | `git show 3ad8f3fb^:<percorso>` |

I file di `.ai-notes/` si aggiungono con `git add -f`. Tutta `.ai-notes/` va tolta prima di una PR verso BAR.

## 5. Stato

| Compito | Stato |
| --- | --- |
| S1 | partenza: istruzioni locali dell'esecutore su `stai/porting`, tre partite A di riferimento dopo T16 — verificato |
| S2 | scheduler: liste nella classe, via `SchedulerHST` e i controlli di turno — verificato. Decisione del 24 novembre 2026 (utente): `AntinukeBST` resta nella lista dei turni |
| S3 | pulizia di `MapHST`: codice morto, `ClosestFreeMex` e `trampled` in `BuildingsHST`; gioco invariato (prova con le stesse righe prima e dopo) — verificato (`maphst.lua` da 1184 a 623 righe) |

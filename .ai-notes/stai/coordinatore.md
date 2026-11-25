# Passaggio di chat del coordinatore del porting di STAI

Questo file serve ad avviare (e riprendere) il lavoro di porting di STAI in una chat di claude.ai. Va letto per intero prima di fare qualunque cosa. Stato al 25 novembre 2026, fine della seconda chat del coordinatore del porting: S1–S12b verificati, S26 e S19 verificati (`gridSize` resta 256); **S24a scritto e da eseguire** (ordine a molte unità nel framework); poi S24b (`AttackerBST` solo sensore). Utente (25 novembre 2026): modo sintetico, niente domande, il coordinatore sceglie il prossimo compito. Per riprendere: leggere questo file, `nuovo-stai.md` (§3 punti 15–19, §4 decisioni, §5 piano S9–S13, §7 stile) e di `handoff.md` solo «Compito attuale» e l'ultimo risultato (la storia è lunga: non serve rileggerla). Se l'utente dice «fatto», verificare S24a, poi scrivere S24b. Formule fisse: vedi §2.

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

**Livello e modello** (utente, 25 novembre 2026): ogni compito indica il livello d'impegno (low, medium, high, extra, max) e il modello adatto all'esecutore (Haiku 5.5, Sonnet 5.5, Opus 5.5). Haiku per i compiti meccanici, Sonnet per indagini e lavoro medio, Opus per decisioni di progetto difficili. Il coordinatore resta su Opus 5.5.

**Commit del coordinatore**: messaggio in inglese, chiuso dalle righe di attribuzione che il sistema indica nella chat. Push con `git -c push.negotiate=true push origin stai/porting`. Mai push su master, niente PR, niente force push.

## 3. Regole in più per il porting

- **STAI deve restare forte**: ogni compito che cambia il gioco si confronta con le partite di riferimento (almeno tre partite quando si vuole dire che qualcosa peggiora o migliora).
- **Il framework si tocca solo se serve a tutte le AI**, con l'ok dell'utente, in commit separati che iniziano con «Shard …». Se il framework ha un difetto, si segnala all'utente prima di correggerlo.
- **Le decisioni aperte** (`nuovo-stai.md` §4) le prende l'utente: il coordinatore presenta le opzioni in modo semplice, con un consiglio motivato, e aspetta.
- **La griglia** (punto 5) non si tocca prima di averne parlato con l'utente. Decisa il 25 novembre 2026: una geometria (`GridHST`), tanti strati.
- **Stile di STAI** (`nuovo-stai.md` §7): ogni compito lo richiama; il codice nuovo o spostato deve sembrare scritto dall'utente.
- **Niente opzioni in `springsettings.cfg`** (utente, 25 novembre 2026): il framework e le AI devono essere autocontenuti.
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
| S4a | `GridHST`: geometria (misura della cella in un solo punto, 256), `CELLS` per indice, funzioni di griglia spostate da `MapHST`; gioco invariato — verificato (test busted, 12 mutazioni; `maphst.lua` 488 righe) |
| S4b | strati (`NewLayer(resetCell)`, `Get`, `Mark`, `Clear`), `MapHST.GRID` come primo strato per indice, lettori di `X`/`Z`/`POS` sulla geometria; gioco invariato — verificato (classe `GridLayer`, 16 mutazioni; `topology` tolto) |
| S5 | `Tool`: libreria `Toolbox` (matematica senza stato), modulo di team per il resto, via 16 funzioni mai chiamate (più 6 rimaste senza chiamanti, approvate dall'utente); `MapHST` usa già `Toolbox`; indice `codice-tolto.md` — verificato (`tool.lua` da 785 a 261 righe, 12 mutazioni, righe `[S3-PROOF]` identiche) |
| S6 | `ArmyHST`, `GridHST`, `MapHST` `"global"` (gioco invariato); commento di `outbox.lua` (commit «Shard …»); `tableConcat` corretta (il gioco cambia: tre partite A) — verificato (righe `[S3-PROOF]` uguali e una volta sola, `global`; tre partite A dentro i riferimenti: 155–178 unità, 26–33 mex) |
| S7 | `collect` alla fine di `StartAIs` (commit «Shard …»), via quella di `MapHST`; `DrawDebug` controlla `drawDebug` prima di `EraseAll`; gioco invariato — verificato (righe `[S3-PROOF]` identiche; `collect` 13 ms una volta all'avvio, con guardia `next(fresh)`) |
| S8a | strato `ENEMY` di `LosHST` in `GridHST`, `GridLayer:GetMarked`; via `OWN`, `ALLY`, `ALLIES`, pool e campi morti; il gioco cambia solo per l'ordine: tre partite A — verificato (prova nella stessa partita: 0 differenze cella per cella; tre partite A sopra S6: 178–202 unità, 34–38 mex; picco di memoria 218 KB) |
| S8s | seme fisso: saltato dall'utente (25 novembre 2026) per risparmiare token; le prove «gioco invariato» si fanno nella stessa partita (come S8a) |
| S9 | strati che durano: `GridLayer:Unmark`, `DAMAGED` (`DamageHST`), `SCOUTED` (`ScoutHST:Scouted`, scrive solo il padrone); via `areaGridCells`/`getGridCellsFields` — verificato (prova nella stessa partita: 0 differenze; `POS` di `DAMAGED` resta da `GridToPos` perché il terreno cambia; una partita A: 161 unità, 32 mex) |
| S10 | difetti della mappa e della griglia: `unarm?I`, `metalScan`/`geoScan`, `SimplifyMetalSpots` (`elmoMapSizeZ`), `RawPosIsInMap`, via `UWMetalSpotCheckUnit` — verificato (gioco invariato su Comet Catcher; tre partite A 132–175 unità, 19–32 mex: varianza del seme) |
| S11 | difetti di tattica: `CELL.base` azzerato, `getCenter` senza NaN, `defId` dell'attaccante e `attackerut` nil in `DamageHST`, `local` in `LosHST:Draw`; via `SquadAttackbackup`, la vecchia `SquadAttack`, `NearbyVulnerable`, `GetPathModifierFunc` — verificato (tre partite A 168–203 unità, 27–34 mex) |
| S12a | preparazione degli ambiti d'alleanza: `CENTER`/`ownImmobile` in `BuildingsHST`, `needAntiAir` in `LosHST`, via `friendlyTeamID` e `isDamaged`, `Toolbox.COLOURS`, `TablePool` per i blob — verificato; la prova ha trovato che `CENTER` era la tabella viva della posizione del comandante (`GetPosition` riscrive sempre la stessa tabella): si completa in S12a2 |
| S12a2 | `CENTER` = media degli edifici, senza edifici posizione attuale del comandante (`BuildingsHST:GetCenter`); ciclo numerico dei blob — verificato (prova: `metal` diverso solo nelle ultime cifre, 25 volte su 5767; tre partite A 134–179 unità, 25–35 mex) |
| S12b | `LosHST`, `TargetHST`, `DamageHST` `"ally"`; `DamageHST` danni di tutta l'alleanza — verificato (B: una istanza per alleanza; tre partite A 155–204 unità, 34–37 mex) |
| S14 | 84 `EchoDebug` costosi dietro `if self.DebugEnabled` — verificato |
| S15 | `map.lua`: disegni sotto la prima AI in ambito ally/global (commit «Shard …») — verificato |
| S16 | indagine ordini grandi: nessun ordine perso, punto 10 chiuso; trovato `#` con buchi in `RaidHST` — verificato |
| S21 | `cmdUnitId` senza buchi in `RaidHST`/`AttackHST` — verificato (0 casi in partita; tre partite A 161–217 unità) |
| S13 | elezione: lettura e misura (differenze solo `BootBST`/`CleanerBST` → nessuno), 12 partite A — verificato; regola nuova decisa dall'utente |
| S22 | regola nuova d'elezione, `labshst` rete `nil`, `bomberhst` contatore — verificato |
| S23 | `BootBST` trova la fabbrica, `mobile` giusto, `ExitFactory` con `GiveOrder`; `ReclaimBST` priorità 0 — verificato (tre partite A 154–199 unità) |
| S8b | percezione: `PerceptionHandler` in STAI, ombre (`ghostEnemy`) per le mobili uscite dalla los ma nel radar; tre partite A — verificato (71–233 ombre per partita, nessuna appesa; partite A 166–198 unità, 29–39 mex, picchi di memoria 64–128 KB) |

**Piano** (fine della seconda chat, 25 novembre 2026; approvato dall'utente; dettagli in `nuovo-stai.md` §5, «Piano del 25 novembre 2026, dopo S8b»):

1. ~~S9 — strati che durano~~: verificato.
2. ~~S10 — difetti della mappa e della griglia~~: verificato.
3. ~~S11 — difetti di tattica e codice morto~~: verificato.
4. ~~S12a, S12a2~~ verificati. S12b (passaggio a `"ally"`, partita B): scritto (impegno extra). Verificarlo.
5. S13 — elezione.

**Roadmap** (25 novembre 2026, dopo S12b; impegno e agente consigliati; il coordinatore resta Opus 5.5):

| Compito | Cosa | Impegno | Agente |
| --- | --- | --- | --- |
| S14 | `EchoDebug` costosi dietro `if self.DebugEnabled` (punto 11), meccanico | medio | Haiku 5.5 |
| S15 | disegni di debug in ambito ally (`map` con team `nil`) | basso | Haiku 5.5 |
| ~~S16~~ | ordini grandi: chiuso | medio | Sonnet 5.5 |
| S21 | `#` con buchi in `RaidHST` (ordini GUARD saltati) | low | Haiku 5.5 |
| ~~S13~~ | elezione: fatto, regola nuova | high | Opus 5.5 |
| ~~S22, S23~~ | fatti | | |
| S25 | metodi inesistenti (`GiveOrderToUnit`) e globali accidentali | low | Haiku 5.5 |
| S24a | ordine «un comando a molte unità» (codec, outbox, relay; «Shard …») | high | Sonnet 5.5 |
| S24b | `AttackerBST` solo sensore: eventi alla squadra, priorità 0, via `attacking` | medium | Sonnet 5.5 |
| S22 | `labshst.lua:367` rete `nil`; `bomberhst` `cmdUnitId` con buchi | low | Haiku 5.5 |
| S17 | `shard_null` (punto 12) — dopo S24, se restano token (utente) | alto | Sonnet 5.5 |
| S18 | `ShardMemStats` autocontenuto (framework, commit «Shard …») | medio | Sonnet 5.5 |
| ~~S19~~ | `gridSize` 128: provato, peggio, ritirato | high | Opus 5.5 |
| S20 | chiusura: guida per STAI, partite finali, branch pulito — **rinviata dall'utente di almeno 7 giorni (non prima del 2 dicembre 2026)** | medio | Sonnet 5.5 |

Utente (25 novembre 2026): pochi crediti, prima i compiti semplici con Haiku. Obiettivo: chiudere il porting dopo S24 (S18, S17 se restano token), poi tenere token per idee e miglioramenti.
S18: l'unico uso di `springsettings` è `ShardMemStats` in `shard_runtime/loader/memstats.lua` (`Spring.GetConfigInt` r. 20 e 54); gli script di prova scrivono la riga in un `springsettings.cfg` temporaneo.

**Cose imparate in questa chat** (per il coordinatore):
- Il seme di `math.random` cambia a ogni partita e in Lua unsynced non si può fissare con `math.randomseed` (salato con un indirizzo): due partite con lo stesso codice si separano presto. Le prove «gioco invariato» si fanno **nella stessa partita** (la struttura vecchia ricalcolata accanto alla nuova e confrontata cella per cella, come in S8a); per i cambi di gioco tre partite A.
- L'esecutore a volte fa più del compito (funzioni morte in più, guardie): va bene se lo scrive; chiedere all'utente e registrare l'approvazione.
- Per risparmiare contesto: `git pull --depth`, leggere solo il blocco dei risultati con `awk '/^### S<n> \(agente/,/^### S<n-1> \(agente/'`, diff a campione con `git diff <base> HEAD -- luarules/`.
- `ShardUnit:GetPosition` riscrive sempre la stessa tabella dell'unità: chi la tiene (come faceva `CENTER`) vede la posizione viva. Prima di descrivere all'utente un valore, controllare se è una tabella condivisa.
- I compiti funzionano meglio quando il coordinatore ha già letto il codice e scrive righe e nomi precisi (lettori, scrittori, campi).

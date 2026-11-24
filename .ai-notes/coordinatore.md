# Passaggio di chat del coordinatore

Questo file serve a riprendere il lavoro in una chat nuova di claude.ai senza perdere niente. Va letto per intero prima di fare qualunque cosa. Stato al 24 novembre 2026 (dopo la verifica di T13).

Messaggio d'avvio per la chat nuova:

> Sei il coordinatore del progetto Shard per BAR. Leggi `.ai-notes/coordinatore.md` nel branch `shard/fase1` di `pandaro/Beyond-All-Reason` e riprendi da lì.

## 1. Chi siamo e come lavoriamo

- **Utente**: pandaro (bio), autore di STAI, usa Shard da più di dieci anni. Scrive in italiano; si risponde in italiano.
- **Coordinatore** (tu, chat su claude.ai): legge, verifica, riassume, scrive i compiti, tiene aggiornati il documento di progetto e la guida. Non scrive codice del gioco.
- **Esecutore** (Claude Code nell'editor VSCodium sulla macchina Linux dell'utente, Ubuntu 24.04): esegue i compiti, i test e le partite headless.
- **Canale**: git. Il compito sta in `.ai-notes/handoff.md` (sezione «Compito attuale»); l'esecutore scrive lì i risultati (sezione «Risultati», intestazione `### T<n> (agente locale, <data>)`).

**Ciclo di ogni compito**

1. Il coordinatore propone il compito in chat, in breve, con l'**impegno** (basso, medio, alto, extra) e il motivo.
2. L'utente approva o corregge. **Niente compito scritto, commit, push o cambio di decisioni senza il suo ok.** Il coordinatore può leggere, verificare, riassumere e registrare risultati misurati senza chiedere.
3. Il coordinatore scrive il compito in `handoff.md` (sostituendo il precedente in «Compito attuale»), committa e fa push.
4. L'utente scrive `/clear` all'esecutore, imposta l'impegno, e gli dice solo «esegui»: l'esecutore sa cosa leggere.
5. L'utente dice «fatto»; il coordinatore fa `git pull`, legge i risultati, controlla a campione i diff, e segna l'intestazione come `— verificato dal coordinatore` (commit e push), poi riassume all'utente e propone il passo dopo.

**Push**: il token di `gh` sta nel portachiavi di sistema; dentro VSCodium l'esecutore a volte non lo legge e compare una richiesta di password. In quel caso l'utente chiude la finestra e fa push dal terminale (`git push origin shard/fase1`), oppure apre VSCodium dal terminale (`codium .`). Non salvare il token in chiaro.

## 2. Regole dell'utente (da rispettare sempre)

- **Lavoro sul framework**; **STAI si tocca il meno possibile**, solo il minimo indispensabile. `Shard/` è l'**AI di esempio**, allineata al framework, su cui si provano i pezzi nuovi.
- **Fedeltà a Shard**: struttura, stile, nomi, firme dei callback. Ogni scostamento va motivato.
- **Preferisce le cose esplicite ai default** (per esempio `Scope()` obbligatorio).
- **Stile**: funzioni piccole e riutilizzabili, composte in funzioni più grandi («macro») che si leggono come passi. Codice **ordinato**, non solo funzionante.
- **Tutto ciò che va nel repository è in inglese** (commit, commenti, nomi, log, test, documentazione). Le note in `.ai-notes/` sono in italiano.
- **Errori**: un errore di caricamento o di `Init` fa cadere quell'AI, mai la battle; un errore **durante la partita** si scrive e l'AI **va avanti** (servono per vedere e correggere più errori). Niente `/luarules reload`.
- **Scheduler senza budget di tempo**: un turno per frame. Il framework offre basi semplici; chi vuole altro se lo scrive.
- Le **richieste di percorso** (`Spring.RequestPath`) sono rinviate: non progettarle senza chiedere.
- **Prima la struttura globale, poi i miglioramenti locali.**
- Non riscrivere da capo: si parte dal codice esistente e si riordina.
- La segnalazione a BAR del test runner rotto la fa l'utente se e quando vuole.
- Risposte: semplici, intuitive, in italiano; quando chiede «come a mia nonna», niente gergo.

Le decisioni tecniche numerate (ambiti, host, relay, ordini, consegna, scheduler, elezione, percezione, metal spot, soglie) sono in `CLAUDE.local.md` («Decisioni da rispettare»): l'utente ne tiene una copia in `~/.spring/games/BAR.sdd/CLAUDE.local.md`; quando cambia una decisione il coordinatore aggiorna anche quel file e lo manda all'utente.

## 3. Dove sta ogni cosa

| Cosa | Dove |
| --- | --- |
| Repository | fork `pandaro/Beyond-All-Reason`, branch `shard/fase1`. Mai push su master, niente PR, niente force push. |
| Documento di progetto (proposta) | Claude Docs, progetto `5f85f536-af2f-4d89-8d7a-749ef0ff1806`, scheda `44b061b0-261b`, nodo `49784d75-2d21` (link: https://claude.ai/artifact/Co9UCbusct3QXgD2HdpyZF). Copia esportata in `.ai-notes/proposta-architettura.md` (da riesportare quando cambia). |
| Compiti e risultati | `.ai-notes/handoff.md` |
| Guida in inglese (bozza) | `.ai-notes/drafts/README.md`, aggiornata dal coordinatore a ogni compito; alla fine va in `luarules/gadgets/ai/README.md` |
| Mappa del loader | `.ai-notes/drafts/mappa-shardailoader.md` |
| Strumenti di prova | `.ai-notes/tools/` (`run_engine_tests.sh`, `run_engine_game.sh`, gadget di controllo, `startscripts/`) |
| Codice rimosso da BAR | `git show 3ad8f3fb^:<percorso>` (commit di rimozione 19 giugno 2026, PR #8004) |
| Istruzioni dell'esecutore | `CLAUDE.local.md` (non committato) |

In `.ai-notes/` sono tracciati solo `handoff.md`, `proposta-architettura.md`, `coordinatore.md`, `drafts/` e `tools/`, aggiunti con `git add -f`. Tutta `.ai-notes/` va tolta prima di una PR verso BAR.

**Commit del coordinatore**: messaggio in inglese, chiuso da

```
Co-Authored-By: <modello in uso> <noreply@anthropic.com>
Claude-Session: <link della sessione>
```

(usa le righe di attribuzione che il sistema ti indica nella chat nuova). Push con `git -c push.negotiate=true push origin shard/fase1`.

## 4. Il framework oggi

**Struttura**

- `luarules/gadgets/ShardAILoader.lua` (circa 300 righe): ricerca dei team AI e call-in dell'engine, ognuno una «macro» di poche righe.
- `luarules/gadgets/ai/shard_runtime/loader/`: un file per compito, ognuno restituisce una tabella, nessun globale.
  - synced: `hosts.lua` (host per ally team, successore), `relay.lua` (controllo e consegna degli ordini);
  - unsynced: `types.lua` (runtime, tipi di AI, oggetti, seme, fallimenti), `lifecycle.lua` (avvio, arresto, catch-up, cambio di host, invio ordini), `delivery.lua` (chiamate protette, elenco errori, consegna degli eventi), `unitregistry.lua` (tabelle di unità provvisorie, unità morte), `memstats.lua` (memoria per frame), `scheduler.lua` (turni).
- `shard_runtime/`: classi (`AIBase`, `ShardAI`, `ShardAlly`, `ShardGlobal`, `Module`, `Behaviour`, `Unit`), `ordercodec.lua`, `spring_lua/` (API vera, `outbox.lua`), `shard_null/` (API finta per i test).
- `shard_runtime/perceptionhandler.lua`: modulo di percezione offerto, non obbligatorio (il framework non filtra).
- `Shard/`: AI di esempio, classe `ShardBasic` (nome proposto, non ancora confermato dall'utente). `STAI/`: l'AI dell'utente.

**Cosa fa**

- Tre ambiti con `Scope()` obbligatorio: `"team"`, `"ally"`, `"global"`; dipendenze solo verso l'alto.
- Include per tipo di AI con ambiente proprio e cache (ogni file gira una volta per tipo).
- AI solo nell'unsynced del client host; un host per ally team (`aiHostPlayer`), successore deterministico.
- Ordini: `game:GiveOrder(id, cmd, params, options, method)` con i codici di STAI, coda per AI, messaggio binario (formato v1), al massimo 25 ordini per messaggio, un messaggio per frame. Relay synced con tutti i controlli (mittente, seq, frame, limiti, team delle unità).
- Eventi solo ai moduli che li ridefiniscono, ordine global → ally → team.
- Scheduler di base: con `MScheduler` nella classe, i moduli elencati a turni (un turno per frame); gli altri a ogni frame; senza liste, tutti a ogni frame. STAI tiene il suo `SchedulerHST`.
- Errori: elenco per messaggio, riepilogo a fine partita. Unità morte tenute 900 frame; ID riciclati e ID mai esistiti gestiti.
- Misura della memoria per frame: `/set ShardMemStats 1` (in headless `SHARD_MEM_STATS=1`).

**Numeri di riferimento** (STAI contro SimpleAI, 15 minuti, Comet Catcher Remake 1.8): circa 180–200 unità STAI, 30–38 mex, circa 4.000 messaggi e 12.000–17.000 ordini, una decina rifiutati (unità morte nel frattempo); memoria 0,2–0,8 KB per frame in media, heap 13–15 MB.

## 5. Compiti

| Compito | Stato |
| --- | --- |
| T1–T2b | recupero, pulizia, include per tipo con cache, StyLua |
| T3–T3b | ambiti, `ShardAlly`, `ShardGlobal`, difetti vecchi |
| T4 | codifica degli ordini e outbox |
| T5a–T5c | loader: relay synced, lato unsynced, STAI in partita |
| T6–T6b | errori contenuti, unità morte, memoria per frame, elenco errori, ID riciclati |
| T7–T7b | loader diviso in file per compito |
| T8 | Shard come AI di esempio (gioca, ma debole) |
| T10 | consegna mirata, unità `nil`, ramo `shard_null` |
| T9 | scheduler di base (EmmyLua e StyLua 2.5.2 da rifare: in T11) |
| T11 | strumenti fissati in `~/.local/bin`, elezione dei behaviour (solo priorità > 0) con `legacyElection` per STAI, turni dei behaviour (`BScheduler`) |
| T12 | percezione come modulo del framework (`shard_runtime/perceptionhandler.lua`, ambito `"ally"`), usato da `AttackHandler` di Shard; tolti `Perception()` e `omniscient` |
| T13 | `shard_null` crea anche gli oggetti d'alleanza e globale, prepara global → ally → team |
| T14 | rete di sicurezza della GC rimessa (in `memstats.lua`, stessi valori, ogni 121 frame); `MAX_INSTANCES_PER_AI_TYPE = 2` per client host. Aperti: la `collect` senza condizione di `Initialize` (r. 276 del vecchio loader) non rimessa; limite per client o per partita |

**Prossimi passi** (ordine proposto all'utente)

1. Fatto: guida aggiornata con elezione, `BScheduler` e percezione.
2. Rinviato per scelta dell'utente: `UnitTaken` arriva ai moduli come `UnitDead` (un nemico che cambia squadra sparisce da `los`/`radar`).
3. **Latenza in multiplayer**: partita vera con due client, da organizzare con l'utente; poi la scelta synced/unsynced come modalità predefinita.
4. **Chiusura verso BAR**: guida in `luarules/gadgets/ai/README.md`, branch pulito senza `.ai-notes/` e con commit riordinati, prove di partita per `AI_POLICY.md`.

**Decisioni e appunti dell'utente (24 novembre 2026, sera)**
- `QueueActivation` e `Job`: **eliminati** dalla proposta. Restano solo come risposta ipotetica se un giorno servissero (100 unità insieme nascono solo con `/give`).
- Ordini per frame: **numero personalizzabile** (costante nel framework, usata da outbox e relay), **partire da 10** (oggi 25). Dato: STAI fa circa 15.000 ordini in 15 minuti, meno di 1 per frame in media; un giocatore fortissimo fa circa 100 azioni al minuto.
- Pool di tabelle: **nel framework**, un piccolo modulo con le sue funzioni, facile da raggiungere, per chi vuole usarlo. Toglierlo da STAI solo al porting e se costa poco.
- Griglia di `LosHST`: **non va più bene così**; se ne parla al porting. Idea dell'utente: **una griglia unica** per tutto, ogni cella una tabella con i dati, più **liste delle celle «vere»** per tema (celle con nemici, con metallo, con unità mie, ecc.).
- T15 scritto: `collect` d'avvio rimessa, ordini per messaggio a 10 (costante unica), `shard_runtime/tablepool.lua`.
- T15 verificato. T16 scritto: `maxInstances` per partita, deterministico (primi N team AI per ID), con il relay che rifiuta i team esclusi.
- Aperto da T15: un gruppo di ordini con più di 10 ordini (un `GiveOrder` a 11+ unità, o 11+ comandi in coda) va da solo e il relay lo **rifiuta intero**. Decisione dell'utente: niente spezzatura, limite alzato a 20 (extra di T16). **Nota**: gli ordini troppo grandi (gruppi oltre 20) possono essere persi; in teoria per quei casi si può usare `GiveOrderArrayToUnitArray` (un solo comando per molte unità).
- Dopo il via dell'utente: documento «Nuovo STAI» per il porting.

**In sospeso per scelta dell'utente**

- Shard di base: non costruisce mex; `PlacementHandler:GenerateSpiral` alloca circa 6 MB in un frame.
- Decisioni del 24 novembre 2026 (utente): nomi `ShardBasic` e `UnitHandler` confermati; `maxInstances` è un numero nostro (ora 2, alla release 1 o 2); la `collect` del vecchio loader torna esattamente dov'era e com'era (era già stato detto: non riproporre di toglierla); multiplayer rinviato (solo con SkyLobby, quando l'utente vorrà); Shard di esempio a bassa priorità, impegno basso.
- Decisioni aperte (prima di queste): rete di sicurezza della GC (`collect` del vecchio loader: per l'utente è una sicurezza contro il crash) e pool di tabelle; `maxInstances` per tipo e «un solo cervello per alleanza»; nomi da confermare (`ShardBasic`, `UnitHandler`, `Perception()`, `QueueActivation`, `Job`); banco di prova intensivo ed estensivo.

**Porting di STAI** (dopo il framework; appunti nel documento): adeguarla allo scheduler di base (liste nella classe, togliere `SchedulerHST`); MapHST `"global"`, LosHST `"ally"`; ID vecchi in `buildersbst` e `bomberhst`; `EchoDebug` con argomenti costosi; stallo di metallo; farla girare sotto `shard_null` (boot, maiuscole dei file, `Spring` finto).

## 6. Cose imparate (non ripetere gli errori)

- `return VFS.Include(file)` è una chiamata in coda: l'engine perde l'ambiente del chiamante. Salvare il risultato in una variabile e poi restituirlo.
- I numeri Lua in Recoil sono float a 32 bit: interi esatti solo fino a 2^24.
- `VFS.Unpack*` non restituisce niente se la posizione è uguale alla lunghezza del messaggio: le coppie di U8 si leggono come un U16.
- Il test runner di BAR oggi non esegue davvero i test (`setfenv` non può cambiare l'ambiente dei widget): conta solo `run_engine_tests.sh`.
- Headless con AI: giocatore spettatore e pronto, velocità alta, output scritto riga per riga; con un giocatore nello stesso team di un'AI la partita resta bloccata (lasciato perdere: le prove con giocatori le fa l'utente).
- `lx test` riscrive `.emmyrc.json`: va ripristinato, mai committato.
- L'engine, nelle partite provate, non ha mai riciclato un ID di unità entro un'ora di gioco.
- In SkyLobby, per accelerare da spettatore: `/setmaxspeed 10` e `/setminspeed 10`.

## 7. Documento di progetto: come modificarlo

Si usa lo strumento dei documenti di claude.ai (prima `guide` con `topic.index`, poi `read` per cercare un blocco con `{"kind":"search","text":"…"}`, poi `update` con `engine: "prose"`). Gli appunti dell'utente vanno vicino a quelli esistenti (stato della Roadmap, sezione garbage collection, decisione sullo scheduler). Dopo modifiche importanti si riesporta il documento in markdown in `.ai-notes/proposta-architettura.md`. Una decisione cambiata va scritta come «Decisione del <data> (utente)» accanto al testo vecchio, che resta come storia.

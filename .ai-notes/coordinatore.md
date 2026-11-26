# Passaggio di chat del coordinatore

**Dal 26 novembre 2026: un solo coordinatore, un solo branch, `shardST1`** (unione di `shard/fase1` e `stai/porting`, che restano come archivio e non si aggiornano più). Dove le note vecchie dicono `shard/fase1` o `stai/porting`, leggi `shardST1`. Push: `git -c push.negotiate=true push origin shardST1`.

Questo file serve a riprendere il lavoro in una chat nuova di claude.ai senza perdere niente. Va letto per intero prima di fare qualunque cosa. Le note di `.ai-notes/stai/` sono archivio del porting: si leggono solo se serve un dettaglio di un compito passato (S1–S27), salvo lo stile di STAI e `codice-tolto.md`, che valgono ancora (§3).

Messaggio d'avvio per la chat nuova:

> Sei il coordinatore unico del progetto Shard/STAI per BAR. Leggi `.ai-notes/coordinatore.md` nel branch `shardST1` di `pandaro/Beyond-All-Reason` e riprendi da lì (§1 metodo, §2 regole, §6 cose imparate, «In sospeso o rinviato», «Da fare»).

## 1. Chi siamo e come lavoriamo

- **Utente**: pandaro (bio), autore di STAI, usa Shard da più di dieci anni. Scrive in italiano; si risponde in italiano.
- **Coordinatore** (tu, chat su claude.ai, Opus 5.5): **uno solo** per framework e STAI (dal 26 novembre 2026 non c'è più la chat separata del porting). Legge, verifica, riassume, scrive i compiti, tiene aggiornati il documento di progetto e la guida. Non scrive codice del gioco; committa solo le note.
- **Esecutore** (Claude Code nell'editor VSCodium sulla macchina Linux dell'utente, Ubuntu 24.04): esegue i compiti, i test e le partite headless.
- **Canale**: git, branch `shardST1`. Il compito sta in `.ai-notes/handoff.md` (sezione «Compito attuale»); l'esecutore scrive lì i risultati (sezione «Risultati», intestazione `### T<n> (agente locale, <data>)`).
- **Numerazione unica**: i compiti proseguono da T20 (framework e STAI insieme). S1–S27 sono del porting, in archivio.

**Ciclo di ogni compito**

1. Il coordinatore propone il compito in chat, in breve, con il motivo, l'**impegno** (low, medium, high, extra, max) e il **modello** dell'esecutore (Haiku 5.5, Sonnet 5.5, Opus 5.5).
2. L'utente approva o corregge. **Niente compito scritto, commit, push o cambio di decisioni senza il suo ok.** Framework e STAI si toccano solo con il suo ok. Il coordinatore può leggere, verificare, riassumere e registrare risultati misurati senza chiedere.
3. Il coordinatore scrive il compito in `handoff.md` (sostituendo il precedente in «Compito attuale»; impegno e modello nella prima riga), committa e fa push, poi dice con queste parole: **«T<n> pronto, assegna impegno <x>»**.
4. L'utente scrive `/clear` all'esecutore, imposta modello e impegno, e gli dice solo **«esegui»**: l'esecutore sa cosa leggere.
5. L'utente dice «fatto»; il coordinatore fa `git pull`, legge i risultati, controlla a campione i diff, segna l'intestazione come `— verificato dal coordinatore` (commit e push), riassume all'utente e dice **«concluso»**.
6. Con **«go next»** si passa al compito successivo.

**Push**: il token di `gh` sta nel portachiavi di sistema; dentro VSCodium l'esecutore a volte non lo legge e compare una richiesta di password. In quel caso l'utente chiude la finestra e fa push dal terminale (`git push origin shardST1`), oppure apre VSCodium dal terminale (`codium .`). Non salvare il token in chiaro.

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
| Repository | fork `pandaro/Beyond-All-Reason`, branch di lavoro **`shardST1`**. Mai push su master, niente PR, niente force push. `shard/fase1` e `stai/porting`: archivio. Il branch pulito per BAR si prepara a parte (vedi «Da fare»). |
| Stile di STAI (vale ancora) | `.ai-notes/stai/nuovo-stai.md` §7: da leggere prima di ogni compito che tocca STAI |
| Codice tolto da STAI (vale ancora) | `.ai-notes/stai/codice-tolto.md`: ogni compito su STAI che toglie codice lo scrive lì |
| Archivio del porting | `.ai-notes/stai/coordinatore.md`, `.ai-notes/stai/handoff.md` (S1–S27), il resto di `nuovo-stai.md` |
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

(usa le righe di attribuzione che il sistema ti indica nella chat nuova). Push con `git -c push.negotiate=true push origin shardST1`.

## 4. Il framework oggi

**Struttura**

- `luarules/gadgets/ShardAILoader.lua` (circa 300 righe): ricerca dei team AI e call-in dell'engine, ognuno una «macro» di poche righe.
- `luarules/gadgets/ai/shard_runtime/loader/`: un file per compito, ognuno restituisce una tabella, nessun globale.
  - synced: `hosts.lua` (host per ally team, successore), `relay.lua` (controllo e consegna degli ordini); `admission.lua` (quali team AI partono, letto anche dall'unsynced);
  - unsynced: `types.lua` (runtime, tipi di AI, oggetti, seme, fallimenti), `lifecycle.lua` (avvio, arresto, catch-up, cambio di host, invio ordini), `delivery.lua` (chiamate protette, elenco errori, consegna degli eventi), `unitregistry.lua` (tabelle di unità provvisorie, unità morte), `memstats.lua` (memoria per frame), `scheduler.lua` (turni).
- `shard_runtime/`: classi (`AIBase`, `ShardAI`, `ShardAlly`, `ShardGlobal`, `Module`, `Behaviour`, `Unit`), `ordercodec.lua`, `spring_lua/` (API vera, `outbox.lua`), `shard_null/` (API finta per i test).
- `shard_runtime/perceptionhandler.lua` e `shard_runtime/tablepool.lua`: moduli offerti, non obbligatori.
- `Shard/`: AI di esempio, classe `ShardBasic` (nome proposto, non ancora confermato dall'utente). `STAI/`: l'AI dell'utente.

**Cosa fa**

- Tre ambiti con `Scope()` obbligatorio: `"team"`, `"ally"`, `"global"`; dipendenze solo verso l'alto.
- Include per tipo di AI con ambiente proprio e cache (ogni file gira una volta per tipo).
- AI solo nell'unsynced del client host; un host per ally team (`aiHostPlayer`), successore deterministico.
- Ordini: `game:GiveOrder(id, cmd, params, options, method)` con i codici di STAI, coda per AI, messaggio binario (formato v1), al massimo 20 ordini per messaggio (`MAX_ORDERS_PER_MESSAGE` in `ordercodec.lua`; una chiamata con più di 20 ordini è rifiutata intera), un messaggio per frame. Relay synced con tutti i controlli (mittente, seq, frame, limiti, team delle unità).
- Eventi solo ai moduli che li ridefiniscono, ordine global → ally → team.
- Scheduler di base: con `MScheduler` nella classe, i moduli elencati a turni (un turno per frame); gli altri a ogni frame; senza liste, tutti a ogni frame. STAI tiene il suo `SchedulerHST`.
- Errori: elenco per messaggio, riepilogo a fine partita. Unità morte tenute 900 frame; ID riciclati e ID mai esistiti gestiti.
- Misura della memoria per frame: interruttore nel codice (`loader/memstats.lua`); niente più `/set ShardMemStats` né springsettings. Timer `[Shard timer]`: interruttore in `loader/timers.lua`.

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
| T14 | rete di sicurezza della GC rimessa (in `memstats.lua`, stessi valori, ogni 121 frame); `MAX_INSTANCES_PER_AI_TYPE = 2` (per client; per partita da T16) |
| T15 | `collect` d'avvio rimessa; `MAX_ORDERS_PER_MESSAGE` unico in `ordercodec.lua`; `shard_runtime/tablepool.lua` |
| T16 | `maxInstances` per partita (`loader/admission.lua`, primi 2 team per tipo, per ID; il relay rifiuta gli esclusi); 20 ordini per messaggio |

**Stato (25 novembre 2026)**: porting di STAI chiuso (S1–S26 verificati, branch `stai/porting`). Commit «Shard …» solo su `stai/porting`: `5d8d4a9b6e` collect alla fine di `StartAIs` (S7, chiude la nota del 25 novembre), `c7debb58fb` commento di `outbox.lua` (S6), `71fb3121b2` disegni di `map.lua` sotto la prima AI in ambito ally/global (S15), `fa4789d5` + `dec92f8f` ordercodec v2 con gruppi (S24a). Aperti per l'utente: tetto di unità per messaggio, marcatore 65535 o byte di tipo, `UnitHandler` sul modello di `UnitHST`, `ShardMemStats` solo da codice, come portare i commit su `shard/fase1`. La PR di STAI (S20) non parte prima del 2 dicembre e aspetta i primi due punti.

**Stato (26 novembre 2026)**: tutto su `shardST1` (i commit di `stai/porting` compresi). Framework T1–T18 verificati: T17 timer `[Shard timer]` (soglia 10 ms, interruttore nel codice), T18 campo `kb=` nella riga; `ShardMemStats` acceso solo da codice. T19 chiuso a metà e **tenuto nel codice, anche nel branch per BAR** (decisione dell'utente, 26 novembre 2026: STAI cambierà comunque prima della PR). Prossimo compito: T20.

**Prossimi passi del framework** (nessuno urgente)

1. **Latenza in multiplayer**: rinviata finché l'utente non vuole montare SkyLobby; poi la scelta synced/unsynced come modalità predefinita.
2. **Chiusura verso BAR**: guida in `luarules/gadgets/ai/README.md`; branch pulito senza `.ai-notes/` e con commit riordinati; per `AI_POLICY.md` qualche partita guardata dall'utente, con screenshot, più i numeri headless.
3. **Shard di esempio** (bassa priorità, impegno basso): non costruisce mex, non arriva mai ad attaccare, `PlacementHandler:GenerateSpiral` alloca circa 6 MB in un frame.

**Decisioni dell'utente (24 novembre 2026)**

- Nomi confermati: `ShardBasic`, `UnitHandler`.
- `QueueActivation` e `Job` eliminati dalla proposta: idee da riprendere solo se servissero.
- La `collect` del vecchio loader (rete di sicurezza ogni 121 frame e quella d'avvio) è rimessa esattamente com'era: **non riproporre di toglierla**.
- `maxInstances`: un numero nostro, per partita, ora 2 (alla release 1 o 2).
- Ordini: 20 per messaggio; niente spezzatura dei gruppi; oltre 20 in una chiamata l'ordine si perde (in teoria `GiveOrderArrayToUnitArray` lo evita, non verificato).
- Pool di tabelle: nel framework (`tablepool.lua`), facoltativo.
- Percezione: il framework non filtra; `PerceptionHandler` facoltativo; un'AI che bara è ammessa.

**Da fare (ordine deciso dall'utente, 26 novembre 2026)**

1. ~~Note per il metodo nuovo~~ (fatto il 26 novembre).
2. **Branch per BAR** (decisione dell'utente, 26 novembre 2026, da confermare): due PR, una per il framework e una per STAI, a tempo debito. Senza `.ai-notes/`, commit riordinati; T19 dentro. `shardST1` resta il branch di lavoro. La PR di STAI (S20) non parte prima del 2 dicembre 2026.
3. **Debug dell'esecutore in diretta**: output nel terminale durante la partita, righe `[Shard timer]` e `[AI Loader]` evidenziate, riepilogo a fine partita; con `run_engine_game.sh` e `.ai-notes/tools/` (oggi lo script filtra solo a partita finita e delle righe `[Shard timer]` stampa solo il numero).
4. **Raddrizzare STAI un modulo alla volta**, ogni modulo con il suo behaviour. Primo: `BuildingsHST` + `BuildersBST` da zero; l'utente lo studia dalla settimana del 30 novembre; **non iniziare senza il suo ok esplicito**. Idea da valutare: modulo dei posti per alleanza (mappa delle celle libere) a cui i costruttori chiedono «costruisci questo lì».
5. **Aperti dal porting, da decidere con l'utente**: tetto di unità per messaggio e marcatore 65535 o byte di tipo in `ordercodec.lua` (bloccano S20); `UnitHandler` sul modello di `UnitHST`; latenza in multiplayer (rinviata finché non c'è SkyLobby).

**Appunti dell'utente per STAI (26 novembre 2026; idee da tenere segnate, non da implementare senza il suo ok)**

*B. Valutazione dei rischi per gruppi di unità.* Premessa: i dati sul pericolo li raccogliamo molto bene (e si può ancora migliorare), ma li usiamo bene, o abbastanza bene?
1. L'attacco è nudo e crudo: il gruppo parte e si suicida contro un muro di torri e unità. Non va bene.
2. I raid devono aggirare i pericoli e arrivare dietro.
3. Lo stesso per i bombardieri: scortati, puntare dietro; a un certo punto serve uno scout aereo massiccio. (Gli aerei si discutono dopo.)

*Idee sparse sul territorio (da non implementare, solo segnate):*
1. Un meccanismo che dica a STAI qual è l'area di competenza del team, quella dell'alleanza, quella dei team e dell'alleanza nemici, e quale area è **neutrale**, cioè dove l'espansione è possibile.
2. Più precisione sulle aree pericolose: **solo le torri, non le unità mobili**. Per 3–4 strati (surface, sky, submerged; nomi da vedere) un layer di griglia calcola **in metallo** il danno che si può ricevere in un punto dalle statiche. Una torre laser vista in una cella dà lì il suo valore in metallo; il pericolo si estende a tutte le celle nel raggio della torre, calando con la distanza fino a 0 fuori dal raggio.
3. Poi il **blobbing**: dalla mappa dei pericoli si accorpano le celle in aree contigue con livelli di pericolo comparabili.
4. Questo apre a una lettura migliore del territorio.
5. Per alleanza, non per team.
6. Anche per l'alleanza amica: dà l'area coperta dalle nostre statiche. Si ottengono aree friendly, enemy e neutral.
7. Problema: l'area oltre i radar.
8. Problema: costo di calcolo.

*C. Rez, reclaim, repair.* La chiave è **ripara, rezza, reclama, in quest'ordine**. Un behaviour scritto bene per il rez è una marcia in più.

**In sospeso o rinviato**

- `UnitTaken` arriva ai moduli come `UnitDead` (un nemico che cambia squadra sparisce da `los`/`radar`).
- Richieste di percorso (`Spring.RequestPath`).
- «Un solo cervello per alleanza».
- Banco di prova intensivo ed estensivo.
- **Metodo di lavoro semplificato (decisione dell'utente, 26 novembre 2026)**: un solo coordinatore + l'esecutore, un solo branch (`shardST1`). Fatto: §1, §3 e protocollo di `handoff.md` aggiornati il 26 novembre. Poi si raddrizza STAI **un modulo alla volta, ogni modulo insieme al suo behaviour**.
- **PR verso BAR (da preparare, nessun conflitto con il branch unico)**: `shardST1` resta il branch di lavoro con `.ai-notes/`; il branch per BAR si prepara a parte, senza `.ai-notes/`, con i commit riordinati (o copiati da `shardST1`), e la PR di STAI (S20, non prima del 2 dicembre) non dipende più da un branch separato. Da decidere: una PR sola (framework + STAI) o due, nell'ordine framework poi STAI. L'utente vuole cominciare a prepararlo.
- **Debug dell'esecutore da strutturare (richiesta dell'utente, 26 novembre 2026)**: l'utente guarda spesso le partite e vuole **vedere sempre in diretta l'output nel terminale**, senza aprire e ricaricare l'infolog (oppure con l'infolog che si ricarica da solo). Da progettare insieme a `run_engine_game.sh` e agli strumenti in `.ai-notes/tools/`: uscita in diretta, righe `[Shard timer]` e `[AI Loader]` evidenziate, riepilogo a fine partita. Impegno da valutare.
- **T19 chiuso a metà (decisione dell'utente, 26 novembre 2026)**: i 4 punti sono su `shardST1` (`60856bd1`, `1256d068`, `1581d462`, `ff3869d3`; risultati in `handoff.md`). I tempi sono risolti (picco di `BuildersBST` da 4870 a 208 ms in 60 minuti), ma su A il team 0 finisce con meno unità (media 153 contro 189). **T19 resta nel codice, anche nel branch per BAR** (ok dell'utente, 26 novembre 2026). Si sa dove è il problema (il punto 2, più punti per anello = base più fitta, e il ciclo sui `dontBuildRects` per ogni punto) e **non lo si cura**: restano da fare mutazioni, EmmyLua, `run_engine_tests.sh` e le domande aperte dell'agente. L'utente rifarà `BuildingsHST` e `BuildersBST` da zero con un progetto studiato dalla settimana del 30 novembre 2026 (modulo dei posti, passo B); fino ad allora non si investe altro tempo qui.
- **Ricerca del posto di `BuildingsHST:FindClosestBuildSite` (STAI, da rifare; appunto dell'utente, 25 novembre 2026)**: dal log di una partita lunga, al frame 49642 la funzione è partita 51 volte nello stesso frame (una per costruttore), quasi tutte senza successo: circa 1388 tentativi, `BuildersBST` 422 ms. Piano proposto, non ancora scritto come compito: (1) budget di ricerche per frame; (2) memoria dei posti bloccati per un tempo (per esempio 600 frame); (3) celle della griglia di `GridHST` invece dei raggi campionati a caso. Il risultato resta il posto libero più vicino. Da chiedere all'utente: piano intero o solo il budget. Il compito va nel `handoff.md` della chat del porting.
- **`collect` dopo gli `Init`**: fatto in S7 (`5d8d4a9b6e`, `collectgarbage("collect")` alla fine di `StartAIs`, in `lifecycle.lua`).
- **`maxInstances` forzabile in prova (richiesta dell'utente, 25 novembre 2026)**: quando il gioco gira da `.sdd` (versione `$VERSION`, prove locali) deve essere possibile alzare `MAX_INSTANCES_PER_AI_TYPE` (`loader/admission.lua`) per gli stress test con tante AI. Nella release resta il limite fisso.

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

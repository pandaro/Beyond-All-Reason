# Nuovo STAI — porting di STAI sul nuovo framework Shard

Stato al 24 novembre 2026. Il framework è sul branch `shard/fase1` (compiti T1–T16, in `.ai-notes/handoff.md`). Il porting si fa sul branch **`stai/porting`**, da creare da `shard/fase1` quando T16 è verificato.

Questo documento raccoglie in modo essenziale ciò che si sa del porting. È il punto di partenza: le righe «da verificare» sono ipotesi, non decisioni.

## 1. Scopo e regole

- **Scopo**: STAI gira sul nuovo framework e ne usa i pezzi (scheduler, ambiti, elezione), senza perdere forza di gioco; poi si migliora.
- **Due passi**: prima il porting con le opzioni di compatibilità (`legacyElection`), confrontando le partite con quelle di oggi; poi si tolgono, una alla volta, sempre confrontando.
- **Regole dell'utente** (le stesse del framework, `.ai-notes/coordinatore.md` §2): fedeltà a Shard e a STAI; preferenza per le cose esplicite; funzioni piccole composte in «macro»; codice ordinato; tutto ciò che va nel repository in inglese, le note in italiano; prima la struttura globale, poi i miglioramenti locali; non riscrivere da capo; niente `/luarules reload`; le richieste di percorso sono rinviate.
- **Il framework si tocca solo se serve a tutte le AI**: ogni cambio va motivato, approvato dall'utente e fatto in commit separati che iniziano con «Shard …».

## 2. Cosa offre il framework a STAI

Dettagli nella guida (`.ai-notes/drafts/README.md`).

| Cosa | Come | Nota per STAI |
| --- | --- | --- |
| Ambiti | `Scope()` obbligatorio: `"team"`, `"ally"`, `"global"`; dipendenze solo verso l'alto; un modulo di team raggiunge tutti come `self.ai.<nome>` | tutti i moduli di STAI oggi dichiarano `"team"` |
| Turni dei moduli | `STAI.MScheduler = { ... }` nella classe; un turno per frame, senza budget; i moduli non elencati ogni frame | il runtime chiama il modulo **solo nel suo turno**: i controlli di turno dentro i moduli diventano inutili |
| Turni dei behaviour | `STAI.BScheduler = { ... }`; stesso schema | un behaviour a turni deve contare i frame, non le chiamate |
| Di chi è il turno | `self.ai.scheduler.moduleTeam`, `.moduleUpdate`, `.behaviourTeam`, `.behaviourUpdate` | **non** `self.ai.schedulerhst.*`: la compatibilità prevista nella proposta non è stata fatta |
| Elezione | vince solo una priorità > 0; se nessuno, nessun behaviour attivo | STAI oggi ha `STAI.legacyElection = true` (la regola vecchia) |
| Eventi | solo ai moduli e behaviour che li ridefiniscono; ordine global → ally → team | |
| Ordini | `game:GiveOrder(...)` e i metodi di `ShardUnit` vanno in una coda; al massimo 20 ordini per messaggio, un messaggio per frame | una sola chiamata con più di 20 ordini viene **rifiutata intera** |
| Percezione | il framework non filtra: `game:GetEnemies()` dà tutti i nemici; `PerceptionHandler` (ambito ally, `los`, `radar`, `Sees`, `OnRadar`) è facoltativo | |
| Pool di tabelle | `local TablePool = shard_include("tablepool")`: `New`, `Get`, `Release`; facoltativo | |
| Errori | un errore in partita si scrive e l'AI va avanti; riepilogo a fine partita | |
| Istanze | al massimo 2 AI dello stesso tipo per partita (`MAX_INSTANCES_PER_AI_TYPE`) | |
| Memoria | rete di sicurezza della GC del vecchio loader; misura con `SHARD_MEM_STATS=1` | |
| Prove senza engine | `shard_null`, con oggetti ally e global | STAI oggi non parte sotto `shard_null` |

## 3. Punti del porting

| # | Punto | Dove | Cosa si sa | Stato |
| --- | --- | --- | --- | --- |
| 1 | Scheduler | `STAI/schedulerHST.lua`; i controlli di turno in testa all'`Update` dei moduli e dei behaviour | le liste di `SchedulerHST` passano nella classe (`STAI.MScheduler`, `STAI.BScheduler`); i controlli `self.ai.schedulerhst.moduleTeam ~= self.ai.id ...` si tolgono; `SchedulerHST` sparisce | deciso |
| 2 | Ambiti globali | `armyhst.lua`, `maphst.lua` | `ArmyHST` e `MapHST` diventano `"global"`: oggi l'analisi della mappa si rifà per ogni AI. Le funzioni di `MapHST` che dipendono dal team (`ClosestFreeMex` usa `buildingshst`, `loshst`, `targethst`; i costi dei percorsi usano `game:GetTeamID()`) ricevono l'AI come parametro o passano in un modulo di team | da verificare |
| 3 | Ambiti d'alleanza | `loshst.lua`, `targethst.lua`, `damagehst.lua` | `LosHST` diventa `"ally"`; `self.ai.friendlyTeamID` (scritto da `LosHST:Init`, letto da `DamageHST`) passa su `ShardAlly`; `UnitCreated` riconosce le unità proprie con `self.ai.id`; `TargetHST` e `DamageHST` probabilmente `"ally"` | da verificare |
| 4 | `self.ai.id` nei moduli condivisi | tutti i moduli che diventano global o ally | in un modulo condiviso `self.ai` è l'oggetto ally o global, non un team | da controllare a ogni modulo spostato |
| 5 | Griglia | `loshst.lua` (griglie `ENEMY`, `OWN`, `ALLIES`, pool di celle) | **l'utente non vuole più la griglia così**. Idea dell'utente: una griglia unica per tutto, ogni cella una tabella di dati, più liste delle celle «vere» per tema (nemici, metallo, unità proprie…). Difetto noto: `Update` libera `"ALLY"`, ma le griglie sono `ALLY` e `ALLIES`; il controllo su `loshst.ALLY` in `ScoutHST` non scatta mai | **da discutere con l'utente prima di toccarla** |
| 6 | Percezione | `loshst.lua`; letture dirette `Spring.*` (circa 26 in `maphst.lua`, 10 in `loshst.lua`, 6 in `damagehst.lua`) | tre strade: tenere `LosHST`, usare `PerceptionHandler`, o barare | aperto |
| 7 | Elezione | `STAI/ai.lua` (`legacyElection`); `bootbst.lua`, `cleanerbst.lua` | con la regola nuova: `BootBST` è spesso primo e a priorità zero; vanno controllati i behaviour che fanno qualcosa in `Activate`; `CleanerBST:Priority` è vuota (vale zero) | aperto: tenere `legacyElection` o passare alla regola nuova |
| 8 | Gestore delle unità | `unithst.lua` | la proposta diceva: `UnitHST` lascia il posto a `UnitHandler`. Oggi `UnitHandler` sta in `Shard/` (l'esempio), non nel runtime | aperto |
| 9 | `collect` di `MapHST` | `maphst.lua` r. 52, `collectgarbage("collect")` alla fine di `Init` | la proposta diceva di toglierla (costa 65–70 ms); l'utente tiene alle `collect` come sicurezza; con `MapHST` globale girerebbe una volta per partita | aperto |
| 10 | Ordini grandi | moduli e behaviour che danno ordini a molte unità | oltre 20 ordini in una chiamata l'ordine si perde; in teoria `GiveOrderArrayToUnitArray` lo evita (non verificato). Guardare i «rifiutati» delle partite | da controllare |
| 11 | Difetti noti | `buildersbst.lua`, `bomberhst.lua`; `EchoDebug` in tutti i file | ID di unità vecchi; `EchoDebug` con argomenti costosi calcolati anche a debug spento; stallo di metallo | da fare |
| 12 | `shard_null` | `STAI/boot.lua`; nomi dei file | boot da sistemare; maiuscole (`schedulerHST.lua` incluso come `"schedulerhst"`); serve uno `Spring` finto per le letture dirette | da fare |
| 13 | Un solo cervello per alleanza | — | idea dell'utente: più STAI nella stessa alleanza comandate da una sola AI; passo naturale dopo gli ambiti | futuro |
| 14 | Percorsi | `maphst.lua` r. 595 e 883, `attackhst.lua` r. 310 | `map:RequestPath` sincrono, senza cache | **rinviato** dall'utente |

## 4. Decisioni aperte (le prende l'utente)

1. Griglia: forma nuova (punto 5).
2. Percezione: `LosHST`, `PerceptionHandler` o barare (punto 6).
3. Elezione: tenere `legacyElection` o passare alla regola nuova, e quando (punto 7).
4. `UnitHST`: resta in STAI o diventa un `UnitHandler` del runtime (punto 8).
5. `collect` di `MapHST`: resta o va tolta (punto 9).

## 5. Ordine di lavoro proposto

Un compito per riga, come per il framework; l'impegno si decide compito per compito.

1. **Partenza**: branch `stai/porting`; tre partite A di riferimento (la variabilità fra partite è grande: 146–201 unità, 15–37 mex); controllo che STAI giri com'è oggi.
2. **Scheduler** (punto 1): liste nella classe, via `SchedulerHST` e i controlli di turno. Confronto con le partite di riferimento.
3. **Ambiti globali** (punti 2 e 4): `ArmyHST`, poi `MapHST`.
4. **Discussione con l'utente sulla griglia** (punto 5), poi **ambiti d'alleanza** (punti 3 e 4) con la griglia nuova.
5. **Percezione** (punto 6), secondo la decisione.
6. **Elezione** (punto 7), secondo la decisione.
7. **Difetti noti e ordini grandi** (punti 10 e 11).
8. **`shard_null`** (punto 12).
9. **Chiusura**: guida per STAI, partite finali, branch pulito.

## 6. Come si verifica

- **Partita A**: STAI contro SimpleAI, Comet Catcher Remake 1.8, 15 minuti, `SHARD_MEM_STATS=1`, con `.ai-notes/tools/run_engine_game.sh`. Righe da confrontare: unità ai minuti 1/5/10/13, unità, fabbriche e mex a fine partita, messaggi/ordini/rifiutati del relay, memoria per frame, heap, righe `[AI Loader] error`.
- **Riferimenti** (sul framework, prima del porting): circa 145–194 unità a fine partita, 15–37 mex, circa 15.000 ordini, 10–15 rifiutati, memoria media 0,2–0,7 KB per frame, heap 13–15 MB. Una partita sola non basta per dire che un cambio peggiora il gioco: servono almeno tre partite.
- **Controlli**: test busted con prova delle mutazioni, StyLua 2.5.2, EmmyLua 0.24.0, `lx --lua-version 5.1 test`, `.ai-notes/tools/run_engine_tests.sh`.

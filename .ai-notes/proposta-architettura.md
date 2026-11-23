# Nuovo framework AI Lua per BAR — proposta di architettura

Nov 22, 2026 · @bio

## Sintesi

La proposta è una **nuova versione di Shard**, non un framework diverso: stessa struttura di cartelle, stesse classi (`ShardAI`, `Module`, `Behaviour`, `Unit`, `BehaviourFactory`), stessi callback e stesso stile di scrittura, così che i moduli e i behaviour di STAI si portino con modifiche minime. Cambia ciò che sta sotto: `AILoader.lua` gira nel lato **unsynced solo sul client che ospita le AI** e affida gli ordini a un piccolo relay **synced** che ne verifica mittente e proprietà; i moduli possono dichiarare un ambito (team, ally team, globale) per non ripetere lo stesso lavoro per ogni AI.

L'organizzazione in tre ambiti (globale, ally team, team) elimina il lavoro ripetuto per ogni AI. Le scelte che reggono il progetto correggono una per una i difetti strutturali trovati in Shard/STAI ([analisi tecnico-strutturale](https://claude.ai/artifact/LXgMjkgunz9TUyAgm2gdxt)):

| # | Decisione | Difetto di Shard/STAI che elimina |
| --- | --- | --- |
| 1 | **Shard resta Shard**: stessa struttura, stesse classi e callback, stesso accesso `self.ai.<nome>`; le modifiche stanno nel runtime e nel loader | — (vincolo di progetto: il codice esistente si porta con modifiche minime) |
| 2 | **Tre ambiti** dichiarati dal modulo con `Scope()`: `team`, `ally`, `global`. Un modulo condiviso si istanzia una volta e resta raggiungibile come `self.ai.<nome>` | analisi della mappa, metal spot, LOS/radar e insiemi di unità calcolati una volta per AI |
| 3 | Tutte le AI di un ally team girano sullo stesso client, scelto dal registro dell'host | AI calcolata e ordini inviati da ogni client |
| 4 | Relay synced dentro `AILoader.lua` che accetta solo messaggi del client host e solo per unità dei team AI che ospita | canale d'ordini aperto a qualunque client |
| 5 | I file di ogni tipo di AI si caricano in un ambiente proprio; `ai`, `game`, `map` e `shard_include` restano, impostati da `Prepare()` come oggi | classi globali sovrascritte fra AI di tipo diverso |
| 6 | I callback arrivano solo ai moduli e ai behaviour che li implementano, e solo per l'ambito che li riguarda | broadcast di ogni evento a ogni AI e a ogni modulo |
| 7 | Lo scheduler di STAI (`SchedulerHST`) entra nel runtime, con un budget per frame | `Update` chiamato a ogni frame anche fuori turno; GC completa forzata |
| 8 | `game` e `map` filtrano i nemici secondo la percezione dell'ally team, `fair` per default | AI onnisciente; LOS/radar ricalcolati da ogni AI |
| 9 | I comandi di `ShardUnit` (`Move`, `Build`, `Attack`…) e `game:GiveOrder` tornano a funzionare sopra una coda binaria, un messaggio per frame | comandi di `ShardUnit` disattivati; una stringa di testo per ogni ordine |
| 10 | `map:GetMetalSpots()` restituisce i metal spot già calcolati da BAR | metal spot ricalcolati per ogni AI con un algoritmo difettoso |

Tutti i valori numerici di questo documento (budget, soglie, dimensioni) sono **obiettivi proposti**: vanno tarati con la fase 0 di misura prima di diventare requisiti.

## Fedeltà a Shard: cosa resta, cosa cambia sotto

Chi conosce Shard deve ritrovare tutto al suo posto: stessi file, stesse classi, stessi callback, stesso modo di scrivere moduli e behaviour. Le modifiche per prestazioni e sicurezza stanno nel runtime e in `AILoader.lua`; dove toccano il codice delle AI sono poche righe, elencate qui.

| Elemento di Shard | Nel nuovo runtime | Per chi scrive l'AI |
| --- | --- | --- |
| `AILoader.lua` | resta il gadget che carica le AI; il lato unsynced lavora solo sul client host, il lato synced ospita il relay e il registro dell'host | niente |
| `shard_runtime/`: `class`, `AIBase`, `Module`, `Behaviour`, `Unit`, `ShardAI`, `api`, `spring_lua/` | stessi file e stesse classi, recuperati dal codice rimosso e corretti | niente |
| `ai/<NomeAI>/`: `boot.lua`, `ai.lua`, `modules.lua`, `behaviours.lua`, `behaviourfactory.lua` | stessa struttura; `boot.lua` restituisce ancora l'istanza (`return STAI()`) | niente |
| `shard_include` | stessa ricerca: prima la cartella dell'AI, poi il runtime | carica nell'ambiente del tipo di AI (§ Caricamento delle AI e ciclo di vita) |
| `Name()`, `internalName()`, `self.ai.<internalName>`, `self.game`, `self.map`, `EchoDebug`, `Warn` | invariati | niente |
| globali `ai`, `game`, `map`, impostate da `Prepare()` | restano | niente; `Prepare()` si chiama solo quando cambia l'oggetto di turno |
| `Module:Scope()` | nuovo e obbligatorio (se manca, o ha un valore sconosciuto, il modulo non si carica e il runtime avvisa): `"team"`, `"ally"` o `"global"` | ogni modulo dichiara il proprio ambito; un modulo condiviso usa `self.ai.allyId` o l'elenco `self.ai.AIs` al posto di `self.ai.id` |
| callback `Init`, `Update`, `GameEnd`, `UnitCreated`, `UnitBuilt` (smistato in `MyUnitBuilt`, `FriendlyUnitBuilt`, `EnemyUnitBuilt`, `NeutralUnitBuilt`), `UnitDead`, `UnitIdle`, `UnitDamaged`, `UnitMoveFailed`, i quattro di visibilità; `Owner*` nei behaviour | stesse firme | arrivano solo a chi li ridefinisce (§ Consegna dei callback) |
| `SchedulerHST` di STAI: `MScheduler`, `BScheduler`, `moduleTeam`, `moduleUpdate` | entra nel runtime: uno per client, con budget | le liste passano alla classe dell'AI; le righe di controllo in `Update` restano valide |
| `UnitHST` di STAI, `UnitHandler` dell'AI d'esempio di Shard | entra nel runtime come `UnitHandler` | in `modules.lua` `UnitHST` diventa `UnitHandler`; la `BehaviourFactory` resta dell'AI |
| `Unit:ElectBehaviour()` | stessa semantica documentata, codice corretto | due casi cambiano; c'è un'opzione di compatibilità (§ Unità e behaviour) |
| metodi d'ordine di `ShardUnit`: `Move`, `Build`, `Attack`, `Reclaim`… | tornano a dare ordini, attraverso la coda binaria | niente |
| `Tool:GiveOrder(id, cmd, params, options, method)` di STAI | diventa `game:GiveOrder`, stessa firma e stessi codici `'1-1'`, `'2-1'`, `'1-2'`, `'2-2'` | una riga in `tool.lua` |
| `game:GetEnemies()`, `game:GetFriendlies()`, `game:GetUnits()` | stessi nomi | `GetEnemies()` restituisce solo i nemici che l'ally team vede, in modalità `fair` |
| `map:GetMetalSpots()`, `map:GetGeoSpots()` | stessi nomi | metal spot letti da BAR, geo spot calcolati una volta per client |
| `Sleep:Wait(functor, frames)`, `SleepST:Wait` | stessa firma | niente; sotto c'è il timer dello scheduler, senza scansione a ogni frame |
| `shard_null/` | resta, per i test busted senza engine | niente |
| `spring_cpp/`, `hooks.lua`, protocollo STGO, GC forzata | rimossi | niente |

**Cosa controllare nel porting di STAI.** Oltre alle due righe di `modules.lua` e `tool.lua` e allo spostamento delle liste di `SchedulerHST`, tre punti: i moduli che diventano condivisi e usano `self.ai.id` (§ Tre ambiti); i behaviour che fanno qualcosa in `Activate` pur avendo priorità zero (§ Unità e behaviour); le letture dirette con `Spring.*` di unità nemiche, che il runtime non filtra (§ Modello del mondo e percezione).

**Formattazione e nomi.** I file di Shard e di STAI rientrano in BAR come codice nuovo, quindi passano per intero da StyLua: cambiano spazi e a capo, non la struttura né i nomi. Le regole di BAR chiedono `PascalCase` per le globali e di preferire i nomi già usati dal codice vicino: le classi di Shard (`ShardAI`, `EcoHST`, `LabsBST`) le rispettano già.

## Contesto: cosa c'è oggi

Si parte da zero sul framework, ma non sull'ambiente: BAR e Recoil offrono già quasi tutti i mattoni necessari, e conviene appoggiarsi a quelli invece di ricostruirli.

| Elemento | Stato al 22 nov 2026 | Uso nella proposta |
| --- | --- | --- |
| Shard e STAI | rimossi da BAR il 19 giu 2026 (commit `3ad8f3fb`, PR #8004); la storia git li conserva | base del nuovo runtime: si recupera quasi tutto (§ Cosa recuperare dal codice rimosso) |
| Shard nativo | assente da Recoil; `AI/Skirmish` contiene BARb, CampaignAI, CircuitAI, CppTestAI, NullAI | nessuno |
| BARb | CircuitAI (C++) ramo `barbarian` + 32 script AngelScript in `luarules/configs/BARb/` | termine di paragone per forza e costo |
| SimpleAI | gadget synced di 872 righe in `luarules/gadgets/ai_simpleai.lua`, ordini con `GiveOrderToUnit` | esempio del modello synced ancora accettato in BAR |
| `luaai.lua` | elenca le Lua AI selezionabili nel lobby | punto di registrazione della nuova AI |
| Metal e geo spot | `api_resource_spot_finder` (gadget synced, layer −9) li calcola una volta e li pubblica in `GG.resource_spot_finder` e nei game rules param `mex_count`, `mex_x<i>`, `mex_y<i>`, `mex_z<i>`, `mex_metal<i>` (commento nel codice: "used by AI") | da riusare, niente ricalcolo |
| Test | busted via lux (`spec/`, builder `spring_synced_builder` e `spring_unsynced_builder`), test d'integrazione headless in Docker (`tools/headless_testing/`, `luaui/Tests/`) | base della strategia di test |
| Regole di contributo | `.github/agents.md` (synced deterministico, niente allocazioni nei call-in per frame, limiti di 200 locali e 60 upvalue per funzione), StyLua 2.5.2, EmmyLua 0.24.0, `AI_POLICY.md` | vincoli di stile e di processo |

Fatti dell'engine verificati nei sorgenti di Recoil e usati nel resto del documento:

- `RecvLuaMsg(msg, playerID)` riceve sempre il `playerID` del mittente, assegnato dal server: è la base dell'autenticazione (`rts/Lua/LuaHandle.cpp`).
- `Spring.SendLuaRulesMsg` non filtra spettatori e accetta byte arbitrari, zeri compresi; il pacchetto ha un tetto di 65.535 byte complessivi (`rts/Net/Protocol/BaseNetProtocol.cpp`).
- `Spring.GetAIInfo(teamID)` restituisce `skirmishAIID, name, hostingPlayerID, …` anche nel synced (`rts/Lua/LuaSyncedRead.cpp`).
- `Spring.GiveOrderToUnit` nell'unsynced funziona solo per team che il giocatore locale controlla: il giocatore che ospita una Lua AI non controlla il team dell'AI, quindi un relay synced è obbligatorio (`rts/Lua/LuaUnsyncedCtrl.cpp`, `rts/Game/Players/Player.cpp`).
- `Spring.GetTimer` e `Spring.GetTimerMicros` esistono solo nell'unsynced: un budget in millisecondi è possibile solo lì (`rts/Lua/LuaUnsyncedRead.cpp`).
- `VFS.PackU8/U16/U32/S8/S16/S32/F32` e i corrispondenti `Unpack*` sono disponibili per una codifica binaria (`rts/Lua/LuaVFS.cpp`).

## Obiettivi, non-obiettivi e requisiti

Il runtime deve restare Shard per chi scrive le AI, essere sicuro e onesto per costruzione, costare poco e solo a chi ospita l'AI, e rendere misurabile ogni affermazione sulle prestazioni.

**Obiettivi.**

1. Chi conosce Shard ritrova la stessa struttura, le stesse classi e lo stesso stile; un'AI scritta per Shard, come STAI, si porta con modifiche minime.
2. Nessun client diverso dall'host può far eseguire ordini a unità dell'AI, né ad altre unità.
3. Il costo dell'AI ricade solo sul client che la ospita; gli altri pagano solo la validazione nel relay.
4. La percezione dell'AI è una scelta di configurazione, non un effetto collaterale.
5. Il costo per frame è limitato e osservabile per modulo, e nessun calcolo uguale per più AI viene ripetuto: ciò che è comune si calcola una volta nell'ambito globale o d'ally team.
6. Un'AI si scrive con moduli e behaviour piccoli e testabili senza avviare l'engine.

**Non-obiettivi.** Il backend nativo di Shard (`spring_cpp`); il supporto di giochi diversi da BAR; battere BARb nella prima versione.

**Requisiti misurabili (obiettivi proposti).**

| Requisito | Soglia proposta | Come si verifica |
| --- | --- | --- |
| Costo medio sull'host | media ≤ 0,2 ms per frame per AI, sul tempo dello scheduler e dei callback, senza la GC dell'engine; misura dopo 15 minuti di gioco con circa 200 unità proprie (BARb: 0,05 ms a 164 unità) | zone Tracy, scenario standard della fase 0 |
| Picchi sull'host | 99° percentile ≤ 1 ms per AI, stesse condizioni (BARb: 0,31 ms; la GC dell'engine ha da sola un p99 di circa 1,4 ms e resta fuori) | stessa misura |
| Costo sui client non host | overhead del relay ≤ 0,05 ms per frame per AI (esclusa l'esecuzione degli ordini, che ogni client paga comunque); nessun codice dell'AI eseguito | Tracy su un client spettatore |
| Ordini in rete | di norma 1 messaggio per frame per AI (2 solo se la coda supera 60.000 byte); dimensione media ≤ 2 KB | contatori del relay |
| Costo degli ordini su ogni client | ≤ 25 ordini per frame per AI in media, circa 0,1 ms per client; conta fuori dal budget dell'host perché lo pagano tutti | contatori dell'outbox e del relay |
| Latenza aggiunta | nessuna oltre la fine del frame in cui l'ordine è emesso | timestamp di emissione e di esecuzione |
| Memoria | nessuna `collectgarbage("collect")` esplicita; heap dell'AI stabile dopo 10 minuti | `gcinfo()` campionato ogni 300 frame |
| Sicurezza | 0 ordini accettati da mittenti non host, in un test che li invia di proposito | test d'integrazione headless |
| Percezione "fair" | 0 letture di tipo, salute o posizione di unità nemiche fuori da LOS/radar | test con la tabella `Spring` strumentata nell'ambiente dell'AI |
| Robustezza | un errore in un modulo non ferma gli altri; l'AI riprende dopo un reload di LuaRules | test d'integrazione con modulo che lancia errori |

## Scelta dell'host

Raccomando l'esecuzione **unsynced sul solo client host**, perché è l'unica che tiene il costo dell'AI su una macchina sola; il prezzo è un relay da progettare con cura. Il synced resta un'alternativa supportata dallo stesso runtime.

| Criterio | Synced (come SimpleAI) | Unsynced, solo host (proposta) | Skirmish AI nativa |
| --- | --- | --- | --- |
| Chi paga la CPU | ogni client; un frame lento dell'AI rallenta la simulazione di tutti | solo l'host | solo l'host |
| Ordini | `GiveOrderToUnit` diretto | messaggio di rete + relay synced | comando binario dell'interfaccia AI |
| Vincoli sul codice | determinismo totale: niente timer, niente dati unsynced, niente ordine di iterazione dipendente da indirizzi | nessuno | C++ o un linguaggio di scripting incluso |
| Budget di tempo | solo in "unità di lavoro" (`GetTimer` non esiste nel synced) | in microsecondi con `Spring.GetTimerMicros` | libero |
| Sicurezza | intrinseca | da progettare (autenticazione nel relay) | intrinseca |
| Percezione | da filtrare a mano | da filtrare a mano | filtrata dall'engine |
| Distribuzione | nell'archivio del gioco | nell'archivio del gioco | con l'engine, ciclo di rilascio di Recoil |
| Esiste già in BAR | SimpleAI | no (STAI ci provava, senza sicurezza né elezione) | BARb |

**Perché non il synced come scelta principale.** Un'AI di media complessità spende millisecondi per frame: nel synced quel tempo si moltiplica per ogni client e allunga il frame di simulazione per tutti i giocatori. Va bene per AI leggere come SimpleAI, non per un framework pensato per AI più ambiziose.

**Perché non il nativo.** Rifarebbe in un altro linguaggio quello che BARb già offre, e legherebbe ogni modifica al ciclo di rilascio dell'engine.

**Elezione e cambio dell'host.** L'host si assegna per ally team, non per singola AI, perché l'ambito ally team deve stare su un solo client (§ Tre ambiti). L'host iniziale di un ally team è l'`hostingPlayerID` restituito da `Spring.GetAIInfo` per il suo primo team AI; lo start script può indicare host diversi per AI alleate, e il registro li unifica. Il lato synced scrive l'host effettivo di ogni team AI in un team rules param pubblico (`aiHostPlayer`), uguale per tutti i team dello stesso ally team. Se quel giocatore lascia la partita (call-in synced `PlayerRemoved`), il synced sceglie un successore per l'intero ally team con una regola deterministica:

1. il giocatore attivo non spettatore con ID più basso nello stesso ally team dell'AI;
2. altrimenti, il giocatore attivo con ID più basso.

Ogni client unsynced confronta `aiHostPlayer` con `Spring.GetMyPlayerID()`: chi diventa host avvia l'AI con la procedura di recupero (§ Caricamento delle AI e ciclo di vita). La memoria interna dell'AI precedente va persa; il mondo invece si ricostruisce dalle unità esistenti.

**Modalità synced dello stesso runtime.** Il runtime non sa dove gira: cambia solo il lato di `AILoader.lua` che lo ospita. In synced gli ordini si applicano direttamente e lo scheduler conta unità di lavoro invece di microsecondi. Serve per AI leggere e per test riproducibili.

## Lavoro ripetuto o inutile in Shard e STAI

In Shard e STAI quasi tutto ciò che riguarda la mappa e la visibilità veniva calcolato una volta per AI, anche quando il risultato era identico per tutte o per tutte le AI di un ally team; altro lavoro veniva eseguito senza che nessuno ne usasse il risultato. È il motivo principale della struttura ad ambiti della sezione seguente.

| Lavoro | Dove (versione rimossa da BAR) | Quante volte veniva fatto | Quante volte serve | Ambito nel nuovo framework |
| --- | --- | --- | --- | --- |
| Scansione di metal spot e geo spot | `shard_runtime/spring_lua/metal.lua`, `geo.lua`, inclusi da `api.lua` | una volta per AI (`api.lua` viene eseguito per ogni AI) | metal: mai, BAR li pubblica; geo: una volta per partita | globale |
| Analisi della mappa: griglia, layer, topologia, hot spot | `STAI/maphst.lua`, `MapHST:Init` (il flag `map_loaded` è per istanza) | una volta per AI | una volta per partita | globale |
| Tracciamento LOS/radar dei nemici | `STAI/loshst.lua`: i call-in sono filtrati sull'ally team, ma ogni AI tiene la propria copia | una volta per AI, anche con più AI nello stesso ally team | una volta per ally team | ally team |
| Griglie dei contatti nemici | `LosHST:Update`: libera tutte le celle e le ricostruisce per ogni contatto | ricostruzione completa a ogni turno | aggiornamento incrementale sui cambi | ally team |
| Insiemi di unità proprie, alleate, nemiche, neutrali | `AILoader.lua`, `gadget:UnitCreated` | cinque insiemi per ogni AI, aggiornati a ogni creazione | un registro unico con viste per ally team e team | globale |
| Oggetto danno per evento | `AILoader.lua`, `gadget:UnitDamaged` → `shardify_damage` | uno per evento, anche se nessun modulo lo usa | nessuno senza destinatari | consegna dei callback |
| Consegna degli eventi | `ShardAI` a tutti i moduli, `Unit` a tutti i behaviour | ogni evento × AI × moduli | solo a chi ridefinisce il callback | consegna dei callback |
| Turni dei moduli | `STAI/schedulerHST.lua`: ogni AI ha una propria copia dello scheduler; ogni modulo riceve `Update` a ogni frame e ritorna subito se non è il suo turno | moduli × AI chiamate per frame, quasi tutte a vuoto | solo il modulo di turno | scheduler unico per client |
| `Update` di tutti i behaviour a ogni frame | `shard_runtime/unit.lua`, `Unit:Update` | tutti i behaviour di ogni unità, a ogni frame | solo i behaviour della classe di turno (`BScheduler`) | scheduler unico per client |
| Eventi di unità nemiche non visibili | `AILoader.lua` inoltra fine costruzione, danni, idle di tutte le unità | sempre | mai in modalità `fair` | ally team (percezione) |
| `Prepare()` e GC completa | `AILoader.lua` | prima di ogni evento per ogni AI; GC ogni 121 frame oltre soglia | `Prepare()` solo quando cambia l'oggetto di turno; GC completa mai | — |

I percorsi abbreviati stanno sotto `luarules/gadgets/ai/` al commit `3ad8f3fb^` di BAR.

## Tre ambiti: globale, ally team, team

Ogni modulo dichiara il proprio ambito con `Scope()` e il runtime lo istanzia una volta per istanza di quell'ambito: una volta per client host, una volta per ally team, una volta per AI. La dichiarazione è obbligatoria, per scelta: un modulo senza Scope(), o con un valore diverso da quei tre, non si carica e il runtime lo segnala con Warn. Meglio un modulo assente e un avviso che un ambito sbagliato per dimenticanza. Ciò che è uguale per tutti si calcola una volta sola e resta raggiungibile da ogni AI con il solito `self.ai.<internalName>`.

&#91;embedded content: tre ambiti · globale, ally team, team\]

| Ambito | Istanze | Contenuto | Chi lo scrive | Chi lo legge |
| --- | --- | --- | --- | --- |
| Globale | una per client host (`ShardGlobal`) | analisi della mappa (griglia, raggiungibilità per move class, acqua e terra), mex e geo, metadati, catalogo dei `UnitDefs` con categorie precalcolate, registro di tutte le unità (chi è di chi), servizio percorsi | solo i moduli globali | tutti |
| Ally team | una per ally team che contiene almeno un'AI Shard (`ShardAlly`) | percezione LOS/radar, memoria dei nemici e strutture fantasma, mappa delle minacce, prenotazioni dei siti di costruzione, obiettivi condivisi e coordinamento fra AI alleate | solo i moduli dell'ally team | moduli dello stesso ally team e i suoi team |
| Team | una per AI: l'istanza della classe dell'AI, per esempio `STAI` | moduli di team: economia, produzione, `UnitHandler` con unità e behaviour, coda degli ordini, generatore casuale | solo i moduli del team | solo il team |

**Regole.**

1. *Dipendenze solo verso l'alto.* Un team legge l'ally team e il globale; l'ally team legge il globale; il globale non conosce né ally team né team.
2. *Scrive solo il proprietario.* Un modulo di team che vuole cambiare un dato dell'ally team (per esempio un avvistamento o una prenotazione) chiama un metodo del modulo che lo possiede, come si fa già fra moduli in STAI (`self.ai.loshst`, `self.ai.buildingshst`): è quel modulo a decidere e a scrivere.
3. *La percezione è dell'ally team.* In modalità `fair` i team vedono i nemici solo attraverso l'ally team: lo stesso dato per tutte le AI alleate, calcolato una volta.
4. *Moduli di AI diverse.* I servizi del runtime (percezione, metal e geo spot, registro delle unità) sono condivisi da tutte le AI; i moduli d'ally team e globali scritti da una specifica AI sono condivisi solo fra team con la stessa AI (stessa cartella `ai/<NomeAI>/`).
5. *Alleati umani.* L'ally team esiste anche se contiene giocatori umani: l'engine condivide il LOS dentro l'ally team, quindi la percezione resta corretta.

**Dove gira ciascun ambito.** L'ambito ally team deve stare su un solo client: il registro dell'host assegna quindi **un host per ally team**, e tutte le AI del framework di quell'ally team girano su quel client. L'ambito globale si calcola una volta per client host: se ally team diversi sono ospitati da client diversi, ogni host lo calcola per conto suo, sempre molto meno di una volta per AI. Un'opzione di configurazione può imporre **un solo host per tutta la partita**, che massimizza la condivisione ma concentra la CPU su un solo giocatore.

**Callback e scheduler per ambito.** Un call-in entra una volta e va agli ambiti interessati: `UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)` raggiunge solo l'ally team indicato, quindi il `LosHST` di quell'ally team lo riceve una volta, non una volta per AI. Lo scheduler è uno per client e fa girare a turno moduli globali, d'ally team e di team, perché nessuna AI resti senza tempo.

**Come si dichiara.** Un metodo in più, nello stesso stile di `Name()` e `internalName()`:

```lua
LosHST = class(Module)

function LosHST:Name()
	return "LosHST"
end

function LosHST:internalName()
	return "loshst"
end

function LosHST:Scope()
	return "ally" -- obbligatorio: senza Scope() il modulo non si carica
end

function LosHST:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
	-- arriva una volta per ally team: il controllo su allyTeam di STAI resta vero e si può togliere
end
```

**Esempio: i moduli di STAI.** Una prima ipotesi, da verificare durante il porting:

| Moduli di STAI | Ambito | Motivo | Da cambiare |
| --- | --- | --- | --- |
| `ArmyHST` | global | tabelle dei tipi di unità ricavate dai `UnitDefs`, uguali per tutti | niente: non usa né il team né l'ally team |
| `MapHST` | global | griglia, layer, topologia, metal e geo spot sono gli stessi per tutte le AI; oggi il flag `map_loaded` vale per istanza, quindi l'analisi si ripete per ogni AI | le funzioni che dipendono dal team o dall'ally team (`ClosestFreeMex` usa `buildingshst`, `loshst` e `targethst`; i costi dei nodi di percorso usano `game:GetTeamID()`) ricevono l'AI come parametro o passano in un modulo di team; il `collectgarbage("collect")` alla fine di `Init` va tolto |
| `LosHST` | ally | i call-in di visibilità sono già filtrati su `self.ai.allyId` | `UnitCreated` riconosce le unità proprie con `self.ai.id`: nell'ally team diventano le unità dei team in `self.ai.AIs`. `Init` scrive `self.ai.friendlyTeamID`, che `DamageHST` legge: con `LosHST` d'ally team quel campo sta su `ShardAlly` |
| `TargetHST`, `DamageHST` | ally, da verificare | lavorano sulle griglie di `LosHST` e sui danni alle unità proprie e alleate | gli usi di `self.ai.id` e di `game:GetTeamID()` |
| `EcoHST`, `LabsHST`, `AttackHST`, `RaidHST`, `BomberHST`, `ScoutHST`, `BuildingsHST`, `EngineerHST`, `CleanHST`, `TasksHST`, `Tool` | team | dati e decisioni del singolo team | niente |
| `SchedulerHST`, `UnitHST`, `SleepST` | nel runtime | servono a tutte le AI | le liste di `SchedulerHST` passano alla classe `STAI`; `UnitHST` lascia il posto a `UnitHandler` |

## Architettura d'insieme

Gli strati restano quelli di Shard: `AILoader.lua` parla con l'engine e smista i call-in; `shard_runtime/` contiene le classi base e l'API (`game`, `map`, `ShardUnit`); le cartelle delle AI contengono moduli e behaviour. In più c'è un relay synced, dentro `AILoader.lua`, che è l'unico punto in cui una decisione diventa un ordine.

&#91;embedded content: architettura proposta · lato unsynced sull'host, relay synced su ogni client\]

Le dipendenze vanno in una sola direzione: moduli e behaviour usano `self.game`, `self.map`, `ShardUnit` e gli altri moduli; l'API usa l'engine. Come in STAI, moduli e behaviour possono chiamare anche `Spring.*` direttamente: la percezione `fair` vale per ciò che passa dall'API e si verifica nei test (§ Modello del mondo e percezione); i test senza engine usano `shard_null`.

**Struttura dei file**, quella di Shard (i file nuovi sono segnati):

```
luarules/gadgets/ShardAILoader.lua                               -- gadget: unsynced solo sull'host; synced con relay e registro dell'host
luarules/gadgets/ai/shard_runtime/                          -- class, aibase, module, behaviour, unit, shardai, api: come prima
luarules/gadgets/ai/shard_runtime/shardally.lua             -- nuovo: contenitore dei moduli con Scope() "ally"
luarules/gadgets/ai/shard_runtime/shardglobal.lua           -- nuovo: contenitore dei moduli con Scope() "global"
luarules/gadgets/ai/shard_runtime/unithandler.lua           -- da UnitHandler di Shard e UnitHST di STAI
luarules/gadgets/ai/shard_runtime/scheduler.lua             -- da SchedulerHST di STAI: uno per client, con budget
luarules/gadgets/ai/shard_runtime/sleep.lua                 -- Sleep di Shard sopra il timer dello scheduler
luarules/gadgets/ai/shard_runtime/spring_lua/               -- game, map, unit, unittype, feature, damage, shard: come prima
luarules/gadgets/ai/shard_runtime/spring_lua/outbox.lua     -- nuovo: coda degli ordini e codifica binaria
luarules/gadgets/ai/shard_runtime/spring_lua/perception.lua -- nuovo: contatti LOS/radar per ally team
luarules/gadgets/ai/shard_runtime/shard_null/               -- API finta per i test senza engine: come prima
luarules/gadgets/ai/<NomeAI>/                               -- boot.lua, ai.lua, modules.lua, behaviours.lua, behaviourfactory.lua, *hst.lua, *bst.lua
luaui/Widgets/shard_help_draw.lua                           -- disegno di debug, recuperato e diviso in canali
spec/shard_runtime/                                         -- test busted senza engine
luaui/Tests/shard/                                          -- test d'integrazione headless
```

**Nome del loader (23 nov 2026).** Il nuovo loader si chiama `ShardAILoader.lua`. Nel resto del documento `AILoader.lua` indica il loader di Shard rimosso da BAR oppure, nelle parti scritte prima di questa decisione, il nuovo loader con il vecchio nome.

## Caricamento delle AI e ciclo di vita

Il caricamento è quello di Shard: `AILoader.lua` trova i team con una Lua AI che ha `luarules/gadgets/ai/<NomeAI>/boot.lua`, include `boot.lua`, che restituisce l'istanza dell'AI (`return STAI()`), e ne chiama `Init()`. Cambiano tre cose: si carica solo sul client host, ogni tipo di AI ha un ambiente proprio, e i moduli condivisi si istanziano una volta per ambito.

### Gli oggetti di ogni ambito

| Ambito | `self.ai` nei suoi moduli | Campi principali | Moduli raggiungibili come `self.ai.<internalName>` |
| --- | --- | --- | --- |
| team | l'istanza della classe dell'AI (`STAI`, sottoclasse di `ShardAI`), una per AI | `id`, `allyId`, `fullname`, `game`, `map`, `modules` | tutti: i propri, quelli dell'ally team e quelli globali |
| ally | `ShardAlly`, uno per ally team e per tipo di AI | `allyId`, `AIs` (le AI di quel tipo nell'ally team), `game`, `map`, `modules` | quelli d'ally team e quelli globali |
| global | `ShardGlobal`, uno per client host e per tipo di AI | `AIs` (tutte le AI di quel tipo ospitate dal client), `game`, `map`, `modules` | quelli globali |

Le dipendenze solo verso l'alto vengono dalla forma degli oggetti: in un modulo d'ally team `self.ai` non contiene moduli di team, in un modulo globale non contiene né moduli d'ally team né di team. Un modulo di team raggiunge tutti, quindi il codice di STAI che scrive `self.ai.loshst` o `self.ai.maphst` resta uguale anche quando quei moduli diventano condivisi. `ShardAlly` e `ShardGlobal` derivano da `ShardAI` e ne riusano il caricamento dei moduli, filtrato per `Scope()`; i behaviour restano sempre di team, legati alla propria unità.

### Un ambiente per ogni tipo di AI

I file di un'AI si caricano con `VFS.Include(file, env)`: `env` è una tabella propria di quel tipo di AI che rimanda (`__index`) all'ambiente del gadget, quindi `Spring`, `UnitDefs`, `CMD`, `class`, `Module` e le altre classi di Shard restano visibili come prima. Le classi che l'AI definisce (`STAI`, `EcoHST`, `LabsBST`…) finiscono in `env` e non sovrascrivono quelle di un'altra AI con lo stesso nome; `shard_include` carica nello stesso ambiente. Non è una sandbox: il codice dell'AI può chiamare `Spring.*`, come fa STAI. Ogni tipo di AI si legge una volta: `boot.lua` restituisce la prima istanza e le altre AI dello stesso tipo si creano dalla stessa classe, senza rileggere i file. I percorsi VFS non distinguono maiuscole e minuscole (Recoil li normalizza), quindi `shard_include("schedulerhst")` trova `STAI/schedulerHST.lua`, come succedeva già.

Un'AI minima nello stile di Shard, con un modulo per ambito:

```lua
-- luarules/gadgets/ai/Esempio/boot.lua
shard_include("ai")
return EsempioAI()

-- luarules/gadgets/ai/Esempio/ai.lua
EsempioAI = class(ShardAI)

function EsempioAI:Name()
	return "EsempioAI"
end

function EsempioAI:internalName()
	return "esempioai"
end

function EsempioAI:Perception()
	return "fair" -- "fair" se assente; "omniscient" per i livelli che barano
end

EsempioAI.MScheduler = { "EcoHST", "LosHST" } -- turni a rotazione, come in SchedulerHST
EsempioAI.BScheduler = { "BuildersBST" }

-- luarules/gadgets/ai/Esempio/modules.lua
shard_include("maphst")
shard_include("loshst")
shard_include("ecohst")

return {
	MapHST, -- Scope() "global": uno per client host
	LosHST, -- Scope() "ally": uno per ally team
	EcoHST, -- Scope() "team": uno per AI, come in Shard
	UnitHandler, -- dal runtime: unità e behaviour
}

-- luarules/gadgets/ai/Esempio/ecohst.lua
EcoHST = class(Module)

function EcoHST:Name()
	return "EcoHST"
end

function EcoHST:internalName()
	return "ecohst"
end

function EcoHST:Scope()
	return "team"
end

function EcoHST:Init()
	self.DebugEnabled = false
	self.spots = self.map:GetMetalSpots() -- letti da BAR, non ricalcolati
end

function EcoHST:Update()
	local metal = Spring.GetTeamResources(self.ai.id, "metal") -- Spring.* resta permesso, come in STAI
	local enemies = self.game:GetEnemies() -- solo i nemici che l'ally team vede
	local seen = self.ai.loshst:posInLos(self.spots[1]) -- LosHST dell'ally team, stesso accesso di sempre
	self:EchoDebug("metallo", metal, "nemici visti", #enemies, "primo spot in LOS", seen)
end

function EcoHST:MyUnitBuilt(engineUnit)
	self:EchoDebug("finita", engineUnit:Name())
end
```

### Ciclo di vita

1. **Caricamento del gadget.** Come oggi: `AILoader.lua` legge i team con `Spring.GetTeamLuaAI` e tiene quelli che hanno `luarules/gadgets/ai/<NomeAI>/boot.lua`. Nessun team → il gadget non si carica (`return false`, come oggi).
2. **Registro synced.** Per ogni team AI il lato synced scrive `aiHostPlayer` = `hostingPlayerID` di `Spring.GetAIInfo`, uguale per tutti i team dello stesso ally team.
3. **Attivazione unsynced.** Ogni client confronta `aiHostPlayer` con `Spring.GetMyPlayerID()`; solo l'host carica le AI: per ogni tipo crea l'ambiente e include `boot.lua`, crea uno `ShardGlobal` per tipo e uno `ShardAlly` per ally team, imposta `id`, `allyId` e `fullname` di ogni AI come faceva `SetupAI`, poi chiama `Init()` nell'ordine globale → ally team → team. Il seme casuale di ogni AI diventa un hash di GameID e `teamID`: oggi `Shard.randomseed` è la somma dei byte del GameID, la stessa per tutte le AI.
4. **Recupero.** Se la partita è già iniziata (reload di LuaRules o cambio di host), il runtime rigenera `UnitCreated` e `UnitBuilt` per le unità esistenti, come faceva `AILoader.lua`, con gli stessi filtri degli eventi normali.
5. **Ogni frame.** Attivazione dei behaviour eletti → attese scadute → turni dello scheduler fino al budget → la coda d'ordini di ogni AI diventa al massimo un messaggio → telemetria.
6. **Fine.** `GameOver` → `GameEnd()` su moduli e behaviour, come in Shard → salvataggio delle statistiche.

**Confini d'errore.** Il runtime chiama il codice dell'AI dentro `xpcall`, con traceback. Un modulo che fallisce 3 volte in 300 frame (soglia proposta) va in quarantena: esce dalle liste dei callback e dalla rotazione dello scheduler, il resto dell'AI continua e la telemetria lo segnala.

## Consegna dei callback

Un callback arriva solo a chi lo ridefinisce. Dopo `Init` il runtime confronta i metodi di ogni modulo con quelli di `AIBase`, e quelli di ogni behaviour con quelli di `Behaviour`, e prepara una lista per callback: un modulo che non ridefinisce `UnitDamaged` non viene mai chiamato per un danno. Il costo per evento passa da O(AI × moduli) di `AILoader.lua` a O(destinatari).

**Subito, come in Shard.** I call-in chiamano i callback nel momento in cui arrivano, senza code intermedie: l'ordine degli eventi resta quello dell'engine. Il tempo speso nei callback si misura per modulo; il lavoro pesante resta in `Update`, come già si fa in STAI.

**Instradamento per ambito.** Ogni call-in si elabora una volta per client e arriva solo agli oggetti d'ambito interessati, e lì solo ai moduli che ridefiniscono il callback:

- *globale*: tutti gli eventi che aggiornano il registro delle unità e i dati di mappa (creazione, distruzione, trasferimenti, feature);
- *ally team*: gli eventi di visibilità (`UnitEnteredLos`, `UnitLeftLos`, `UnitEnteredRadar`, `UnitLeftRadar`) solo per l'ally team indicato nel call-in, più gli eventi delle unità dei suoi team;
- *team*: gli eventi delle proprie unità e quelli che la percezione dell'ally team gli rende visibili.

Con due AI nello stesso ally team, un ingresso in LOS arriva una volta al `LosHST` dell'ally team, non due.

| Callback | Call-in di origine | Chi lo riceve | Note |
| --- | --- | --- | --- |
| `UnitCreated(unit, unitDefId, teamId, builderId)` | `UnitCreated` | moduli di team dell'AI proprietaria; moduli d'ally team per le unità dei loro team; moduli globali per le unità degli ally team ospitati dal client | per i moduli di team è come oggi: solo le unità proprie |
| `UnitBuilt(unit)`, smistato da `AIBase` in `MyUnitBuilt`, `FriendlyUnitBuilt`, `EnemyUnitBuilt`, `NeutralUnitBuilt` | `UnitFinished` | AI proprietaria e alleate; per i nemici, solo se in LOS; moduli globali per le unità degli ally team ospitati | lo smistamento di `aibase.lua` non cambia |
| `UnitGiven(unit)` | `UnitGiven` | AI che riceve l'unità | `AIBase:UnitGiven` chiama `UnitCreated` e `UnitBuilt`, come previsto in `aibase.lua`; `AILoader.lua` chiamava solo `UnitCreated`, quindi un'unità ricevuta non passava dall'elezione di fine costruzione |
| `UnitDead(unit)` | `UnitDestroyed`, `UnitTaken` | AI proprietaria e alleate; per i nemici, solo se in LOS o in radar in quel momento; moduli globali per le unità degli ally team ospitati | prima arrivava a tutte le AI |
| `UnitIdle(unit)` | `UnitIdle` | solo l'AI proprietaria | prima arrivava a tutte le AI, per ogni unità |
| `UnitDamaged(unit, attacker, damage)` | `UnitDamaged` | AI proprietaria e alleate dell'unità colpita; per un nemico colpito, solo se visibile | attaccante passato solo se visibile; l'oggetto danno si crea solo se c'è almeno un destinatario |
| `UnitMoveFailed(unit)` | `UnitMoveFailed` | solo l'AI proprietaria | per ora non arriva: l'engine lo manda solo al codice synced e solo per i tipi di unità osservati con `Script.SetWatchUnit`, e `luarules/gadgets.lua` lo tiene commentato fra i call-in opzionali. Per questo `AILoader.lua` non lo inoltrava |
| `UnitEnteredLos`, `UnitLeftLos`, `UnitEnteredRadar`, `UnitLeftRadar` | stessi call-in | solo l'ally team indicato nel call-in | stessa firma `(unitID, unitTeam, allyTeam, unitDefID)` |
| `GameEnd()` | `GameOver` | tutti | `AILoader.lua` non gestiva `GameOver`: `GameEnd` non arrivava mai ai moduli |
| `OwnerCreated`, `OwnerBuilt`, `OwnerIdle`, `OwnerDamaged`, `OwnerMoveFailed`, `OwnerDead` | eventi della propria unità | i behaviour di quell'unità che li ridefiniscono, attivi o no, come in Shard | per ID dell'unità, senza scorrere le altre |

**Regole di consegna.**

1. Ordine: prima i moduli globali, poi quelli d'ally team, poi quelli di team; dentro ogni ambito, l'ordine di `modules.lua`. Un modulo di team trova così già aggiornati i dati condivisi dello stesso evento.
2. Le liste si preparano dopo `Init`, quindi contano anche i callback assegnati all'istanza dentro `Init`; un callback aggiunto più tardi non viene visto.
3. `AIBase:UnitBuilt` smista a `MyUnitBuilt` e agli altri tre: chi ne ridefinisce uno riceve `UnitBuilt`. Allo stesso modo `Behaviour:OwnerMoveFailed` chiama `OwnerIdle`, quindi chi ridefinisce `OwnerIdle` riceve anche `OwnerMoveFailed`.
4. Un modulo in quarantena esce da tutte le liste (§ Caricamento delle AI e ciclo di vita).
5. La telemetria conta chiamate e tempo per modulo e per callback.

```lua
-- shard_runtime/shardai.lua: le liste si preparano una volta, dopo Init
-- Update vale per i moduli fuori da MScheduler; gli altri li chiama lo scheduler nel loro turno
local callbacks = {
	"Update", "GameEnd", "UnitCreated", "UnitBuilt", "UnitDead", "UnitIdle", "UnitDamaged",
	"UnitMoveFailed", "UnitEnteredLos", "UnitLeftLos", "UnitEnteredRadar", "UnitLeftRadar",
}
-- AIBase:UnitBuilt smista a questi quattro: chi ne ridefinisce uno riceve UnitBuilt
local builtHandlers = { "MyUnitBuilt", "FriendlyUnitBuilt", "EnemyUnitBuilt", "NeutralUnitBuilt" }

local function Overrides(object, name)
	return object[name] ~= AIBase[name]
end

function ShardAI:PrepareHandlers()
	self.handlers = {}
	for _, name in ipairs(callbacks) do
		local list = {}
		for i, m in ipairs(self.modules) do
			local wanted = Overrides(m, name)
			if name == "UnitBuilt" then
				for _, handler in ipairs(builtHandlers) do
					wanted = wanted or Overrides(m, handler)
				end
			end
			if wanted then
				table.insert(list, m)
			end
		end
		self.handlers[name] = list
	end
end

-- stesso callback di prima, senza passare dai moduli che non lo usano
function ShardAI:UnitIdle(engineunit)
	if self.gameend == true then
		return
	end
	for i, m in ipairs(self.handlers.UnitIdle) do
		m:UnitIdle(engineunit)
	end
end
```

## Scheduler: i turni di STAI, con un budget per frame

Lo scheduler è quello di STAI (`SchedulerHST`): turni a rotazione fra moduli e fra team, scritti come liste di nomi (`MScheduler` per i moduli, `BScheduler` per i behaviour). Entra nel runtime con due differenze: il runtime chiama solo il modulo o la classe di behaviour di turno, invece di chiamare tutti e lasciare che ciascuno esca subito, e un budget in microsecondi decide quanti turni entrano in un frame.

**Uno per client.** In STAI ogni AI aveva la propria copia di `SchedulerHST`, e tutte calcolavano la stessa rotazione; ogni modulo riceveva `Update` a ogni frame solo per scoprire che non era il suo turno. Nel runtime lo scheduler è uno per client host e la rotazione comprende i moduli di team (uno per AI), d'ally team (uno per ally team) e globali (uno solo). Per compatibilità il runtime aggiorna `self.ai.schedulerhst.moduleTeam`, `moduleUpdate`, `behaviourTeam` e `behaviourUpdate` prima di ogni turno, così le righe di controllo di STAI restano vere.

**Meccanismi.**

| Meccanismo | Uso | Come si scrive |
| --- | --- | --- |
| Turno a rotazione | lavoro periodico di moduli e behaviour | il nome della classe in `MScheduler` o `BScheduler`; il lavoro resta in `Update()`, che per i behaviour gira anche da inattivi, come in Shard |
| `Update` a ogni frame | moduli e behaviour fuori dalle liste che ridefiniscono `Update` | come in Shard |
| Attesa | ritentativi, azioni rimandate | `Wait(functor, frames)` del modulo `Sleep` (in STAI `SleepST`), stessa firma di oggi |
| Lavoro lungo | ricerca dei siti, mappe di minaccia, analisi del terreno | `self.ai.schedulerhst:Job(fn)`: `fn` è una coroutine che chiama `coroutine.yield()` ogni tanto e riprende al frame dopo |

**Ciclo del frame.**

1. Attivazione dei behaviour eletti nel frame precedente, solo per le unità in attesa (§ Unità e behaviour).
2. Attese scadute di `Sleep`.
3. `Update` dei moduli e dei behaviour fuori dalle liste.
4. Turni a rotazione, uno dopo l'altro finché resta budget; almeno uno per frame, come in STAI.
5. Ripresa dei lavori lunghi finché resta budget.
6. Ciò che non entra riprende al frame dopo, dal punto in cui la rotazione si era fermata: nessun turno salta.

**Misura del budget.** Nell'unsynced il tempo si legge con `Spring.GetTimerMicros()` dopo ogni turno e dopo ogni `yield`; il budget proposto è 1.000 µs per AI per frame, configurabile nella classe dell'AI (`STAI.budgetMicros`). Con budget zero si torna al comportamento di STAI: un turno per frame. Nel synced i timer non esistono: ogni turno conta come un'unità di lavoro e il budget è un numero fisso di unità, deterministico su tutti i client.

**Sfasamento.** La rotazione distribuisce già il lavoro: lo stesso modulo di AI diverse non cade nello stesso frame, e dopo un turno che esaurisce il budget il frame si chiude.

**Sotto carico.** Se la simulazione rallenta (velocità effettiva inferiore a quella richiesta, da `Spring.GetGameSpeed`), lo scheduler può ridurre il budget fino a un minimo configurato. Va deciso in fase 0 se questa regola serve davvero.

```lua
-- luarules/gadgets/ai/STAI/ai.lua: le liste di SchedulerHST passano alla classe dell'AI
STAI.MScheduler = { "EcoHST", "LosHST", "TargetHST", "DamageHST", "ScoutHST", "AttackHST", "RaidHST", "BomberHST", "LabsHST" }
STAI.BScheduler = {
	"BootBST", "CommanderBST", "BuildersBST", "EngineerBST", "LabsBST", "ScoutBST",
	"RaidBST", "AttackerBST", "ReclaimBST", "CleanerBST", "AntinukeBST", "NukeBST",
}
STAI.budgetMicros = 1000

-- un modulo di STAI non cambia: il runtime lo chiama solo nel suo turno,
-- quindi la riga di controllo è sempre vera e si può togliere quando si vuole
function EcoHST:Update()
	if self.ai.schedulerhst.moduleTeam ~= self.ai.id or self.ai.schedulerhst.moduleUpdate ~= self:Name() then return end
	-- ...
end

-- un lavoro lungo: una coroutine che cede il passo e riprende al frame dopo
self.ai.schedulerhst:Job(function()
	for ring = 1, maxRing do
		if self:TestRing(ring) then
			return
		end
		coroutine.yield()
	end
end)
```

## Modello del mondo e percezione

In Shard l'AI vedeva tutto: `AILoader.lua` inoltrava a ogni AI gli eventi di tutte le unità e `game:GetEnemies()` restituiva tutti i nemici. Nel nuovo runtime la percezione è un dato dell'ally team, alimentato dai call-in LOS/radar dell'engine, e le funzioni di `game`, `map` e `ShardUnit` che riguardano i nemici la rispettano.

**Dove vive.** La tabella dei contatti nemici sta nell'oggetto dell'ally team (`ShardAlly`): una sola per ally team, condivisa dalle AI alleate e dai loro moduli. Il registro di tutte le unità (chi è di chi) sta nell'oggetto `Shard`, accanto alla cache degli oggetti `ShardUnit`, e prende il posto dei cinque insiemi che `AILoader.lua` teneva per ogni AI (`ownUnitIds`, `friendlyUnitIds`, `alliedUnitIds`, `enemyUnitIds`, `neutralUnitIds`).

**Si può riusare il lavoro dei widget di BAR?** L'idea di non ricalcolare il LOS è giusta, ma la fonte giusta è l'engine, non i widget. L'engine mantiene già, per ogni ally team, lo stato LOS/radar di ogni unità, genera i call-in di ingresso e uscita e risponde a `Spring.GetUnitLosState`, `Spring.IsPosInLos`, `Spring.GetPositionLosState`. I widget di BAR legati alla visibilità (`gui_los_view_gl4.lua`, `gfx_los_view.lua`, `unit_ghostradar_gl4.lua`, `unit_ghostsite_gl4.lua`) non vanno bene come fonte per quattro motivi:

1. girano in LuaUI, un ambiente Lua separato: un gadget LuaRules non può leggere `WG`;
2. lavorano solo per l'ally team del giocatore locale (`Spring.GetMyAllyTeamID()`), non per gli ally team delle AI;
3. il giocatore può disattivarli;
4. servono a disegnare, non a fornire dati.

La percezione del runtime fa quindi la stessa cosa che fanno quei widget per il giocatore, cioè consumare i call-in dell'engine, ma una volta per ally team delle AI e in modo incrementale, mentre STAI la ripeteva per ogni AI e ricostruiva le griglie a ogni turno.

**Livelli di percezione.**

| Informazione | `fair` (predefinito) | `omniscient` (dichiarato, per livelli di difficoltà che barano) |
| --- | --- | --- |
| Unità proprie e alleate | complete | complete |
| Nemico in LOS | posizione, tipo, salute | complete |
| Nemico solo in radar | posizione approssimata, tipo solo se già identificato (`typed`) | complete |
| Nemico non visibile | ultima posizione nota e frame dell'ultimo avvistamento | complete |
| Strutture nemiche viste | restano note come "fantasmi" finché non le si vede distrutte o assenti | complete |
| Distruzione di nemici | solo se visibili al momento | sempre |

Lo stato di visibilità viene dai call-in `UnitEnteredLos`/`LeftLos`/`EnteredRadar`/`LeftRadar` filtrati sull'ally team dell'AI e, quando serve, da `Spring.GetUnitLosState(unitID, allyTeamID, true)`. Con accesso completo in lettura, la posizione di un contatto solo radar è esatta: il livello `fair` la arrotonda su una griglia (64 elmo proposti) per imitare l'errore radar che vede un giocatore. Il valore va tarato.

**Cosa contiene.**

- *Registro delle unità*, nell'oggetto `Shard`, aggiornato dagli eventi (creazione, fine costruzione, trasferimenti, distruzione); niente scansioni di tutte le unità.
- *Contatti nemici*: `id`, `unitDefID` o nil, ultima posizione, ultimo frame visto, stato LOS/radar, flag struttura.
- *Indice spaziale a celle* (512 elmo proposti) sui contatti, per rispondere a "nemici entro R" senza chiamare l'engine.
- *Cache per frame*: solo per dati derivati e interrogazioni costose (ricerche nel raggio, test di costruzione, aggregati). Le letture semplici vanno direttamente all'engine: costano 17–32 ns (fase 0, § Piano di misura).

**Come si verifica la regola.** Il runtime rispetta la percezione in ciò che offre: `game:GetEnemies()`, gli eventi dei nemici, i metodi di `ShardUnit` chiamati su un nemico. I metodi di `ShardUnit` sanno chi chiede perché `Prepare()` imposta la globale `ai` prima di ogni chiamata, come in Shard; i moduli globali non vedono unità nemiche. Il codice dell'AI può comunque chiamare `Spring.*`, come fa STAI: in quel caso la percezione è responsabilità dell'AI. Nei test l'ambiente dell'AI riceve una tabella `Spring` strumentata che conta le letture di unità nemiche fuori da LOS e radar, e per un'AI `fair` il requisito è zero; in partita la tabella è quella vera, senza costi aggiunti.

```lua
local enemies = self.game:GetEnemies() -- solo i contatti dell'ally team
for i = 1, #enemies do
	local enemy = enemies[i]
	local pos = enemy:GetPosition() -- solo in radar: posizione arrotondata
	local name = enemy:Name() -- nil se il tipo non è mai stato visto
end
local health = self.game:GetUnitByID(unitID):GetHealth() -- nil per un nemico fuori LOS
```

## Canale dei comandi

Gli ordini si danno come in Shard e in STAI: con i metodi di `ShardUnit` (`unit:Move(p)`, `unit:Build(t, p)`, `unit:Attack(u)`…) o con `game:GiveOrder(id, cmd, params, options, method)`, che ha la firma di `Tool:GiveOrder` di STAI. Sotto, ogni AI ha una sola coda d'ordini; a fine frame la coda diventa al massimo un messaggio binario, che il relay synced esegue solo se arriva dall'host dell'AI e riguarda unità del suo team.

&#91;embedded content: percorso di un ordine · dall'AI host alla simulazione\]

### La coda degli ordini

- `game:GiveOrder(id, cmd, params, options, method)` accoda un ordine. `method` mantiene i codici di STAI: `'1-1'` un comando a un'unità, `'2-1'` più comandi a un'unità, `'1-2'` un comando a più unità, `'2-2'` più comandi a più unità. I metodi di `ShardUnit` passano da qui con `'1-1'`, nella coda dell'AI proprietaria dell'unità.
- **Accorpamento per unità nel frame**: un ordine senza `shift` sostituisce quelli ancora in coda per la stessa unità; un ordine con `shift` si accoda. L'ordine relativo viene preservato.
- **Controlli locali economici** prima di accodare: unità propria e viva secondo il registro. Evitano byte inutili; il controllo vero resta nel relay.

**Tetto agli ordini per frame.** Ogni ordine costa all'engine circa 4,2 µs su ogni client (fase 0). L'outbox applica quindi un tetto di ordini per frame per AI (proposta: 25 in media, circa 0,1 ms per client, configurabile): gli ordini oltre il tetto restano in coda con priorità (reazioni di combattimento prima, riposizionamenti dopo) e partono nei frame successivi. Un ordine ancora in coda per un'unità che ne riceve uno nuovo senza `shift` viene sostituito, quindi la coda non cresce senza limite.

### Formato del messaggio (versione 1)

```
intestazione (16 byte)
  magic    4 byte   "AIFw"
  versione U8       1
  teamID   U8
  seq      U32      crescente per team
  frame    U32      frame di emissione (per misurare la latenza)
  count    U16      numero di ordini
ordine (8 + 4n byte)
  unitID   U16      Game.maxUnits < 65.536, verificato all'avvio
  cmdID    S32      negativo per i comandi di costruzione
  options  U8       bit standard dei comandi (shift, ctrl, alt, right, meta)
  n        U8       numero di parametri
  params   F32 × n
```

Un ordine di movimento pesa 20 byte; lo stesso ordine nel formato STGO di STAI pesava circa 90 byte ed era un messaggio a sé. Il pacchetto di Recoil ha un tetto di 65.535 byte complessivi: l'outbox spezza la coda oltre 60.000 byte di carico (circa 3.000 movimenti), un caso che non dovrebbe presentarsi. Codifica e decodifica usano `VFS.Pack*`/`VFS.Unpack*`, senza parsing di testo. La precisione di F32 basta per coordinate fino a 40.960 elmo e per ID di unità o feature passati come parametri.

I quattro `method` diventano record per unità: `'1-2'` e `'2-2'` si espandono in un record per ogni unità, e il relay ricompone in una sola `GiveOrderArrayToUnit` gli ordini consecutivi della stessa unità. Resta da misurare se `GiveOrderToUnitArray` costa meno, per unità, degli ordini singoli.

**Lettura dei byte.** In Recoil `VFS.Unpack*` non restituisce nulla se la posizione chiesta è uguale alla lunghezza del messaggio. Un ordine senza parametri in fondo al messaggio, come uno `STOP`, finisce con i due U8 `options` e `n`: il relay li legge insieme come un U16, e fa lo stesso con `versione` e `teamID`. Letto come U8, l'ultimo `n` andrebbe perso.

**Numeri a precisione singola (misurato in T4, 23 nov 2026).** In Recoil i numeri Lua sono float a 32 bit, sia nel synced sia nell'unsynced: `2^24 + 1 == 2^24`, e `2147483647` non esiste. Conseguenze:

- `seq` e frame di emissione sono esatti fino a 2^24, cioè circa 155 ore a 30 frame al secondo con un messaggio per frame: abbastanza per una partita.
- I limiti dei campi si scrivono come potenze di due con l'estremo superiore escluso (`value < 2^31`), che sono esatte anche in float.
- Ogni calcolo di interi grandi va rivisto: per esempio l'hash del seme casuale della bozza del loader, `(h * 31 + byte) % 2147483647`, perde cifre e va riscritto sotto 2^24.
- I test busted girano in doppia precisione: questi casi li copre solo un test con l'engine vero.

Il decoder del gadget di prova leggeva `n` come U8 e aveva questo difetto. La misura `STOP` non ne è stata toccata: in quei messaggi c'era un byte di riempimento, e nessun ordine è stato rifiutato. Le varianti dirette non passano dal decoder. Ora il gadget legge `options` e `n` come un U16, senza riempimento, con il formato di questa proposta.

### Relay synced

Il relay è il lato synced di `AILoader.lua` e prende il posto del parser STGO: gira su ogni client e accetta il messaggio solo se tutte le verifiche passano; altrimenti lo scarta e incrementa un contatore.

1. `magic` e `versione` riconosciuti; se il magic corrisponde, `RecvLuaMsg` restituisce `true` per non far elaborare il messaggio ad altri gadget.
2. `playerID` del mittente (fornito dal server, non falsificabile) uguale a `aiHostPlayer` del `teamID` dichiarato.
3. `seq` maggiore dell'ultimo accettato per quel team.
4. Al massimo 2 messaggi per **frame di emissione** (il campo `frame` dell'intestazione) per team, e `count` entro un limite configurato (proposta: 4.000). Non si limita per frame di arrivo: dopo un rallentamento o un ritardo di rete arrivano legittimamente più messaggi nello stesso frame, e la fase 0 ha mostrato che un limite per frame di arrivo scarta ordini validi. Il frame di emissione non può essere nel futuro né più vecchio di una finestra configurata.
5. Per ogni ordine: `Spring.ValidUnitID(unitID)` e `Spring.GetUnitTeam(unitID) == teamID`; gli ordini che falliscono vengono scartati singolarmente.
6. Gli ordini consecutivi della stessa unità diventano una sola chiamata `Spring.GiveOrderArrayToUnit`.
7. Il relay non fa altro: nessuna logica dell'AI, nessuna allocazione per ordine oltre alle tabelle dei parametri.

Il relay può restituire all'host il numero di ordini scartati tramite `SendToUnsynced`, a solo scopo di telemetria.

**Verifica obbligatoria.** Un test d'integrazione invia messaggi validi da un giocatore che non è l'host e messaggi dell'host che toccano unità di altri team: nessuno dei due deve produrre ordini.

## Unità e behaviour

Il modello resta quello di Shard: un oggetto `Unit` per ogni unità propria, con i behaviour che sceglie la `BehaviourFactory` dell'AI, ed elezione per priorità con `Unit:ElectBehaviour()`. Cambiano tre cose: il gestore delle unità (`UnitHST` in STAI, `UnitHandler` nell'AI d'esempio) passa nel runtime come `UnitHandler`; gli eventi arrivano per ID solo ai behaviour che li ridefiniscono; l'elezione fa quello che dice il suo commento.

&#91;embedded content: stati di un'unità · 4 stati, attivazione al frame dopo l'elezione\]

**Elezione.** Restano le regole scritte nel commento di `Unit:ElectBehaviour`: vince la priorità più alta tra quelle maggiori di zero; se nessuna è maggiore di zero non si attiva nessun behaviour; il behaviour attivo si disattiva subito e il nuovo si attiva al frame successivo; se vince quello attivo non cambia nulla. Il codice di Shard le violava in due punti: il primo behaviour della lista veniva scelto anche con priorità zero o negativa, e dopo la disattivazione `activeBehaviour` puntava ancora al behaviour disattivato, così un'elezione ripetuta prima del frame successivo poteva disattivarlo una seconda volta o lasciare attivo il behaviour sbagliato.

```lua
-- shard_runtime/unit.lua: stessa funzione e stesso commento di Shard, con due correzioni
function Unit:ElectBehaviour()
	if self:HasBehaviours() == false then
		return
	end

	local bestBehaviour = nil
	local bestScore = 0 -- solo priorità maggiori di zero, come dice il commento
	for i, behaviour in ipairs(self.behaviours) do
		local score = behaviour:Priority() or 0
		if score > bestScore then
			bestScore = score
			bestBehaviour = behaviour
		end
	end

	local elected = self.nextBehaviour or self.activeBehaviour
	if bestBehaviour == elected then
		return
	end
	if self.activeBehaviour ~= nil then
		self.activeBehaviour:PreDeactivate()
		self.activeBehaviour:Deactivate()
		self.activeBehaviour = nil -- niente riferimenti a un behaviour disattivato
	end
	self.nextBehaviour = bestBehaviour
	if bestBehaviour ~= nil then
		self.ai.unithandler:QueueActivation(self) -- attivazione al frame dopo, solo per le unità in attesa
	end
end
```

**Quando si elegge.** Come in Shard: a fine costruzione dell'unità (`UnitBuilt` della propria unità) e ogni volta che un behaviour chiama `self.unit:ElectBehaviour()`, direttamente come fa STAI o con `RequestControlOfUnit` e `YieldControlOfUnit`. In più, quando l'unità arriva da un altro team (`UnitGiven`). Un'elezione chiesta mentre ne è in corso un'altra, per esempio da `Deactivate`, si ripete subito dopo e non dentro quella in corso.

**Due casi che cambiano per STAI.**

1. Con tutte le priorità a zero Shard attivava comunque il primo behaviour della lista; in STAI è spesso `BootBST`, che `defaultBehaviours` mette per primo nelle unità mobili e nelle fabbriche. Con l'elezione corretta l'unità resta senza behaviour attivo finché un behaviour non ha priorità maggiore di zero. Non cambia nulla per i behaviour il cui `Update` non controlla `self.active`, come `LabsBST`, perché il loro `Update` gira comunque; va controllato chi fa qualcosa in `Activate`.
2. Una `Priority()` che non restituisce niente vale zero: in STAI `CleanerBST:Priority` è vuota, e con il confronto corretto un `nil` farebbe fallire l'elezione.

Per il porting c'è un'opzione dell'AI, `STAI.legacyElection = true`, che ripristina la scelta del primo behaviour: si porta STAI con lo stesso comportamento di oggi, poi si toglie l'opzione e si confrontano le partite.

**I metodi di un behaviour.**

| Metodo | Quando lo chiama il runtime | Note |
| --- | --- | --- |
| `Init()` | alla creazione, dalla `BehaviourFactory` | come in Shard |
| `Priority()` | a ogni elezione | deve costare poco; `nil` vale zero |
| `PreActivate`, `Activate`, `PreDeactivate`, `Deactivate` | al cambio di controllo | i `Pre*` di `Behaviour` impostano `self.active`, come oggi |
| `Update()` | nel turno della sua classe (`BScheduler`), o a ogni frame se fuori lista; anche da inattivo | come in Shard: chi deve lavorare solo da attivo controlla `self.active`, come già fanno `NukeBST` e `AttackerBST` |
| `OwnerCreated`, `OwnerBuilt`, `OwnerIdle`, `OwnerDamaged`, `OwnerMoveFailed`, `OwnerDead` | eventi della propria unità | a tutti i behaviour dell'unità che li ridefiniscono, attivi o no |
| `UnitCreated`, `UnitBuilt`, `UnitDead`, `UnitDamaged`, `UnitIdle` | eventi di altre unità | solo ai behaviour che li ridefiniscono |
| `GameEnd()` | fine partita | come in Shard |

**Assegnazione dei behaviour.** Resta alla `BehaviourFactory` dell'AI (`behaviourfactory.lua` e `behaviours.lua`), come in STAI: `AddBehaviours(unit)` sceglie le classi per nome di unità o per categoria. `UnitHandler` la chiama una volta per ogni unità propria; con `ArmyHST` globale, le liste di categorie si calcolano una volta per client invece che una volta per AI.

## Servizi di mappa condivisi

I dati di mappa stanno nell'ambito globale: si calcolano una volta per client host e si condividono tra tutte le AI in sola lettura; dove BAR li calcola già, si leggono da BAR. Le funzioni di `map` restano quelle di Shard: cambia solo da dove prendono i dati. Shard ricalcolava i metal spot per ogni AI, con un algoritmo difettoso.

| Servizio | API di Shard | Fonte | Note |
| --- | --- | --- | --- |
| Metal spot | `map:GetMetalSpots()`, `map:SpotCount()`, `map:GetSpot(i)` | game rules param `mex_count`, `mex_x<i>`, `mex_y<i>`, `mex_z<i>`, `mex_metal<i>` pubblicati da `api_resource_spot_finder`; nel synced direttamente `GG.resource_spot_finder` | `mex_count = -1` indica una metal map: l'AI deve cambiare strategia di estrazione |
| Geo spot | `map:GetGeoSpots()`, `map:GeoCount()`, `map:GetGeo(i)` | feature con `geoThermal = true`, lette una volta all'avvio (`spring_lua/geo.lua`) | non pubblicati nei game rules da BAR |
| Metadati | `map:MapDimensions()`, `map:AverageWind()`, `map:TidalStrength()`, `map:MaximumHeight()`… | `Game.mapSizeX/Z`, `Game.windMin/Max`, `Game.tidal`, `Spring.GetGroundExtremes()` | calcolati una volta |
| Siti di costruzione | `map:FindClosestBuildSite(unittype, builderpos, searchradius, minimumdistance, validFunction)`, `map:CanBuildHere(unittype, position)` | ricerca ad anelli, sincrona come in Shard; le ricerche ampie diventano un lavoro lungo dello scheduler | vedi sotto |
| Percorsi | `map:RequestPath`, `map:GetPathObject`, `map:TestPath`, `map:PathTest` | `Spring.RequestPath` per move class, con cache per (move class, cella di partenza, cella d'arrivo) e scadenza | proposta provvisoria: vedi sotto |

**Percorsi: questione aperta, rinviata a data da destinarsi.** È stato segnalato un problema strutturale nelle richieste di percorso; va analizzato prima di fissare il servizio percorsi. Per riferimento, nella versione rimossa le richieste passavano da `map:RequestPath`, `GetPathObject`, `TestPath` e `PathTest` (`shard_runtime/spring_lua/map.lua`), usate da `STAI/maphst.lua` (righe 595 e 883) e `STAI/attackhst.lua` (riga 310), sempre in modo sincrono dentro l'aggiornamento del modulo e senza cache. La riga della tabella sopra resta una proposta provvisoria.

**Ricerca dei siti di costruzione.** Anelli concentrici di raggio r crescente con passo `spacing`; su ogni anello l'incremento angolare è `spacing / r`, così i punti restano a distanza costante e l'anello ne ha circa 2πr / spacing. In Shard l'incremento era `r · 2π · 2π / spacing` e produceva un solo punto per anello. Ogni candidato passa da `Spring.Pos2BuildPos` e `Spring.TestBuildOrder`; la distanza dalle altre costruzioni si verifica sulle impronte già note al registro delle unità invece che con otto test extra come faceva `placementhandler`.

**Prenotazioni.** Un sito scelto resta prenotato per l'ally team per un tempo limitato (proposta: 300 frame) o finché la costruzione non parte, così due costruttori non scelgono lo stesso punto.

**Caricamento.** Il calcolo iniziale (geo spot, metadati, eventuali griglie di terreno) gira come lavoro lungo nei primi frame invece che durante il caricamento del gadget, per non allungare l'avvio della partita.

## Debug, telemetria e test

Ogni requisito della tabella iniziale ha un test automatico o una misura; la telemetria è parte del runtime, non un'aggiunta da riattivare a mano come le zone Tracy commentate in Shard.

### Telemetria

| Misura | Granularità | Dove si legge |
| --- | --- | --- |
| Chiamate, µs totali e massimi, sforamenti di budget | per modulo, behaviour e callback | pannello del widget di debug; zone Tracy quando la globale `tracy` esiste |
| Tempo totale dell'AI per frame (media, 99° percentile su finestra mobile) | per AI | pannello e log di fine partita |
| Eventi ricevuti e consegnati | per callback | pannello |
| Ordini emessi, accorpati, inviati, scartati dal relay; byte per messaggio | per AI | pannello e contatori del relay |
| Heap Lua (`gcinfo()`) | ogni 300 frame | log |
| Moduli in quarantena | per AI | pannello e log d'errore |

Il widget `shard_help_draw.lua`, recuperato e diviso in canali, riceve statistiche e disegni dall'unsynced dell'host con lo stesso meccanismo di prima: funzioni registrate con `widgetHandler:RegisterGlobal` e chiamate con `Script.LuaUI.<nome>`, dietro i metodi `map:DrawRectangle`, `map:DrawCircle`, `map:DrawLine` e gli altri di Shard. I canali (economia, combattimento, piazzamento) si attivano uno per volta; su un client che non ospita l'AI non c'è nulla da mostrare.

### Test

| Livello | Strumento | Cosa copre |
| --- | --- | --- |
| Unità, senza engine | busted via lux (`lx --lua-version 5.1 test`), builder `spring_unsynced_builder` e `spring_synced_builder` in `spec/builders/` | consegna dei callback, scheduler con orologio finto, elezione, accorpamento della coda, codifica e decodifica dei messaggi, logica di validazione del relay come funzione pura, percezione `fair`; tutto sopra l'API finta di `shard_null` |
| Integrazione | test headless in Docker (`tools/headless_testing/`), file in `luaui/Tests/shard/` | sicurezza del relay, percezione, reload di LuaRules a partita in corso, cambio di host, partita di 10 minuti contro NullAI senza errori |
| Prestazioni | scenario standard della fase 0, Tracy | budget medio e 99° percentile, costo sui client non host |

Test d'integrazione obbligatori prima di qualunque PR verso BAR:

1. un giocatore non host invia un messaggio valido → zero ordini eseguiti;
2. l'host invia ordini per unità di un altro team → tutti scartati, contatore incrementato;
3. in modalità `fair`, un nemico mai entrato in LOS non compare in nessuna risposta di `game`, `map` o `ShardUnit`, e la tabella `Spring` strumentata non conta letture illecite;
4. `/luarules reload` al minuto 5 → l'AI riprende entro 30 frame e continua a costruire;
5. l'host lascia la partita → il successore riprende il controllo entro 60 frame.

### Gate di qualità di BAR

StyLua 2.5.2 (tab, 120 colonne, CRLF), annotazioni LuaCATS sulle classi del runtime (`AIBase`, `Module`, `Behaviour`, `Unit`, `ShardUnit`, `game`, `map`) per EmmyLua 0.24.0, busted e test headless come da `.github/agents.md`. Per `AI_POLICY.md`, l'uso di assistenti AI nel codice va dichiarato nella PR e ogni parte va verificata da una persona in partita, con prove allegate.

## Ambiente di sviluppo

Il lavoro sul framework va provato in partita, quindi il centro dell'ambiente è Claude Code in locale, sullo stesso computer su cui gira BAR tramite SkyLobby; la chat online serve per progettazione e documenti, le sessioni cloud per pezzi che non richiedono il gioco.

| Strumento | Uso | Limite |
| --- | --- | --- |
| Claude Code in locale (estensione VS Code o scheda Code dell'app desktop) | scrivere codice e test, avviare partite e test headless, leggere `infolog.txt` | nessuno rilevante; le due interfacce leggono la stessa configurazione |
| Sessioni cloud di Claude Code | codec, scheduler, consegna dei callback, specifiche busted: lavori lunghi che finiscono in un branch del fork | girano su una macchina virtuale clonata da GitHub, senza BAR né engine |
| Chat su claude.ai | progettazione, analisi, aggiornamento di questi documenti | non esegue né il gioco né i test |

### Copia di sviluppo del gioco con SkyLobby

Il README di BAR descrive la procedura per il launcher ufficiale; con SkyLobby il principio è lo stesso, perché l'engine carica una cartella di gioco non compressa che finisce in `.sdd`.

1. Allinea il tuo fork a `beyond-all-reason/Beyond-All-Reason`: il fork `pandaro` analizzato è fermo a novembre 2025, prima della rimozione di Shard e STAI.
2. La directory dati di Spring usata da SkyLobby è `~/.spring`. Clona il fork in `~/.spring/games/BAR.sdd`: `git clone --recurse-submodules <url del fork> ~/.spring/games/BAR.sdd`. Il controllo è che esista `~/.spring/games/BAR.sdd/modinfo.lua`.
3. In SkyLobby, ricarica l'elenco dei giochi e scegli **Beyond All Reason $VERSION**: è il nome che `modinfo.lua` dà alla copia di sviluppo, distinto dalle versioni scaricate.
4. Aggiungi la nuova AI nella battaglia come Lua AI; compare nell'elenco dopo la registrazione in `luaai.lua`.

Da verificare sulla tua installazione: se SkyLobby elenca le Lua AI lette da `luaai.lua` della copia `.sdd`. Il file `devmode.txt` del README serve al menu sviluppatore del launcher ufficiale; con SkyLobby non dovrebbe servire.

### Test e strumenti

- **Test headless senza Docker**, con l'engine già scaricato: `<cartella dell'engine>/spring-headless --isolation --write-dir ~/.spring ~/.spring/games/BAR.sdd/tools/headless_testing/startscript.txt`; servono la mappa Supreme Isthmus v2.1 e la cartella \~/.spring/`testlog`, dove finisce `results.json` (`tools/headless_testing/README.md`).
- **Strumenti alle versioni dei gate di BAR**: Lua 5.1, lux 0.54.0 (`lx --lua-version 5.1 test`), StyLua 2.5.2, EmmyLua 0.24.0; Docker solo per riprodurre esattamente la CI.
- **Tracy** per le misure della fase 0, con un engine compilato con il supporto Tracy.

### Istruzioni per Claude Code nel repository

Un file `CLAUDE.local.md` nella radice di `BAR.sdd`, escluso da git con `.git/info/exclude`, rimanda a `.github/agents.md` (regole del repository per gli agenti) e riassume le decisioni di questo documento: fedeltà a Shard (struttura, classi, stile), tre ambiti, host per ally team, relay autenticato, soglie della fase 0. Ogni sessione parte così dal contesto giusto. Per `AI_POLICY.md`, ogni PR verso BAR dichiara l'uso di assistenti AI e allega prove di partita.

## Cosa recuperare dal codice rimosso

Con la scelta di restare fedeli a Shard, dal codice rimosso si recupera quasi tutto il runtime: si riparte dai file com'erano e si cambia solo ciò che serve. Tutti i percorsi si leggono al commit `3ad8f3fb^` di BAR (`git show 3ad8f3fb^:<percorso>`).

Nella tabella `shard_runtime/`, `ai/Shard/` e `ai/STAI/` stanno sotto `luarules/gadgets/ai/`.

| Elemento | Percorso | Decisione | Motivo |
| --- | --- | --- | --- |
| Classi del runtime | `shard_runtime/class.lua`, `aibase.lua`, `module.lua`, `behaviour.lua`, `unit.lua`, `shardai.lua`, `api.lua` | **recuperare** e correggere | sono la struttura da mantenere; correzioni: elezione, consegna mirata, `Module:internalName` ridefinito per errore in `behaviour.lua` |
| API su Recoil | `shard_runtime/spring_lua/` (`game`, `map`, `unit`, `unittype`, `feature`, `damage`, `shard`, `boot`) | **recuperare** e correggere | `ShardUnit` torna a dare ordini, `game:GetEnemies()` rispetta la percezione, `shard_include` carica nell'ambiente dell'AI |
| Backend finto | `shard_runtime/shard_null/` | **recuperare** | base dei test busted senza engine |
| Loader | `luarules/gadgets/ShardAILoader.lua` | **riscrivere** tenendo la struttura, con il nome nuovo | host per ally team, relay binario autenticato, consegna mirata, niente GC forzata |
| Scheduler di STAI | `ai/STAI/schedulerHST.lua` | **portare nel runtime** | stessi turni, una copia per client, budget |
| Gestore delle unità | `ai/STAI/unithst.lua`, `ai/Shard/unithandler.lua` | **portare nel runtime** come `UnitHandler` | consegna per ID, attivazioni in attesa |
| Sleep | `ai/Shard/sleep.lua`, `ai/STAI/sleepst.lua` | **portare nel runtime**, stessa API | sotto il timer dello scheduler; oggi alloca una tabella a ogni frame |
| Widget di debug draw (1.164 righe) | `luaui/Widgets/shard_help_draw.lua` | **recuperare** | funziona, va solo diviso in canali |
| Spazi davanti alle uscite delle fabbriche (50 righe + test) | `common/stai_factory_rect.lua`, `luaui/Tests/ai_stai_factory_rect.lua` | **recuperare** nel servizio dei siti | risolve un problema reale (PR #6271, AI che bloccano le uscite) ed è già testato |
| Geo spot da feature (20 righe) | `shard_runtime/spring_lua/geo.lua` | **recuperare**, calcolato una volta per client | semplice e corretto |
| Ricerca a spirale divisa su più frame | `ai/Shard/placementhandler.lua` | riprendere l'idea dietro `map:FindClosestBuildSite` | il codice ha errori bloccanti (`start_position` globale, doppio callback) |
| Task queue | `ai/Shard/taskqueuebehaviour.lua`, `ai/Shard/taskqueues.lua` | eventuale libreria opzionale per AI semplici | utile per prototipi, troppo rigida come base |
| Wrapper dei percorsi | `shard_runtime/spring_lua/map.lua` | stesse funzioni; il servizio è rinviato | nessuna cache, blocchi commentati |
| Zone Tracy | `shard_runtime/aibase.lua`, `shardai.lua` | riprendere l'idea nella telemetria | quasi tutte commentate |
| Metal spot | `shard_runtime/spring_lua/metal.lua` | **scartare** | BAR li pubblica già; l'algoritmo aveva l'errore `x`/`ix` |
| Protocollo STGO | `AILoader.lua`, `ai/STAI/tool.lua` | **scartare** | sostituito dalla coda binaria; `Tool:GiveOrder` resta come facciata di `game:GiveOrder` |
| Backend nativo e registro degli hook | `shard_runtime/spring_cpp/`, `hooks.lua` | **scartare** | niente backend nativo; registro mai usato |
| GC forzata adattiva | `luarules/gadgets/AILoader.lua` | **aperto** | da riparlarne: per l'utente è una sicurezza contro il crash per perdita di memoria; la `collect` provoca scatti (appunto in «Risultati: garbage collection») |
| Logica di gioco di STAI | `luarules/gadgets/ai/STAI/` | **portare** come prima AI | verifica la compatibilità con Shard e dà subito un'AI completa |

## Piano di misura delle prestazioni

Prima di scrivere il framework si misurano i costi dell'engine che il progetto dà per scontati; dopo, ogni versione si confronta con le soglie su uno scenario fisso. La prima misura ha già ridimensionato la stima del 21% fra gadget e nativo dell'analisi precedente (vedi i risultati qui sotto).

### Fase 0: misure di base

| Misura | Metodo | Serve a |
| --- | --- | --- |
| Costo per chiamata di `GetUnitPosition`, `GetUnitHealth`, `GetUnitsInCylinder`, `TestBuildOrder`, `RequestPath` dall'unsynced LuaRules | gadget di prova: 10.000 chiamate per funzione, `Spring.GetTimerMicros` | tarare le cache del runtime e il budget |
| Costo del relay per ordine nel synced | Tracy attorno a `RecvLuaMsg`, messaggi da 1, 100 e 1.000 ordini | verificare la soglia di 0,05 ms per frame |
| Latenza ordine in frame | frame di emissione nell'intestazione contro frame di esecuzione, con ping simulato di 0, 50 e 150 ms | quantificare il costo del giro di rete |
| Costo di SimpleAI (synced) e BARb (nativo) | Tracy sullo scenario standard | termini di paragone reali |
| Effetto della GC | `gcinfo()` e zone Tracy con allocazioni dell'AI simulate | decidere se servono pool di tabelle |

### Risultati: costo delle chiamate all'engine

Le letture semplici dall'engine costano 17–32 ns, quindi la cache per frame delle letture semplici non serve; i costi veri sono le ricerche spaziali e i test di costruzione. Misura del 22 nov 2026 con `dbg_ai_framework_bench.lua` (branch `ai-framework/fase0`): engine 2026.07.04, mappa Comet Catcher Remake 1.8, 1.002 unità, frame 2851, gioco in pausa; 5 ripetizioni da almeno 10.000 chiamate, granularità del timer 8 µs. Valori per chiamata, al netto del ciclo vuoto (4,0 ns).

| Misura | Mediana | Minimo | Note |
| --- | --- | --- | --- |
| Lettura da tabella Lua (riferimento) | 3,1 ns | 2,6 ns |  |
| `GetUnitTeam` | 17,3 ns | 12,4 ns | sotto 100 passi del timer: impreciso |
| `GetUnitVelocity` | 19,4 ns | 15,8 ns | impreciso |
| `GetUnitDefID` | 22,6 ns | 17,0 ns |  |
| `GetUnitPosition` | 24,6 ns | 21,7 ns |  |
| `GetUnitHealth` | 29,0 ns | 19,8 ns |  |
| `GetUnitLosState` (raw) | 32,0 ns | 30,3 ns |  |
| `GetGroundHeight` | 111,3 ns | 34,5 ns | impreciso; forte dipendenza dalla posizione letta |
| `Pos2BuildPos` | 130,4 ns | 70,5 ns | impreciso |
| `GetUnitsInCylinder`, raggio 500 | 928 ns | 882 ns | 23,7 unità restituite in media |
| `GetUnitsInCylinder`, raggio 1500 | 3.678 ns | 3.602 ns | 169,8 unità restituite in media |
| `Pos2BuildPos` + `TestBuildOrder` | 1.585 ns | 1.313 ns |  |
| Codifica di un ordine di movimento | 205 ns | 198 ns | 20,5 µs per 100 ordini |
| Decodifica di un ordine di movimento | 158 ns | 157 ns | 15,8 µs per 100 ordini |

**Conseguenze sul progetto.**

1. *Cache per frame delle letture semplici: eliminata.* Una lettura costa poco più di una lettura da tabella più il suo indice; 1.000 letture per frame valgono circa 25 µs, il 2,5% del budget di 1 ms. Il runtime memorizza solo dati derivati e interrogazioni costose.
2. *Le ricerche nel raggio costano per unità restituita* (circa 22–39 ns l'una). L'indice spaziale dell'ambito ally team resta, soprattutto per applicare la percezione `fair`, e conviene anche per le ricerche ampie.
3. *Ricerca dei siti*: circa 1,5 µs per candidato; 100 candidati ≈ 160 µs. Resta un lavoro lungo dello scheduler. Il controllo di distanza con 8 test extra per candidato (come in `placementhandler` di Shard) costerebbe circa 13 µs per candidato: escluso.
4. *Relay*: la sola decodifica sta nella soglia di 0,05 ms per frame fino a circa 300 ordini per frame. Manca il costo di `GiveOrderArrayToUnit`: è la prossima misura, a gioco in corsa, con la latenza in frame.

La riga `[AIBENCH-JSON]` di questa esecuzione risulta troncata dopo il campo `paused`: da verificare se il taglio è nell'infolog o solo nella copia.

**Seconda esecuzione (stessa sera, 1.002 unità, timer 8 µs).** Le letture per unità tengono (12–22 ns), il codec anche (entro il 5%). `GetUnitsInCylinder` dipende dalle unità restituite, non dal raggio: 3,2 µs per 231 unità e 8,4 µs per 789, cioè circa 11–14 ns per unità più un piccolo costo fisso. `GetGroundHeight` (37,5 ns) e `Pos2BuildPos` (80 ns) sono usciti più veloci della prima volta: punti casuali e stato della cache variano, quindi vanno letti come intervalli (35–111 ns e 70–130 ns). `Pos2BuildPos` + `TestBuildOrder`: 1,66 µs.

### Risultati: relay e latenza

Il relay costa circa 4,2 µs per ordine di movimento, ma quasi tutto è l'esecuzione dell'ordine da parte dell'engine, non il relay. Misura del 22 nov 2026, stesso branch, engine 2026.07.04, 1.001 unità, gioco in corsa, granularità del timer 32 µs; 180 messaggi, tutti accettati, nessun ordine scartato.

| Ordini per messaggio | Media | Mediana | Per ordine | Latenza |
| --- | --- | --- | --- | --- |
| 1 | 86 µs | 64 µs | — | 0 frame (massimo 1) |
| 100 | 435 µs | 416 µs | 4,35 µs | 0 frame |
| 1.000 | 4.209 µs | 4.128 µs | 4,21 µs | 0 frame |

**Lettura.**

- Estrapolando a zero ordini, il costo fisso per messaggio è circa 15 µs. La mediana di 64 µs con un solo ordine risente della granularità del timer e di un picco isolato di 896 µs.
- La decodifica vale circa 0,16 µs per ordine (misura del codec): il 96% dei 4,2 µs è `GiveOrderArrayToUnit` con `CMD_MOVE`.
- Quel costo è dell'engine: la simulazione è deterministica, quindi ogni ordine si esegue su ogni client chiunque lo dia (giocatore, SimpleAI, BARb, relay). Probabilmente comprende l'avvio della richiesta di percorso di ogni movimento; da verificare, si collega alla questione dei percorsi rinviata.
- La latenza di 0 frame vale solo in single player, dove il client è anche server. In multiplayer si aggiunge almeno il giro verso il server: da misurare con un secondo client.

**Varianti: il costo è dell'engine.** Messaggi da 1.000 ordini, gli unici abbastanza lunghi per il passo del timer (64 µs in questa esecuzione):

| Variante | Media | Mediana | Per ordine |
| --- | --- | --- | --- |
| Relay completo, `CMD.MOVE` | 4.034 µs | 3.968 µs | 4,03 µs |
| Relay completo, `CMD.STOP` | 3.937 µs | 3.904 µs | 3,94 µs |
| Riferimento: `GiveOrderArrayToUnit` diretto dal synced, senza relay | 3.630 µs | 3.584 µs | 3,63 µs |
| Solo decodifica e verifiche, ordini non applicati | 923 µs | 896 µs | 0,92 µs |

- **Il 90% è dell'engine**: applicare l'ordine costa 3,6 µs anche senza relay. Il relay aggiunge circa 0,9 µs per ordine.
- **`STOP` costa quanto `MOVE`**: il costo non viene dal percorso né dal movimento. L'ipotesi dei gadget `AllowCommand` di BAR è stata verificata e scartata con le prove A/B qui sotto: l'80–95% del costo è dell'engine.
- **Gli 0,9 µs del relay si possono ridurre**: la decodifica pura vale 0,16 µs; il resto sono tabelle create per ogni ordine (comando e parametri). Con tabelle riusate scenderebbero, ma resterebbero piccoli rispetto all'engine.
- 0,92 + 3,63 = 4,55 contro 4,03 misurati: la somma non è esatta, compatibile con il rumore fra le fasi.
- Il costo fisso per messaggio non è misurabile con questo passo del timer: sotto 200 µs.
- **Il limite per frame del relay ha scartato 7 messaggi validi** nella fase di sola decodifica: dopo un rallentamento ne sono arrivati più di 2 nello stesso frame. In uso reale sarebbero ordini dell'AI persi: la regola va cambiata (§ Canale dei comandi, punto 4).

**Dove vanno i 3,6 µs: prove A/B.** Variante diretta dal synced, 1.000 ordini, 60 campioni per riga, nessun ordine rifiutato; i gadget sono stati spenti in memoria con `/luarules disablegadget`, nessun file modificato. Valori medi per ordine.

| Prova | `MOVE` | `STOP` |
| --- | --- | --- |
| A, come oggi | 3,93 µs | 3,62 µs |
| B, LuaUI spento | 3,63 µs | 3,50 µs |
| C, 6 gadget spenti | 3,77 µs | 3,10 µs |
| C2, tutti i gadget dei comandi spenti | 3,80 µs | 3,19 µs |
| D, B + C | 3,80 µs | 2,95 µs |
| D2, LuaUI + tutti i gadget spenti | 3,68 µs | 2,86 µs |

- **Resta l'engine**: senza gadget e senza LuaUI restano 3,7 µs per `MOVE` e 2,9 µs per `STOP`, cioè l'80–95% del costo. Né il framework né i gadget di BAR possono ridurlo in modo sensibile.
- **I gadget pesano poco**: circa 0,1 µs per gadget per ordine; su `STOP` gadget e LuaUI insieme valgono circa 0,7 µs, su `MOVE` stanno sotto il rumore (±0,3 µs).
- **LuaUI non conta**: B toglie 0,1–0,3 µs, quanto il rumore fra le prove.
- **`MOVE` pesa più di `STOP` nell'engine** (3,7 contro 2,9 µs a gadget spenti).
- Anomalia senza conclusioni: un messaggio con un solo `STOP` costa 190–240 µs, circa il doppio di un solo `MOVE`; i messaggi da un ordine sono troppo rumorosi per dire di più.

**Decisione che ne segue**: nessuna ottimizzazione da cercare sul costo degli ordini; resta il tetto agli ordini per frame nell'outbox.

**Conseguenza: la soglia del relay si divide in due requisiti.**

| Requisito | Cosa misura | Proposta |
| --- | --- | --- |
| Overhead del relay | costo fisso del messaggio, decodifica, verifiche | ≤ 0,05 ms per frame per AI: misurati 0,9 µs per ordine (0,16 di decodifica, il resto tabelle per ordine, riducibili) più un costo fisso sotto 200 µs, da rimisurare con un timer più fine |
| Ritmo degli ordini dell'AI | ordini per unità emessi per frame; ogni client ne paga l'esecuzione (circa 4,2 µs per movimento) | media ≤ 25 ordini per frame per AI, picchi distribuiti su più frame dall'outbox; valore da tarare |

Un'AI che emette 1.000 ordini in un frame costa 4,2 ms a ogni giocatore, il 12% di un frame da 33,3 ms: è un limite di comportamento dell'AI, non di architettura.

### Risultati: BARb e SimpleAI come riferimento

Un'AI completa come BARb costa in media circa 0,05 ms per frame a 160 unità, con un p99 intorno a 0,3 ms: meno dello 0,2% di un frame da 33 ms. Misura del 23 nov 2026: BARb (team 1) e SimpleAI (team 0) nella stessa partita, Comet Catcher Remake 1.8, finestre di 30 secondi. Unità totali in partita: 27, 71, 156 e 212 ai minuti 2, 5, 10 e 15.

| Minuto | AI | Unità proprie | Media ms/frame | p99 ms | Max ms | µs per unità propria |
| --- | --- | --- | --- | --- | --- | --- |
| 2 | BARb | 15 | 0,016 | 0,122 | 0,804 | 1,10 |
| 2 | SimpleAI | 12 | 0,012 | 0,207 | 0,527 | 0,96 |
| 5 | BARb | 44 | 0,026 | 0,144 | 0,619 | 0,59 |
| 5 | SimpleAI | 27 | 0,015 | 0,271 | 0,303 | 0,56 |
| 10 | BARb | 111 | 0,050 | 0,270 | 0,644 | 0,45 |
| 10 | SimpleAI | 45 | 0,017 | 0,287 | 0,431 | 0,38 |
| 15 | BARb | 164 | 0,050 | 0,312 | 0,647 | 0,30 |
| 15 | SimpleAI | 48 | 0,013 | 0,239 | 0,543 | 0,27 |

**Lettura.**

- **Costano poco tutte e due.** Media sotto 0,05 ms per frame, p99 sotto 0,32 ms, massimo sotto 1,1 ms.
- **BARb cresce con le unità, SimpleAI no.** BARb passa da 0,016 a 0,050 ms mentre le sue unità passano da 15 a 164: costo triplicato per 11 volte le unità. SimpleAI resta piatto perché lavora una volta ogni 15 frame. Per tutte e due il costo per unità scende col tempo.
- **Chi paga.** SimpleAI è synced: i suoi circa 0,015 ms li paga ogni client. BARb è unsynced: i suoi circa 0,05 ms li paga solo il client che la ospita.
- **Gli ordini pesano quanto l'AI.** In entrambi i casi gli ordini si eseguono in synced su tutti i client, e quel costo non compare in nessuno dei due timer. A circa 4 µs per ordine (misure del relay), 12 ordini per frame costano a ogni client quanto l'intera BARb al suo host. Il tetto di ordini per frame dell'outbox conta quanto il budget dello scheduler.
- **Per il budget dello scheduler.** 0,05 ms di media e 0,3 ms di p99 a 160 unità sono un riferimento ragionevole. Le soglie della tabella dei requisiti (media ≤ 1 ms, p99 ≤ 4 ms) sono larghe di un ordine di grandezza: vanno riviste su questi numeri, lasciando margine per un'AI in Lua, più lenta del C++ di BARb.

**Avvertenze di misura.**

- Il confronto è indicativo, non esatto al µs: per BARb il tempo viene dal timer per AI dell'engine, per SimpleAI dagli agganci del gadget di prova sui suoi call-in.
- Il timer per AI dell'engine esiste solo con `/debug` attivo; il profiler aggiunge un piccolo costo, uguale per le due AI.
- Chiedere `frameData` a `Spring.GetProfilerTimeRecord` fa crashare l'engine.
- Il passo del timer cresce con il tempo di esecuzione della partita.
- `VFS.UnpackU8` non legge l'ultimo byte di una stringa (§ Canale dei comandi).

### Risultati: garbage collection

Non servono pool di tabelle in generale: basta non allocare nei percorsi eseguiti a ogni frame. La `collectgarbage("collect")` di STAI invece costa 65–70 ms ogni volta e va vietata. Misura del 23 nov 2026, `/luarules aibench gc`, unsynced, 900 frame per scenario a gioco in corsa; le tabelle allocate restano in vita 300 frame. Passo del timer salito da 2 a 16 µs durante la misura.

| Scenario | Media ms | p99 ms | Max ms | Heap KB (inizio / metà / fine) | GC engine ms/frame (media / p99 / max) |
| --- | --- | --- | --- | --- | --- |
| 0 tabelle per frame | 0,001 | 0,004 | 0,008 | 46.796 / 47.146 / 47.040 | 0,164 / 1,385 / 2,052 |
| 100 tabelle per frame | 0,030 | 0,052 | 0,076 | 46.850 / 56.921 / 57.840 | 0,179 / 1,538 / 2,723 |
| 1.000 tabelle per frame | 0,246 | 0,448 | 0,544 | 46.864 / 150.474 / 167.031 | 0,370 / 2,373 / 3,828 |
| 10.000 tabelle per frame | 1,781 | 2,424 | 3,560 | 46.864 / 1.108.211 / 952.848 | 1,469 / 4,850 / 16,990 |
| 1.000 per frame + `step 0` a ogni frame | 0,256 | 0,464 | 3,632 | 46.889 / 150.500 / 166.669 | 0,440 / 3,815 / 6,585 |
| 1.000 per frame + `collect` ogni 121 frame (STAI) | 0,720 | 0,672 | 69,664 | 46.888 / 136.291 / 128.786 | 0,349 / 2,405 / 3,829 |
| una `collect`, heap \~74 MB | 18,2 | 24,8 | 24,8 | 73.773 | 0,61 / 2,55 / 2,55 |
| una `collect`, heap \~208 MB | 83,7 | 86,1 | 86,1 | 208.178 | 0,73 / 1,59 / 1,59 |
| una `collect`, heap \~531 MB | 132,8 | 135,1 | 135,1 | 530.742 | 0,53 / 2,17 / 2,17 |

**Come leggerla.**

- Nelle tre righe di `collect` media, p99 e massimo sono calcolati su 5 collect, non per frame; l'heap è quello prima della prima collect.
- L'heap della LuaRules unsynced parte già da circa 47 MB: per questo la riga prevista a 50 MB è arrivata a 74.
- Il timer `Lua::CollectGarbage::Unsynced` somma tutti gli stati Lua unsynced, LuaUI compreso: vale 0,16 ms di media e 1,4 ms di p99 anche quando il gadget non alloca nulla.
- Con 10.000 tabelle per frame l'heap è arrivato a 1,1 GB senza errori di memoria.

**Conseguenze sul progetto.**

1. *Pool di tabelle: solo dove servono.* 100 tabelle per frame costano 0,03 ms nostri più circa 0,015 ms di GC dell'engine; 1.000 costano 0,25 ms più circa 0,2 ms. Un pool conviene solo in un modulo che creerebbe centinaia di tabelle per frame. La regola resta: niente allocazioni nei percorsi eseguiti a ogni frame.
2. *`collectgarbage("step", 0)` non aiuta:* i nostri tempi restano uguali e la GC dell'engine sale.
3. *La `collect` di STAI è il costo peggiore misurato finora:* circa 65–70 ms su 136 MB di heap, cioè due frame persi ogni 4 secondi. Cresce con tutto l'heap della LuaRules, non solo con i dati dell'AI (18 ms a 74 MB, 84 ms a 208 MB, 133 ms a 531 MB). Resta vietata, compresa quella in fondo a `MapHST:Init`.
4. *Il p99 sotto 0,3 ms è raggiungibile* con un'allocazione realistica: con circa 100 tabelle per frame il p99 è 0,05 ms, con 1.000 sale a 0,45 ms. La GC dell'engine, con un p99 di circa 1,4 ms anche senza di noi, viene da tutto il Lua unsynced ed è fuori dal budget del runtime.

**Appunto del 23 nov 2026: le due difese di memoria di STAI.**

- *Il guardiano del vecchio `AILoader.lua`.* Ogni 121 frame, sulla prima AI, leggeva `gcinfo()`. Se superava il limite (200 MB all'inizio, poi 50 MB in più per ogni AI), chiamava `collectgarbage("collect")` e alzava il limite a memoria viva + 200 MB + 50 MB per AI, fino a 1 GB. Come rete di sicurezza l'idea era sensata, ma non regge ai numeri. `gcinfo()` misura tutto il Lua della LuaRules, non solo Shard. La `collect` costa 65–70 ms a 136 MB. Libera solo la spazzatura, che la GC incrementale dell'engine raccoglierebbe comunque, mentre una perdita vera (dati ancora raggiungibili) resta e fa solo alzare il limite. **Aperto, da riparlarne: per l'utente è una sicurezza contro il crash del gioco in caso di perdita. Proposta del coordinatore: si tiene la parte di misura e si toglie la `collect`:** campionamento periodico di `gcinfo()`, picco nel log e un `Warn` se la memoria viva cresce di continuo, cioè il segno di una perdita da cercare.
- *I pool di celle di `LosHST`.* Le celle delle griglie `ENEMY` e `OWN` non si distruggono a ogni aggiornamento: tornano in una griglia di riserva e si svuotano quando si riprendono. Da valutare con l'utente. È la tecnica giusta in Lua 5.1 per un punto caldo che rifà migliaia di tabelle a ogni giro, e coincide con la conclusione delle misure qui sopra: pool solo dove servono. Si tiene, con tre ritocchi da fare durante il porting di `LosHST`. (1) Una griglia unica con un contatore di giro al posto dello spostamento fra griglia e riserva: una cella con il giro vecchio vale vuota e si azzera quando si usa, così sparisce il passaggio con `pairs` su tutte le celle a ogni aggiornamento. (2) Niente `"pool" .. nome` a ogni chiamata. (3) Un difetto latente: `Update` libera `"ALLY"`, mentre le griglie sono `ALLY` e `ALLIES` e il pool è `poolALLIES`; nessuna delle due viene mai riempita, quindi il controllo su `loshst.ALLY` in `ScoutHST` non scatta mai. Con `LosHST` d'ally team i pool si allocano una volta per alleanza invece che una volta per AI.

### Scenario standard

- Due mappe da fissare: una piccola per 1 contro 1 e una grande per 8 AI.
- Start script fisso, quindi GameID e seme fissi; engine headless di `tools/headless_testing/`.
- Configurazioni: 1 AI contro NullAI; 4 AI tutti contro tutti; 8 AI tutti contro tutti.
- Durata: 20 minuti di tempo di gioco.
- Per il costo sui client non host: un secondo client spettatore collegato, misurato a parte.

### Metriche e uscita

Media, 99° percentile e massimo dei ms per frame dell'AI sull'host; ms per frame del relay su ogni client; ordini e byte per frame; heap Lua; latenza in frame. La telemetria scrive un JSON a fine partita, nello stesso stile del `results.json` dei test headless, così i numeri di ogni versione si confrontano automaticamente con le soglie della sezione Obiettivi.

## Roadmap a fasi

Il lavoro procede in sei fasi senza date, ognuna chiusa da un criterio verificabile: si passa alla successiva solo quando il criterio è soddisfatto. La fase 0 viene prima di qualunque codice del framework perché può cambiare le soglie e alcune scelte.

&#91;embedded content: roadmap · 6 fasi, ognuna con un criterio d'uscita\]

I numeri dei criteri (costo a vuoto, 8 vittorie su 10) sono proposte da confermare dopo la fase 0, come tutte le soglie del documento.

**Stato al 23 nov 2026.** La fase 0 è chiusa: costi delle chiamate, relay, varianti, `AllowCommand`, BARb e SimpleAI, garbage collection. Manca solo la latenza in multiplayer, che si misura prima di scegliere il default synced o unsynced. La fase 1 non ne dipende, perché il runtime è lo stesso nei due modi e cambia solo il lato di `AILoader.lua` che lo ospita. Le nuove soglie (media ≤ 0,2 ms, p99 ≤ 1 ms, ≤ 25 ordini per frame) sono nella tabella dei requisiti.

## Rischi e questioni aperte

Il rischio più grande non è tecnico: BAR ha appena rimosso Shard e STAI come "inutilizzati", e una nuova versione di Shard va proposta ai maintainer prima di essere costruita. Il secondo è che l'esecuzione unsynced si fida, per costruzione, del client che ospita l'AI.

| Rischio | Impatto | Mitigazione |
| --- | --- | --- |
| BAR non vuole riaccogliere Shard accanto a BARb e SimpleAI | il lavoro resta fuori dal gioco | discutere la proposta con i maintainer prima della fase 1, portando i numeri della fase 0 |
| L'host può modificare la propria copia del codice e far barare l'AI (informazioni complete, ordini arbitrari alle unità dell'AI) | partite con AI truccate | il relay limita i danni alle sole unità dell'AI; per contesti competitivi resta la modalità synced, dove il codice è lo stesso per tutti |
| L'host lascia la partita | l'AI perde la memoria interna | successore deterministico e recupero dal mondo; i piani ripartono da zero |
| Host con ping alto | ordini in ritardo di diversi frame | misura in fase 0; scelta del successore con il ping più basso (`Spring.GetPlayerInfo` riporta il ping) |
| Limiti del server su frequenza o banda dei messaggi Lua | ordini persi o ritardati | un messaggio per frame; misura in fase 0 con 8 AI |
| Il budget per frame peggiora la qualità delle decisioni | AI più debole | profilazione per modulo, lavori lunghi a passi, budget configurabile |
| La percezione `fair` è imprecisa (errore radar, fantasmi) | AI troppo informata o troppo cieca | parametri tarati confrontando con un giocatore umano in LuaUI |
| Cambi nelle API di Recoil | rotture | `spring_lua/` e `AILoader.lua` sono gli unici punti del runtime che le toccano; le chiamate dirette a `Spring.*` nel codice delle AI vanno controllate a parte; test headless con engine stock in CI |
| Il porting di STAI cambia il comportamento in modo non voluto (elezione, percezione, turni) | AI più debole o diversa da quella di oggi | porting in due passi: prima con le opzioni di compatibilità, poi senza, confrontando partite con lo stesso seme |

Un rischio in più introdotto dagli ambiti: con un host per ally team, il client che ospita due o tre AI alleate paga il loro costo complessivo. La condivisione riduce quel costo rispetto a STAI, ma la soglia di budget va verificata con più AI sullo stesso client (scenario a 8 AI della fase 0).

**Questioni aperte.**

1. BAR è interessato? Serve una risposta dei maintainer prima della fase 1.
2. Default unsynced o synced: dipende dai numeri della fase 0 e da quanto i maintainer accettano la fiducia nell'host.
3. **Richieste di percorso**: problema strutturale segnalato, rinviato a data da destinarsi; il servizio percorsi resta provvisorio fino ad allora (§ Servizi di mappa condivisi).
4. Host per ally team o host unico per tutta la partita: il primo distribuisce la CPU, il secondo condivide anche l'ambito globale; va deciso con i numeri della fase 0.
5. Come si spartiscono il budget i tre ambiti: pesi fissi, adattivi o dichiarati dall'AI.
6. Valori definitivi delle soglie: budget, griglia dell'errore radar, limiti del relay, quarantena.
7. Nomi nuovi da confermare: `Scope()`, `ShardAlly`, `ShardGlobal`, `Perception()`, `QueueActivation`, `Job`, `legacyElection`, e il nome della versione nel `GetInfo` di `AILoader.lua`.
8. Globali `ai`, `game`, `map` di `Prepare()`: restano per compatibilità; vanno deprecate più avanti a favore di `self.ai`, `self.game`, `self.map`?
9. L'opzione `legacyElection` serve solo durante il porting di STAI o resta anche dopo?
10. Quali metodi di `ShardUnit` filtrare per i nemici, oltre a posizione, salute e tipo.
11. Licenza: i gadget di BAR dichiarano di norma GPL v2 o successiva e `AILoader.lua` dichiarava "GPL"; va confermata per il nuovo codice e per le parti recuperate.
12. Chi mantiene il runtime dopo l'ingresso in BAR.

**Appunto del 23 nov 2026: quante AI per tipo, e un solo cervello per alleanza.**

- Ogni tipo di AI dichiara al proprio interno quante istanze consente: per esempio un campo nella classe dell'AI, `STAI.maxInstances` (nome da decidere). Il valore lo sceglie chi scrive l'AI.
- Scenario ideale: se qualcuno carica 8 STAI nella stessa alleanza, a comandarle è in realtà sempre la stessa AI. Un solo cervello decide per tutti i team dell'alleanza; i team restano solo i proprietari delle unità. È il passo naturale dopo gli ambiti: quasi tutti i moduli diventano d'ally team.
- Da verificare: se e come BARb riduce i «cervelli» quando ne vengono inseriti troppi.
- Resta aperto il caso FFA: ogni AI è in un'alleanza diversa e non c'è nulla da condividere. Va deciso cosa succede alle AI oltre il massimo consentito.

## Fonti e riferimenti nel codice

**Documenti collegati.** [Shard framework (BAR) — analisi tecnico-strutturale](https://claude.ai/artifact/LXgMjkgunz9TUyAgm2gdxt): difetti del framework rimosso, confronto con l'originale, stima gadget contro nativo.

**Repository e commit consultati.**

- [beyond-all-reason/Beyond-All-Reason](https://github.com/beyond-all-reason/Beyond-All-Reason), master `50bd47b` (21 nov 2026): `luaai.lua`, `luarules/gadgets/ai_simpleai.lua`, `common/upgets/api_resource_spot_finder.lua`, `.github/agents.md`, `AI_POLICY.md`, `.busted`, `spec/builders/`, `.github/workflows/test_integration.yml`; commit `3ad8f3fb` (rimozione di Shard e STAI) e `3ad8f3fb^`.
- [beyond-all-reason/RecoilEngine](https://github.com/beyond-all-reason/RecoilEngine), master `59650ac` (22 nov 2026): `rts/Lua/LuaHandle.cpp` (`RecvLuaMsg`, call-in di unità e giocatori), `rts/Lua/LuaUnsyncedCtrl.cpp` (`SendLuaRulesMsg`, `GiveOrderToUnit` unsynced), `rts/Lua/LuaSyncedRead.cpp` (`GetAIInfo`, `GetTeamLuaAI`, `GetUnitLosState`), `rts/Lua/LuaUnsyncedRead.cpp` (`GetTimerMicros`), `rts/Lua/LuaVFS.cpp` (`Include`, `Pack*`), `rts/Net/Protocol/BaseNetProtocol.cpp` (dimensione massima del pacchetto), `rts/Game/Players/Player.cpp` (`CanControlTeam`), `.gitmodules`.
- [pandaro/Beyond-All-Reason](https://github.com/pandaro/Beyond-All-Reason), commit `ef5c848`: versione di Shard e STAI analizzata.
- [pandaro/Shard](https://github.com/pandaro/Shard), commit `7ee03c8`: Shard originale con host nativo e gadget synced.
- [Documentazione delle API Lua di Recoil](https://recoilengine.org/docs/lua-api), citata in `.github/agents.md`.

**Aggiunte per ambiti, percezione e ambiente di sviluppo.**

- [README di BAR, Development Quick Start](https://github.com/beyond-all-reason/Beyond-All-Reason#development-quick-start) e [tools/headless\_testing/README.md](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/master/tools/headless_testing): copia `.sdd`, test headless con il client installato.
- Widget di visibilità di BAR: `luaui/Widgets/gui_los_view_gl4.lua`, `gfx_los_view.lua`, `unit_ghostradar_gl4.lua`, `unit_ghostsite_gl4.lua` (master `50bd47b`).
- Versione rimossa di STAI al commit `3ad8f3fb^`: `luarules/gadgets/ai/STAI/loshst.lua`, `maphst.lua`, `schedulerHST.lua`, `attackhst.lua`.
- [Claude Code in VS Code](https://code.claude.com/docs/en/vs-code.md), [Claude Code nell'app desktop](https://code.claude.com/docs/en/desktop.md), [Claude Code nel cloud](https://code.claude.com/docs/en/claude-code-on-the-web.md), [memoria e CLAUDE.md](https://code.claude.com/docs/en/memory.md).

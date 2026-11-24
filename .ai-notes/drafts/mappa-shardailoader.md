# Mappa di `ShardAILoader.lua` (stato dopo T6, 1166 righe)

Scopo: vedere dove sta il disordine prima di decidere come riordinare. Nessuna modifica proposta al comportamento.

## Come è fatto oggi

| Righe | Lato | Cosa contiene |
| --- | --- | --- |
| 1–54 | entrambi | `GetInfo`, cache di `Spring.*`, ricerca dei team AI (`aiTeams`), uscita se non ce ne sono, controllo di `Game.maxUnits` |
| 55–297 | synced | stato del relay (`aiHostPlayer`, `lastSeq`, `lastFrame`, `messagesInFrame`, contatori), host (`IsActive`, `ChooseSuccessor`, `RegisterHosts`), ordini (`AddOrder`, `GiveOrders`, `Reject`), call-in (`Initialize`, `GameStart`, `PlayerRemoved`, `RecvLuaMsg`, `Shutdown`) |
| 298–345 | unsynced | altre cache di `Spring.*`, **11 variabili di stato** (host, avvio, catch-up, runtime, seme, memoria ×5, tipi falliti, ally nuovi) |
| 346–388 | unsynced | runtime e seme: `LoadRuntime`, `gadget:HashGameID`, `TeamSeed` |
| 389–447 | unsynced | errori e chiamate protette: `ObjectLabel`, `ReportError`, `WithTraceback`, `ProtectedCall`, `Call` |
| 448–502 | unsynced | consegna degli eventi: `HasModules`, `Deliver`, `DeliverToShared`, `DeliverToAIs`, `DeliverToAll`, `DeliverSight` |
| 503–536 | unsynced | tabelle di unità provvisorie: `AddToUnitTables`, `RemoveFromUnitTables` |
| 537–576 | unsynced | anello delle unità morte: `GrowDeadRing`, `KeepDeadUnit`, `ExpireDeadUnits` |
| 577–764 | unsynced | caricamento: `gadget:NewAPI`, `gadget:LoadAIType`, `gadget:GetAlly`, `gadget:SetupAI`, `RemoveValue`, `RemoveAlly`, `RemoveNewAllies`, `LoadingFailed`, `gadget:AddAI` |
| 765–858 | unsynced | avvio e arresto: `StopAI`, `StartObject`, `DropFailed`, `gadget:StartAIs`, `Ready` |
| 859–926 | unsynced | `gadget:CatchUp`, `HostChanged`, `RelayRejected` |
| 927–1013 | unsynced | `Initialize`, `GameStart`, `UpdateObject`, `GameFrame` |
| 1014–1166 | unsynced | call-in delle unità, LOS/radar, `FeatureDestroyed`, `GameOver`, `GameID`, `Shutdown` |

## I percorsi principali

- **Avvio**: `Initialize` → per ogni team ospitato qui `AddAI` → (`LoadRuntime`, `SetupAI` → `LoadAIType` → `NewAPI`, `GetAlly`) → al primo `GameFrame` o in `GameStart`, `Ready` → `StartAIs` → `StartObject` per global, ally, team → `DropFailed`.
- **Ogni frame**: `GameFrame` → `Ready` → `UpdateObject` × tutti gli oggetti → `outbox:Flush` × AI → `ExpireDeadUnits` → misura della memoria → picco di `gcinfo()`.
- **Un evento di unità**: call-in → `Ready` → tabelle di unità / anello dei morti → `Deliver*` → `Call` → `xpcall` → `ReportError`.
- **Cambio di host**: `HostChanged` → `AddAI` + `StartAIs` + `CatchUp`, oppure `StopAI`.

## Dove sta il disordine

1. **Due modi di scrivere le funzioni d'aiuto.** Alcune sono metodi del gadget (`gadget:NewAPI`, `LoadAIType`, `GetAlly`, `SetupAI`, `AddAI`, `StartAIs`, `CatchUp`, `HashGameID`), altre `local function`. Non c'è una regola: sembrano call-in dell'engine ma non lo sono.
2. **Lo stato è sparso.** Le 11 variabili dell'unsynced stanno in cima, ma l'anello dei morti dichiara le sue a metà file (righe 537–538) e la memoria ne ha cinque fra loro scollegate.
3. **`GameFrame` fa cinque lavori diversi** in 50 righe (update, invio degli ordini, scadenza dei morti, statistiche della memoria, picco della memoria), tutti scritti lì dentro invece che chiamati per nome.
4. **Caricamento e gestione dei fallimenti intrecciati.** `AddAI`, `SetupAI`, `GetAlly`, `newAllies`, `RemoveNewAllies`, `LoadingFailed`, `failedTypes`, `runtimeFailure`, `DropFailed`, `StopAI` si leggono solo tutti insieme.
5. **Le parti provvisorie sono sparse** (consegna a tutti, tabelle di unità, `Update` a ogni frame): commentate, ma in punti diversi.
6. **Ogni call-in comincia con `if not Ready() then return end`**, e `Ready` può avviare le AI: un controllo che ha un effetto collaterale.
7. **Synced e unsynced non seguono lo stesso ordine** di sezioni.

## Confronto con il vecchio `AILoader.lua` (559 righe)

Era: synced (tabelle d'appoggio, decodifica degli ordini, `RecvLuaMsg`), poi unsynced con `Initialize`, `SetupAI`, `GameStart`, `GameFrame` e i call-in uno dopo l'altro, ognuno completo in sé. Più corto perché faceva meno (niente ambiti, niente controlli del relay, niente errori contenuti), e più facile da leggere perché ogni call-in diceva tutto.

## Proposta di disposizione (da discutere)

Nel tuo stile: funzioni piccole con un nome che dice cosa fanno, composte in «macro» che si leggono come una sequenza di passi.

**Un file per compito**, tutti in `shard_runtime/` tranne il gadget:

| File | Lato | Contenuto |
| --- | --- | --- |
| `ShardAILoader.lua` | entrambi | solo: ricerca dei team AI, i call-in dell'engine, ognuno una macro di poche righe che chiama le funzioni dei file sotto |
| `relay.lua` | synced | stato e controlli del relay, `AddOrder`/`GiveOrders` |
| `hosts.lua` | synced | `IsActive`, `ChooseSuccessor`, `RegisterHosts` |
| `loader.lua` | unsynced | caricamento dei tipi e degli oggetti, fallimenti, `StartAIs`, `StopAI`, `CatchUp` |
| `delivery.lua` | unsynced | `Call`, errori, consegna degli eventi (qui si concentra la parte provvisoria «eventi a tutti») |
| `unitregistry.lua` | unsynced | tabelle di unità (provvisorie) e anello dei morti |
| `memstats.lua` | unsynced | misura della memoria per frame e picco |

**Stesso ordine in ogni file**: intestazione con lo scopo, costanti, stato, funzioni piccole, funzioni composte, cosa esporta.

**Un `GameFrame` che si legge così:**

```lua
function gadget:GameFrame(n)
	if not hosting then
		return
	end
	StartAIsOnce()
	UpdateAll()
	FlushOrders(n)
	ExpireDeadUnits(n)
	MemStatsFrame(n)
end
```

**Domande per te:**

1. Va bene dividere in più file del runtime, o preferisci un file solo con sezioni ben ordinate (più vicino al vecchio loader)?
2. Le funzioni d'aiuto come `gadget:Metodo` o come `local function`? (Shard usava i metodi del gadget per `SetupAI`.)
3. I nomi dei file e delle sezioni ti tornano?

## Decisioni

- **24 nov 2026, utente**: si divide in più file, uno per compito.
- **Proposte del coordinatore, da confermare**:
  - i file del loader stanno in `shard_runtime/loader/` (separati dal runtime che vedono le AI);
  - ogni file restituisce una tabella con le sue funzioni (`local Relay = VFS.Include(...)`), niente globali: l'ambiente delle AI ricade sul gadget, quindi un globale del loader sarebbe visibile a STAI;
  - dentro i file solo `local function`; `gadget:Metodo` solo per i call-in dell'engine;
  - i file synced (`relay.lua`, `hosts.lua`) restano deterministici e non includono niente di unsynced.

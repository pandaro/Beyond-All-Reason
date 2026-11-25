# Shard for Beyond All Reason

Shard is a framework for writing Lua AIs for Beyond All Reason (Recoil engine). It loads an AI from a folder, gives it a small object model (the AI, its modules, its units and their behaviours), forwards engine events to it, and wraps the engine API in `game`, `map` and unit objects.

This guide covers the framework as it is being rebuilt. Each section says how settled it is:

- **Stable**: the code is in the branch and tested.
- **In progress**: being implemented now; the description is the agreed design.
- **Planned**: agreed design, not yet in the code. Do not rely on it.

The design behind these choices is in the architecture proposal. This guide only says what a user of the framework needs to know.

## Contents

1. [Files and folders](#files-and-folders)
2. [A minimal AI](#a-minimal-ai)
3. [Classes](#classes)
4. [Loading: `shard_include` and environments](#loading-shard_include-and-environments)
5. [The AI object](#the-ai-object)
6. [Modules](#modules)
7. [Scopes: team, ally, global](#scopes-team-ally-global)
8. [Events](#events)
9. [Units and behaviours](#units-and-behaviours)
10. [The API: `game`, `map`, units](#the-api-game-map-units)
11. [Logging and debugging](#logging-and-debugging)
12. [Testing](#testing)
13. [Rules for code that runs every frame](#rules-for-code-that-runs-every-frame)
14. [How an AI runs in a game](#how-an-ai-runs-in-a-game)

## Files and folders

**Stable.**

```
luarules/gadgets/ShardAILoader.lua          -- the gadget that finds AI teams, runs them and relays their orders
luarules/gadgets/ai/shard_runtime/          -- the framework: classes, API, test doubles
    class.lua                               -- class()
    aibase.lua                              -- AIBase: the base of every Shard object
    shardai.lua                             -- ShardAI: one AI instance
    shardally.lua, shardglobal.lua          -- containers of shared modules
    module.lua                              -- Module
    behaviour.lua                           -- Behaviour
    unit.lua                                -- Unit: the per-unit mini AI that holds behaviours
    api.lua                                 -- builds the game and map objects
    ordercodec.lua                          -- the binary format of order messages
    spring_lua/                             -- the real API on top of the engine
        outbox.lua                          -- ShardOutbox: the per-AI order queue
    shard_null/                             -- a fake API for tests without the engine
luarules/gadgets/ai/<AIName>/               -- one folder per AI type
    boot.lua                                -- returns the first instance of the AI
    ai.lua                                  -- the AI class
    modules.lua                             -- the list of module classes
    behaviourfactory.lua, behaviours.lua    -- which behaviours each unit gets
    *hst.lua, *bst.lua                      -- modules and behaviours (naming convention of STAI)
```

Two AIs ship with the framework: `Shard`, the small reference AI, and `STAI`.

VFS paths are case-insensitive in Recoil, so `shard_include("schedulerhst")` finds `schedulerHST.lua`.

## A minimal AI

**Stable.**

```lua
-- luarules/gadgets/ai/MyAI/boot.lua
shard_include("ai")
return MyAI()
```

```lua
-- luarules/gadgets/ai/MyAI/ai.lua
MyAI = class(ShardAI)

function MyAI:Name()
	return "MyAI"
end

function MyAI:internalName()
	return "myai"
end
```

```lua
-- luarules/gadgets/ai/MyAI/modules.lua
shard_include("ecohst")

return {
	EcoHST,
}
```

```lua
-- luarules/gadgets/ai/MyAI/ecohst.lua
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
end

function EcoHST:Update()
	local metal = self.game:GetResourceByName("metal")
	self:EchoDebug("metal", metal.currentLevel, "income", metal.income)
end
```

The module is then reachable from every other module of the AI as `self.ai.ecohst`.

## Classes

**Stable.**

Every Shard object is made with `class()`:

```lua
Base = class(function(self, a) self.a = a end) -- a class with a constructor
Derived = class(Base)                           -- a subclass
local object = Derived(1)                       -- calling the class makes an instance
object:is_a(Base)                               -- true
```

Things to know:

- **A subclass is a shallow copy of its base, made when `class()` runs.** A method added to the base after the subclass exists is not inherited. Define base methods before deriving from them.
- The instance's metatable is its class: `getmetatable(object)` is `Derived`, which can be called to make another instance.
- Shard classes use `Init()` (capital I) for setup, called by the framework once the object is wired up. The lower-case `init` is the `class()` constructor; avoid it unless you need constructor arguments.

The framework classes:

| Class | Base | What it is |
| --- | --- | --- |
| `AIBase` | | Default no-op event handlers, `SetAI`, logging. |
| `ShardAI` | `AIBase` | One AI: owns its modules and forwards events to them. Your AI class derives from it. |
| `ShardAlly`, `ShardGlobal` | `ShardAI` | Containers of shared modules (see [Scopes](#scopes-team-ally-global)). |
| `Module` | `AIBase` | A part of an AI that lives for the whole game: economy, production, map analysis… |
| `Behaviour` | `AIBase` | A piece of logic attached to one unit. |
| `Unit` | `AIBase` | The mini AI of one unit: holds its behaviours and elects which one is in control. |
| `BehaviourFactory` | `AIBase` | Decides which behaviours a new unit gets. Each AI provides its own. |

## Loading: `shard_include` and environments

**Stable.**

Inside an AI, files are loaded with `shard_include(name)`, without the `.lua` extension. It looks, in this order, for:

1. `ai/<AIName>/<name>.lua`
2. `ai/<AIName>/<name>/main.lua`
3. `shard_runtime/<name>.lua`
4. `shard_runtime/<name>/main.lua`

and returns what the file returns. If none exists it prints the candidates and returns `nil`.

**Each AI type has its own environment.** The loader gives every AI type a table that falls back (`__index`) to the gadget environment, so `Spring`, `UnitDefs`, `CMD`, `class`, `Module` and the other framework classes are visible as usual. Globals that the AI's files define (`MyAI`, `EcoHST`…) end up in that table. Two AI types can therefore both define a class called `EcoHST` without overwriting each other. This is not a sandbox: the AI can still call any `Spring.*` function.

**Each file runs once per AI type.** The first `shard_include("ecohst")` runs the file; later calls, from any AI of the same type, return the value it returned the first time without running it again. So a class is defined once and every AI of that type shares it. The cache ignores case and remembers `nil` results too.

Consequences for AI authors:

- Code at the top level of a file runs once per AI type, not once per AI. Per-AI state belongs in `Init()`, not at file level.
- A table returned by a file (like the list in `modules.lua`) is shared by every AI of that type: read it, do not modify it.

The function behind this is `shard_generate_include_func(runtime_path, ai_path, env)` in `spring_lua/boot.lua`. Without `env` it behaves as in the old Shard: no cache, files run in the caller's environment every time.

## The AI object

**Stable.**

`boot.lua` returns the first instance of the AI. The loader makes one instance per team that runs this AI, fills in its fields and calls `Init()` through `Prepare()`.

Fields set by the loader:

| Field | Meaning |
| --- | --- |
| `id` | Team ID. |
| `allyId` | Ally team ID. |
| `fullname` | The AI's name as chosen in the lobby. |
| `api` | The API object: `api.game`, `api.map`, `api.shard_include`. |
| `ally`, `global` | The containers of the shared modules. |

Set by `ShardAI:Init()`: `game`, `map` (shortcuts to `api.game` and `api.map`), `modules` (the module instances this AI owns, in `modules.lua` order), and one field per module named after its `internalName()`.

`Prepare()` runs before the AI handles anything. It sets the globals `ai`, `game`, `map` and `shard_include` to this AI's, and calls `Init()` the first time. Older code reads those globals; new code should prefer `self.ai`, `self.game` and `self.map`, which are always right.

## Modules

**Stable.**

A module is a class derived from `Module`, listed in the AI's `modules.lua`. Every module must define:

| Method | Returns | Notes |
| --- | --- | --- |
| `Name()` | a readable name | Shown in logs. |
| `internalName()` | a lowercase identifier | The module is stored as `self.ai.<internalName>`. If it is missing, or two modules share a name, the module is not loaded and a warning is printed. |
| `Scope()` | `"team"`, `"ally"` or `"global"` | Mandatory. Without it, or with any other value, the module is not loaded and a warning is printed. See [Scopes](#scopes-team-ally-global). |

After loading, each module has `self.ai` (the object that owns it), `self.game` and `self.map`. Modules are initialised in the order of `modules.lua`, so a module can use, in its `Init()`, the modules listed before it.

Modules talk to each other through methods: `self.ai.loshst:posInLos(pos)`. A module that wants to change another module's data calls a method of that module; only the owner writes its own data.

Modules may call `Spring.*` directly, as STAI does.

## Scopes: team, ally, global

**Stable.** The loader creates `ShardAlly` and `ShardGlobal` and feeds them events. In STAI, ArmyHST, GridHST and MapHST are `"global"`; the other modules declare `"team"` for now, and LosHST will move to `"ally"` when it is ported.

Some work is the same for every AI: the map analysis does not depend on the team, and the line of sight is shared by the whole ally team. Each module declares where it lives with `Scope()`, and the framework creates it once per instance of that scope:

| `Scope()` | Instances | Owned by | Typical content |
| --- | --- | --- | --- |
| `"team"` | one per AI | the AI (`ShardAI`) | economy, production, the AI's units |
| `"ally"` | one per ally team and AI type | `ShardAlly` | line of sight and radar, enemy memory, threat maps |
| `"global"` | one per hosting client and AI type | `ShardGlobal` | map analysis, unit type tables |

How it looks from the code:

- A team module reaches modules of all three scopes as `self.ai.<internalName>`, so existing code like `self.ai.maphst` keeps working when MapHST becomes global.
- In an ally module, `self.ai` is the `ShardAlly`. It has `allyId` and `AIs` (the AIs of this type in the ally team), and reaches ally and global modules, but not team modules.
- In a global module, `self.ai` is the `ShardGlobal`. It has `AIs` (all AIs of this type on this client), and reaches only global modules.
- Dependencies go one way only: team → ally → global.
- Each module receives an event once, from the object that owns it. An ally module hears `UnitEnteredLos` once per ally team, not once per AI.
- A shared module has no team of its own: `self.ai.id` and `self.game:GetTeamID()` do not apply. Use `self.ai.allyId` or loop over `self.ai.AIs`.

Behaviours are always per team: they belong to one unit.

Shared modules are shared only between AIs of the same type: STAI's MapHST is never shared with Shard's.

"Global" means once per client that hosts AIs, not once per game. If two ally teams are hosted by two different players, each player's client has its own global modules.

How the framework loads them: `ShardAI:Init` passes every class listed in `modules.lua` to `ShardAI:LoadModule`, which reads `Scope()` on the class before making an instance.

- Same scope as the container: a new instance, owned by this container.
- Wider scope: `self.<internalName>` points to the instance the `ally` or `global` container already holds. The container above must therefore be initialised first: global, then ally, then team.
- Narrower scope: skipped.
- Missing or unknown `Scope()`: not loaded, with one warning per module class.

`AddModule(module)` accepts only modules of the container's own scope. Log lines from shared modules show `ally <allyId>` or `global` where team modules show their team ID.

## Events

**Stable**, except where marked.

The engine's events reach the AI as method calls. `ShardAI` forwards each one to its modules in `modules.lua` order. A module overrides only the events it needs; `AIBase` provides empty defaults.

| Method | Arguments | Notes |
| --- | --- | --- |
| `Init()` | | Once, before any other event. |
| `Update()` | | Every frame, unless the module runs in turns (see [Scheduler](#scheduler)). |
| `GameEnd()` | | At the end of the game. |
| `GameMessage(text)` | the message | |
| `UnitCreated(unit, unitDefId, teamId, builderId)` | `unit` is a `ShardUnit` | A unit starts being built. |
| `UnitBuilt(unit, unitDefId, teamId)` | | A unit is finished. `AIBase` splits it into `MyUnitBuilt(unit)`, `FriendlyUnitBuilt(unit)`, `EnemyUnitBuilt(unit)` and `NeutralUnitBuilt(unit)`; override those, or `UnitBuilt` itself. |
| `UnitGiven(unit)` | | A unit changes owner. `AIBase` turns it into `UnitCreated` plus `UnitBuilt`. |
| `UnitDead(unit)` | | |
| `UnitIdle(unit)` | | The unit has no more orders. |
| `UnitDamaged(unit, attacker, damage)` | `damage` is a damage object | |
| `UnitEnteredLos`, `UnitLeftLos`, `UnitEnteredRadar`, `UnitLeftRadar` | `(unitID, unitTeam, allyTeam, unitDefID)` | Raw engine IDs, not `ShardUnit` objects. |
| `UnitMoveFailed(unit)` | | **Never delivered in BAR**: the engine sends it only to synced code and BAR does not enable it. Do not rely on it. |

**Who receives an event.** An event reaches only the modules that override its method; the list is built after `Init()` (so a method assigned in `Init()` counts) and again after `AddModule`. `UnitBuilt` also reaches modules that override only `MyUnitBuilt`, `FriendlyUnitBuilt`, `EnemyUnitBuilt` or `NeutralUnitBuilt`; `UnitGiven` reaches the modules that want `UnitCreated` or `UnitBuilt`. An object none of whose modules wants an event is not called at all. Order: global modules first, then ally modules, then team modules, and within each object the order of `modules.lua`. Events about a unit that no longer exists are not delivered.

### Scheduler

By default every module's `Update()` runs every frame, as in the old Shard. An AI can instead run some modules in turns by listing them in its class:

```lua
MyAI.MScheduler = { "EcoHST", "AttackHST" } -- names returned by Name()
```

- Listed modules get `Update()` only on their turn: one turn per frame, one module of one AI. Turns go through the list, and for each name through every AI hosted on this client that declares it. A shared module gets one turn per round, not one per AI.
- Modules not listed still get `Update()` every frame.
- There is no time budget: a turn takes as long as it takes.
- `self.ai.scheduler.moduleTeam` and `.moduleUpdate` tell whose turn it is.
- An AI that wants a different scheduler writes its own and declares no list (STAI does this with its `SchedulerHST`).

Behaviours can run in turns the same way:

```lua
MyAI.BScheduler = { "TaskQueueBehaviour" } -- names returned by the behaviours' Name()
```

- A listed behaviour gets `Update()` only on its turn: one turn per frame, one behaviour name of one AI, for all the units of that AI that have it. Turns go through the list, and for each name through every AI hosted on this client that declares it.
- Behaviours not listed still get `Update()` on every unit update. A unit activates a newly elected behaviour on every update, in turn or not.
- A turn is not skipped when the AI has no unit with that behaviour.
- `self.ai.scheduler.behaviourTeam` and `.behaviourUpdate` tell whose turn it is.
- A behaviour that works in turns should count elapsed frames, not calls: Shard's `TaskQueueBehaviour` does this.


## Units and behaviours

**Stable**: the classes, the events and the election rule.

Every unit the AI owns gets a `Unit` object, its mini AI. The `BehaviourFactory` gives it a list of behaviours: `behaviours.lua` maps unit names to lists of behaviour classes, and `defaultBehaviours(unit, ai)` covers the rest. At any time at most one behaviour is **active**: it is the one in control of the unit.

A behaviour is a class derived from `Behaviour`:

```lua
ScoutBST = class(Behaviour)

function ScoutBST:Name()
	return "ScoutBST"
end

function ScoutBST:Init()
	self:SetPriority(50)
end

function ScoutBST:Activate()
	-- this behaviour now controls self.unit
end

function ScoutBST:Deactivate()
	-- another behaviour took over
end

function ScoutBST:OwnerIdle()
	if self:IsActive() then
		-- give the next order
	end
end
```

Fields: `self.unit` (the `Unit`; `self.unit:Internal()` is the `ShardUnit`), `self.engineID`, `self.ai`, `self.game`, `self.map`.

Events about the behaviour's own unit arrive as `Owner*`; events about other units of the AI keep their usual names:

| Own unit | Other units |
| --- | --- |
| `OwnerCreated(unit, unitDefId, teamId, builderId)` | `UnitCreated(unit, unitDefId, teamId, builderId)` |
| `OwnerBuilt()` | `UnitBuilt(unit)` |
| `OwnerIdle()` | `UnitIdle(unit)` |
| `OwnerDamaged(attacker, damage)` | `UnitDamaged(unit, attacker, damage)` |
| `OwnerDead()` | `UnitDead(unit)` |

All behaviours of a unit receive these events, active or not; check `self:IsActive()` before giving orders.

**Election.** `Priority()` returns the behaviour's priority (set it with `SetPriority`). `self.unit:ElectBehaviour()` picks the behaviour in control; `YieldControlOfUnit()` and `RequestControlOfUnit()` both trigger a new election. The rule:

- Only a priority greater than zero can win; `nil` counts as zero. On a tie the first behaviour in the list wins.
- If the active behaviour wins again, nothing changes.
- If another behaviour wins, the active one is deactivated at once (`PreDeactivate`, `Deactivate`) and the winner is activated on the unit's next update (`PreActivate`, `Activate`).
- If no behaviour has a priority above zero, the unit has no active behaviour: the active one is deactivated, and a behaviour waiting for activation is dropped.

So a behaviour that must control the unit returns a priority above zero, and one that has nothing to do returns zero.

An AI class can keep the older rule with `MyAI.legacyElection = true`: the first behaviour in the list wins even when every priority is zero or less. STAI uses it; new AIs should not.

## The API: `game`, `map`, units

**Stable** as listed. **Planned** changes are noted at the end.

Positions are tables `{ x = …, y = …, z = … }`.

**`game`** (`self.game`): the game and this AI's team.

- Identity and time: `GetTeamID()`, `GetAllyTeamID()`, `Frame()`, `IsPaused()`, `GameName()`.
- Units: `GetUnits()`, `GetFriendlies()`, `GetEnemies()`, `GetUnitByID(id)`, `GetTypeByName(name)`, `getUnitsInCylinder(pos, range)`, `GetTeamUnitDefCount(team, unitDefID)`, `GetTeamUnitsByDefs(team, unitDefIDs)`, `GetUnitSeparation(id1, id2, d2d, surface)`, `GetUnitLos(id, bitmask)`.
- Resources: `GetResourceByName("metal")`, `GetResource(index)`, `GetResources()`, `GetResourceCount()`. A resource has `currentLevel`, `storage`, `pull`, `income`, `expense`, `share`, `sent`, `received`.
- Output: `SendToConsole(...)`, `AddMarker(position, label)`, `DrawDisplay(on)`.

**`map`** (`self.map`): the map.

- Size and terrain: `MapDimensions()`, `MapName()`, `GetGroundHeight(x, z)`, `MaximumHeight()`, `MinimumHeight()`.
- Wind and tide: `GetWind()`, `AverageWind()`, `MinimumWindSpeed()`, `MaximumWindSpeed()`, `TidalStrength()`.
- Resources: `GetMetalSpots()`, `SpotCount()`, `GetSpot(i)`, `GetGeoSpots()`, `GeoCount()`, `GetGeo(i)`. Metal spots come from BAR's resource spot finder (game rules params `mex_count`, `mex_x<i>`, `mex_y<i>`, `mex_z<i>`), read the first time they are asked for; the framework does not compute its own. On a metal map there are none.
- Building: `CanBuildHere(unittype, position)`, `FindClosestBuildSite(unittype, builderpos, searchradius, minimumdistance, validFunction)`.
- Features: `GetMapFeatures()`, `GetMapFeaturesAt(position, radius)`.
- Debug drawing: see [Logging and debugging](#logging-and-debugging).

**`ShardUnit`** (the engine unit, `self.unit:Internal()` in a behaviour):

- Identity: `ID()`, `Name()`, `Type()`, `Team()`, `AllyTeam()`, `IsMine(team)`, `IsFriendly(allyTeam)`, `IsEnemy(allyTeam)`, `isNeutral()`, `IsAlive()`.
- State: `GetPosition()`, `GetHealth()`, `GetMaxHealth()`, `IsBeingBuilt()`, `BuildProgress()`, `CurrentCommand()`, `GetUnitCommands(count)`, `IsCloaked()`, `Stunned()`.
- Orders: `Move(p)`, `AttackMove(p)`, `Patrol(p)`, `Attack(unit)`, `AttackPos(p)`, `Guard(unit)`, `Repair(unit)`, `Build(type, p, facing)`, `Reclaim(thing)`, `AreaReclaim(p, radius)`, `Stop()`, `HoldFire()`, `FireAtWill()`, `HoldPosition()`, `Roam()`, `SelfDestruct()`, and others in `spring_lua/unit.lua`.

**`ShardUnitType`** (`unit:Type()`, `game:GetTypeByName(name)`): read-only data from the unit definition: `Name()`, `ID()`, `IsBuilder()`, `IsFactory()`, `CanBuild(type)`, `CanMove()`, `CanFly()`, `Extractor()`, `BuildCostMetal()`, `BuildCostEnergy()`, `BuildTime()`, `Health()`, `LosRadius()`, and more in `spring_lua/unittype.lua`.

**Orders** (**Stable**):

```lua
self.game:GiveOrder(unitID, CMD.MOVE, { x = 100, y = 0, z = 200 }, 0, "1-1")
self.game:GiveOrder(factoryID, { -defA, -defB }, { 0, 0 }, { 0, 0 }, "2-1")
self.game:GiveOrder({ id1, id2 }, CMD.STOP, nil, 0, "1-2")
unit:Move({ x = 100, y = 0, z = 200 })
```

| `method` | Meaning | `id` | `cmd` | `params`, `options` |
| --- | --- | --- | --- | --- |
| `"1-1"` | one command to one unit | a unit ID | a command | one value each |
| `"2-1"` | several commands to one unit, in order | a unit ID | an array of commands | arrays, one entry per command |
| `"1-2"` | one command to several units | an array of unit IDs | a command | one value each, the same for every unit |
| `"2-2"` | one command per unit, paired by index | an array of unit IDs | an array of commands | arrays, one entry per unit |

- `params` is `nil`, a number, an array of numbers (at most 255), or a position `{ x, y, z }`.
- `options` is a `CMD.OPT_*` bit mask, or an array of names: `"shift"`, `"alt"`, `"ctrl"`, `"meta"`, `"right"`.
- A call with the wrong shape is dropped with a warning; no order of it is queued.
- The order methods of `ShardUnit` (`Move`, `Build`, `Attack`…) go through the same path as `"1-1"`.

Orders are not given at once: they go to the AI's queue (`ShardOutbox`). Once per frame the queue sends one compact binary message with at most 25 orders; the rest waits for the next frames, in order. The orders of one call are never split across two messages. The synced side of the loader checks that the message comes from the player hosting the AI and that every unit belongs to the AI's team, then gives the orders to the engine.

At most 20 orders go in one message (`MAX_ORDERS_PER_MESSAGE` in `ordercodec.lua`). The orders of one call are never split, so a call with more than 20 orders (one order to 21 or more units, or 21 or more queued commands to one unit) is refused whole and lost. For many units, one command to all of them at once (`GiveOrderArrayToUnitArray`) may avoid this in theory (not verified yet).

**Perception** is up to the AI. `game` does not filter: `GetEnemies()` returns every enemy unit. An AI that should see only what its ally team sees keeps track of it from the line of sight and radar events. The framework offers a small module for this, `PerceptionHandler` (see [Units known to an AI](#how-an-ai-runs-in-a-game)); an AI can use it, write its own, or cheat. The example AI uses it: `AttackHandler` attacks only enemies in line of sight.

**Numbers.** Lua numbers in Recoil are 32-bit floats: integers are exact only up to 2^24 (16,777,216). Keep counters and IDs below that, and avoid arithmetic on large integers such as hashes.

## Logging and debugging

**Stable.**

- `self:Warn(...)`: always printed, with team, AI and module name.
- `self:Info(...)`: always printed.
- `self:EchoDebug(...)`: printed only when `self.DebugEnabled` is true. Set it in `Init()` per module or behaviour.

The map can draw shapes for debugging, shown by the `shard_help_draw` widget: `DrawPoint`, `DrawLine`, `DrawCircle`, `DrawRectangle` and the matching `Erase*`, plus `EraseAll(channel)`. Every call takes a `channel` number, so different modules can draw without clearing each other's drawings. `ShardUnit:DrawHighlight(color, label, channel)` highlights a unit.

## Testing

**Stable.**

- **Unit tests** use busted and run without the engine: `lx --lua-version 5.1 test` from the game folder. Framework tests live in `spec/luarules/gadgets/ai/shard_runtime/`. They load runtime files with a fake `VFS` and fake framework objects, so they need nothing from the game.
- **`shard_null`** is a fake API (`game`, `map`, units) for running AI code outside the engine.
- **Integration tests** run a headless game and check that nothing breaks: `spring-headless --isolation --write-dir ~/.spring ~/.spring/games/BAR.sdd/tools/headless_testing/startscript.txt`. Results are in `~/.spring/testlog/results.json`.
- **Formatting**: StyLua 2.5.2 with the repository's `.stylua.toml`. CI checks every line a pull request changes.

## Rules for code that runs every frame

These apply to the framework and are recommended for AIs.

- Do not create tables in code that runs every frame: reuse them. Garbage collection is the engine's, and short-lived tables make it run more often.
- Never call `collectgarbage("collect")`: a full collection can stop the game for tens of milliseconds.
- Spread heavy work across frames: the scheduler gives each AI a time budget.

## How an AI runs in a game

**Stable**, except where marked.

**Registering an AI.** An AI is offered in the lobby when `luaai.lua`, at the root of the game, lists its name, and `luarules/gadgets/ai/<name>/boot.lua` exists. The name in `luaai.lua` must match the folder name.

**Where it runs.** `ShardAILoader.lua` has two halves:

- The **unsynced** half runs the AIs. It runs only on one client per ally team, the **host**, registered by the synced half in the team rules param `aiHostPlayer`. At first the host is the player who added the AI in the lobby. If that player leaves, another active player of the same ally team takes over, then any active player, then a spectator; the lowest player ID wins, so every client agrees. The new host loads the AI and replays the existing units to it; the old host stops it.
- The **synced** half runs on every client. It never runs AI code: it only checks and applies the orders.

**Start-up.** On the host, each AI type is loaded once, then its objects are created and initialised in this order: the `ShardGlobal`, the `ShardAlly` of each ally team, the team AIs. A container without modules of its own scope gets no events and no updates.

**Every frame.** The loader calls `Update()` on every object that has modules to update every frame (global, then ally, then team), runs one scheduled turn, then sends each AI's order queue as one message (see [Orders](#the-api-game-map-units)).

**Orders and their checks.** The synced half accepts an order message only if:

- it comes from the player registered as host of that team;
- its sequence number is higher than the last one, and its emission frame is not in the future, not older than 900 frames (30 seconds), and not older than the previous message's;
- the team sent at most 2 messages for that emission frame, with at most 4,000 orders each;
- the message is not cut short.

Each order is then given only if its unit exists and belongs to the AI's team; other orders of the same message still go through. Rejected orders are counted and reported back to the AI's host; totals are printed at the end of the game.

**Events.** See [Events](#events): only to the modules that want them. Among team AIs, `UnitCreated` goes only to the unit's owner (as in the old Shard). Line of sight and radar events go to the `ShardAlly` of the ally team concerned and to every team AI.

**Units known to an AI.** The loader keeps, for every team AI, the sets `ownUnitIds`, `friendlyUnitIds`, `alliedUnitIds`, `enemyUnitIds`, `neutralUnitIds` (Gaia's units are neutral). `game:GetUnits()`, `GetFriendlies()` and `GetEnemies()` read them, and they see every unit on the map: the framework does not filter them. `shard_runtime/perceptionhandler.lua` is an optional ally-scope module, one per ally team and shared by its AIs: the sets `los` and `radar` (`[unitID] = true`) and the functions `Sees(unitID)` and `OnRadar(unitID)`, filled from the line of sight and radar events and emptied by `UnitDead`. When the AI starts in a running game, or its host changes, the loader replays the sight events for the units already seen. An AI lists it in `modules.lua` after `shard_include("perceptionhandler")`, replaces it with a file of the same name in its own folder, or does without it.

**Errors.** Every call from the loader to an object runs protected. An error while loading an AI or in `Init()` stops that AI (and, for a shared object, the AIs that use it); the game goes on. An error during the game is printed with its traceback the first time it happens and only counted afterwards; the AI keeps running. Errors are told apart by object, event and message, and at the end of the game the log lists each of them with how many times and in which frames it happened.

**End of the game.** `GameEnd()` is called on every object.

**Random numbers.** Each team AI gets `randomseed`, derived from the game ID and the team ID: the same game replays with the same seed.

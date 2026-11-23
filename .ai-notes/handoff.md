# Handoff fra il coordinatore (claude.ai) e l'agente locale

## Protocollo

- Branch condiviso: `shard/fase1` su `pandaro/Beyond-All-Reason`. Il coordinatore scrive qui il compito; l'agente locale lo esegue e scrive qui i risultati.
- Quando l'utente scrive «vai»:
  1. `git pull` su `shard/fase1`;
  2. leggi «Compito attuale» ed eseguilo, rispettando `CLAUDE.local.md` e `.github/agents.md`;
  3. scrivi i risultati sotto «Risultati» (cosa hai fatto, file toccati, numeri, problemi, domande);
  4. commit e push su `shard/fase1`, poi fermati e di' all'utente «fatto».
- «vai» autorizza i commit e il push su `shard/fase1` previsti dal compito. Mai push su `master`, mai PR, mai force push.
- `.ai-notes/` è escluso da git sulla macchina locale: per questi file usa `git add -f` (`.ai-notes/handoff.md`, e altri file di `.ai-notes/` solo se il compito lo dice). Prima di `git add -A` o `git commit -a` segui la skill `submodule-pointer`.
- `.ai-notes/proposta-architettura.md` è l'export aggiornato della proposta: la aggiorna il coordinatore, non modificarla.
- Prima di una PR verso BAR, `.ai-notes/` va tolta dal branch.

## Compito attuale

### T1: recupero del runtime di Shard com'era

1. Aggiorna il tuo `CLAUDE.local.md` (file locale, non committarlo): fase attuale «fase 1, runtime»; aggiungi una riga che rimanda a questo protocollo.
2. Recupera dal commit `3ad8f3fb^`, senza modificarli:
   - `luarules/gadgets/ai/shard_runtime/` (tutto);
   - `luarules/gadgets/ai/STAI/`;
   - `luarules/gadgets/ai/Shard/`;
   - `luaui/Widgets/shard_help_draw.lua`;
   - `common/stai_factory_rect.lua` e `luaui/Tests/ai_stai_factory_rect.lua`.

   NON recuperare `luarules/gadgets/AILoader.lua` e non registrare nulla in `luaai.lua`: finché il runtime non funziona nessuna AI deve comparire nel lobby. La bozza del nuovo loader è in `.ai-notes/drafts/AILoader.lua` e resta lì per ora.
   Commit 1: «Recupero di Shard e STAI com'erano a 3ad8f3fb^».
3. Togli ciò che la proposta scarta: `shard_runtime/spring_cpp/`, `shard_runtime/hooks.lua` (e il suo include in `spring_lua/boot.lua`), `shard_runtime/spring_lua/metal.lua` (e il suo include in `spring_lua/map.lua`, lasciando un commento che i metal spot arriveranno dai game rules param di BAR).
   Commit 2: «Shard: tolti backend nativo, hooks e scansione dei metal spot».
4. Verifica che il gioco si avvii ancora con una partita normale (nessuna AI Shard): basta che non ci siano errori nuovi nell'infolog che citino `shard` o `STAI`.

Nei risultati: elenco dei file recuperati con il numero di righe, file che a `3ad8f3fb^` non esistono, esito del punto 4.

## Risultati

(vuoto)

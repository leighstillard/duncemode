# duncemode trigger categories

Full reference for the trigger categories in `hooks/duncemode-detect.sh`. The regex variables at the top of that script are the source of truth; this document mirrors them in human-readable form so Claude can reason about triggers when running on Claude.ai without the hook, and so you can edit the list without reading bash.

## Cascade rule

Modes are `off` → `on` → `all`. Escalation is automatic and one-way. De-escalation is manual only — the user has to say `duncemode off` or `duncemode on` to step back down.

| From mode | Trigger fires | New mode |
|---|---|---|
| `off` | any frustration / disbelief / think-harder category | `on` |
| `on` | any frustration / disbelief / think-harder category | `all` |
| any | bullshit family, `duncemode all`, escalation markers while already on | `all` |
| any | `duncemode off` (explicit) | `off` |

## Categories

| # | Category | Effect | Examples |
|---|---|---|---|
| 1 | **Explicit toggle** | Sets mode directly | `duncemode on`, `duncemode off`, `duncemode all`, `duncemode status`, `turn on duncemode`, `enable/disable duncemode` |
| 2 | **Bullshit family** | Always jumps to `all` | `bullshit`, `/bullshit`, `call bullshit`, `that's bullshit`, `bullshit that`, `total bullshit`, `complete bullshit`, `bs`, `that's bs` |
| 3 | **Disbelief / verification demand** | `off` → `on`, `on` → `all` | `really?`, `seriously?`, `are you sure`, `are you certain`, `did you actually`, `did you really`, `prove it`, `show me`, `show your work`, `receipts`, `i don't believe you`, `that can't be right`, `that doesn't sound right`, `verify that` |
| 4 | **Accusation of wrongness / fabrication** | `off` → `on`, `on` → `all` | `that's wrong`, `you're wrong`, `that's incorrect`, `no that's not right`, `you lied`, `you made that up`, `you're making this up`, `you're hallucinating`, `hallucination`, `you fabricated`, `confabulating`, `that's lazy`, `lazy answer`, `low effort`, `half-assed`, `you didn't actually` |
| 5 | **Demands to think harder** | `off` → `on`, `on` → `all` | `think harder`, `think deeper`, `dig deeper`, `look deeper`, `trace it`, `end to end`, `rubber duck`, `rubber ducky`, `debug it properly`, `look again`, `try again properly`, `do it right`, `stop being lazy`, `do the work` |
| 6 | **Frustration — profanity / exclamations** | `off` → `on`, `on` → `all` | `wtf`, `what the fuck`, `what the hell`, `wth`, `ffs`, `for fuck's sake`, `jesus christ`, `jfc`, `god damn it`, `goddamn`, `fucking hell`, `bloody hell` |
| 7 | **Frustration — name-calling the agent** | `off` → `on`, `on` → `all` | `stupid`, `dumb`, `idiot`, `moron`, `dense`, `useless`, `broken`, `garbage`, `trash`, `pathetic`, `incompetent`, `lazy`, `you're lazy`, `being lazy`, `so lazy`, `too lazy`, `retarded` |
| 8 | **Escalation markers (user repeating themselves)** | Forces `all` if already `on`, else lifts to `on` | `still wrong`, `still broken`, `still not working`, `still doesn't work`, `i told you`, `i already said`, `i just said`, `same thing`, `you're not listening`, `read what i said` |
| 9 | **False-positive risk (defer to context)** | Hook fires but skill uses judgement | bare `really` (no `?`), bare `seriously`, bare `come on` |
| 10 | **Frustration — Australian vernacular** | `off` → `on`, `on` → `all` | `bloody oath`, `you bloody`, `bloody useless`, `not bloody likely`, `rooted`, `cooked`, `stuffed`, `buggered`, `wanker`, `drongo`, `dropkick`, `galah`, `muppet`, `pillock`, `crack the shits`, `spat the dummy`, `chucked a wobbly`, `fair dinkum`, `you're having a laugh`, `you're joking`, `pull the other one`, `fair crack of the whip`, `give it a red-hot go` |

## Notes

**Tier 10 false-positive risks.** `rooted`, `cooked`, `stuffed`, and `buggered` all have legitimate non-frustrated meanings in Australian English (cooked dinner, stuffed toy, rooted Android phone, buggered off to the shops). In the context of a message to Claude about work they're almost always frustration, same way `broken` and `garbage` in tier 7 will occasionally false-positive on legitimate technical descriptions. Tune to taste by editing the `AUSSIE_RE` variable in the hook.

**Mate warning shot not included.** `mate` at the start of a message is often the last syllable before someone loses patience entirely, but it's far too false-positive-prone to hook on — in Australian English `mate` is also a completely neutral greeting. Left to Claude's judgement via context.

**Source of truth.** The regex variables at the top of `hooks/duncemode-detect.sh`. If you add a trigger category, also update this file so the two stay in sync.
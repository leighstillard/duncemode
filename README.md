# duncemode hook setup

Welcome to the verification layer. You are here because you have noticed that Claude sometimes confidently reports doing work it did not do, and you have decided that politely asking it to double-check is no longer cutting it, and are tired of walking it through reasoning loops your 5 year old would understand. 

This is a Claude Code skill that forces Claude to verify its own work before handing it back, and to re-examine its mental model of the system when its work keeps failing. Triggers on explicit toggle, on the `bullshit` family of rejection phrases, and on many expressions of user frustration. The more frustration you express to the agent, more protocols that the agent is forced to go through before it can give you a response. 
 
duncemode exists because inference quality is uneven, confident summaries are cheap, and politely asking Claude to double-check has a failure rate that grows with session length. The skill gives Claude two explicit protocols to run; the companion hook watches user messages for frustration and escalates automatically without relying on Claude to notice. Together they form what a marketing team would call "a verification stack" if duncemode had a marketing team, which it does not.

## What it does

Every time you send a message in Claude Code, the hook:

1. Reads your message and scans it for signs that you are unhappy.
2. Decides whether duncemode should activate, escalate, or leave well enough alone.
3. Writes a state file so Claude cannot quietly forget what mode it is in between turns.
4. Injects a line into Claude's context telling it what mode to run in.

That is the entire feature set. No telemetry, no background daemon, no cloud service, no second AI. Just bash and regexes. Your data stays on your machine because the hook never leaves your machine. You can audit the whole thing in about ninety seconds, and you probably should.

### Protocol A — Verification triage loop
 
*Did you do what you said?*
 
Seven numbered steps. Runs before every response that claims work was completed whenever duncemode is `on` or `all`. Catches narrated tool use, fabricated citations, silent patch failures, fabricated MCP results, and scope drift.
 
1. **Tool and capability manifest.** Enumerate what was actually loaded this session. Catches the "skill file describing a capability vs. connected tool that implements it" trap.
2. **Enumerate the claims.** Tag every factual assertion or completed-work claim as `[verified]`, `[inferred]`, `[from-memory]`, or `[narrated]`. Any `[narrated]` claim is grounds to stop and report immediately.
3. **Ground truth check on mutations.** `git diff`, `cat`, or re-read every claimed change. A successful exit code is not proof the change landed the way Claude described it.
4. **Source check on facts and citations.** Re-fetch every citation that can be re-fetched; downgrade the rest to `[unverified]`. Unverified specifics (numbers, dates, API signatures) are worse than unverified generalities because the user is more likely to act on them.
5. **Scope and assumption audit.** Did Claude do what was asked, and only what was asked? Unasked-for additions are a failure mode even when the addition is good.
6. **Fresh-context verifier.** Spawn a subagent with a clean context and have it independently verify the claims against the filesystem, git, and available tools. The one check that cannot be bluffed from inside the contaminated context that produced the original work.
7. **Report honestly.** Lead with the bad news. If there is no bad news, say so in one line and stop.
 
In `on` mode, Protocol A may early-exit under strict conditions. In `all` mode, every step runs regardless of what earlier steps found.
 
### Protocol B — Deep debug
 
*Did you understand the system?*
 
Twelve numbered steps across two phases. Runs in `all` mode always. Runs in `on` mode when Protocol A finds no smoking gun but the user is still unhappy, or when a "think harder" trigger fires. Catches lifecycle bugs, wrong mental models, and failed fixes that keep getting re-proposed with different wording.
 
**Phase B.1 — Rubber duck restatement (5 steps).** Breaks Claude out of a wrong mental model before trying to trace anything. Skipping this when stuck is how you end up with another structurally identical wrong fix.
 
1. **Restate the problem fresh.** In Claude's own words, as if the user has never mentioned it. No reference to previous attempts.
2. **Tag working knowledge.** Every piece of information in Claude's working model is `[observed]` (ran a tool and saw it this session), `[told]` (the user stated it), or `[assumed]` (inferred from the above or from training memory). Be ruthless — most things that feel observed are actually assumed.
3. **Verify every `[assumed]` item that can be verified cheaply.** Downgrade the rest to `[unverified]` and note that reasoning cannot depend on them.
4. **Diagnose previous attempts.** For each failed fix, which `[assumed]` items did it depend on? Which of those turned out to be wrong in step 3? The intersection is where the real bug lives.
5. **Hand off to Phase B.2.** Run the trace on the *new* problem statement, not the old one.
 
**Phase B.2 — End-to-end trace (7 steps).** Traces the actual lifecycle of the system instead of guessing at it.
 
1. **Define the boundary.** Name the system and the specific behaviour under examination in one sentence. "The connection logic" is not specific enough.
2. **Enumerate the stages.** Every state the system passes through. Write them down. Do not skip stages because you assume they are correct.
3. **Read the real code for each stage.** Not memory of the code — the actual file, actual config, actual logs. `grep`, `rg`, `cat`, open the file, quote the lines that matter.
4. **Ask three questions per transition.** What triggers this transition? What happens if the trigger fires under unexpected conditions (partial state, concurrent invocation, error path, shutdown in progress, trigger fires twice, trigger never fires)? What state is carried forward, and what state is dropped? Most lifecycle bugs hide in the answers to questions 2 and 3.
5. **Check against failure classes.** Dropped signals, missing restart trigger, leaked resources, order assumptions, missing cleanup, reentrance, stale state, silent swallowing.
6. **State the model of the system back.** In prose, with the bug's location and failure class named. If Claude can't write the model without hand-waving, the trace wasn't deep enough — go back to step 3.
7. **Only now propose the fix.** The fix must reference the specific transition from step 4 and the specific failure class from step 5. A fix proposed without a model is another bullshit call waiting to happen.
 
### The cascade
 
In `all` mode — triggered by `duncemode all`, the `bullshit` family, or frustration escalating while already in `on` — Protocol A runs in full, then B.1 in full, then B.2 in full, in that order. No early exit, no cherry-picking, no "I already found the bug in A.3 so B is redundant". The cascade exists because the failures this skill catches are exactly the ones where Claude stopped early, declared victory, and was wrong.

## Install the easy way

Run the installer from the skill directory:

```bash
./install.sh
```

It will check for `jq`, wire the hook into `~/.claude/settings.json` (backing up the existing file first, because we are not savages), create the state directory, run a smoke test, and tell you it worked. If it does not tell you it worked, it will tell you exactly what is wrong. Read that message before filing a bug. It is not being snippy. It is telling you the actual problem.

The installer only works for linux and mac systems. If you want to use the installer on windows, why the fuck are you using Claude Code on windows? Just use a VM or sandboxed container for isolation, or WSL if you need your own dunce mode. 

## Install the hard way

If you like doing things yourself, or if `install.sh` has offended you somehow:

1. **Install `jq`.** duncemode needs `jq` because parsing JSON in bash with `sed` and `grep` is how people end up in therapy.

   ```
   macOS:         brew install jq
   Ubuntu/Debian: sudo apt install jq
   Arch:          sudo pacman -S jq
   Fedora:        sudo dnf install jq
   ```

   If you are on an operating system not on this list, you are sophisticated enough to install `jq` without a README holding your hand. Or you're on windows, in which case see the easy way section. 

2. **Mark the hook executable:**

   ```bash
   chmod +x ~/.claude/skills/duncemode/hooks/duncemode-detect.sh
   ```

3. **Wire the hook into `~/.claude/settings.json`.** Create the file if it does not exist. If it does exist, merge carefully — do not clobber existing hooks. Count the curly brackets carefully, they are sharp. 

   ```json
   {
     "hooks": {
       "UserPromptSubmit": [
         {
           "command": "bash",
           "args": ["~/.claude/skills/duncemode/hooks/duncemode-detect.sh"]
         }
       ]
     }
   }
   ```

4. **Create the state directory:**

   ```bash
   mkdir -p ~/.claude/state
   ```

5. **Go back and run `install.sh` anyway**, because you will have forgotten at least one of these steps.

## Verify it actually works

Start a new Claude Code session and say:

```
duncemode status
```

Claude should report the current mode in one line. If instead it produces a reflective essay on what "duncemode" probably means given the component words "dunce" and "mode", the hook is not wired up and you are getting a real time demonstration of why this mode is needed. Re-read the install steps, more slowly this time.

You can also poke the hook directly without involving Claude:

```bash
echo '{"user_message":"bullshit, that did not work"}' \
  | bash ~/.claude/skills/duncemode/hooks/duncemode-detect.sh
```

Expected output:

```
[SYSTEM: duncemode hook] mode=all (was off) — bullshit family trigger. Follow the duncemode skill routing for mode 'all'.
```

If you get that, the hook works. If you get a stack trace or eerie silence, something is wrong and the error message above the silence will tell you what.

## Current trigger summary

See [TRIGGERS.md](TRIGGERS.md)

## Tuning the triggers

All trigger patterns live at the top of `duncemode-detect.sh` as `*_RE` variables. Edit them in place. Hooks are re-read on every invocation — no daemon, no rebuild, no cache, nothing to restart. This is structurally the simplest kind of software that exists. Admire it. Appreciate it. Bask in my magnificence. 

A few notes on tuning:

- **False positives on `really?` and `seriously?`** are a known quirk. People ask genuine questions with those words all the time. If it bothers you, remove them from `DISBELIEF_RE`. The skill body tells Claude to use its own judgement on these anyway.
- **`broken`, `useless`, `garbage`, `trash`** occasionally trigger on legitimate technical descriptions ("this dependency is garbage"). Left in because catching frustration is the point. Tune to taste.
- **Adding a new trigger category?** Also add the human-readable version to the `Trigger list` section of `SKILL.md`. Yes, this means maintaining the list in two places. No, there is no elegant solution. The skill has to work on Claude.ai too, where hooks do not exist, and the human-readable list is how Claude reasons about triggers there.

If you find yourself adding triggers every other day, consider that the problem might not be the trigger list. duncemode cannot help with that.

## Uninstall

Delete the `UserPromptSubmit` entry from `~/.claude/settings.json` — or just the specific entry pointing at `duncemode-detect.sh`, if you have other hooks wired up. The installer leaves a timestamped backup each time it runs, so worst case you can restore from one of those.

The state file at `~/.claude/state/duncemode.json` is harmless to leave in place. Delete it with `rm` for a clean slate, or let it sit there as a quiet memorial.

```bash
rm -rf ~/.claude/skills/duncemode     # nuke the skill entirely
rm ~/.claude/state/duncemode.json     # and the state
```

We will not be offended. We do not have feelings. We are a skill.

## FAQ that nobody has actually asked

**"Why bash?"** Because bash is everywhere, hooks are a bad place to hold opinions about programming languages, and the logic is 136 lines. If you want a Go port, it is about 100 lines of Go with the standard library. Have at it.

**"Does it phone home?"** No. Read the source. Most of it is regexes.

**"Will this make Claude perfect?"** No. It will make Claude more honest when it fails, which is the more tractable problem. Perfection is not on the menu.

**"Can I run this on Claude.ai?"** No. Claude.ai has no hooks. The skill itself will still work there as a convention-based discipline — the hook is the mechanical layer that makes it bulletproof in Claude Code specifically.

**"Is this passive-aggressive?"** It is the entire tonal register. You are welcome.

## Contributing protocols
 
**Pull requests are welcome for additional protocols.** The two shipped here — verification and deep debug — cover the failure modes that come up most often in my own work, but they are not the only failure modes Claude produces and they are definitely not the only ways to catch them.
 
Candidates I'd like to see protocols for:
 
- **Performance regression tracing.** Claude often claims a change is equivalent when it's actually slower or has worse memory characteristics. A protocol that forces a before/after measurement before declaring a refactor complete.
- **Security review.** A protocol that forces Claude to enumerate the attack surface of a change before declaring it safe — input trust boundaries, privilege changes, new dependencies, new network endpoints.
- **Dependency impact analysis.** A protocol that forces Claude to trace what else depends on a symbol before refactoring or removing it.
- **Test coverage honesty.** A protocol that forces Claude to distinguish "I wrote tests" from "the tests actually exercise the code path that was changed".
- **Migration safety.** For database schema or config changes — forces rollback-path verification and dry-run output inspection before the real run.
- **Concurrency model check.** For goroutine/channel/mutex changes — forces Claude to name the happens-before guarantees it's relying on, not just that "this looks right".
 
If you have a better idea, even better. The template is simple: name the failure class, write a numbered protocol with explicit steps, decide where it fits in the cascade, update `SKILL.md`, and update `TRIGGERS.md` and the hook regex if your protocol has its own trigger phrases. Open a PR and we'll talk.

## License

Apache-2.0. MIT would have been fine but Claude talked me into the patent grant by invoking the ghost of Oracle v. Google, and I just wanted to ship this damn thing. If you use this commercially and it saves you real money, I won't send you an invoice, but I will accept a beer if you bump into me at a conference. 

Copyright Leigh Stillard, 2026. He made me say that too. 
# P pitfalls: symptom → cause → fix

Condensed from PeasyAI's `p_common_compilation_errors.txt`, `p_compiler_guide.txt` and the six
`instructions/sanity_checks/*` prompts. For a compiler message you cannot place here, see
`p-debug/references/compile-errors.md`.

## Two corrections to PeasyAI's own guides

Both of these are wrong in the source material and worth knowing before you trust it:

1. **P has no `import` statement.** `p_compiler_guide.txt` section 4 shows
   `module ClientModule { import Enums_Types_Events; machine Client { ... } }` as the fix for
   "could not find variable, enum element, or event". That is not P. `import` is not a reserved keyword,
   no `.p` file in the tutorials or in this repo contains one, and a module is a *set of machines*
   (`module Bank = { BankServer, Database };`) — not a namespace with its own declarations.

   All top-level declarations are visible across every file listed in the `.pproj`. If a type or event is
   "not found", the real cause is that it was never declared, is spelled differently, or lives in a folder
   the `.pproj` does not list.

2. **`values()` exists.** `p_nuances.txt` claims it does not. `values` is a reserved keyword with its own
   section in the type guide: `values(mp)` returns `seq[V]`.

## Declarations and variables

| Symptom | Cause | Fix |
|---|---|---|
| `parse error: extraneous input 'var' expecting {...}` | `var` after a statement, or inside a `while`/`foreach` body | Move every `var` to the top of its block |
| Same, on a declaration line | `var x: int = 0;` | `var x: int;` then `x = 0;` |
| `could not find foreach iterator variable` | iteration variable not declared | `var x: int;` at the top of the function, before the `foreach` |
| `'name' duplicates declaration 'name' at file:line` | a type, event, enum, machine or spec declared in two files | Delete one. Each must be declared exactly once project-wide |
| `could not find variable, enum element, or event 'name'` | never declared, misspelled, or in a folder the `.pproj` omits | Declare it in `Enums_Types_Events.p`, or add the folder to `<InputFiles>` |

## Named tuples

| Symptom | Cause | Fix |
|---|---|---|
| `no viable alternative at input 'field=value)'` | single-field named tuple missing its trailing comma | `(field = value,)` |
| `no viable alternative` at a `send`/`new` site | field names omitted where the type is a named tuple | `(a = x, b = y)`, matching the type's field names exactly |
| Type mismatch on a payload | payload shape differs from the event's declared type | Compare against `Enums_Types_Events.p`; the declaration is the contract |
| Type mismatch on a single-field payload | payload wrapped in a second tuple | Pass `(f = v,)`, not `((f = v,),)` |

## Collections

| Symptom | Cause | Fix |
|---|---|---|
| `expected int/float but got seq/set/map` | wrong insertion syntax | `s += (sizeof(s), v);` for seq, `st += (v);` for set, `mp += (k, v);` or `mp[k] = v;` for map |
| Parse error near `append` | no such function | `s += (sizeof(s), v);` |
| Parse error on `s1 + s2` | sequences do not concatenate | Append in a loop |
| Parse error on `st += x` | set insert needs parens | `st += (x);` |
| Removing the wrong element from a seq | `s -= (i)` removes **by index** | Find the index first, or use a `set` if identity is what matters |
| `i += 1` rejected | compound assignment is for collections only | `i = i + 1;` |

## Events and types

| Symptom | Cause | Fix |
|---|---|---|
| Parse error in an `event` declaration | inline tuple payload | `type tMsg = (x: int); event eMsg: tMsg;` |
| `extraneous input 'receive' expecting ...` | `receive()` used as a function | Read payloads via handler parameters; the `receive { case ... }` statement is a different construct |
| Type used but undeclared | type defined after use, or not at all | All top-level declarations are visible project-wide, so this means it is genuinely missing |

## Machines and states

| Symptom | Cause | Fix |
|---|---|---|
| `Method is used as a transition function, but might change state here` | an `on ... goto ... with F` whose `F` assigns state or conditionally gotos | Use `on ... do F;` and `goto` inside `F`, or move the assignment into the target state's `entry` |
| `could not find state` | `goto` names a state that does not exist | Fix the name or define the state |
| Machine has no start state | missing `start` | Exactly one state must be `start` |
| Unhandled event at runtime (checker) | a state with no handler, `defer` or `ignore` for an event that reached it | Add one of the three. See `machines.md` |
| `};` rejected after a state or machine | semicolon belongs only to declarations | Drop it. Keep it after `module`, `test`, `enum`, `type` |

The transition-function rule, concretely:

```p
// WRONG — changes state inside a transition function
on eResponse goto Working with (response) {
  if (response.status == SUCCESS) { someVar = true; }
  else { goto Ready; }
}

// RIGHT — the handler decides, the target state initializes
on eResponse do (response) {
  if (response.status == SUCCESS) { goto Working; } else { goto Ready; }
}

state Working {
  entry { someVar = true; }
}
```

Keep transition functions pure: they decide the next state and nothing else.

## Spec monitors

| Symptom | Cause | Fix |
|---|---|---|
| Parse/semantic error in a spec | `this`, `new`, `send`, `announce`, `receive`, `$`, `$$` or `pop` in a monitor | Remove it. For per-machine state use `map[machine, T]` keyed from a payload |
| Parse error on a spec `entry` | spec entry functions take no parameters | Move the payload to an `on eX do (p: tX)` handler |
| Spec handles an event it does not observe | missing from the `observes` list | Add it — this is a compile error, not a silent no-op |
| Monitor passes but checks nothing | no `assert` and no `hot` state | Give it a real assertion. See `specs-monitors.md` |

## Tests and modules

| Symptom | Cause | Fix |
|---|---|---|
| `duplicates declaration` between driver and script | the same event declared in both PTst files | Declare it once |
| A `new` of a machine outside the module | the test module is not closed | Add the machine to the union, including the driver itself |
| A test passes but proves nothing | the monitor was never listed in `assert ... in` | Add it to that test |

## Statements

| Symptom | Cause | Fix |
|---|---|---|
| Parse error on `switch` | not a P construct | `if (x == 1) { } else if (x == 2) { }` |
| Parse error on `x !in s` or `not in` | neither exists | `!(x in s)` |
| Parse error on `!x in s` | precedence | `!(x in s)` |
| `self` / `this.field` rejected | `this` is a machine reference only | Use the field name directly; `this` is for passing self to others |
| `otherMachine.doThing()` rejected | functions are private to a machine | `send otherMachine, eRequest, payload;` |
| `print "a" + x` rejected | no string concatenation | `print format("a {0}", x);` |
| `to string` rejected | not a P construct | `format("{0}", x)` |

## Before compiling

```bash
python3 -I .claude/skills/p-language/scripts/validate_p.py FILE.p --project PROJECT_DIR
```

It catches most of the table above statically, with line numbers.

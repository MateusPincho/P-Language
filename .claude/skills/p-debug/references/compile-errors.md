# P compiler error lookup

The 69 unique entries from PeasyAI's `resources/compile_analysis/*.json`, de-duplicated and merged with
`p_compiler_guide.txt`. Keyed on the fragment of the message you actually see, so grep this file for a
distinctive substring of the error.

Messages come from ANTLR, so a long `expecting {...}` list usually follows. Match on the leading part.

## Misplaced declarations

The single largest class. P is strict about *where* things go.

| Message fragment | Fix |
|---|---|
| `extraneous input 'var' expecting {'announce', 'assert', 'break', ...}` | A `var` after a statement. Move it to the top of the function or machine body |
| `mismatched input 'var' expecting {'defer', 'entry', 'exit', 'ignore', 'on', '}'}` | A `var` directly inside a state body. It belongs at the top of the machine, or inside a function |
| `extraneous input 'var' expecting {<EOF>, 'enum', 'event', ...}` | A `var` at file scope. Variables live in a machine or a function, never at top level |
| `mismatched input '=' expecting ';'` | `var x: int = 0;`. Split the declaration from the assignment |
| `extraneous input 'type'` / `extraneous input 'enum'` / `mismatched input 'type'` inside a machine | Type and enum declarations go at file top level, normally in `Enums_Types_Events.p` |
| `extraneous input 'event' expecting {'cold', 'fun', 'hot', ...}` | An `event` declared inside a machine. Move it to file scope |
| `extraneous input 'on' expecting {'cold', 'fun', 'hot', 'start', 'state', 'var', '}'}` | An event handler outside a state. Every `on` belongs in a state body |
| `extraneous input 'on' expecting {'announce', 'assert', ...}` | An `on` handler inside a function. Same fix |
| `extraneous input 'defer' expecting {'announce', 'assert', ...}` | `defer` inside a function. It is an event handler and belongs in a state body |
| `extraneous input 'ignore' expecting {'announce', 'assert', ...}` | Same, for `ignore` |
| `extraneous input 'goto' expecting {'defer', 'entry', 'exit', 'ignore', 'on', '}'}` | A `goto` directly in a state body. It must be inside a function body |
| `extraneous input 'case' expecting {'announce', 'assert', ...}` | `case` only appears inside a `receive { }` statement |

## Names and lookups

| Message fragment | Fix |
|---|---|
| `could not find variable, enum element, or event` | Not declared, or misspelled. Declare it — all top-level declarations are project-wide visible, so there is no import to add |
| `could not find event` | Declare it in `Enums_Types_Events.p` |
| `could not find enum, typedef, event set, machine, or interface` | Declare it |
| `could not find variable` | Declare at the top of the function body or machine body: `var x: tFoo;` |
| `could not find function` | The function does not exist. Define it or drop the call |
| `could not find state` | `goto` must be followed by a real state name |
| `could not find foreach iterator variable` | Declare the iteration variable at the top of the function |
| `could not find interface` | Create a machine with the missing interface's name |
| `could not find module` | Add a `module <name> = { <Machine> };` declaration |
| `duplicates declaration` | The same name declared twice. Remove all but one, or rename. Enum values are global constants and must be unique program-wide |
| `duplicates handler` | One state handling the same event twice. `defer` and `ignore` count as handlers |
| `expecting Iden` | A reserved keyword used as an identifier. Rename |
| `mismatched input 'entry' expecting Iden` | `entry` is reserved; do not use it as a name |
| `mismatched input 'state' expecting {'any', 'bool', 'event', ...}` | `state` is reserved; there is no variable of type `state` |
| `mismatched input 'set' expecting Iden` | Invalid line, usually `set` used as a name |

## Functions and parameters

| Message fragment | Fix |
|---|---|
| `functions at entry or exit and do or goto transitions cannot take more than 1 parameter` | Package the values into one named tuple, or a declared type |
| `mismatched input ',' expecting ')'` | The call site expects a single parameter |
| `goto, function or constructor call expected` | Argument count mismatch at a `goto`, call, or `new` |
| `mismatched input '(' expecting ';'` | Often an attempt to call a function on another machine. Machines interact only by events |
| `expected: namedtuple` | Attempting to read another machine's variables. Not possible — send an event |
| `mismatched input 'with' expecting {';', ','}` | Malformed `goto` with payload. The form is `goto S, payload;` |
| `is used as a transition function, but might change state here.` | The function behind `on ... goto ... with F` changes state. See below |

```p
// WRONG
on eResponse goto Working with (response) {
  if (response.status == SUCCESS) { someVar = true; } else { goto Ready; }
}

// RIGHT — handler decides, target state initializes
on eResponse do (response) {
  if (response.status == SUCCESS) { goto Working; } else { goto Ready; }
}
state Working { entry { someVar = true; } }
```

## Types and collections

| Message fragment | Fix |
|---|---|
| `got type:` | Type mismatch. Compare against the declaration in `Enums_Types_Events.p` |
| `field` (type is missing a field) | The named tuple is missing a field the type declares. Add it |
| `no viable alternative at input 'field=value)'` | Single-field named tuple missing its trailing comma: `(field = value,)` |
| `+=` misuse | `+=` only inserts into a collection. For numbers use `i = i + 1` |
| `no viable alternative at input '({'` | Cannot build a map/seq/set inline from `({...})`. Declare a variable, then insert element by element |
| `extraneous input '{' expecting {'float', 'default', 'format', ...}` | Cannot call a function on a value with braces. Declare a collection variable first |
| `extraneous input '['` | A stray `[`. Remove it |
| `expected either both float or both int;` | `<`, `>`, `==`, `!=` need both sides the same numeric type |
| `expected an interface or int or float type` | Bad `to` coercion. `to` supports only float→int and enum→int |
| `incomparable` | Same. Drop the `to` |
| `no viable alternative at input '.keys'` | Use `keys(expr)`, not `expr.keys()` |
| `no viable alternative at input '.values'` | Use `values(expr)`, not `expr.values()` |
| `mismatched input ',' expecting 'in'` | `foreach` takes one variable. For a map, iterate `keys(m)` or `values(m)` |
| `String expr format placeholders must contain only digits. Escape braces by doubling them.` | `format` placeholders are `{0}`, `{1}`, … — one digit per argument. Double a literal brace |
| `10000` | A `choose` expression allows at most 10,000 choices |

## Unsupported constructs

| Message fragment | Fix |
|---|---|
| `missing ')' at 'is'` | `is` does not exist. Use `==` / `!=` |
| `could not find function 'distinct'` | No `distinct`. Use a `set` |
| `no viable alternative at input '(all(` | No `all`. Write the loop |

## Specs and monitors

| Message fragment | Fix |
|---|---|
| `mismatched input '{' expecting 'observes'` | Syntax is `spec Name observes eA, eB { ... }` |
| `$, $$, this, new, send, announce, receive, and pop are not allowed in monitors` | Remove them. Keep `assert`. Do not put event handlers in functions |

## Modules and tests

| Message fragment | Fix |
|---|---|
| `Module not closed. test module is not closed with respect to created interfaces;` | A machine gets created that is not in the test module. Add it to the union |
| `does not exist in the test module` | The `main=` machine must be in the module expression. Add it via `union` |
| `no viable alternative at input '(union'` | Modules cannot be declared or used in `TestDriver.p` |
| `invalid composition operation. bound interfaces after composition are not disjoint` | Unioning a module with one it already contains. Remove the redundant member |

## Catch-alls

| Message fragment | Fix |
|---|---|
| `no viable alternative at input` | Generic parse failure. Check the exact line against `p-language/references/syntax-core.md` |
| `expecting {';', ','}` | Malformed statement. Usually a missing semicolon or a stray token |
| `mismatched input '.+' expecting ...` | Malformed declaration, usually a `var` in the wrong place |

## Before reaching for this table

```bash
python3 -I .claude/skills/p-language/scripts/validate_p.py FILE.p --project PROJECT_DIR
```

It reports the misplaced-`var`, inline-init, trailing-comma, `append()`, undeclared-event and
forbidden-keyword-in-spec classes directly, with line numbers, and without a compile round trip.

# P code review checklist

The rules the static checker enforces, written out so they can be applied by eye during review, and so a
reported finding can be understood rather than just obeyed.

Run the tool when you can:

```bash
python3 -I .claude/skills/p-language/scripts/validate_p.py FILE.p --project PROJECT_DIR
```

Each heading below names the validator or fixer that covers it, so a finding maps back to a rule.

## Syntax

- [ ] Braces balanced; parentheses balanced. *(SyntaxValidator)*
- [ ] No assignment inside a condition — `if (x = 1)` should be `if (x == 1)`. *(SyntaxValidator)*
- [ ] No `;` after a code block's `}`. Keep it after `module`, `test`, `enum`, `type`. *(SyntaxValidator)*
- [ ] No trailing comma in a parameter list: `fun F(x: T,)`. *(fixer: trailing-comma-in-params)*
- [ ] `return expr;` has its semicolon. *(fixer: missing-semicolons)*
- [ ] `entry Fn;`, not `entry Fn();`. *(fixer: entry-function-syntax)*
- [ ] `raise halt;`, not a bare `halt;`. *(fixer: bare-halt)*

## Variables

- [ ] No inline initialization: `var x: int = 0;` must be two statements. *(InlineInitValidator)*
- [ ] Every `var` is at the top of its block — `fun` body, `entry`/`exit`, or `on ... do { }`.
      *(VarDeclarationOrderValidator)*
- [ ] No `var` inside a `while` or `foreach` body. *(VarDeclarationOrderValidator)*
- [ ] A `foreach` iteration variable is declared at the top of the enclosing function.

## Collections

- [ ] No `append(` — there is no such function. *(CollectionOpsValidator)*
- [ ] No `receive(` as a function call. The `receive { case ... }` statement is different.
      *(CollectionOpsValidator)*
- [ ] No `s = s + (x,)` — sequences do not concatenate. *(CollectionOpsValidator)*
- [ ] Sequence insert passes an index: `s += (sizeof(s), v);`.
- [ ] Set insert parenthesizes the value: `st += (v);`.
- [ ] `i = i + 1` for numbers; `+=` is for collections only.

## Declarations

- [ ] Every type used in a `var`, `map[...]`, `seq[...]` or `set[...]` is declared somewhere in the
      project. *(TypeDeclarationValidator)*
- [ ] Every event used in `send`, `raise`, `announce`, `on`, `ignore` or `defer` has an `event`
      declaration. *(EventDeclarationValidator)*
- [ ] No name declared twice across files — types, events, enums, machines, specs. Enum values are global
      and must be unique project-wide. *(DuplicateDeclarationValidator)*
- [ ] Event payloads are named user-defined types, not inline tuples.

## Machine structure

- [ ] Exactly one `start state`. *(MachineStructureValidator)*
- [ ] No state with an empty body. *(MachineStructureValidator, INFO)*
- [ ] Every `goto` names a state that exists. *(MachineStructureValidator)*
- [ ] **Every state handles, defers or ignores every event that can reach it.** No validator checks this —
      it is the most common checker bug and only `p check` finds it.
- [ ] One configuration pattern per machine: constructor payload *or* init event, not both.
- [ ] A Pattern B machine defers real work until its config event arrives.

## Named tuples

- [ ] Single-field tuple *values* carry a trailing comma: `(f = v,)`. Type annotations do not.
      *(fixer: single-field-tuples)*
- [ ] At `new M(args)` and `send t, eX, args`, the argument matches the declared type — named tuple where
      one is expected, with the right field names. *(NamedTupleConstructionValidator)*
- [ ] Field accesses on a parameter use field names the parameter's type actually declares.
      *(PayloadFieldValidator)*

Both of those last two are **warnings, not errors**, because they guess. The validator has no type
information for a plain variable, so passing a correctly typed variable looks the same to it as passing a
wrong literal. Read the finding; do not apply it blind.

## Spec monitors

- [ ] No `this`, `new`, `send`, `announce`, `receive`, `$`, `$$` or `pop` in a spec body.
      *(SpecForbiddenKeywordValidator)*
- [ ] Every event handled in the body appears in `observes`. *(SpecObservesConsistencyValidator)*
- [ ] Every event in `observes` is declared. *(SpecObservesConsistencyValidator)*
- [ ] `entry` functions in a spec take no parameters.
- [ ] At least one `assert`, or a `hot` state. A monitor with neither checks nothing.
- [ ] One property per `spec`.
- [ ] No empty or placeholder functions.
- [ ] `observes` is complete **for the property** — reasoned from what the property needs to know, not
      from what is nearby. No validator can check this.
- [ ] Handlers use payloads to track the specific machine or request, not just to count.

## Test files

- [ ] The file has `test ... ;` declarations, or its declarations live in a sibling PTst file.
      *(TestFileValidator)* A deliberate `TestDriver.p` + `TestScript.p` split makes this warning expected
      noise.
- [ ] Each test asserts the specs it should. *(TestFileValidator)* A monitor absent from `assert ... in`
      does not run in that test.
- [ ] The test module is closed: every machine created is in the union, including the driver itself.
- [ ] No event declared in both the driver and the script file.
- [ ] A test whose failure is intended says so in a comment.

## Wiring

No validator covers these; they come from PeasyAI's LLM review stage. See
`p-project/references/wiring-review.md`.

- [ ] Dependency order: nothing is `new`ed before the machines it references exist.
- [ ] Circular dependencies broken with an init event, on the side with the simpler config.
- [ ] No empty collection (`default(set[machine])`) passed where a populated one is needed.
- [ ] A `Timer` is created with the machine that will handle `eTimeOut`, not with the test driver.

## Deliberate suppressions

Four PeasyAI checks report findings on valid P. They were tuned against fresh LLM output, where a wrong
guess costs a regeneration; on hand-written code they misfire. Each is narrowed rather than disabled, in
`scripts/plint/suppress.py`, and each was confirmed against a file `p compile` accepts:

1. **`};` after a declaration.** Required after `module`, `test`, `enum` and `type`; only flagged now when
   the brace closes a *code block*. (Upstream `ClientServerModules.p` is three valid lines PeasyAI calls
   three errors.)
2. **A variable passed where a named tuple is expected.** `send t, eResp, response;` is normal when
   `response` already holds the right tuple. The validator has no type for a plain variable, so the
   finding is dropped for an identifier, field access, index or call — and kept for a literal.
3. **`assert A, B in { ... }`.** PeasyAI's regex requires the spec name to sit immediately between
   `assert` and `in`, so a multi-spec list matched for neither name and every monitor was reported as
   un-asserted. Re-derived by parsing the clause.
4. **A parameter name reused across sibling handlers.** `PayloadFieldValidator` maps parameter *name* to
   type rather than scope, so `on eA do (o: tA)` next to `on eB do (o: tB)` makes every `o.field` suspect.
   Findings are dropped when a name is bound to more than one type in the file; a single binding is still
   checked.

Two consequences worth knowing:

- `PayloadFieldValidator` only knows types from the **context** files, not from the file under test. A
  project whose types live in `Enums_Types_Events.p` is covered; a single-file model is not.
- Cross-file checks need `--project`. Without it, every event looks undeclared.

Comments and string literals are masked before any matching, so a doc comment mentioning `spec` or a
`format("{0}; ...")` string no longer produces phantom findings. Both were a real problem: PeasyAI's
validators match raw source, and the upstream ClientServer header comment alone yields a spec named
`machine` with whole English sentences as event names.

## What the tool does not catch

Worth stating plainly, since a clean run is easy to over-read:

- Event-handling completeness per state — only `p check`.
- Whether an assertion expresses the intended property.
- Whether `observes` is complete for the property.
- Whether the model matches the design document.
- Anything about the protocol being correct.

A clean static run means the file will probably compile. It says nothing about whether the model is right.

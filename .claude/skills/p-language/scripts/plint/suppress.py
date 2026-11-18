"""False-positive suppression for PeasyAI's validators. Added for the skill.

PeasyAI's validators were tuned against freshly generated LLM output, where a
wrong guess costs a regeneration. Run against hand-written, known-compiling P
they produce ERROR-severity findings on valid code. Each suppression here was
confirmed against a file that `p compile` accepts, and is narrowed to the
pattern that actually misfires rather than disabling the check.

Verified against ``p-source/P/Tutorial/1_ClientServer`` and
``Projects/ProjectRobot2026``.
"""

from __future__ import annotations

import re
from typing import List

from .pcomments import mask_source
from .validators import IssueSeverity, ValidationIssue

# ── 1. `};` is not always extraneous ─────────────────────────────────
#
# SyntaxValidator flags every `}` followed by `;`, because an LLM writing a
# machine or state body often appends one. But `};` is required when the brace
# closes a *declaration* rather than a code block:
#
#     module Client = { Client };                    <- valid, required
#     test tc [main=M]: assert S in { A, B };        <- valid, required
#     enum tStatus { OK, FAIL };                     <- valid
#
# Upstream `PSrc/ClientServerModules.p` is three valid lines and PeasyAI calls
# all three errors. Reported as ERROR, so it alone fails a clean project.

_BRACE_SEMI_MSG = "Extraneous semicolon after closing brace"

# A `{` closes a declaration when the enclosing declaration -- the text back to
# the previous `;` or `}` at depth 0 -- is introduced by one of these keywords,
# or when the brace is a set/union/assert-list initializer. Matching only the
# immediately preceding token is not enough: upstream 2PC writes
# `union A, B, C, { X };`, where `union` sits several commas back.
_DECL_KEYWORD = re.compile(r"\b(?:module|test|enum|union)\b", re.IGNORECASE)
_DECL_TAIL = re.compile(r"(?:=|\bin|\bunion|,)\s*$", re.IGNORECASE)


def _matching_open(blanked: str, close_idx: int) -> int:
    """Index of the `{` matching the `}` at *close_idx*, or -1."""
    depth = 0
    for i in range(close_idx, -1, -1):
        ch = blanked[i]
        if ch == "}":
            depth += 1
        elif ch == "{":
            depth -= 1
            if depth == 0:
                return i
    return -1


def _declaration_start(blanked: str, open_idx: int) -> int:
    """Index just past the previous top-level `;` or `}` before *open_idx*."""
    depth = 0
    for i in range(open_idx - 1, -1, -1):
        ch = blanked[i]
        if ch in "}])":
            depth += 1
        elif ch in "{([":
            depth -= 1
        elif ch == ";" and depth <= 0:
            return i + 1
    return 0


def _closes_declaration(blanked: str, open_idx: int) -> bool:
    decl = blanked[_declaration_start(blanked, open_idx):open_idx]
    if _DECL_KEYWORD.search(decl):
        return True
    return bool(_DECL_TAIL.search(decl.rstrip()))


def recheck_brace_semicolons(code: str, validator_name: str) -> List[ValidationIssue]:
    """Re-run the `};` check, flagging only braces that close a code block."""
    blanked = mask_source(code)
    issues: List[ValidationIssue] = []
    for m in re.finditer(r"\}\s*;", blanked):
        open_idx = _matching_open(blanked, m.start())
        if open_idx < 0:
            continue
        if _closes_declaration(blanked, open_idx):
            continue
        issues.append(ValidationIssue(
            severity=IssueSeverity.ERROR,
            validator=validator_name,
            message="Extraneous semicolon after a code block's closing brace (}; -> })",
            line_number=blanked.count("\n", 0, m.start()) + 1,
            suggestion="Drop the ';'. It is required only after a module, test, "
                       "enum or type declaration.",
        ))
    return issues


# ── 2. A variable of the right type is not a "bare value" ────────────
#
# NamedTupleConstructionValidator flags any `new M(x)` / `send t, eX, x` whose
# argument is not a literal named tuple. But passing a variable that already
# holds the right named tuple is the normal way to write it:
#
#     response = (status = ..., accountId = ..., balance = ..., rId = ...);
#     send wReq.source, eWithDrawResp, response;     <- valid
#
# The validator has no type information for `response`, so it cannot tell. It
# guesses wrong on upstream `PSrc/Server.p:45`. Keep the finding when the
# argument is a literal, where the shape really is wrong; drop it for an
# identifier, field access, call or `default(...)`.

_BARE_VALUE_MSG = re.compile(r"passing bare value '([^']*)'")
# Identifier, field access, indexing, call, or default(...) -- possibly nested,
# possibly truncated mid-expression by the validator's own 50-char cap (which is
# why this is not anchored at the end).
_RESOLVABLE = re.compile(r"^(?:default\s*\(|[A-Za-z_]\w*)[\w.\[\]()\s,+\-*/]*$", re.DOTALL)


def _is_unresolvable_reference(expr: str) -> bool:
    """True when *expr* could be a correctly typed variable, so we cannot judge."""
    expr = expr.strip()
    if not expr:
        return False
    if expr in ("true", "false", "null", "halt"):
        return False
    if re.match(r"^-?\d", expr) or expr.startswith('"'):
        return False
    return bool(_RESOLVABLE.match(expr))


def filter_issues(code: str, issues: List[ValidationIssue]) -> List[ValidationIssue]:
    """Drop confirmed false positives and substitute narrowed replacements."""
    kept: List[ValidationIssue] = []
    rechecked_brace_semis = False
    ambiguous = _ambiguous_params(code)

    for issue in issues:
        if _BRACE_SEMI_MSG in issue.message:
            if not rechecked_brace_semis:
                kept.extend(recheck_brace_semicolons(code, issue.validator))
                rechecked_brace_semis = True
            continue

        m = _BARE_VALUE_MSG.search(issue.message)
        if m and _is_unresolvable_reference(m.group(1)):
            continue

        m = _MISSING_SPEC_MSG.search(issue.message)
        if m and test_asserts_spec(code, m.group(1), m.group(2)):
            continue

        m = _FIELD_MSG.search(issue.message)
        if m and m.group(1) in ambiguous:
            continue

        kept.append(issue)

    return kept


# ── 3. `assert A, B in { ... }` lists a set of specs, not just one ───
#
# TestFileValidator checks each spec with r"\bassert\s+<Spec>\s+in\b", which
# requires the spec name to sit immediately between `assert` and `in`. A test
# that asserts several monitors at once -- the normal form, and the one this
# repo and the upstream tutorials both use --
#
#     test tcTwoClients [main=TestTwoClients]:
#       assert MutualExclusion, GuaranteedLockProgress in
#       { TestTwoClients, LockServer, Client };
#
# matches for neither name: the first is followed by a comma, the second is not
# preceded by `assert`. So every spec is reported as un-asserted. Upstream
# `1_ClientServer/PTst/Testscript.p` misfires identically.
#
# Re-derive by parsing the assert clause and splitting the list.

_TEST_DECL = re.compile(r"test\s+(?:param\s*\([^)]*\)\s*)?(\w+)\s*\[\s*main\s*=\s*\w+\s*\]\s*:(.*?);",
                        re.DOTALL)
_ASSERT_CLAUSE = re.compile(r"\bassert\s+(.+?)\s+in\b", re.DOTALL)
_MISSING_SPEC_MSG = re.compile(r"Test '(\w+)' does not assert spec '(\w+)'")


def _asserted_specs(body: str):
    """Spec names in a test declaration's `assert ... in` clause."""
    m = _ASSERT_CLAUSE.search(body)
    if not m:
        return set()
    return {part.strip() for part in m.group(1).split(",") if part.strip()}


def test_asserts_spec(code: str, test_name: str, spec: str) -> bool:
    """True when *test_name* really does assert *spec*."""
    masked = mask_source(code)
    for name, body in _TEST_DECL.findall(masked):
        if name == test_name:
            return spec in _asserted_specs(body)
    return False


# ── 4. A parameter name reused across handlers is ambiguous ──────────
#
# PayloadFieldValidator maps *parameter name* -> type, not scope. When sibling
# handlers in one state reuse a parameter name with different payload types --
# normal style, since each handler is its own scope -- the map keeps one type
# and every field access from the other handlers is reported against it.
#
# `Projects/ProjectRobot2026/Common/RuntimeSpecs.p` binds `o` three times:
#
#     on eObligationCreated   do (o: tObligation) { open[o.id] = o.due; }
#     on eObligationFulfilled do (o: tOutcome)    { ... }
#     on eSanctionApplied     do (o: tOutcome)    { ... }
#
# `tObligation` has `due`; `tOutcome` does not. The validator resolves `o` to
# `tOutcome` and flags the valid `o.due`.
#
# Drop the finding when the parameter name is bound to more than one type in
# the file: the validator cannot know which scope the access came from. A
# parameter with a single binding is still checked.

_PARAM_BINDING = re.compile(
    r"(?:\bfun\s+\w+\s*\(|\bentry\s*\(|\bon\s+[\w\s,]+?\s+(?:do|goto\s+\w+\s+with)\s*\w*\s*\()"
    r"\s*(\w+)\s*:\s*([\w\[\], ]+?)\s*\)"
)
_FIELD_MSG = re.compile(r"'(\w+)\.(\w+)' — field")


def _ambiguous_params(code: str):
    """Parameter names bound to more than one type in this file."""
    seen: dict = {}
    for name, typ in _PARAM_BINDING.findall(mask_source(code)):
        seen.setdefault(name, set()).add(typ.strip())
    return {n for n, types in seen.items() if len(types) > 1}

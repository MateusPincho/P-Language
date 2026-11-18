#!/usr/bin/env python3
"""
Static analysis for P language source files. No LLM, no network, stdlib only.

Lifted from PeasyAI (``src/core/validation/`` + ``src/core/compilation/``) so the
same deterministic checks run without the PeasyAI MCP server or an API key. The
modules under ``plint/`` are near-verbatim copies of PeasyAI's; keep them that
way so they stay diffable against upstream. Policy lives here.

Two deliberate departures from PeasyAI, both for safety on hand-written code:

1. Comment- and string-blind detection. PeasyAI's validators pattern-match raw source, so a
   doc comment mentioning P constructs produces phantom findings. Every
   validator here sees a copy with comment bodies blanked to spaces (length and
   line numbers preserved), so findings point at code.

2. Guarded fixes. Fixing is opt-in, applies only a curated safe subset, and
   refuses to write a file whose comments or brace/paren balance changed. See
   SAFE_FIXES and OPINIONATED_FIXES.

3. False-positive suppression. Two validators report ERRORs on valid P. See
   ``plint/suppress.py``, which narrows each rather than disabling it.

Usage
-----
    python3 -I validate_p.py FILE.p [FILE.p ...] [options]

    --project DIR   Project root for cross-file checks (undeclared types/events,
                    duplicate declarations, named-tuple construction at new/send
                    sites). Defaults to walking up to the nearest *.pproj.
                    For the shared-Common/ layout, point this at the directory
                    ABOVE the .pproj so ../Common/*.p is in scope.
    --fix           Apply the safe rewrites in place.
    --fix-all       Also apply the opinionated rewrites. Review the diff.
    --json          Machine-readable output.
    -q, --quiet     Errors only.

Exit status
-----------
    0  no ERROR-severity issues
    1  at least one ERROR-severity issue remains
    2  usage or I/O problem

A clean run is not a substitute for ``p compile``. It catches what is cheap to
catch statically so the compiler is spent on real problems.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plint.pcomments import extract_comments, mask_source  # noqa: E402
from plint.suppress import filter_issues  # noqa: E402
from plint.pipeline import ValidationPipeline  # noqa: E402
from plint.p_post_processor import PCodePostProcessor, PostProcessResult  # noqa: E402
from plint.validators import IssueSeverity  # noqa: E402


# ── Fix policy ────────────────────────────────────────────────────────
#
# Two of PeasyAI's Stage-1 rewrites change code that is already valid P. They
# exist because an LLM writing P gets these wrong often enough to rewrite blind.
# On hand-written code they are destructive, so they sit behind --fix-all:
#
#   _fix_named_field_tuple_construction
#       (f1 = v1, f2 = v2)  ->  (v1, v2)
#       Both forms are valid P. Going positional only helps when the field
#       names are wrong.
#
#   _fix_enum_access_syntax
#       tEnum.VALUE  ->  VALUE
#       Pattern is r"\bt([A-Z]\w*)\.([\w]+)\b", which also matches legitimate
#       field access on any variable named tSomething.
#
OPINIONATED_FIXES = (
    "_fix_named_field_tuple_construction",
    "_fix_enum_access_syntax",
)

SAFE_FIXES = (
    "_fix_trailing_comma_in_params",        # fun F(x: T,)      -> fun F(x: T)
    "_fix_variable_declaration_order",      # hoist var decls to top of fun body
    "_fix_single_field_tuples",             # (f = v)           -> (f = v,)
    "_fix_test_declaration_syntax",         # no-op by design; documents intent
    "_fix_test_declaration_union_syntax",   # (union { A, B })  -> { A, B }; adds ;
    "_fix_missing_semicolons",              # return expr       -> return expr;
    "_fix_entry_function_syntax",           # entry Fn();       -> entry Fn;
    "_fix_bare_halt",                       # halt;             -> raise halt;
    "_fix_forbidden_in_monitors",           # warn; drop `x = this as machine;`
)


class CuratedPostProcessor(PCodePostProcessor):
    """PCodePostProcessor restricted to a chosen fix list.

    Overrides process() rather than editing plint/ so the copied modules stay
    diffable against upstream.
    """

    def __init__(self, include_opinionated: bool = False):
        super().__init__()
        self._fixes = SAFE_FIXES + (OPINIONATED_FIXES if include_opinionated else ())

    def process(self, code, filename="", is_test_file=False):  # noqa: D102
        self.fixes_applied = []
        self.warnings = []
        for name in self._fixes:
            code = getattr(self, name)(code)
        if is_test_file:
            code = self._warn_timer_wired_to_this(code, filename)
            code = self._ensure_test_declarations(code, filename)
        return PostProcessResult(
            code=code,
            fixes_applied=self.fixes_applied,
            warnings=self.warnings,
        )


class MaskedValidator:
    """Wrap a Validator so it never sees comment or string-literal text.

    Findings keep exact line numbers because blanking preserves length. Any
    auto-fix is dropped: PeasyAI's VarDeclarationOrderValidator builds its
    replacement strings and absolute offsets from the code handed to
    validate(), so applying a fix derived from blanked text to the real file
    would splice comment-free code over the original. Fixing is Stage 1's job
    here, where the fix list is curated and the result is verified.
    """

    def __init__(self, inner):
        self._inner = inner

    @property
    def name(self):
        return self._inner.name

    def validate(self, code, context=None):
        blanked_ctx = None
        if context:
            blanked_ctx = {k: mask_source(v) for k, v in context.items()}
        result = self._inner.validate(mask_source(code), blanked_ctx)
        for issue in result.issues:
            issue.auto_fixable = False
            issue.fix_function = None
        return result


def _build_pipeline(is_test: bool) -> ValidationPipeline:
    base = ValidationPipeline(include_test_validators=is_test)
    base.validators = [MaskedValidator(v) for v in base.validators]
    return base


# ── Write guards ──────────────────────────────────────────────────────

def _balance(code: str):
    blanked = mask_source(code)
    return blanked.count("{") - blanked.count("}"), blanked.count("(") - blanked.count(")")


def _rewrite_is_safe(before: str, after: str):
    """Return (ok, reason). Refuse writes that touch comments or balance."""
    if extract_comments(before) != extract_comments(after):
        return False, "rewrite altered comment text"
    if _balance(before) != _balance(after):
        return False, "rewrite changed brace/paren balance"
    return True, ""


# ── Reporting ─────────────────────────────────────────────────────────

_ORDER = {IssueSeverity.ERROR: 0, IssueSeverity.WARNING: 1, IssueSeverity.INFO: 2}
_LABEL = {
    IssueSeverity.ERROR: "ERROR  ",
    IssueSeverity.WARNING: "WARNING",
    IssueSeverity.INFO: "INFO   ",
}


def _clean(text):
    """Undo the doubled braces PeasyAI's .format()-era suggestion strings carry."""
    if not text:
        return text
    return text.replace("{{", "{").replace("}}", "}")


def _print_file_report(display_path, result, quiet):
    issues = sorted(
        result.issues,
        key=lambda i: (_ORDER.get(i.severity, 9), i.line_number or 0, i.validator),
    )
    if quiet:
        issues = [i for i in issues if i.severity is IssueSeverity.ERROR]

    if not issues:
        print(f"{display_path}: clean")
        return

    n_err = len(result.errors)
    n_warn = len(result.warnings)
    print(f"\n{display_path}  ({n_err} error, {n_warn} warning)")
    for issue in issues:
        where = f":{issue.line_number}" if issue.line_number else ""
        print(f"  {_LABEL[issue.severity]} {display_path}{where}  [{issue.validator}]")
        print(f"      {issue.message}")
        if issue.suggestion:
            print(f"      -> {_clean(issue.suggestion)}")


def _issue_to_dict(issue):
    return {
        "severity": issue.severity.value,
        "validator": issue.validator,
        "message": issue.message,
        "line": issue.line_number,
        "suggestion": _clean(issue.suggestion),
    }


# ── Main ──────────────────────────────────────────────────────────────

def _resolve_project(path, explicit):
    if explicit:
        return str(Path(explicit).resolve())
    return ValidationPipeline._find_project_root(str(path))


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="validate_p.py",
        description="Static analysis for P language source files.",
    )
    parser.add_argument("files", nargs="+", metavar="FILE", help="one or more .p files")
    parser.add_argument("--project", metavar="DIR", default=None,
                        help="project root for cross-file checks")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--fix", action="store_true",
                       help="apply the safe rewrites in place")
    group.add_argument("--fix-all", action="store_true",
                       help="also apply the opinionated rewrites (review the diff)")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("-q", "--quiet", action="store_true", help="errors only")
    args = parser.parse_args(argv)

    fixing = args.fix or args.fix_all
    payload = {"files": [], "error_count": 0, "warning_count": 0}
    exit_code = 0

    for raw in args.files:
        path = Path(raw)
        if not path.is_file():
            print(f"validate_p.py: not a file: {raw}", file=sys.stderr)
            return 2
        try:
            code = path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"validate_p.py: cannot read {raw}: {exc}", file=sys.stderr)
            return 2

        resolved = path.resolve()
        project = _resolve_project(resolved, args.project)
        is_test = "PTst" in resolved.parts
        pipeline = _build_pipeline(is_test)

        fixes, refused = [], ""
        if fixing:
            processor = CuratedPostProcessor(include_opinionated=args.fix_all)
            pp = processor.process(code, path.name, is_test_file=is_test)
            if pp.code != code:
                ok, reason = _rewrite_is_safe(code, pp.code)
                if ok:
                    path.write_text(pp.code, encoding="utf-8")
                    code = pp.code
                    fixes = list(pp.fixes_applied)
                else:
                    refused = reason

        # Report against the file as it now stands on disk, with no further
        # fixes folded in, so the output reflects what is actually there.
        result = pipeline.validate(
            code, filename=path.name, project_path=project,
            is_test_file=is_test, apply_fixes=False,
        )
        result.issues = filter_issues(code, result.issues)
        result.is_valid = not result.errors

        if result.errors:
            exit_code = 1

        if args.json:
            payload["files"].append({
                "path": str(resolved),
                "project": project,
                "is_test_file": is_test,
                "is_valid": result.is_valid,
                "fixes_applied": fixes,
                "fix_refused": refused,
                "issues": [_issue_to_dict(i) for i in result.issues],
            })
            payload["error_count"] += len(result.errors)
            payload["warning_count"] += len(result.warnings)
        else:
            if fixes:
                print(f"\n{raw}: applied {len(fixes)} fix(es)")
                for f in fixes:
                    print(f"      fixed: {f}")
            if refused:
                print(f"\n{raw}: fix NOT written - {refused}", file=sys.stderr)
            _print_file_report(raw, result, args.quiet)

    if args.json:
        print(json.dumps(payload, indent=2))

    return exit_code


if __name__ == "__main__":
    sys.exit(main())

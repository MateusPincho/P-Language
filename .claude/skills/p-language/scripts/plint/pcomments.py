"""Source masking for P code. Added for the skill; not from PeasyAI.

None of PeasyAI's validators strip comments before pattern matching, so a doc
comment that merely *mentions* P constructs produces phantom findings. On the
upstream ClientServer tutorial the header comment of ``PSpec/BankBalanceCorrect.p``
alone yields a spec named ``machine`` and several "observes undefined event"
warnings whose event names are whole English sentences.

String literals cause the same class of error: ``format("...{0}; now...")``
reads as an extraneous ``};``, and ``"not in the new leader's log"`` reads as
the forbidden ``new`` keyword in a spec monitor. Both appear in the upstream
Raft tutorial.

``blank_comments`` and ``blank_strings`` replace the offending characters with
spaces, leaving newlines in place. Length and line structure are preserved
exactly, so offsets and line numbers computed against the masked text still
address the real file. ``mask_source`` applies both and is what validators
should see.
"""

from __future__ import annotations

from typing import List, Tuple


def blank_comments(code: str) -> str:
    """Return *code* with comment bodies replaced by spaces.

    Handles ``//`` line comments and ``/* */`` block comments, and does not
    treat comment markers inside string literals as comments. Output has the
    same length as the input, and newlines are preserved.
    """
    out: List[str] = []
    i = 0
    n = len(code)
    while i < n:
        ch = code[i]

        if ch == '"':
            out.append(ch)
            i += 1
            while i < n:
                out.append(code[i])
                if code[i] == "\\" and i + 1 < n:
                    out.append(code[i + 1])
                    i += 2
                    continue
                if code[i] == '"':
                    i += 1
                    break
                if code[i] == "\n":
                    i += 1
                    break
                i += 1
            continue

        if ch == "/" and i + 1 < n and code[i + 1] == "/":
            while i < n and code[i] != "\n":
                out.append(" ")
                i += 1
            continue

        if ch == "/" and i + 1 < n and code[i + 1] == "*":
            out.append("  ")
            i += 2
            while i < n:
                if code[i] == "*" and i + 1 < n and code[i + 1] == "/":
                    out.append("  ")
                    i += 2
                    break
                out.append("\n" if code[i] == "\n" else " ")
                i += 1
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def extract_comments(code: str) -> List[Tuple[int, str]]:
    """Return ``(line_number, text)`` for each comment, for change detection.

    Used to prove a rewrite left every comment intact before writing a file
    back to disk.
    """
    blanked = blank_comments(code)
    comments: List[Tuple[int, str]] = []
    line = 1
    run: List[str] = []
    run_line = 1
    for orig, masked in zip(code, blanked):
        if masked == " " and orig != " ":
            if not run:
                run_line = line
            run.append(orig)
        else:
            if run:
                comments.append((run_line, "".join(run)))
                run = []
        if orig == "\n":
            line += 1
    if run:
        comments.append((run_line, "".join(run)))
    return comments


def blank_strings(code: str) -> str:
    """Return *code* with string literal contents replaced by spaces.

    Quotes are kept so the token still reads as a string. Braces, semicolons
    and keywords inside a literal are not code and must not be matched as
    such. Run after :func:`blank_comments`.
    """
    out = []
    i = 0
    n = len(code)
    while i < n:
        ch = code[i]
        if ch != '"':
            out.append(ch)
            i += 1
            continue
        out.append(ch)
        i += 1
        while i < n:
            if code[i] == "\\" and i + 1 < n:
                out.append("  ")
                i += 2
                continue
            if code[i] == '"':
                out.append('"')
                i += 1
                break
            if code[i] == "\n":
                out.append("\n")
                i += 1
                break
            out.append(" ")
            i += 1
    return "".join(out)


def mask_source(code: str) -> str:
    """Comments and string contents blanked. What validators should match on."""
    return blank_strings(blank_comments(code))

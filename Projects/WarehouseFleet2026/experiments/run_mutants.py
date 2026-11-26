#!/usr/bin/env python3
"""E0, monitor sanity: one mutant per monitor; each mutant must make its monitor fail.

    python3 -I experiments/run_mutants.py <schedules> <seed>[,<seed>...] [mutant ...]
    python3 -I experiments/run_mutants.py 10000 1                 # every mutant, seed 1
    python3 -I experiments/run_mutants.py 100000 1,2,3 M08_N2     # calibration runs

For each mutant this
  1. copies WarehouseFleet/ to WarehouseFleet2026/.mutants/<mutant>/ (inside the
     repo, so the container sees it) without its build output,
  2. applies the mutation: exact text replacements, each required to match once,
  3. appends a probe test that attaches ONLY the target monitor:
       test tcProbe [main=<driver>]: assert <monitor> in (union Fleet, { <driver> });
  4. runs, inside the container, from the copy:
       p compile
       p check -tc tcProbe -s <schedules> --seed <seed>
  5. appends a line to experiments/mutants.tsv, keeps the checker log in
     experiments/logs/, and deletes the copy.

A mutant is KILLED when the run reports a bug from the target monitor, OTHER-BUG
when it fails for another reason (machine assert, unhandled event), SURVIVED
when no bug is found.
"""
import os
import re
import shutil
import subprocess
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)                       # .../WarehouseFleet2026
REPO = os.path.dirname(os.path.dirname(PROJECT))      # repo root
MODEL = os.path.join(PROJECT, "WarehouseFleet")

# name: (monitor, driver, [(file, old, new), ...], what the mutation breaks)
MUTANTS = {
    "M01_N1": ("ZoneMutualExclusion", "TestRandomTasks",
        [("PSrc/ZoneController.p",
          "if (!occupied) {                                  // N1: free -> grant",
          "if (true) {   // MUTANT: grant even when occupied")],
        "controller grants a zone that is occupied"),
    "M02_N5": ("NoRobotWithHuman", "TestRandomTasks",
        [("PSrc/ZoneController.p",
          "if (Locked()) {                                   // N5",
          "if (false) {   // MUTANT: no lockout")],
        "Zone 1 admits robots under V2 (N6 evacuation kept)"),
    "M03_N4a": ("SanctionOnlyAfterExpiry", "TestRandomTasks",
        [("PSrc/ObligationManager.p",
          "send robots[a.robotId], eDeliveryConfirmed, a;",
          "send robots[a.robotId], eSanction, (robotId = a.robotId, taskId = a.taskId, "
          "cooldown = cooldown, infractions = infractions[a.robotId]);   // MUTANT")],
        "Fleet Manager sanctions an on-time delivery"),
    "M04_N4b": ("NoDoubleOutcome", "TestFairness",
        [("PSrc/ObligationManager.p",
          "      if (active[a.robotId]) {\n        active[a.robotId] = false;\n        send robots[a.robotId], eDeliveryConfirmed, a;",
          "      if (true) {   // MUTANT: confirm late arrivals too\n        active[a.robotId] = false;\n        send robots[a.robotId], eDeliveryConfirmed, a;")],
        "Fleet Manager confirms a delivery that already expired"),
    "M05_L_task": ("EveryTaskResolved", "TestFairness",
        [("PSrc/ObligationManager.p",
          "    on eDeadlineExpired do (e: tTaskRef) {\n",
          "    on eDeadlineExpired do (e: tTaskRef) {\n      if (true) { return; }   // MUTANT: never sanction\n")],
        "an expired task is never sanctioned"),
    "M06_L_robot": ("EveryRobotSettles", "TestFairness",
        [("PSrc/Robot.p",
          "        goto AwaitDirection;\n      }\n      goto InBay;",
          "        goto AwaitDirection;\n      }\n      goto Done;   // MUTANT: never return")],
        "a sanctioned robot never makes the return trip"),
    "M07_L_human": ("HumanEventuallyEnters", "TestRandomTasks",
        [("PSrc/AdaptationCoordinator.p",
          "        if (!naive) {\n          send human, eHumanAccessGranted;",
          "        if (false) {   // MUTANT: never admit the human\n          send human, eHumanAccessGranted;")],
        "coordinator never admits the human"),
    "M08_N2": ("PriorityRespected", "TestRandomTasks",
        [("PSrc/ZoneController.p",
          "if (a.priority != b.priority) { return a.priority > b.priority; }",
          "if (a.priority != b.priority) { return a.priority < b.priority; }   // MUTANT")],
        "N2 reversed: the lower priority wins"),
    "M09_N2empty": ("EmptyRobotHasPriorityZero", "TestFairness",
        [("PSrc/Robot.p",
          "      priority = 0;\n      returning = true;\n      if (oneDirection)",
          "      priority = task.priority;   // MUTANT\n      returning = true;\n      if (oneDirection)")],
        "a robot returning empty keeps its package priority"),
    "M10_N3": ("OutrankedOccupantPreempted", "TestRandomTasks",
        [("PSrc/ZoneController.p",
          "if (!preempting && Wins(req, occ)) {              // N3",
          "if (false) {   // MUTANT: never preempt")],
        "N3 removed: an outranked occupant is never told to retreat"),
    "M11_N7": ("DeadlinesKeepRunning", "TestRandomTasks",
        [("PSrc/ObligationManager.p",
          "remaining[rid] = remaining[rid] - 1;",
          "remaining[rid] = remaining[rid] - (now % 2);   // MUTANT: every other tick")],
        "deadlines count only every other tick"),
    "M12_N8": ("V1EventuallyRestored", "TestRandomTasks",
        [("PSrc/AdaptationCoordinator.p",
          "      Broadcast(V1);                          // N8",
          "      acks = 0;   // MUTANT: V1 never restored")],
        "coordinator never restores V1"),
    "M13_L3": ("AdaptationTerminates", "TestE9Abort",
        [("PSrc/ZoneController.p",
          "        send coord, eNormChangeAck, (zone = zone, version = V2);\n      }\n    } else {\n      GrantNext();",
          "        awaitingClear = true;   // MUTANT: never ack after evacuating\n      }\n    } else {\n      GrantNext();"),
         ("PSrc/AdaptationCoordinator.p",
          "      if ($) {\n        Abort();",
          "      if ($) {\n        acks = acks;   // MUTANT: the timeout never aborts")],
        "a switch that is neither committed nor aborted"),
    "M14_E9admit": ("AbortNeverAdmits", "TestE9Abort",
        [("PSrc/AdaptationCoordinator.p",
          "    send human, eHumanAccessRefused;",
          "    send human, eHumanAccessGranted;   // MUTANT: admit after abort")],
        "an aborted switch admits the human"),
    "M15_E9unblock": ("AbortUnblocksControllers", "TestE9Abort",
        [("PSrc/AdaptationCoordinator.p",
          "    send human, eHumanAccessRefused;\n    Broadcast(V1);",
          "    send human, eHumanAccessRefused;\n    acks = 0;   // MUTANT: V1 not restored after abort")],
        "an abort leaves the controllers on V2"),
}


def run(cmd, log):
    with open(log, "a") as f:
        f.write(f"$ {cmd}\n")
        f.flush()
        p = subprocess.run(["docker", "compose", "--project-directory", REPO, "run", "--rm", "-T",
                            "p", "bash", "-lc", cmd], stdout=f, stderr=subprocess.STDOUT)
    return p.returncode


def first(pattern, text, default="?"):
    m = re.findall(pattern, text)
    return m[-1] if m else default


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    schedules = int(sys.argv[1])
    seeds = [int(s) for s in sys.argv[2].split(",")]
    names = sys.argv[3:] or list(MUTANTS)
    os.makedirs(os.path.join(HERE, "logs"), exist_ok=True)
    for name in names:
        monitor, driver, edits, what = MUTANTS[name]
        copy = os.path.join(PROJECT, ".mutants", name)
        shutil.rmtree(copy, ignore_errors=True)
        shutil.copytree(MODEL, copy, ignore=shutil.ignore_patterns("PGenerated", "PCheckerOutput"))
        for rel, old, new in edits:
            path = os.path.join(copy, rel)
            src = open(path).read()
            n = src.count(old)
            if n != 1:
                sys.exit(f"{name}: mutation text found {n} times in {rel}, expected 1")
            open(path, "w").write(src.replace(old, new))
        with open(os.path.join(copy, "PTst/TestScript.p"), "a") as f:
            f.write(f"\n// E0 probe for {name}\ntest tcProbe [main={driver}]:\n"
                    f"  assert {monitor} in (union Fleet, {{ {driver} }});\n")
        rel_copy = os.path.relpath(copy, REPO)
        clog = os.path.join(HERE, "logs", f"{name}_compile.log")
        open(clog, "w").close()
        rc = run(f"cd {rel_copy} && p compile", clog)
        compiled = rc == 0 and "Compilation succeeded" in open(clog).read()
        for seed in seeds:
            log = os.path.join(HERE, "logs", f"{name}_s{schedules}_seed{seed}.log")
            open(log, "w").close()
            if not compiled:
                line = [str(date.today()), name, monitor, str(schedules), str(seed),
                        "COMPILE-ERROR", "", "", "", what]
            else:
                run(f"cd {rel_copy} && p check -tc tcProbe -s {schedules} --seed {seed} -o PCheckerOutput/probe", log)
                text = open(log).read()
                bugs = first(r"Found (\d+) bug", text)
                explored = first(r"Explored (\d+) schedule", text)
                secs = first(r"Elapsed (\d+\.\d+) sec\.\n", text)
                err = ""
                bug_dir = os.path.join(copy, "PCheckerOutput", "probe", "BugFinding")
                if os.path.isdir(bug_dir):
                    for fn in sorted(os.listdir(bug_dir)):
                        if fn.endswith(".txt") and "summary" not in fn:
                            for l in open(os.path.join(bug_dir, fn)):
                                if "<ErrorLog>" in l:
                                    err = l.replace("<ErrorLog> ", "").strip()
                                    break
                        if err:
                            break
                # Only the target monitor is attached, so a PSpec assertion (or a
                # liveness report naming it) can only come from that monitor.
                if bugs not in ("0", "?") and ("PSpec/" in err or monitor in err):
                    killed = "KILLED"
                elif bugs not in ("0", "?"):
                    killed = "OTHER-BUG"
                else:
                    killed = "SURVIVED"
                line = [str(date.today()), name, monitor, str(schedules), str(seed),
                        killed, bugs, explored, secs, what, err]
            with open(os.path.join(HERE, "mutants.tsv"), "a") as f:
                f.write("\t".join(line) + "\n")
            print("\t".join(line[1:9]), flush=True)
        shutil.rmtree(copy, ignore_errors=True)


if __name__ == "__main__":
    main()

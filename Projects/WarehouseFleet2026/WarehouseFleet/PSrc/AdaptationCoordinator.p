// Centralized adaptation: switches the norm set V1 -> V2 when the human picker
// asks for Zone 1, and back to V1 when the human leaves (N5, N6, N8).
//
// The switch is two-phase: the human is admitted only after every controller
// has acked V2, and controller 1 acks only once Zone 1 is empty (N6).
// naive = true skips that wait; it exists only to show, in tcNaiveAdaptation,
// that the NoRobotWithHuman monitor can fail.
//
// Experiment switches, all off in the final model:
//   blockAll      (E4) after all V2 acks, send eNormCommit so zones 0 and 2 reopen
//   notifyManager (E7) tell the Fleet Manager when V2 starts (and wait) and ends
//   abortable     (E9) the switch may time out; the coordinator then aborts,
//                      restores V1 and refuses the human
machine AdaptationCoordinator {
  var controllers: seq[machine];
  var naive: bool;
  var blockAll: bool;
  var abortable: bool;
  var notifyManager: bool;
  var manager: machine;
  var human: machine;
  var acks: int;
  var aborted: bool;

  start state Init {
    entry (cfg: tCoordConfig) {
      controllers = cfg.controllers;
      naive = cfg.naive;
      blockAll = cfg.blockAll;
      abortable = cfg.abortable;
      notifyManager = cfg.notifyManager;
      manager = cfg.manager;
      goto NormalV1;
    }
  }

  state NormalV1 {
    on eHumanRequest do (h: machine) {
      human = h;
      if (notifyManager) {
        send manager, eAdaptationNotice, (version = V2, coord = this);
        goto NotifyingManager;
      }
      StartSwitch();
    }
    ignore eAdaptTimeout;   // E9: stale timeout from an earlier switch
  }

  // E7 only: the Fleet Manager must know V2 has started before any controller
  // can deny a robot because of it.
  state NotifyingManager {
    on eAdaptationNoticeAck do { StartSwitch(); }
  }

  state SwitchingToV2 {
    on eNormChangeAck do (a: tNormAck) {
      assert a.version == V2,
        format("expected a V2 ack, zone {0} acked {1}", a.zone, a.version);
      acks = acks + 1;
      if (acks == sizeof(controllers)) {
        if (blockAll) { BroadcastCommit(); }      // E4
        if (!naive) {
          send human, eHumanAccessGranted;
        }
        goto HumanActive;
      }
    }
    on eAdaptTimeout do {                         // E9: k ticks elapsed, nondeterministically
      if ($) {
        Abort();
      } else {
        send this, eAdaptTimeout;
      }
    }
    defer eHumanExit;   // only reachable when naive
  }

  state HumanActive {
    on eHumanExit do {
      Broadcast(V1);                          // N8
      goto RestoringV1;
    }
    ignore eAdaptTimeout;
  }

  state RestoringV1 {
    on eNormChangeAck do (a: tNormAck) {
      if (a.version == V2) {
        // E9: a controller that installed V2 before the abort reached it
        assert aborted, format("zone {0} acked V2 while V1 is being restored", a.zone);
        return;
      }
      acks = acks + 1;
      if (acks == sizeof(controllers)) {
        if (notifyManager) {
          send manager, eAdaptationNotice, (version = V1, coord = this);   // E7
        }
        aborted = false;
        goto NormalV1;
      }
    }
    defer eHumanRequest;
    ignore eAdaptTimeout;
  }

  fun StartSwitch() {
    Broadcast(V2);
    if (naive) {
      send human, eHumanAccessGranted;   // BUG (intended): no wait for evacuation
    }
    if (abortable) {
      send this, eAdaptTimeout;          // E9: arm the timeout
    }
    goto SwitchingToV2;
  }

  // E9: give up the switch; V2 is not installed and the human is refused.
  fun Abort() {
    aborted = true;
    announce eAdaptationAborted;
    send human, eHumanAccessRefused;
    Broadcast(V1);
    goto RestoringV1;
  }

  fun Broadcast(v: tNormVersion) {
    var i: int;
    acks = 0;
    i = 0;
    while (i < sizeof(controllers)) {
      send controllers[i], eNormChange, (version = v, coord = this);
      i = i + 1;
    }
  }

  fun BroadcastCommit() {
    var i: int;
    i = 0;
    while (i < sizeof(controllers)) {
      send controllers[i], eNormCommit;
      i = i + 1;
    }
  }
}

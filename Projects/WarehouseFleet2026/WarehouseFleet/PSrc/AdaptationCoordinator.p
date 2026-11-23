// Centralized adaptation: switches the norm set V1 -> V2 when the human picker
// asks for Zone 1, and back to V1 when the human leaves (N5, N6, N8).
//
// The switch is two-phase: the human is admitted only after every controller
// has acked V2, and controller 1 acks only once Zone 1 is empty (N6).
// naive = true skips that wait; it exists only to show, in tcNaiveAdaptation,
// that the NoRobotWithHuman monitor can fail.
machine AdaptationCoordinator {
  var controllers: seq[machine];
  var naive: bool;
  var human: machine;
  var acks: int;

  start state Init {
    entry (cfg: tCoordConfig) {
      controllers = cfg.controllers;
      naive = cfg.naive;
      goto NormalV1;
    }
  }

  state NormalV1 {
    on eHumanRequest do (h: machine) {
      human = h;
      Broadcast(V2);
      if (naive) {
        send human, eHumanAccessGranted;   // BUG (intended): no wait for evacuation
      }
      goto SwitchingToV2;
    }
  }

  state SwitchingToV2 {
    on eNormChangeAck do (a: tNormAck) {
      assert a.version == V2,
        format("expected a V2 ack, zone {0} acked {1}", a.zone, a.version);
      acks = acks + 1;
      if (acks == sizeof(controllers)) {
        if (!naive) {
          send human, eHumanAccessGranted;
        }
        goto HumanActive;
      }
    }
    defer eHumanExit;   // only reachable when naive
  }

  state HumanActive {
    on eHumanExit do {
      Broadcast(V1);                          // N8
      goto RestoringV1;
    }
  }

  state RestoringV1 {
    on eNormChangeAck do (a: tNormAck) {
      assert a.version == V1,
        format("expected a V1 ack, zone {0} acked {1}", a.zone, a.version);
      acks = acks + 1;
      if (acks == sizeof(controllers)) {
        goto NormalV1;
      }
    }
    defer eHumanRequest;
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
}

// The human picker: occasionally needs Zone 1. When it asks and how long it
// stays are both nondeterministic, so the checker places the V2 episode at
// every point of the robots' trips.
machine HumanPicker {
  var coord: machine;
  var delay: int;   // steps before asking for Zone 1
  var stay: int;    // steps spent inside Zone 1

  start state Init {
    entry (cfg: tHumanConfig) {
      coord = cfg.coord;
      delay = choose(cfg.maxDelay + 1);
      stay = choose(cfg.maxStay) + 1;
      goto Idle;
    }
  }

  state Idle {
    entry {
      if (delay > 0) {
        delay = delay - 1;
        send this, eHumanStep;
      } else {
        send coord, eHumanRequest, this;
        goto WaitingAccess;
      }
    }
    on eHumanStep goto Idle;
  }

  state WaitingAccess {
    on eHumanAccessGranted do {
      announce eHumanEnter;
      goto Working;
    }
  }

  state Working {
    entry {
      if (stay > 0) {
        stay = stay - 1;
        send this, eHumanStep;
      } else {
        send coord, eHumanExit;   // the human has left Zone 1
        goto Gone;
      }
    }
    on eHumanStep goto Working;
  }

  state Gone { }
}

// Monitors used only by individual experiments (see ../../EXPERIMENTS.md).

// E6: no head-on conflict. A robot is never denied a zone because a robot
// travelling the opposite way holds it. Directions are taken at the moment each
// request was sent (a denial can be announced after the requester has already
// turned back): the task's origin gives the direction, and it reverses when
// the robot abandons the delivery (the return trip goes back to the origin).
// Valid only with side bays (parking = true).
spec NoHeadOnConflict observes eTaskAssigned, eTaskAbandoned, eRequestZone, eAccessDenied,
                               eZoneGranted {
  var dir: map[int, tDirection];         // robotId -> current direction
  var reqDir: map[int, tDirection];      // robotId*1000 + reqId -> direction when sent
  var holderDir: map[int, tDirection];   // zone -> direction of the request that holds it

  start state Monitoring {
    on eTaskAssigned do (a: tAssignment) {
      if (a.task.origin == STATION_A) { dir[a.task.robotId] = A_TO_B; }
      else { dir[a.task.robotId] = B_TO_A; }
    }
    on eTaskAbandoned do (a: tAbandon) {
      if (dir[a.robotId] == A_TO_B) { dir[a.robotId] = B_TO_A; }
      else { dir[a.robotId] = A_TO_B; }
    }
    on eRequestZone do (r: tRequestZone) {
      reqDir[r.robotId * 1000 + r.reqId] = dir[r.robotId];
    }
    on eZoneGranted do (g: tAdmission) {
      holderDir[g.zone] = reqDir[g.robotId * 1000 + g.reqId];
    }
    on eAccessDenied do (d: tAdmission) {
      var mine: tDirection;
      if (d.cause != OCCUPIED || d.occupantId == -1 || !(d.zone in holderDir)) { return; }
      mine = reqDir[d.robotId * 1000 + d.reqId];
      assert mine == holderDir[d.zone],
        format("head-on conflict: robot {0} (direction {1}) denied zone {2}, held by robot {3} (direction {4})",
               d.robotId, DirName(mine), d.zone, d.occupantId, DirName(holderDir[d.zone]));
    }
  }
}

// E10(a): side bays of capacity one. Never two robots in the same bay.
spec BayCapacityOne observes eBayEntered, eBayLeft {
  var inBay: map[int, set[int]];   // bay -> robotIds

  start state Monitoring {
    on eBayEntered do (b: tRobotZone) {
      var s: set[int];
      if (b.zone in inBay) { s = inBay[b.zone]; }
      assert sizeof(s) == 0,
        format("bay {0} over capacity: robot {1} entered while {2} is inside", b.zone, b.robotId, s);
      s += (b.robotId);
      inBay[b.zone] = s;
    }
    on eBayLeft do (b: tRobotZone) {
      var s: set[int];
      if (b.zone in inBay) { s = inBay[b.zone]; }
      if (b.robotId in s) { s -= (b.robotId); }
      inBay[b.zone] = s;
    }
  }
}

// E9 (the kit's L3): a requested change is eventually completed (the human is
// admitted) or explicitly aborted (the human is refused).
spec AdaptationTerminates observes eHumanRequest, eHumanAccessGranted, eHumanAccessRefused {
  start cold state Idle {
    on eHumanRequest goto Pending;
    ignore eHumanAccessGranted, eHumanAccessRefused;
  }
  hot state Pending {
    on eHumanAccessGranted goto Idle;
    on eHumanAccessRefused goto Idle;
    ignore eHumanRequest;
  }
}

// E9: an aborted change never admits the picker. The abort is taken from the
// coordinator's own announcement (eAdaptationAborted), not from the refusal it
// sends: E0 showed that a coordinator which admits instead of refusing would
// otherwise go unnoticed (mutant M14).
spec AbortNeverAdmits observes eHumanRequest, eAdaptationAborted, eHumanEnter {
  var aborted: bool;

  start state Monitoring {
    on eHumanRequest do { aborted = false; }
    on eAdaptationAborted do { aborted = true; }
    on eHumanEnter do {
      assert !aborted, "E9 violated: the picker entered Zone 1 after the change was aborted";
    }
  }
}

// E9: an abort leaves no controller blocked: after eAdaptationAborted, every
// controller eventually acks V1.
spec AbortUnblocksControllers observes eAdaptationAborted, eNormChangeAck {
  var v1Acks: int;

  start cold state Idle {
    on eAdaptationAborted goto Unblocking;
    ignore eNormChangeAck;
  }
  hot state Unblocking {
    entry { v1Acks = 0; }
    on eNormChangeAck do (a: tNormAck) {
      if (a.version == V1) {
        v1Acks = v1Acks + 1;
        if (v1Acks == NUM_ZONES()) { goto Idle; }
      }
    }
  }
}

// Monitors for the norms that properties 1-4 of the PDF do not check:
// N2 (two monitors), N3, N7 and N8. They judge the controllers' decisions
// against an independent encoding of the norm (OutranksN2), using what the
// controllers announce (eAccessDenied, eZoneGranted, ePreemptIssued).

// N2, first clause: when the controller admits a robot to a zone, no robot that
// it has queued for that zone (and that has not withdrawn) outranks it.
spec PriorityRespected observes eAccessDenied, eZoneGranted, eCancelRequest {
  var waiting: map[int, tAdmission];   // key zone*100 + robotId -> its queued request
  var withdrawn: set[int];             // ReqKey of requests withdrawn before their denial was announced

  start state Monitoring {
    on eAccessDenied do (d: tAdmission) {
      // A controller's send is a scheduling point: the robot can withdraw a
      // request (eCancelRequest) before the controller announces denying it,
      // and can do so for several requests in a row (found at -s 100000).
      if (ReqKey(d.zone, d.robotId, d.reqId) in withdrawn) {
        withdrawn -= (ReqKey(d.zone, d.robotId, d.reqId));
        return;
      }
      waiting[Key(d.zone, d.robotId)] = d;
    }
    on eCancelRequest do (c: tZoneRelease) {
      var k: int;
      k = Key(c.zone, c.robotId);
      if (k in waiting && waiting[k].reqId == c.reqId) {
        waiting -= (k);
      } else {
        withdrawn += (ReqKey(c.zone, c.robotId, c.reqId));
      }
    }
    on eZoneGranted do (g: tAdmission) {
      var k: int;
      var w: tAdmission;
      k = Key(g.zone, g.robotId);
      if (k in waiting) { waiting -= (k); }
      foreach (k in keys(waiting)) {
        w = waiting[k];
        if (w.zone == g.zone) {
          assert !OutranksN2(w.priority, w.violations, w.robotId,
                             g.priority, g.violations, g.robotId),
            format("N2 violated: zone {0} admitted robot {1} (P={2}, inf={3}) while robot {4} (P={5}, inf={6}) was waiting",
                   g.zone, g.robotId, g.priority, g.violations, w.robotId, w.priority, w.violations);
        }
      }
    }
  }

  fun Key(zone: int, robotId: int): int { return zone * 100 + robotId; }
  fun ReqKey(zone: int, robotId: int, reqId: int): int {
    return (zone * 100 + robotId) * 100000 + reqId;
  }
}

// N2, second clause: a robot returning empty has priority 0. Every request a
// robot sends after abandoning its delivery must carry priority 0.
spec EmptyRobotHasPriorityZero observes eTaskAssigned, eTaskAbandoned, eRequestZone {
  var empty: set[int];   // robotIds that abandoned their delivery

  start state Monitoring {
    on eTaskAssigned do (a: tAssignment) {
      if (a.task.robotId in empty) { empty -= (a.task.robotId); }
    }
    on eTaskAbandoned do (a: tAbandon) {
      empty += (a.robotId);
    }
    on eRequestZone do (r: tRequestZone) {
      if (r.robotId in empty) {
        assert r.priority == 0,
          format("N2 violated: robot {0} returns empty but requested zone {1} with priority {2}",
                 r.robotId, r.zone, r.priority);
      }
    }
  }
}

// N3: when a controller queues a request that outranks the robot holding the
// zone (and the zone is not locked), that robot has been told to retreat:
// an ePreempt for its current holding was issued, now or earlier.
spec OutrankedOccupantPreempted observes eZoneGranted, ePreemptIssued, eAccessDenied,
                                         eRelease, eCancelRequest {
  var holding: map[int, tAdmission];   // zone -> the grant the occupant holds it by
  var preempted: map[int, int];        // zone -> reqId of the holding told to retreat

  start state Monitoring {
    on eZoneGranted do (g: tAdmission) {
      holding[g.zone] = g;
      if (g.zone in preempted) { preempted -= (g.zone); }
    }
    on ePreemptIssued do (p: tPreemption) {
      preempted[p.zone] = p.reqId;
    }
    on eRelease do (r: tZoneRelease) { Drop(r); }
    on eCancelRequest do (r: tZoneRelease) { Drop(r); }
    on eAccessDenied do (d: tAdmission) {
      var occ: tAdmission;
      if (d.cause != OCCUPIED || d.locked || !(d.zone in holding)) { return; }
      occ = holding[d.zone];
      if (occ.robotId != d.occupantId) { return; }   // monitor and controller out of step: skip
      if (OutranksN2(d.priority, d.violations, d.robotId,
                     occ.priority, occ.violations, occ.robotId)) {
        assert d.zone in preempted && preempted[d.zone] == occ.reqId,
          format("N3 violated: robot {0} (P={1}) outranks robot {2} (P={3}) in zone {4}, but no retreat was ordered",
                 d.robotId, d.priority, occ.robotId, occ.priority, d.zone);
      }
    }
  }

  fun Drop(r: tZoneRelease) {
    if (r.zone in holding && holding[r.zone].robotId == r.robotId
        && holding[r.zone].reqId == r.reqId) {
      holding -= (r.zone);
    }
  }
}

// N4 + N7: deadlines run on every tick, under V1 and V2 alike. A task whose
// deadline is d expires exactly when the d-th tick is processed, and no task is
// still open when tick d+1 is sent.
spec DeadlinesKeepRunning observes eTaskAssigned, eTick, eDeadlineExpired, eDeliveryConfirmed {
  var deadline: map[int, int];   // taskId -> deadline in ticks
  var open: set[int];            // taskIds neither expired nor delivered
  var now: int;                  // last tick sent

  start state Monitoring {
    on eTaskAssigned do (a: tAssignment) {
      deadline[a.task.taskId] = a.task.deadline;
      open += (a.task.taskId);
    }
    on eTick do (n: int) {
      var t: int;
      now = n;
      foreach (t in open) {
        assert now <= deadline[t],
          format("N7 violated: task {0} (deadline {1}) is still open at tick {2}",
                 t, deadline[t], now);
      }
    }
    on eDeadlineExpired do (e: tTaskRef) {
      assert now == deadline[e.taskId],
        format("N4 violated: task {0} expired at tick {1}, its deadline is {2}",
               e.taskId, now, deadline[e.taskId]);
      open -= (e.taskId);
    }
    on eDeliveryConfirmed do (d: tTaskRef) {
      if (d.taskId in open) { open -= (d.taskId); }
    }
  }
}

// N8: after the human leaves (eHumanExit), every controller eventually
// installs V1 again (acks it).
spec V1EventuallyRestored observes eHumanExit, eNormChangeAck {
  var v1Acks: int;

  start cold state Idle {
    on eHumanExit goto Restoring;
    ignore eNormChangeAck;
  }

  hot state Restoring {
    entry { v1Acks = 0; }
    on eNormChangeAck do (a: tNormAck) {
      if (a.version == V1) {
        v1Acks = v1Acks + 1;
        if (v1Acks == NUM_ZONES()) { goto Idle; }
      }
    }
    ignore eHumanExit;
  }
}

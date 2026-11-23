// An autonomous robot carrying one package through the corridor.
// It holds its current zone while requesting the next one (a robot is never
// between zones), retreats to a side bay when preempted (N3, N6), and abandons
// its delivery when sanctioned (N4, N7), returning empty with priority 0.
machine Robot {
  var id: int;
  var controllers: seq[machine];
  var om: machine;
  var violations: int;

  var task: tTask;
  var priority: int;
  var returning: bool;      // empty return trip after a sanction

  var route: seq[int];      // zones in travel order
  var pos: int;             // index in route of the zone held, or of the bay's zone; -1 at origin station

  var curZone: int;         // zone physically occupied, -1 if none
  var curReqId: int;        // request that won curZone
  var pendingZone: int;     // zone requested and not yet granted, -1 if none
  var pendingReqId: int;
  var bay: int;             // side bay the robot is in, -1 if none
  var nextReqId: int;

  start state Init {
    entry (cfg: tRobotConfig) {
      id = cfg.robotId;
      controllers = cfg.controllers;
      violations = cfg.violations;
      curZone = -1;
      pendingZone = -1;
      bay = -1;
      pos = -1;
      goto AtStation;
    }
  }

  state AtStation {
    on eTaskAssigned do (a: tAssignment) {
      task = a.task;
      om = a.manager;
      priority = task.priority;
      returning = false;
      route = Route(task.origin, -1);
      pos = -1;
      goto Traveling;
    }
  }

  // In a zone (or at the origin station) heading for route[pos+1].
  state Traveling {
    entry {
      if (pos == sizeof(route) - 1) {
        LeaveZone();
        if (returning) {
          send om, eReturned, id;
          goto Done;
        }
        goto Arrived;
      }
      RequestZone(route[pos + 1]);
    }

    on eGrant do (g: tZoneReply) {
      if (IsPendingGrant(g)) {
        LeaveZone();
        EnterPending();
        pos = pos + 1;
        goto Traveling;
      }
      // else: stale grant for a withdrawn request; the cancel already freed it
    }

    ignore eDeny;   // N1: wait; the controller has queued the request

    on ePreempt do (p: tZoneReply) {
      if (HoldsZone(p)) {
        Retreat();
        goto InBay;
      }
    }

    on eSanction do (s: tSanction) {
      Abandon(s);
      goto CoolingDown;
    }
  }

  // In side bay `bay`, waiting to re-enter route[pos] (== bay).
  state InBay {
    entry {
      RequestZone(route[pos]);
    }

    on eGrant do (g: tZoneReply) {
      if (IsPendingGrant(g)) {
        bay = -1;
        EnterPending();
        goto Traveling;
      }
    }

    ignore eDeny, ePreempt;   // holds no zone, so any preemption is stale

    on eSanction do (s: tSanction) {
      Abandon(s);
      goto CoolingDown;
    }
  }

  // At the destination station; the Fleet Manager decides delivered vs late.
  state Arrived {
    entry {
      send om, eArrived, (robotId = id, taskId = task.taskId);
    }
    on eDeliveryConfirmed goto Done;
    on eSanction do (s: tSanction) {   // arrival was processed after the deadline
      Abandon(s);
      goto CoolingDown;
    }
    ignore eGrant, eDeny, ePreempt;
  }

  // N4: serving COOLDOWN in a bay, or at the station it was standing at.
  state CoolingDown {
    on eCooldownOver do {
      if (bay == -1) {
        send om, eReturned, id;
        goto Done;
      }
      // Return empty, priority 0, to the origin station, re-entering at the bay's zone.
      route = Route(task.origin, bay);
      pos = 0;
      priority = 0;
      returning = true;
      goto InBay;
    }
    ignore eGrant, eDeny, ePreempt;
  }

  state Done {
    ignore eGrant, eDeny, ePreempt;
  }

  // ---------------------------------------------------------------- helpers

  // from == -1: the delivery route away from `origin`.
  // from == k:  the return route from zone k back to `origin`.
  fun Route(origin: tStation, from: int): seq[int] {
    var r: seq[int];
    var z: int;
    if (from == -1) {
      if (origin == STATION_A) {
        z = 0;
        while (z < NUM_ZONES()) { r += (sizeof(r), z); z = z + 1; }
      } else {
        z = NUM_ZONES() - 1;
        while (z >= 0) { r += (sizeof(r), z); z = z - 1; }
      }
    } else {
      z = from;
      if (origin == STATION_A) {
        while (z >= 0) { r += (sizeof(r), z); z = z - 1; }
      } else {
        while (z < NUM_ZONES()) { r += (sizeof(r), z); z = z + 1; }
      }
    }
    return r;
  }

  fun RequestZone(z: int) {
    nextReqId = nextReqId + 1;
    pendingZone = z;
    pendingReqId = nextReqId;
    send controllers[z], eRequestZone,
      (robot = this, robotId = id, reqId = pendingReqId, zone = z,
       priority = priority, violations = violations);
  }

  fun IsPendingGrant(g: tZoneReply): bool {
    return pendingZone != -1 && g.zone == pendingZone && g.reqId == pendingReqId;
  }

  fun HoldsZone(p: tZoneReply): bool {
    return curZone != -1 && p.zone == curZone && p.reqId == curReqId;
  }

  fun EnterPending() {
    curZone = pendingZone;
    curReqId = pendingReqId;
    pendingZone = -1;
    announce eZoneEntered, (robotId = id, zone = curZone);
  }

  // Leave the current zone (if any) and tell its controller.
  fun LeaveZone() {
    if (curZone != -1) {
      announce eZoneLeft, (robotId = id, zone = curZone);
      send controllers[curZone], eRelease, (robotId = id, reqId = curReqId, zone = curZone);
      curZone = -1;
    }
  }

  fun CancelPending() {
    if (pendingZone != -1) {
      send controllers[pendingZone], eCancelRequest,
        (robotId = id, reqId = pendingReqId, zone = pendingZone);
      pendingZone = -1;
    }
  }

  // N3 / N6: retreat to the side bay of the zone held. Not a sanction.
  fun Retreat() {
    bay = curZone;
    LeaveZone();
    CancelPending();
  }

  // N4 / N7: abandon the delivery and go to the adjacent side bay
  // (or stay at the station the robot is standing at).
  fun Abandon(s: tSanction) {
    assert !returning, format("robot {0} sanctioned while returning empty", id);
    assert s.taskId == task.taskId,
      format("robot {0} sanctioned for task {1}, carrying task {2}", id, s.taskId, task.taskId);
    violations = s.infractions;
    if (curZone != -1) {
      bay = curZone;
      LeaveZone();
    }
    CancelPending();
  }
}

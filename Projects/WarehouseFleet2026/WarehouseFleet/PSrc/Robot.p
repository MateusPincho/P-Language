// An autonomous robot carrying one package through the corridor.
// It holds its current zone while requesting the next one (a robot is never
// between zones), retreats to a side bay when preempted (N3, N6), and abandons
// its delivery when sanctioned (N4, N7), returning empty with priority 0.
//
// parking = false (E5) and oneDirection = true (E6) are experiment switches;
// the final model has parking = true and oneDirection = false.
machine Robot {
  var id: int;
  var controllers: seq[machine];
  var om: machine;
  var violations: int;
  var parking: bool;        // E5: false = side bays unavailable
  var oneDirection: bool;   // E6: hold the corridor direction before entering
  var dirGuard: machine;    // E6 only
  var myDir: tDirection;    // E6 only
  var hasDirection: bool;   // E6 only
  var dirPending: bool;     // E6 only

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
      parking = cfg.parking;
      oneDirection = cfg.oneDirection;
      dirGuard = cfg.dirGuard;
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
      myDir = A_TO_B;
      if (task.origin == STATION_B) { myDir = B_TO_A; }
      goto Traveling;
    }
  }

  // In a zone (or at the origin station) heading for route[pos+1].
  state Traveling {
    entry {
      if (pos == sizeof(route) - 1) {
        LeaveZone();
        ReleaseDirection();
        if (returning) {
          send om, eReturned, id;
          goto Done;
        }
        goto Arrived;
      }
      if (pos == -1 && oneDirection && !hasDirection) {
        goto AwaitDirection;                       // E6: wait for the corridor direction
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
      if (HoldsZone(p) && parking) {
        Retreat();
        goto InBay;
      }
      // parking = false (E5): no bay to retreat to, the robot stays
    }

    on eSanction do (s: tSanction) {
      if (parking || curZone == -1) {
        Abandon(s);
        goto CoolingDown;
      }
      AbandonInPlace(s);                           // E5: keep going, empty
    }

    on eCooldownOver do {
      assert !parking, format("robot {0}: cooldown over while traveling", id);
    }
  }

  // E6: waiting at the origin station, or in a bay before the return trip,
  // for the DirectionGuard to grant the travel direction.
  state AwaitDirection {
    entry {
      dirPending = true;
      send dirGuard, eDirRequest, (robot = this, robotId = id, dir = myDir);
    }
    on eDirGrant do {
      dirPending = false;
      hasDirection = true;
      if (bay != -1) { goto InBay; }
      goto Traveling;
    }
    on eSanction do (s: tSanction) {
      CancelDirection();
      Abandon(s);
      goto CoolingDown;
    }
    ignore eGrant, eDeny, ePreempt;   // holds no zone, so these are stale
  }

  // In side bay `bay`, waiting to re-enter route[pos] (== bay).
  state InBay {
    entry {
      RequestZone(route[pos]);
    }

    on eGrant do (g: tZoneReply) {
      if (IsPendingGrant(g)) {
        announce eBayLeft, (robotId = id, zone = bay);
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
        ReleaseDirection();
        send om, eReturned, id;
        goto Done;
      }
      // Return empty, priority 0, to the origin station, re-entering at the bay's zone.
      route = Route(task.origin, bay);
      pos = 0;
      priority = 0;
      returning = true;
      if (oneDirection) {                         // E6: the return trip reverses direction
        ReleaseDirection();
        myDir = Reverse(myDir);
        goto AwaitDirection;
      }
      goto InBay;
    }
    ignore eGrant, eDeny, ePreempt, eDirGrant;
  }

  state Done {
    ignore eGrant, eDeny, ePreempt, eDirGrant;
    on eCooldownOver do {
      assert !parking, format("robot {0}: cooldown over after finishing", id);
    }
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

  fun Reverse(d: tDirection): tDirection {
    if (d == A_TO_B) { return B_TO_A; }
    return A_TO_B;
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

  fun ReleaseDirection() {
    if (hasDirection) {
      send dirGuard, eDirRelease, id;
      hasDirection = false;
    }
  }

  fun CancelDirection() {
    if (dirPending) {
      send dirGuard, eDirCancel, id;
      dirPending = false;
    }
  }

  // N3 / N6: retreat to the side bay of the zone held. Not a sanction.
  fun Retreat() {
    bay = curZone;
    LeaveZone();
    announce eBayEntered, (robotId = id, zone = bay);
    CancelPending();
  }

  // N4 / N7: abandon the delivery and go to the adjacent side bay
  // (or stay at the station the robot is standing at).
  fun Abandon(s: tSanction) {
    var where: int;
    CheckSanction(s);
    violations = s.infractions;
    where = curZone;
    if (where == -1) { where = bay; }
    announce eTaskAbandoned, (robotId = id, taskId = s.taskId, where = where);
    if (curZone != -1) {
      bay = curZone;
      LeaveZone();
      announce eBayEntered, (robotId = id, zone = bay);
    }
    CancelPending();
  }

  // E5 (parking = false): abandon the delivery but keep the zone and the
  // pending request, and carry on to the end of the route, empty.
  fun AbandonInPlace(s: tSanction) {
    CheckSanction(s);
    violations = s.infractions;
    announce eTaskAbandoned, (robotId = id, taskId = s.taskId, where = curZone);
    priority = 0;
    returning = true;
  }

  fun CheckSanction(s: tSanction) {
    assert !returning, format("robot {0} sanctioned while returning empty", id);
    assert s.taskId == task.taskId,
      format("robot {0} sanctioned for task {1}, carrying task {2}", id, s.taskId, task.taskId);
  }
}

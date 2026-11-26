// The Fleet Manager: assigns tasks, tracks deadlines and cooldowns per robot,
// applies sanctions (N4). In the final model (remedy = NO_REMEDY) it has no
// notion of the norm version, so deadlines run identically under V1 and V2 (N7).
//
// remedy is the E7 switch. SUSPEND: the coordinator tells the Fleet Manager
// when V2 starts and ends, and no deadline counts down meanwhile.
// SUSPEND_EXCUSE: in addition, a deadline that expires for a task that was
// open during a V2 episode is excused instead of sanctioned.
machine ObligationManager {
  var robots: map[int, machine];
  var tasks: map[int, tTask];          // robotId -> its task
  var remaining: map[int, int];        // robotId -> ticks left on the deadline
  var active: map[int, bool];          // robotId -> obligation still open
  var cooldownLeft: map[int, int];     // robotId -> cooldown ticks left (0 = none running)
  var infractions: map[int, int];
  var finished: set[int];              // delivered, or back at a station after a sanction
  var cooldown: int;
  var clock: machine;
  var remedy: tRemedy;                 // E7
  var v2Active: bool;                  // E7: as told by the coordinator
  var overlapped: map[int, bool];      // E7: task was open during a V2 episode
  var excused: map[int, bool];         // E7: deadline excused, no longer counted

  start state Init {
    entry (cfg: tOMConfig) {
      var t: tTask;
      var i: int;
      robots = cfg.robots;
      cooldown = cfg.cooldown;
      infractions = cfg.infractions;
      remedy = cfg.remedy;
      i = 0;
      while (i < sizeof(cfg.tasks)) {
        t = cfg.tasks[i];
        tasks[t.robotId] = t;
        remaining[t.robotId] = t.deadline;
        active[t.robotId] = true;
        cooldownLeft[t.robotId] = 0;
        overlapped[t.robotId] = false;
        excused[t.robotId] = false;
        send robots[t.robotId], eTaskAssigned, (task = t, manager = this);
        i = i + 1;
      }
      clock = new Clock(this);
      goto Supervising;
    }
  }

  state Supervising {
    on eTick do OnTick;

    // N4: the deadline expired. Cancel the delivery, count the infraction,
    // and send the robot to cool down.
    on eDeadlineExpired do (e: tTaskRef) {
      infractions[e.robotId] = infractions[e.robotId] + 1;
      cooldownLeft[e.robotId] = cooldown;
      send robots[e.robotId], eSanction,
        (robotId = e.robotId, taskId = e.taskId, cooldown = cooldown,
         infractions = infractions[e.robotId]);
    }

    on eArrived do (a: tTaskRef) {
      if (active[a.robotId]) {
        active[a.robotId] = false;
        send robots[a.robotId], eDeliveryConfirmed, a;
        Finish(a.robotId);
      }
      // else: arrived after the deadline; the sanction is already on its way
    }

    on eReturned do (rid: int) {
      Finish(rid);
    }

    on eAdaptationNotice do OnAdaptationNotice;   // E7 only
  }

  state AllDone {
    ignore eTick;   // a tick may be in flight when the clock is stopped
    on eAdaptationNotice do OnAdaptationNotice;   // E7: the human may still be working
  }

  fun OnTick(now: int) {
    var rid: int;
    foreach (rid in keys(tasks)) {
      if (active[rid] && !excused[rid]) {
        if (!(remedy != NO_REMEDY && v2Active)) {       // E7: suspended during V2
          remaining[rid] = remaining[rid] - 1;
        }
        if (remaining[rid] <= 0) {
          if (remedy == SUSPEND_EXCUSE && overlapped[rid]) {
            excused[rid] = true;                          // E7: no sanction, delivery continues
            announce eObligationExcused, (robotId = rid, taskId = tasks[rid].taskId);
          } else {
            active[rid] = false;
            send this, eDeadlineExpired, (robotId = rid, taskId = tasks[rid].taskId);
          }
        }
      }
      if (cooldownLeft[rid] > 0) {
        cooldownLeft[rid] = cooldownLeft[rid] - 1;
        if (cooldownLeft[rid] == 0) {
          send robots[rid], eCooldownOver, rid;
        }
      }
    }
    send clock, eTickAck;
  }

  // E7: the coordinator announces V2 before any controller installs it (and
  // waits for this ack), and announces V1 after every controller restored it.
  fun OnAdaptationNotice(n: tNormChange) {
    var rid: int;
    v2Active = (n.version == V2);
    if (n.version == V2) {
      foreach (rid in keys(tasks)) {
        if (active[rid]) { overlapped[rid] = true; }
      }
      send n.coord, eAdaptationNoticeAck;
    }
  }

  fun Finish(rid: int) {
    finished += (rid);
    if (sizeof(finished) == sizeof(tasks)) {
      send clock, eStopClock;
      goto AllDone;
    }
  }
}

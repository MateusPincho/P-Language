// The Fleet Manager: assigns tasks, tracks deadlines and cooldowns per robot,
// applies sanctions (N4). It has no notion of the norm version, so deadlines
// run identically under V1 and V2 (N7).
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

  start state Init {
    entry (cfg: tOMConfig) {
      var t: tTask;
      var i: int;
      robots = cfg.robots;
      cooldown = cfg.cooldown;
      infractions = cfg.infractions;
      i = 0;
      while (i < sizeof(cfg.tasks)) {
        t = cfg.tasks[i];
        tasks[t.robotId] = t;
        remaining[t.robotId] = t.deadline;
        active[t.robotId] = true;
        cooldownLeft[t.robotId] = 0;
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
  }

  state AllDone {
    ignore eTick;   // a tick may be in flight when the clock is stopped
  }

  fun OnTick(now: int) {
    var rid: int;
    foreach (rid in keys(tasks)) {
      if (active[rid]) {
        remaining[rid] = remaining[rid] - 1;
        if (remaining[rid] <= 0) {
          active[rid] = false;
          send this, eDeadlineExpired, (robotId = rid, taskId = tasks[rid].taskId);
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

  fun Finish(rid: int) {
    finished += (rid);
    if (sizeof(finished) == sizeof(tasks)) {
      send clock, eStopClock;
      goto AllDone;
    }
  }
}

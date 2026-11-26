// E6 only (remedy 1, one travel direction at a time). Not created in the final
// model. A robot must hold the corridor direction before it enters the corridor
// from a station, and before it starts a return trip from a side bay. Robots
// travelling the same way share it; the opposite direction waits until the
// corridor (zones and bays) holds nobody with the current direction.
machine DirectionGuard {
  var current: tDirection;
  var holders: set[int];                 // robotIds holding the current direction
  var queue: map[int, tDirRequest];      // robotId -> waiting request

  start state Serving {
    on eDirRequest do (r: tDirRequest) {
      if (sizeof(holders) == 0 || r.dir == current) {
        Grant(r);
      } else {
        queue[r.robotId] = r;
        announce eDirectionDenied, r.robotId;
      }
    }
    on eDirRelease do (rid: int) { Release(rid); }
    // A robot sanctioned while waiting withdraws; if the grant was already
    // sent, the withdrawal counts as a release.
    on eDirCancel do (rid: int) {
      if (rid in queue) {
        queue -= (rid);
      } else {
        Release(rid);
      }
    }
  }

  fun Grant(r: tDirRequest) {
    current = r.dir;
    holders += (r.robotId);
    send r.robot, eDirGrant;
  }

  fun Release(rid: int) {
    var waiting: seq[int];
    var k: int;
    var dir: tDirection;
    var found: bool;
    if (!(rid in holders)) { return; }
    holders -= (rid);
    if (sizeof(holders) > 0) { return; }
    // Corridor empty: grant every queued robot of one direction.
    foreach (k in keys(queue)) {
      if (!found) { dir = queue[k].dir; found = true; }
      if (queue[k].dir == dir) { waiting += (sizeof(waiting), k); }
    }
    foreach (k in waiting) {
      Grant(queue[k]);
      queue -= (k);
    }
  }
}

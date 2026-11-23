// One per zone. Distributed regimentation: admits or denies robots from its
// local occupancy and the norm version it currently holds (N1, N2, N3, N5, N6).
machine ZoneController {
  var zone: int;
  var version: tNormVersion;
  var occupied: bool;
  var occ: tRequestZone;                  // the request that won the zone
  var waiters: map[int, tRequestZone];    // robotId -> queued request
  var preempting: bool;                   // an ePreempt to the occupant is outstanding
  var awaitingClear: bool;                // owe the coordinator a V2 ack once empty (N6)
  var coord: machine;

  start state Init {
    entry (z: int) {
      zone = z;
      version = V1;
      goto Serving;
    }
  }

  state Serving {
    on eRequestZone do OnRequest;

    on eRelease do (r: tZoneRelease) {
      if (IsOccupant(r)) { FreeZone(); }
    }

    // The robot withdrew: either a queued request, or a grant it never used
    // (it retreated or was sanctioned before the grant reached it).
    on eCancelRequest do (r: tZoneRelease) {
      if (r.robotId in waiters && waiters[r.robotId].reqId == r.reqId) {
        waiters -= (r.robotId);
      } else if (IsOccupant(r)) {
        FreeZone();
      }
    }

    on eNormChange do OnNormChange;
  }

  // N5: zone 1 under V2 admits nobody.
  fun Locked(): bool {
    return version == V2 && zone == HUMAN_ZONE();
  }

  fun IsOccupant(r: tZoneRelease): bool {
    return occupied && occ.robotId == r.robotId && occ.reqId == r.reqId;
  }

  // N2: does request a win over request b?
  fun Wins(a: tRequestZone, b: tRequestZone): bool {
    if (a.priority != b.priority) { return a.priority > b.priority; }
    if (a.violations != b.violations) { return a.violations < b.violations; }
    return a.robotId < b.robotId;   // R1 wins the final tie
  }

  fun OnRequest(req: tRequestZone) {
    // A robot withdraws before it re-requests, and messages between a pair are
    // FIFO, so the occupant can never be asking for its own zone again.
    assert !(occupied && occ.robotId == req.robotId),
      format("zone {0}: request {1} from robot {2}, which already holds the zone with request {3}",
             zone, req.reqId, req.robotId, occ.reqId);

    if (Locked()) {                                   // N5
      Queue(req);
      return;
    }
    if (!occupied) {                                  // N1: free -> grant
      Grant(req);
      return;
    }
    Queue(req);                                       // N1: occupied -> deny, wait
    if (!preempting && Wins(req, occ)) {              // N3
      preempting = true;
      send occ.robot, ePreempt, (zone = zone, reqId = occ.reqId);
    }
  }

  fun Queue(req: tRequestZone) {
    waiters[req.robotId] = req;
    send req.robot, eDeny, (zone = zone, reqId = req.reqId);
  }

  fun Grant(req: tRequestZone) {
    occupied = true;
    occ = req;
    preempting = false;
    if (req.robotId in waiters) { waiters -= (req.robotId); }
    send req.robot, eGrant, (zone = zone, reqId = req.reqId);
  }

  fun FreeZone() {
    occupied = false;
    preempting = false;
    if (Locked()) {
      if (awaitingClear) {                            // N6: zone 1 is now empty
        awaitingClear = false;
        send coord, eNormChangeAck, (zone = zone, version = V2);
      }
    } else {
      GrantNext();
    }
  }

  // N2 among everyone queued.
  fun GrantNext() {
    var best: tRequestZone;
    var found: bool;
    var rid: int;
    if (occupied || Locked()) { return; }
    foreach (rid in keys(waiters)) {
      if (!found || Wins(waiters[rid], best)) {
        best = waiters[rid];
        found = true;
      }
    }
    if (found) { Grant(best); }
  }

  fun OnNormChange(n: tNormChange) {
    coord = n.coord;
    version = n.version;
    if (Locked()) {
      if (!occupied) {
        send coord, eNormChangeAck, (zone = zone, version = version);
      } else {
        awaitingClear = true;
        if (!preempting) {                            // N6: regardless of priority
          preempting = true;
          send occ.robot, ePreempt, (zone = zone, reqId = occ.reqId);
        }
      }
    } else {
      send coord, eNormChangeAck, (zone = zone, version = version);
      GrantNext();
    }
  }
}

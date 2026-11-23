// Safety properties. 1-3 are the PDF's (slide 16); NoDoubleOutcome is ours.

// Property 1 (PDF): there are never two robots in the same zone.
spec ZoneMutualExclusion observes eZoneEntered, eZoneLeft {
  var occupant: map[int, int];   // zone -> robotId

  start state Monitoring {
    on eZoneEntered do (e: tRobotZone) {
      assert !(e.zone in occupant),
        format("N1 violated: robot {0} entered zone {1}, already occupied (occupancy {2})",
               e.robotId, e.zone, occupant);
      occupant[e.zone] = e.robotId;
    }
    on eZoneLeft do (e: tRobotZone) {
      assert e.zone in occupant && occupant[e.zone] == e.robotId,
        format("robot {0} left zone {1}, which it was not recorded in", e.robotId, e.zone);
      occupant -= (e.zone);
    }
  }
}

// Property 2 (PDF): no robot is in Zone 1 while the human is inside.
// Observes eZoneLeft too (ours): needed to know Zone 1 is empty when the human enters.
spec NoRobotWithHuman observes eHumanEnter, eHumanExit, eZoneEntered, eZoneLeft {
  var robotsInZone: set[int];
  var humanInside: bool;

  start state Monitoring {
    on eZoneEntered do (e: tRobotZone) {
      if (e.zone == HUMAN_ZONE()) {
        assert !humanInside,
          format("N5 violated: robot {0} entered zone {1} while the human is inside",
                 e.robotId, e.zone);
        robotsInZone += (e.robotId);
      }
    }
    on eZoneLeft do (e: tRobotZone) {
      if (e.zone == HUMAN_ZONE()) {
        robotsInZone -= (e.robotId);
      }
    }
    on eHumanEnter do {
      assert sizeof(robotsInZone) == 0,
        format("N6 violated: the human entered zone {0} while robots {1} are inside",
               HUMAN_ZONE(), robotsInZone);
      humanInside = true;
    }
    on eHumanExit do {
      humanInside = false;
    }
  }
}

// Property 3 (PDF): a sanction occurs only after a deadline has expired,
// and at most once per expiry.
spec SanctionOnlyAfterExpiry observes eDeadlineExpired, eSanction {
  var expired: set[int];   // taskIds whose deadline expired and are not yet sanctioned

  start state Monitoring {
    on eDeadlineExpired do (e: tTaskRef) {
      expired += (e.taskId);
    }
    on eSanction do (s: tSanction) {
      assert s.taskId in expired,
        format("N4 violated: robot {0} sanctioned for task {1} without an expired deadline",
               s.robotId, s.taskId);
      expired -= (s.taskId);
    }
  }
}

// (ours) A task is never both delivered and sanctioned, and neither happens twice.
spec NoDoubleOutcome observes eDeliveryConfirmed, eSanction {
  var delivered: set[int];
  var sanctioned: set[int];

  start state Monitoring {
    on eDeliveryConfirmed do (d: tTaskRef) {
      assert !(d.taskId in delivered) && !(d.taskId in sanctioned),
        format("task {0} confirmed delivered but already delivered={1} sanctioned={2}",
               d.taskId, d.taskId in delivered, d.taskId in sanctioned);
      delivered += (d.taskId);
    }
    on eSanction do (s: tSanction) {
      assert !(s.taskId in delivered) && !(s.taskId in sanctioned),
        format("task {0} sanctioned but already delivered={1} sanctioned={2}",
               s.taskId, s.taskId in delivered, s.taskId in sanctioned);
      sanctioned += (s.taskId);
    }
  }
}

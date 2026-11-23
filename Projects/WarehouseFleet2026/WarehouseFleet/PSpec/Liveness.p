// Liveness properties (ours). A run must not end in a hot state.

// Every assigned task is eventually confirmed delivered or sanctioned.
spec EveryTaskResolved observes eTaskAssigned, eDeliveryConfirmed, eSanction {
  var open: set[int];   // taskIds

  start cold state Idle {
    on eTaskAssigned goto Pending with Add;
  }

  hot state Pending {
    on eTaskAssigned do Add;
    on eDeliveryConfirmed do (d: tTaskRef) { Resolve(d.taskId); }
    on eSanction do (s: tSanction) { Resolve(s.taskId); }
  }

  fun Add(a: tAssignment) {
    open += (a.task.taskId);
  }

  fun Resolve(taskId: int) {
    assert taskId in open, format("task {0} resolved but was never open", taskId);
    open -= (taskId);
    if (sizeof(open) == 0) { goto Idle; }
  }
}

// Every robot with a task eventually settles: delivered, or back at a station
// after a sanction. Catches a deadlock on the empty return trip.
spec EveryRobotSettles observes eTaskAssigned, eDeliveryConfirmed, eReturned {
  var unsettled: set[int];   // robotIds

  start cold state Idle {
    on eTaskAssigned goto Pending with Add;
  }

  hot state Pending {
    on eTaskAssigned do Add;
    on eDeliveryConfirmed do (d: tTaskRef) { Settle(d.robotId); }
    on eReturned do (rid: int) { Settle(rid); }
  }

  fun Add(a: tAssignment) {
    unsettled += (a.task.robotId);
  }

  fun Settle(rid: int) {
    assert rid in unsettled, format("robot {0} settled twice", rid);
    unsettled -= (rid);
    if (sizeof(unsettled) == 0) { goto Idle; }
  }
}

// After the human asks for Zone 1, the human eventually enters: the N6
// evacuation cannot hang.
spec HumanEventuallyEnters observes eHumanRequest, eHumanEnter {
  start cold state Idle {
    on eHumanRequest goto Waiting;
    ignore eHumanEnter;
  }

  hot state Waiting {
    on eHumanEnter goto Idle;
    ignore eHumanRequest;
  }
}

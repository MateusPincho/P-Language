// E3: sanction fairness (the kit's F1, refined).
//
// Every delay a robot suffers is reported with its cause by the controller that
// caused it (eAccessDenied, ePreemptIssued) or by the DirectionGuard (E6):
//   regulation-caused: CLOSED (N5 lockout), EVACUATED (N6), DIRECTION (E6)
//   traffic-caused:    OCCUPIED (N1, the other robot holds the zone),
//                      OUTRANKED (N3, the other robot's package wins)
// A delay counts against a task if it happens while that task's deadline is
// still running: from eTaskAssigned until the deadline expires
// (eDeadlineExpired), or the robot abandons the delivery (eTaskAbandoned) or
// has it confirmed. A delay after the expiry cannot have caused the sanction;
// counting it was a false alarm found in E7 (see EXPERIMENTS.md, E3).
//
// Each monitor fails when a sanctioned task also suffered a delay of its class.
// The verdict does not depend on the order in which the sanction and the delay
// are observed: it is checked when the second of the two arrives.
//
// Like the kit's F1, these flag CANDIDATE unfair sanctions. A delay of a given
// class during the task is not proof that this delay made the robot miss its
// deadline; the monitor cannot establish causation.

spec NoRegulationCausedSanction observes eTaskAssigned, eAccessDenied, ePreemptIssued,
                                         eDirectionDenied, eSanction, eTaskAbandoned,
                                         eDeliveryConfirmed, eDeadlineExpired {
  var taskOf: map[int, int];            // robotId -> its open task
  var delayed: map[int, tDelayCause];   // taskId -> a regulation cause it suffered
  var sanctioned: set[int];

  start state Monitoring {
    on eTaskAssigned do (a: tAssignment) { taskOf[a.task.robotId] = a.task.taskId; }
    on eAccessDenied do (d: tAdmission) { Note(d.robotId, d.cause); }
    on ePreemptIssued do (p: tPreemption) { Note(p.robotId, p.cause); }
    on eDirectionDenied do (rid: int) { Note(rid, DIRECTION); }
    on eSanction do (s: tSanction) {
      sanctioned += (s.taskId);
      Check(s.taskId);
    }
    on eDeadlineExpired do (e: tTaskRef) { Close(e.robotId); }
    on eTaskAbandoned do (a: tAbandon) { Close(a.robotId); }
    on eDeliveryConfirmed do (d: tTaskRef) { Close(d.robotId); }
  }

  fun Note(rid: int, c: tDelayCause) {
    var t: int;
    if (!(rid in taskOf) || !IsRegulationCause(c)) { return; }
    t = taskOf[rid];
    delayed[t] = c;
    Check(t);
  }

  fun Close(rid: int) {
    if (rid in taskOf) { taskOf -= (rid); }
  }

  fun Check(t: int) {
    assert !(t in sanctioned && t in delayed),
      format("F1 (regulation-caused): task {0} was sanctioned after a delay imposed by the regulation: {1}",
             t, CauseName(delayed[t]));
  }
}

spec NoTrafficCausedSanction observes eTaskAssigned, eAccessDenied, ePreemptIssued,
                                      eSanction, eTaskAbandoned, eDeliveryConfirmed, eDeadlineExpired {
  var taskOf: map[int, int];
  var delayed: map[int, tDelayCause];   // taskId -> a traffic cause it suffered
  var sanctioned: set[int];

  start state Monitoring {
    on eTaskAssigned do (a: tAssignment) { taskOf[a.task.robotId] = a.task.taskId; }
    on eAccessDenied do (d: tAdmission) { Note(d.robotId, d.cause); }
    on ePreemptIssued do (p: tPreemption) { Note(p.robotId, p.cause); }
    on eSanction do (s: tSanction) {
      sanctioned += (s.taskId);
      Check(s.taskId);
    }
    on eDeadlineExpired do (e: tTaskRef) { Close(e.robotId); }
    on eTaskAbandoned do (a: tAbandon) { Close(a.robotId); }
    on eDeliveryConfirmed do (d: tTaskRef) { Close(d.robotId); }
  }

  fun Note(rid: int, c: tDelayCause) {
    var t: int;
    if (!(rid in taskOf) || IsRegulationCause(c)) { return; }
    t = taskOf[rid];
    delayed[t] = c;
    Check(t);
  }

  fun Close(rid: int) {
    if (rid in taskOf) { taskOf -= (rid); }
  }

  fun Check(t: int) {
    assert !(t in sanctioned && t in delayed),
      format("F1 (traffic-caused): task {0} was sanctioned after a delay caused by the other robot: {1}",
             t, CauseName(delayed[t]));
  }
}

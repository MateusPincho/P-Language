// Test environment: builds the corridor system from a scenario.
// R1 starts at Station A carrying A -> B; R2 starts at Station B carrying
// B -> A, so they meet head-on in the corridor. E8 adds R3 at Station A.
// `variant` selects an experiment; BASELINE() is the final model.

type tScenario = (p1: int, d1: int, v1: int,      // R1: priority, deadline, initial infractions
                  p2: int, d2: int, v2: int,      // R2: same
                  p3: int, d3: int, v3: int,      // R3 (only when nRobots == 3)
                  nRobots: int,
                  cooldown: int,
                  withHuman: bool, naive: bool,
                  humanMaxDelay: int, humanMaxStay: int,
                  variant: tVariant);

machine FleetScenario {
  start state Init {
    entry (s: tScenario) {
      var controllers: seq[machine];
      var coord: machine;
      var om: machine;
      var dirGuard: machine;
      var robots: map[int, machine];
      var tasks: seq[tTask];
      var infractions: map[int, int];
      var z: int;

      z = 0;
      while (z < NUM_ZONES()) {
        controllers += (z, new ZoneController((zone = z, blockAll = s.variant.blockAll)));
        z = z + 1;
      }
      if (s.variant.oneDirection) {
        dirGuard = new DirectionGuard();
      }

      robots[R1()] = NewRobot(R1(), controllers, s.v1, s.variant, dirGuard);
      robots[R2()] = NewRobot(R2(), controllers, s.v2, s.variant, dirGuard);
      infractions[R1()] = s.v1;
      infractions[R2()] = s.v2;
      tasks += (0, (taskId = 1, robotId = R1(), priority = s.p1, deadline = s.d1,
                    origin = STATION_A, dest = STATION_B));
      tasks += (1, (taskId = 2, robotId = R2(), priority = s.p2, deadline = s.d2,
                    origin = STATION_B, dest = STATION_A));
      if (s.nRobots == 3) {
        robots[3] = NewRobot(3, controllers, s.v3, s.variant, dirGuard);
        infractions[3] = s.v3;
        tasks += (2, (taskId = 3, robotId = 3, priority = s.p3, deadline = s.d3,
                      origin = STATION_A, dest = STATION_B));
      }

      om = new ObligationManager((robots = robots, tasks = tasks, cooldown = s.cooldown,
                                  infractions = infractions, remedy = s.variant.remedy));
      coord = new AdaptationCoordinator((controllers = controllers, naive = s.naive,
                                         blockAll = s.variant.blockAll,
                                         abortable = s.variant.abortable,
                                         notifyManager = (s.variant.remedy != NO_REMEDY),
                                         manager = om));

      if (s.withHuman) {
        new HumanPicker((coord = coord, maxDelay = s.humanMaxDelay, maxStay = s.humanMaxStay));
      }
    }
  }

  fun NewRobot(rid: int, controllers: seq[machine], v: int, variant: tVariant,
               dirGuard: machine): machine {
    return new Robot((robotId = rid, controllers = controllers, violations = v,
                      parking = variant.parking, oneDirection = variant.oneDirection,
                      dirGuard = dirGuard));
  }
}

// ---------------------------------------------------------------- scenarios

// Slides 4-6: head-on conflict, R2's package (P=8) outranks R1's (P=4).
fun HeadOn(withHuman: bool, variant: tVariant): tScenario {
  return (p1 = 4, d1 = 15, v1 = 0, p2 = 8, d2 = 15, v2 = 0, p3 = 1, d3 = 15, v3 = 0,
          nRobots = 2, cooldown = 2, withHuman = withHuman, naive = false,
          humanMaxDelay = 10, humanMaxStay = 10, variant = variant);
}

// Every task attribute chosen by the checker: priority 1-10, deadline 1-15,
// initial infractions 0-1 (so N2's infraction tiebreak and R1 tiebreak are reachable).
fun RandomTasks(variant: tVariant): tScenario {
  return (p1 = choose(10) + 1, d1 = choose(15) + 1, v1 = choose(2),
          p2 = choose(10) + 1, d2 = choose(15) + 1, v2 = choose(2),
          p3 = 1, d3 = 15, v3 = 0,
          nRobots = 2, cooldown = 2, withHuman = true, naive = false,
          humanMaxDelay = 10, humanMaxStay = 10, variant = variant);
}

// Slide 13: short deadlines and a long human stay, so a robot waiting for the
// locked Zone 1 can run out of time under V2.
fun ShortDeadlines(variant: tVariant): tScenario {
  return (p1 = choose(10) + 1, d1 = choose(4) + 3, v1 = 0,
          p2 = choose(10) + 1, d2 = choose(4) + 3, v2 = 0,
          p3 = 1, d3 = 15, v3 = 0,
          nRobots = 2, cooldown = 2, withHuman = true, naive = false,
          humanMaxDelay = 3, humanMaxStay = 20, variant = variant);
}

fun WithVariant(blockAll: bool, parking: bool, remedy: tRemedy,
                oneDirection: bool, abortable: bool): tVariant {
  return (blockAll = blockAll, parking = parking, remedy = remedy,
          oneDirection = oneDirection, abortable = abortable);
}

// ---------------------------------------------------------------- drivers
// One driver per test case in TestScript.p.

// Baseline (E1, E2, cover) -- the original five tests.
machine TestHeadOnV1 {
  start state Init { entry { new FleetScenario(HeadOn(false, BASELINE())); } }
}
machine TestHumanAdaptation {
  start state Init { entry { new FleetScenario(HeadOn(true, BASELINE())); } }
}
machine TestRandomTasks {
  start state Init { entry { new FleetScenario(RandomTasks(BASELINE())); } }
}
machine TestNaiveAdaptation {
  start state Init {
    entry {
      var s: tScenario;
      s = HeadOn(true, BASELINE());
      s.naive = true;
      new FleetScenario(s);
    }
  }
}
machine TestCoverSanctionInV2 {
  start state Init {
    entry {
      new FleetScenario((p1 = 4, d1 = choose(4) + 3, v1 = 0, p2 = 8, d2 = choose(4) + 3, v2 = 0,
                         p3 = 1, d3 = 15, v3 = 0, nRobots = 2, cooldown = 2,
                         withHuman = true, naive = false, humanMaxDelay = 3, humanMaxStay = 20,
                         variant = BASELINE()));
    }
  }
}

// E3: sanction fairness, on the final model with short deadlines.
machine TestFairness {
  start state Init { entry { new FleetScenario(ShortDeadlines(BASELINE())); } }
}

// E3, traffic only: the same short deadlines with no human, so no regulation
// delay (CLOSED/EVACUATED) can occur. Added after the first E3 run, whose
// traffic trace also contained a CLOSED delay.
machine TestFairnessNoHuman {
  start state Init {
    entry {
      var s: tScenario;
      s = ShortDeadlines(BASELINE());
      s.withHuman = false;
      new FleetScenario(s);
    }
  }
}

// E4: every controller locks and evacuates while V2 is installed.
machine TestE4BlockAll {
  start state Init {
    entry { new FleetScenario(RandomTasks(WithVariant(true, true, NO_REMEDY, false, false))); }
  }
}
// E4 without side bays.
machine TestE4BlockAllNoParking {
  start state Init {
    entry { new FleetScenario(RandomTasks(WithVariant(true, false, NO_REMEDY, false, false))); }
  }
}
// E5: no side bays (only Zone 1 locks, as in the final model).
machine TestE5NoParking {
  start state Init {
    entry { new FleetScenario(RandomTasks(WithVariant(false, false, NO_REMEDY, false, false))); }
  }
}

// E6: one travel direction at a time.
machine TestE6OneDirection {
  start state Init {
    entry { new FleetScenario(RandomTasks(WithVariant(false, true, NO_REMEDY, true, false))); }
  }
}
machine TestE6Fairness {
  start state Init {
    entry { new FleetScenario(ShortDeadlines(WithVariant(false, true, NO_REMEDY, true, false))); }
  }
}

// E7: deadlines suspended during V2; with and without excusal.
machine TestE7Suspend {
  start state Init {
    entry { new FleetScenario(ShortDeadlines(WithVariant(false, true, SUSPEND, false, false))); }
  }
}
machine TestE7SuspendExcuse {
  start state Init {
    entry { new FleetScenario(ShortDeadlines(WithVariant(false, true, SUSPEND_EXCUSE, false, false))); }
  }
}
machine TestE7SuspendExcuseRandom {
  start state Init {
    entry { new FleetScenario(RandomTasks(WithVariant(false, true, SUSPEND_EXCUSE, false, false))); }
  }
}

// E8: three robots (R3 also leaves Station A).
machine TestE8ThreeRobots {
  start state Init {
    entry {
      var s: tScenario;
      s = RandomTasks(BASELINE());
      s.nRobots = 3;
      s.p3 = choose(10) + 1;
      s.d3 = choose(15) + 1;
      s.v3 = choose(2);
      new FleetScenario(s);
    }
  }
}

// E9: the coordinator may time out and abort the switch.
machine TestE9Abort {
  start state Init {
    entry { new FleetScenario(RandomTasks(WithVariant(false, true, NO_REMEDY, false, true))); }
  }
}

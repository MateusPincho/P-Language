// Test environment: builds the corridor system from a scenario.
// R1 starts at Station A carrying A -> B; R2 starts at Station B carrying
// B -> A, so they meet head-on in the corridor.

type tScenario = (p1: int, d1: int, v1: int,      // R1: priority, deadline, initial infractions
                  p2: int, d2: int, v2: int,      // R2: same
                  cooldown: int,
                  withHuman: bool, naive: bool,
                  humanMaxDelay: int, humanMaxStay: int);

machine FleetScenario {
  start state Init {
    entry (s: tScenario) {
      var controllers: seq[machine];
      var coord: machine;
      var robots: map[int, machine];
      var tasks: seq[tTask];
      var infractions: map[int, int];
      var z: int;

      z = 0;
      while (z < NUM_ZONES()) {
        controllers += (z, new ZoneController(z));
        z = z + 1;
      }
      coord = new AdaptationCoordinator((controllers = controllers, naive = s.naive));

      robots[R1()] = new Robot((robotId = R1(), controllers = controllers, violations = s.v1));
      robots[R2()] = new Robot((robotId = R2(), controllers = controllers, violations = s.v2));
      infractions[R1()] = s.v1;
      infractions[R2()] = s.v2;

      tasks += (0, (taskId = 1, robotId = R1(), priority = s.p1, deadline = s.d1,
                    origin = STATION_A, dest = STATION_B));
      tasks += (1, (taskId = 2, robotId = R2(), priority = s.p2, deadline = s.d2,
                    origin = STATION_B, dest = STATION_A));

      new ObligationManager((robots = robots, tasks = tasks, cooldown = s.cooldown,
                             infractions = infractions));

      if (s.withHuman) {
        new HumanPicker((coord = coord, maxDelay = s.humanMaxDelay, maxStay = s.humanMaxStay));
      }
    }
  }
}

// Slides 4-6: head-on conflict under V1 only. R2's package (P=8) outranks R1's (P=4).
machine TestHeadOnV1 {
  start state Init {
    entry {
      new FleetScenario((p1 = 4, d1 = 15, v1 = 0, p2 = 8, d2 = 15, v2 = 0, cooldown = 2,
                         withHuman = false, naive = false, humanMaxDelay = 0, humanMaxStay = 1));
    }
  }
}

// Slides 9-10: the same trip, with the human picker requesting Zone 1 at a
// nondeterministic moment and staying a nondeterministic time.
machine TestHumanAdaptation {
  start state Init {
    entry {
      new FleetScenario((p1 = 4, d1 = 15, v1 = 0, p2 = 8, d2 = 15, v2 = 0, cooldown = 2,
                         withHuman = true, naive = false, humanMaxDelay = 10, humanMaxStay = 10));
    }
  }
}

// Every task attribute chosen by the checker: priority 1-10, deadline 1-15,
// initial infractions 0-1 (so N2's infraction tiebreak and R1 tiebreak are reachable).
machine TestRandomTasks {
  start state Init {
    entry {
      new FleetScenario((p1 = choose(10) + 1, d1 = choose(15) + 1, v1 = choose(2),
                         p2 = choose(10) + 1, d2 = choose(15) + 1, v2 = choose(2),
                         cooldown = 2, withHuman = true, naive = false,
                         humanMaxDelay = 10, humanMaxStay = 10));
    }
  }
}

// Bug injection: the coordinator admits the human without waiting for the
// Zone 1 evacuation ack.
machine TestNaiveAdaptation {
  start state Init {
    entry {
      new FleetScenario((p1 = 4, d1 = 15, v1 = 0, p2 = 8, d2 = 15, v2 = 0, cooldown = 2,
                         withHuman = true, naive = true, humanMaxDelay = 10, humanMaxStay = 10));
    }
  }
}

// Slide 13: short deadlines and a long human stay, so a robot waiting for
// the locked Zone 1 can run out of time under V2.
machine TestCoverSanctionInV2 {
  start state Init {
    entry {
      new FleetScenario((p1 = 4, d1 = choose(4) + 3, v1 = 0, p2 = 8, d2 = choose(4) + 3, v2 = 0,
                         cooldown = 2, withHuman = true, naive = false,
                         humanMaxDelay = 3, humanMaxStay = 20));
    }
  }
}

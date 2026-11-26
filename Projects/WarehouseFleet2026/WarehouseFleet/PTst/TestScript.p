// Test cases. Every "Prediction" was written BEFORE the test was first run;
// the observed results, with schedule counts, are in ../../EXPERIMENTS.md.
// Experiment numbers (E0-E10) follow the assignment; EXPERIMENTS.md maps each
// one to this model.

module Fleet = { FleetScenario, Robot, ZoneController, ObligationManager,
                 AdaptationCoordinator, HumanPicker, Clock, DirectionGuard };

// =================================================================== E1
// Baseline: the final model. Every safety and liveness monitor attached.

// Prediction: no bug. N1-N4 under V1 only.
test tcHeadOnV1 [main=TestHeadOnV1]:
  assert ZoneMutualExclusion, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         PriorityRespected, EmptyRobotHasPriorityZero, OutrankedOccupantPreempted,
         DeadlinesKeepRunning, EveryTaskResolved, EveryRobotSettles
  in (union Fleet, { TestHeadOnV1 });

// Prediction: no bug. N1-N8 with the V1 -> V2 -> V1 adaptation.
test tcHumanAdaptation [main=TestHumanAdaptation]:
  assert ZoneMutualExclusion, NoRobotWithHuman, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         PriorityRespected, EmptyRobotHasPriorityZero, OutrankedOccupantPreempted,
         DeadlinesKeepRunning, EveryTaskResolved, EveryRobotSettles,
         HumanEventuallyEnters, V1EventuallyRestored
  in (union Fleet, { TestHumanAdaptation });

// Prediction: no bug. Same as above over chosen priorities, deadlines and
// initial infractions.
test tcRandomTasks [main=TestRandomTasks]:
  assert ZoneMutualExclusion, NoRobotWithHuman, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         PriorityRespected, EmptyRobotHasPriorityZero, OutrankedOccupantPreempted,
         DeadlinesKeepRunning, EveryTaskResolved, EveryRobotSettles,
         HumanEventuallyEnters, V1EventuallyRestored
  in (union Fleet, { TestRandomTasks });

// =================================================================== E2
// Prediction: INTENDED COUNTEREXAMPLE of NoRobotWithHuman. The coordinator is
// deliberately broken (naive = true): it admits the human before Zone 1 is
// evacuated. A failure here is not a regression.
test tcNaiveAdaptation [main=TestNaiveAdaptation]:
  assert ZoneMutualExclusion, NoRobotWithHuman
  in (union Fleet, { TestNaiveAdaptation });

// ============================================================ property 4
// Prediction: INTENDED WITNESS. SanctionDuringV2 asserts false when a robot is
// sanctioned while V2 is active; the reported "bug" proves reachability.
// "0 bugs" here would mean property 4 is NOT covered.
test tcCoverSanctionInV2 [main=TestCoverSanctionInV2]:
  assert SanctionDuringV2
  in (union Fleet, { TestCoverSanctionInV2 });

// =================================================================== E3
// Sanction fairness on the final model. Both monitors are expected to fail:
// each failure is a trace of one cause.

// Prediction: FAILS. A robot denied the locked Zone 1 (CLOSED) or evacuated
// from it (EVACUATED) runs out of time and is sanctioned.
test tcE3FairnessRegulation [main=TestFairness]:
  assert NoRegulationCausedSanction
  in (union Fleet, { TestFairness });

// Prediction: FAILS. In the head-on conflict, the losing robot waits for or is
// pushed out of a zone (OCCUPIED / OUTRANKED) and is then sanctioned.
test tcE3FairnessTraffic [main=TestFairness]:
  assert NoTrafficCausedSanction
  in (union Fleet, { TestFairness });

// Prediction (same as tcE3FairnessTraffic, written before this test's first
// run; the test was added after round 1 to isolate traffic): FAILS, with a trace
// that contains no regulation delay at all, since there is no human.
test tcE3TrafficNoHuman [main=TestFairnessNoHuman]:
  assert NoTrafficCausedSanction, NoRegulationCausedSanction
  in (union Fleet, { TestFairnessNoHuman });

// =================================================================== E4
// Every controller locks and evacuates its zone while V2 is being installed;
// zones 0 and 2 reopen at the commit.

// Prediction: no bug. With side bays every robot can be evacuated, so the
// switch completes (HumanEventuallyEnters holds) and safety is preserved.
test tcE4BlockAllParking [main=TestE4BlockAll]:
  assert ZoneMutualExclusion, NoRobotWithHuman, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         PriorityRespected, OutrankedOccupantPreempted, EveryTaskResolved,
         EveryRobotSettles, HumanEventuallyEnters, V1EventuallyRestored
  in (union Fleet, { TestE4BlockAll });

// Prediction: FAILS HumanEventuallyEnters. Without bays a robot inside a locked
// zone cannot leave it, so the controllers never ack and the human never enters.
test tcE4BlockAllNoParking [main=TestE4BlockAllNoParking]:
  assert ZoneMutualExclusion, NoRobotWithHuman, HumanEventuallyEnters
  in (union Fleet, { TestE4BlockAllNoParking });

// =================================================================== E5
// Prediction: FAILS HumanEventuallyEnters by circular wait. Without bays the
// robot in Zone 1 can only leave forward; if the other robot holds that zone
// and waits for Zone 1 (locked), nobody moves.
test tcE5NoParking [main=TestE5NoParking]:
  assert ZoneMutualExclusion, NoRobotWithHuman, HumanEventuallyEnters
  in (union Fleet, { TestE5NoParking });

// =================================================================== E6
// Remedy 1: one travel direction at a time.

// Prediction: FAILS NoHeadOnConflict on the final model (the head-on conflict
// is the scenario itself). Reference point for the two tests below.
test tcE6HeadOnInBaseline [main=TestRandomTasks]:
  assert NoHeadOnConflict
  in (union Fleet, { TestRandomTasks });

// Prediction: no bug. No head-on conflict, and every safety and liveness
// monitor of the baseline still holds.
test tcE6OneDirection [main=TestE6OneDirection]:
  assert NoHeadOnConflict, ZoneMutualExclusion, NoRobotWithHuman, SanctionOnlyAfterExpiry,
         NoDoubleOutcome, PriorityRespected, EmptyRobotHasPriorityZero,
         OutrankedOccupantPreempted, DeadlinesKeepRunning, EveryTaskResolved,
         EveryRobotSettles, HumanEventuallyEnters, V1EventuallyRestored
  in (union Fleet, { TestE6OneDirection });

// Prediction: FAILS, but no longer by a head-on conflict: a returning robot and
// a delivering robot travel the same way, so same-direction congestion
// (OCCUPIED/OUTRANKED) can still precede a sanction.
test tcE6FairnessTraffic [main=TestE6Fairness]:
  assert NoTrafficCausedSanction
  in (union Fleet, { TestE6Fairness });

// Prediction: FAILS. The remedy adds its own regulation-caused delay: waiting
// at the entrance for the direction (DIRECTION), plus the Zone 1 closure.
test tcE6FairnessRegulation [main=TestE6Fairness]:
  assert NoRegulationCausedSanction
  in (union Fleet, { TestE6Fairness });

// =================================================================== E7
// Remedy 2: deadlines suspended while V2 is active; optionally, deadlines of
// tasks that were open during V2 are excused instead of sanctioned.

// Prediction: FAILS NoRegulationCausedSanction. Suspension alone does not
// return the time a robot lost by being evacuated or held back behind the
// other robot after V1 is restored.
test tcE7SuspendOnly [main=TestE7Suspend]:
  assert NoRegulationCausedSanction
  in (union Fleet, { TestE7Suspend });

// Prediction: no bug. With excusal no regulation-caused sanction remains, and
// every other monitor still holds (DeadlinesKeepRunning is not attached: the
// remedy deliberately replaces N7).
test tcE7SuspendExcuseShort [main=TestE7SuspendExcuse]:
  assert NoRegulationCausedSanction, ZoneMutualExclusion, NoRobotWithHuman,
         SanctionOnlyAfterExpiry, NoDoubleOutcome, PriorityRespected,
         EmptyRobotHasPriorityZero, OutrankedOccupantPreempted, EveryTaskResolved,
         EveryRobotSettles, HumanEventuallyEnters, V1EventuallyRestored
  in (union Fleet, { TestE7SuspendExcuse });

// Prediction: no bug. Same, over the random tasks of tcRandomTasks.
test tcE7SuspendExcuseRandom [main=TestE7SuspendExcuseRandom]:
  assert NoRegulationCausedSanction, ZoneMutualExclusion, NoRobotWithHuman,
         SanctionOnlyAfterExpiry, NoDoubleOutcome, PriorityRespected,
         EmptyRobotHasPriorityZero, OutrankedOccupantPreempted, EveryTaskResolved,
         EveryRobotSettles, HumanEventuallyEnters, V1EventuallyRestored
  in (union Fleet, { TestE7SuspendExcuseRandom });

// Prediction: FAILS. The remedy targets regulation-caused cases only;
// traffic-caused sanctions remain.
test tcE7Traffic [main=TestE7SuspendExcuse]:
  assert NoTrafficCausedSanction
  in (union Fleet, { TestE7SuspendExcuse });

// Prediction: FAILS DeadlinesKeepRunning. Sanity check that the remedy really
// suspends deadlines (it replaces N7 by design).
test tcE7ReplacesN7 [main=TestE7Suspend]:
  assert DeadlinesKeepRunning
  in (union Fleet, { TestE7Suspend });

// =================================================================== E8
// Prediction: no bug, and a much longer run time per schedule and many more
// distinct timelines than tcRandomTasks. (The 4-zone variant is run by
// experiments/run_scale.sh, because NUM_ZONES is a global constant.)
test tcE8ThreeRobots [main=TestE8ThreeRobots]:
  assert ZoneMutualExclusion, NoRobotWithHuman, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         PriorityRespected, EmptyRobotHasPriorityZero, OutrankedOccupantPreempted,
         DeadlinesKeepRunning, EveryTaskResolved, EveryRobotSettles,
         HumanEventuallyEnters, V1EventuallyRestored
  in (union Fleet, { TestE8ThreeRobots });

// =================================================================== E9
// Prediction: no bug. Every change ends committed or aborted (L3); an aborted
// change never admits the picker and leaves every controller back on V1; the
// safety monitors still hold.
test tcE9AbortSafety [main=TestE9Abort]:
  assert AdaptationTerminates, AbortNeverAdmits, AbortUnblocksControllers,
         ZoneMutualExclusion, NoRobotWithHuman, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         PriorityRespected, OutrankedOccupantPreempted, EveryTaskResolved, EveryRobotSettles
  in (union Fleet, { TestE9Abort });

// Prediction: FAILS HumanEventuallyEnters, by design: an aborted change is
// never installed, so the refused picker never enters.
test tcE9AbortBreaksL2 [main=TestE9Abort]:
  assert HumanEventuallyEnters
  in (union Fleet, { TestE9Abort });

// =================================================================== E10
// Prediction: FAILS BayCapacityOne. Two robots can end up in Bay 1 together:
// one waits there after being evacuated or outranked, and the other is pushed
// out of Zone 1 into the same bay. (The assignment's prediction for one finite
// bay per zone is "as E1"; our corridor lets two retreats meet in one bay.)
test tcE10BayCapacity [main=TestRandomTasks]:
  assert BayCapacityOne
  in (union Fleet, { TestRandomTasks });

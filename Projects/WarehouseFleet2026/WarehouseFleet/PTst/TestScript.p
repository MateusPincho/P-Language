// Test cases. Every "Expected" line is a hypothesis until the test is run;
// actual results, with schedule counts, are in ../../README.md -> Status.

// Expected (hypothesis): no bug. N1-N4 under V1 only.
test tcHeadOnV1 [main=TestHeadOnV1]:
  assert ZoneMutualExclusion, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         EveryTaskResolved, EveryRobotSettles in
  { TestHeadOnV1, FleetScenario, Robot, ZoneController, ObligationManager,
    AdaptationCoordinator, HumanPicker, Clock };

// Expected (hypothesis): no bug. N1-N8 with the V1 -> V2 -> V1 adaptation.
test tcHumanAdaptation [main=TestHumanAdaptation]:
  assert ZoneMutualExclusion, NoRobotWithHuman, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         EveryTaskResolved, EveryRobotSettles, HumanEventuallyEnters in
  { TestHumanAdaptation, FleetScenario, Robot, ZoneController, ObligationManager,
    AdaptationCoordinator, HumanPicker, Clock };

// Expected (hypothesis): no bug. Same as above over chosen priorities,
// deadlines and initial infractions.
test tcRandomTasks [main=TestRandomTasks]:
  assert ZoneMutualExclusion, NoRobotWithHuman, SanctionOnlyAfterExpiry, NoDoubleOutcome,
         EveryTaskResolved, EveryRobotSettles, HumanEventuallyEnters in
  { TestRandomTasks, FleetScenario, Robot, ZoneController, ObligationManager,
    AdaptationCoordinator, HumanPicker, Clock };

// Expected (hypothesis): INTENDED COUNTEREXAMPLE of NoRobotWithHuman.
// The coordinator is deliberately broken (naive = true): it admits the human
// before Zone 1 is evacuated. This shows the property-2 monitor is not vacuous.
// A failure here is not a regression.
test tcNaiveAdaptation [main=TestNaiveAdaptation]:
  assert ZoneMutualExclusion, NoRobotWithHuman in
  { TestNaiveAdaptation, FleetScenario, Robot, ZoneController, ObligationManager,
    AdaptationCoordinator, HumanPicker, Clock };

// Expected (hypothesis): INTENDED WITNESS for property 4 (cover): a robot is
// sanctioned while V2 is active. SanctionDuringV2 asserts false on reaching
// that situation, so the reported "bug" is the reachability proof.
// A failure here is the desired outcome; "0 bugs" would mean NOT covered.
test tcCoverSanctionInV2 [main=TestCoverSanctionInV2]:
  assert SanctionDuringV2 in
  { TestCoverSanctionInV2, FleetScenario, Robot, ZoneController, ObligationManager,
    AdaptationCoordinator, HumanPicker, Clock };

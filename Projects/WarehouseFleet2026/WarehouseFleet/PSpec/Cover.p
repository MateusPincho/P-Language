// Property 4 (PDF, a "cover" property): a sanction occurs while V2 is active.
//
// P has no cover construct. This is a witness monitor: it asserts false the
// moment the situation is reached. It is wired ONLY into tcCoverSanctionInV2,
// where the reported "bug" is the expected outcome and its trace is the proof
// that the obligation/adaptation conflict of slide 13 is reachable.
spec SanctionDuringV2 observes eNormChange, eSanction {
  var v2Active: bool;

  start state Monitoring {
    on eNormChange do (n: tNormChange) {
      v2Active = (n.version == V2);
    }
    on eSanction do (s: tSanction) {
      assert !v2Active,
        format("COVER WITNESS (expected): robot {0} sanctioned for task {1} while V2 is active",
               s.robotId, s.taskId);
    }
  }
}

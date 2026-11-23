// Logical time. P is untimed, so deadlines and cooldowns are counted in ticks.
// Only the Fleet Manager subscribes. A tick is acked before the next one is
// sent, so ticks never pile up in the Fleet Manager's queue.
machine Clock {
  var om: machine;
  var now: int;

  start state Init {
    entry (manager: machine) {
      om = manager;
      now = 0;
      goto Ticking;
    }
  }

  state Ticking {
    entry {
      now = now + 1;
      send om, eTick, now;
    }
    on eTickAck goto Ticking;
    on eStopClock goto Stopped;
  }

  state Stopped {
    ignore eTickAck, eStopClock;
  }
}

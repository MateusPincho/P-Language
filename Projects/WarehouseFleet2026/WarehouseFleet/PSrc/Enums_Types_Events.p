// Types and events for the warehouse corridor regulation model.
// See ../../SPECIFICATION.md. Events marked (ours) are not in the PDF's table.

/********************************************************************
 * Enums and constants
 ********************************************************************/
enum tNormVersion { V1, V2 }
enum tStation { STATION_A, STATION_B }

fun NUM_ZONES(): int { return 3; }
fun HUMAN_ZONE(): int { return 1; }   // the zone the human picker needs (N5, N6)
fun R1(): int { return 1; }           // R1 wins the final N2 tiebreak
fun R2(): int { return 2; }

/********************************************************************
 * Payload and configuration types
 ********************************************************************/
// A delivery task. Priority belongs to the package, not the robot.
type tTask = (taskId: int, robotId: int, priority: int, deadline: int,
              origin: tStation, dest: tStation);
type tAssignment = (task: tTask, manager: machine);

// Robot -> ZoneController. reqId is fresh per request (ours) so stale replies can be told apart.
type tRequestZone = (robot: machine, robotId: int, reqId: int, zone: int,
                     priority: int, violations: int);
// ZoneController -> Robot, for eGrant / eDeny / ePreempt.
type tZoneReply = (zone: int, reqId: int);
// Robot -> ZoneController, for eRelease / eCancelRequest.
type tZoneRelease = (robotId: int, reqId: int, zone: int);
// Monitor vocabulary: a robot's physical position.
type tRobotZone = (robotId: int, zone: int);

type tTaskRef = (robotId: int, taskId: int);
type tSanction = (robotId: int, taskId: int, cooldown: int, infractions: int);

type tNormChange = (version: tNormVersion, coord: machine);
type tNormAck = (zone: int, version: tNormVersion);

/********************************************************************
 * Experiment switches (see ../../EXPERIMENTS.md). BASELINE() is the
 * final model; every other value exists only for one experiment.
 ********************************************************************/
enum tRemedy { NO_REMEDY, SUSPEND, SUSPEND_EXCUSE }   // E7
enum tDirection { A_TO_B, B_TO_A }                    // E6
// Why a robot lost time (E3). Regulation-caused: CLOSED, EVACUATED, DIRECTION.
// Traffic-caused: OCCUPIED, OUTRANKED.
enum tDelayCause { OCCUPIED, CLOSED, OUTRANKED, EVACUATED, DIRECTION }

type tVariant = (blockAll: bool,       // E4: every controller locks while V2 is installed
                 parking: bool,        // E5: false = robots cannot use the side bays
                 remedy: tRemedy,      // E7
                 oneDirection: bool,   // E6
                 abortable: bool);     // E9: the coordinator may time out and abort
fun BASELINE(): tVariant {
  return (blockAll = false, parking = true, remedy = NO_REMEDY,
          oneDirection = false, abortable = false);
}

type tZoneConfig = (zone: int, blockAll: bool);
type tRobotConfig = (robotId: int, controllers: seq[machine], violations: int,
                     parking: bool, oneDirection: bool, dirGuard: machine);
type tOMConfig = (robots: map[int, machine], tasks: seq[tTask], cooldown: int,
                  infractions: map[int, int], remedy: tRemedy);
type tCoordConfig = (controllers: seq[machine], naive: bool, blockAll: bool,
                     abortable: bool, notifyManager: bool, manager: machine);
type tHumanConfig = (coord: machine, maxDelay: int, maxStay: int);
type tDirRequest = (robot: machine, robotId: int, dir: tDirection);

// Monitor vocabulary added for the experiments (announced, never received).
// A controller's admission decision, with its own view of the zone.
type tAdmission = (zone: int, robotId: int, reqId: int, priority: int, violations: int,
                   occupantId: int, locked: bool, cause: tDelayCause);
type tPreemption = (zone: int, robotId: int, reqId: int, cause: tDelayCause);
type tAbandon = (robotId: int, taskId: int, where: int);   // where: zone held, or -1

/********************************************************************
 * Events
 ********************************************************************/
// Fleet Manager <-> Robot
event eTaskAssigned: tAssignment;
event eArrived: tTaskRef;              // (ours) robot reached its destination
event eDeliveryConfirmed: tTaskRef;    // (ours) Fleet Manager accepts the delivery
event eDeadlineExpired: tTaskRef;      // ObligationManager -> itself (N4, N7)
event eSanction: tSanction;            // N4
event eCooldownOver: int;              // (ours) robotId
event eReturned: int;                  // (ours) robotId, back at a station after a sanction

// Robot <-> ZoneController
event eRequestZone: tRequestZone;      // N1, N2
event eGrant: tZoneReply;              // N1
event eDeny: tZoneReply;               // N1, N5
event ePreempt: tZoneReply;            // N3, N6
event eRelease: tZoneRelease;          // (ours)
event eCancelRequest: tZoneRelease;    // (ours)

// Clock <-> Fleet Manager
event eTick: int;
event eTickAck;                        // (ours)
event eStopClock;                      // (ours)

// Human picker <-> Adaptation Coordinator <-> ZoneControllers
event eHumanRequest: machine;          // N5
event eHumanExit;                      // N8
event eHumanAccessGranted;             // (ours)
event eHumanStep;                      // (ours) HumanPicker's internal step
event eNormChange: tNormChange;        // N5, N6, N8
event eNormChangeAck: tNormAck;        // (ours)

// Monitor vocabulary (announced, never received by machines)
event eZoneEntered: tRobotZone;
event eZoneLeft: tRobotZone;
event eHumanEnter;

// Experiment events: only sent when a switch in tVariant is on
event eNormCommit;                     // E4: V2 installed everywhere, non-human zones reopen
event eAdaptationNotice: tNormChange;  // E7: coordinator -> Fleet Manager (version, coordinator)
event eAdaptationNoticeAck;            // E7
event eAdaptTimeout;                   // E9: coordinator's own timeout
event eHumanAccessRefused;             // E9: the change was aborted
event eDirRequest: tDirRequest;        // E6: Robot -> DirectionGuard
event eDirGrant;                       // E6
event eDirRelease: int;                // E6: robotId
event eDirCancel: int;                 // E6: robotId

// Experiment monitor vocabulary (announced, never received by machines)
event eAccessDenied: tAdmission;       // every denial, with its cause (E3, N2, N3)
event eZoneGranted: tAdmission;        // every grant (N2, N3)
event ePreemptIssued: tPreemption;     // every ePreempt, with its cause (E3, N3)
event eTaskAbandoned: tAbandon;        // a sanctioned robot gives up its delivery (E3)
event eDirectionDenied: int;           // E6: robotId waits for the travel direction
event eObligationExcused: tTaskRef;    // E7: deadline expired but excused
event eAdaptationAborted;              // E9
event eBayEntered: tRobotZone;         // E10: zone = bay index
event eBayLeft: tRobotZone;            // E10

// N2, as written in the PDF, encoded independently of ZoneController.Wins so
// that a mutation of the controller cannot also change what the monitors expect.
fun OutranksN2(p1: int, v1: int, id1: int, p2: int, v2: int, id2: int): bool {
  if (p1 != p2) { return p1 > p2; }
  if (v1 != v2) { return v1 < v2; }
  return id1 < id2;
}
fun IsRegulationCause(c: tDelayCause): bool {
  return c == CLOSED || c == EVACUATED || c == DIRECTION;
}

// Readable names for monitor messages (format prints enum values as numbers).
fun CauseName(c: tDelayCause): string {
  if (c == OCCUPIED) { return "OCCUPIED (zone held by the other robot, N1)"; }
  if (c == CLOSED) { return "CLOSED (Zone 1 locked under V2, N5)"; }
  if (c == OUTRANKED) { return "OUTRANKED (pushed out by a higher priority, N3)"; }
  if (c == EVACUATED) { return "EVACUATED (pushed out for the human, N6)"; }
  return "DIRECTION (waiting for the travel direction, E6)";
}
fun DirName(d: tDirection): string {
  if (d == A_TO_B) { return "A->B"; }
  return "B->A";
}

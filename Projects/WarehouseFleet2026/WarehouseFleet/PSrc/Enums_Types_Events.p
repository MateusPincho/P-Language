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

type tRobotConfig = (robotId: int, controllers: seq[machine], violations: int);
type tOMConfig = (robots: map[int, machine], tasks: seq[tTask], cooldown: int,
                  infractions: map[int, int]);
type tCoordConfig = (controllers: seq[machine], naive: bool);
type tHumanConfig = (coord: machine, maxDelay: int, maxStay: int);

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

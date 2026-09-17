/* SPDX-License-Identifier: MIT
 *
 * AwgChain pack 52: the in-process kill switch is re-armed after a repair.
 *
 * Pack 51 moved the WFP filters into the manager service. The repair loop
 * still printed "the kill switch follows the new interfaces by itself",
 * which is not true for those filters: every rule is bound to the adapter
 * LUID that existed when the lock was installed. A repair tears the tunnels
 * down and raises them again, so Windows hands out fresh adapters with fresh
 * LUIDs (the interface index was seen jumping from 7 to 18 in the log).
 * After that the lock guards interfaces that no longer exist.
 *
 * So after every successful repair we lift the lock and install it again
 * against the adapters that are here now. The filters live in one dynamic
 * WFP session, so the old set has to go before the new one can be added;
 * that leaves a gap of a few milliseconds, which is still far better than a
 * lock pointing at dead interfaces.
 */

package manager

import (
	"log"
	"time"
)

const (
	chainRelockTries = 10
	chainRelockGap   = 2 * time.Second
)

// chainRearmLockAfterRepair reinstalls the in-process kill switch on the
// adapters that exist after a repair. It does nothing when the lock is not
// ours: the separate guard process watches interface changes on its own, and
// a chain that was never locked is armed by chainArmGuard as usual.
func (s *ManagerService) chainRearmLockAfterRepair(leaf string) {
	if chainInProcLockDisabled() {
		return
	}
	if !chainLockIsOn() {
		return
	}

	chainDisarmLockInProc()

	for try := 1; try <= chainRelockTries; try++ {
		if chainArmLockInProc(leaf) {
			log.Printf("[AwgChain] Repair: kill switch re-armed on the new interfaces on try %d", try)
			return
		}
		time.Sleep(chainRelockGap)
	}

	log.Printf("[AwgChain] Repair: the kill switch could NOT be re-armed after %d tries, so the machine is open right now. The watch keeps trying.", chainRelockTries)
}

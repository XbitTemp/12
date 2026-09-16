//go:build windows

/* AwgChain - patch 20: a hop is given more than one chance to start.
 *
 * chainStartParents called ManagerService.Start once. When the service of the
 * hop underneath was still finishing its own shutdown, Windows refused the
 * start and the manager reported
 *
 *   Please allow the tunnel <name> to finish activating
 *
 * The whole repair attempt was then thrown away, even though waiting two
 * seconds would have been enough. The log of 2026-09-15 shows this happening
 * on try 1 and try 2 of every single repair, with try 3 always succeeding.
 *
 * Every start error is treated the same way here on purpose: the message from
 * the manager is localised, so matching on its text would break on a
 * non-English Windows.
 */

package manager

import (
	"log"
	"time"
)

const (
	chainHopStartTries    = 5
	chainHopStartRetryGap = 2 * time.Second
)

// chainStartHopWithRetry starts a hop, waiting for a service that is still
// busy instead of giving the whole attempt away.
func (s *ManagerService) chainStartHopWithRetry(name string) error {
	var err error
	for try := 1; try <= chainHopStartTries; try++ {
		err = s.Start(name)
		if err == nil {
			if try > 1 {
				log.Printf("[%s] Chain: the hop started on try %d", name, try)
			}
			return nil
		}
		if try == chainHopStartTries {
			break
		}
		log.Printf("[%s] Chain: the hop service is not ready yet (try %d of %d): %v", name, try, chainHopStartTries, err)
		s.chainWaitStopped(name)
		time.Sleep(chainHopStartRetryGap)
	}
	return err
}
/* SPDX-License-Identifier: MIT
 *
 * AwgChain pack 55: the honest "leak protection" line in the Interface box.
 *
 * The manager is asked every two seconds in the background, so drawing the
 * line never waits on the pipe.
 */

package ui

import (
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-windows-client/manager"
)

var (
	chainProtectMu    sync.Mutex
	chainProtectInfo  manager.ChainStatusInfo
	chainProtectFresh bool
	chainProtectOnce  sync.Once
)

// chainProtectStart makes sure the background poll is running.
func chainProtectStart() {
	chainProtectOnce.Do(func() {
		go func() {
			for {
				info, err := manager.IPCClientChainStatus()
				chainProtectMu.Lock()
				chainProtectInfo = info
				chainProtectFresh = err == nil
				chainProtectMu.Unlock()
				time.Sleep(2 * time.Second)
			}
		}()
	})
}

// chainProtectionText says what the line should read for this tunnel.
func chainProtectionText(name string) (string, bool) {
	chainProtectStart()

	chainProtectMu.Lock()
	info := chainProtectInfo
	fresh := chainProtectFresh
	chainProtectMu.Unlock()

	if !fresh {
		return chainProtectNoSvc, true
	}
	if !info.LockOn {
		return chainProtectOff, true
	}
	if !info.InProc {
		return chainProtectGuard, true
	}
	if info.LockLeaf == "" || strings.EqualFold(info.LockLeaf, name) {
		return chainProtectOn, true
	}
	return fmt.Sprintf(chainProtectOther, info.LockLeaf), true
}

// chainApplyProtection draws the line. It is called from setTunnel, which the
// view already runs once a second.
func (cv *ConfView) chainApplyProtection(name string) {
	if cv == nil || cv.interfaze == nil || cv.interfaze.chainProtection == nil {
		return
	}
	text, show := chainProtectionText(name)
	if !show {
		cv.interfaze.chainProtection.hide()
		return
	}
	cv.interfaze.chainProtection.show(text)
}

// chainLiftLockBeforeQuit is called on the way out of the program. When the
// Settings tab asks for it, the manager is told to open the machine up again
// before the program disappears from the tray.
func chainLiftLockBeforeQuit() {
	global, err := manager.IPCClientChainGlobal()
	if err != nil {
		return
	}
	if !global.LiftLockOnQuit {
		return
	}
	manager.IPCClientChainLiftLock()
}

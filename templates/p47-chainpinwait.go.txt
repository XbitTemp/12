//go:build windows

/* AwgChain - pack 47: the hop above wakes the hop underneath.
 *
 * Pack 45 taught the tunnel service to survive a missing pin interface: it
 * now waits instead of shutting down. The stress test proved it works, and
 * showed the next gap: nobody starts the hop underneath. When Windows or a
 * user starts only the service of hop 2 (autostart, the button in the
 * window, sc start), the manager is not in the loop, so hop 1 stays stopped
 * and hop 2 waits forever.
 *
 * This file closes that gap: while waiting for the pinned adapter, the
 * service also asks the service control manager to start the tunnel service
 * of the hop underneath, every ten seconds. The service name follows the
 * usual scheme: AwgChainTunnel$<interface name>.
 */

package tunnel

import (
	"errors"
	"log"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"

	"github.com/amnezia-vpn/amneziawg-windows/v3/conf"
	"github.com/amnezia-vpn/amneziawg-windows/v3/tunnel/winipcfg"
)

const (
	chainPinRetryGap   = 2 * time.Second
	chainPinRetryTries = 45
	chainPinStartEvery = 5
	chainServicePrefix = "AwgChainTunnel$"
)

// chainPinNotReadyError marks a pin failure that time alone can cure.
type chainPinNotReadyError struct {
	err error
}

func (e *chainPinNotReadyError) Error() string {
	return e.err.Error()
}

func (e *chainPinNotReadyError) Unwrap() error {
	return e.err
}

func chainPinNotReady(err error) error {
	if err == nil {
		return nil
	}
	return &chainPinNotReadyError{err: err}
}

func chainIsPinNotReady(err error) bool {
	var target *chainPinNotReadyError
	return errors.As(err, &target)
}

// chainPinnedInterfaceReady reports whether the pinned adapter exists and is up.
func chainPinnedInterfaceReady(name string) bool {
	name = strings.TrimSpace(name)
	if name == "" {
		return false
	}
	iface, err := findInterfaceByName(name)
	if err != nil || iface == nil {
		return false
	}
	return iface.OperStatus == winipcfg.IfOperStatusUp
}

// chainStartHopBelow asks Windows to start the tunnel service that owns the
// pinned adapter. Every failure is only logged: the wait continues either way,
// so a hop started by hand or by the manager still works.
func chainStartHopBelow(name string) {
	name = strings.TrimSpace(name)
	if name == "" {
		return
	}
	serviceName := chainServicePrefix + name

	m, err := mgr.Connect()
	if err != nil {
		log.Printf("Chain: cannot reach the service manager to start %s: %v", serviceName, err)
		return
	}
	defer m.Disconnect()

	service, err := m.OpenService(serviceName)
	if err != nil {
		log.Printf("Chain: no service %s to start: %v", serviceName, err)
		return
	}
	defer service.Close()

	status, err := service.Query()
	if err == nil && (status.State == svc.Running || status.State == svc.StartPending) {
		return
	}

	err = service.Start()
	if err != nil {
		log.Printf("Chain: could not start %s: %v", serviceName, err)
		return
	}
	log.Printf("Chain: asked Windows to start the hop underneath (%s)", serviceName)
}

var chainPinRetrying sync.Map

// chainRetrySetup keeps the tunnel alive and retries the socket binding until
// the hop underneath is up, starting that hop as well.
func (iw *interfaceWatcher) chainRetrySetup(family winipcfg.AddressFamily, cause error) {
	via := ""
	if iw.conf != nil {
		via = strings.TrimSpace(iw.conf.Interface.PinEndpointVia)
	}
	if via == "" {
		return
	}

	log.Printf("Chain: %v, so we wait for it instead of shutting the tunnel down", cause)

	if _, busy := chainPinRetrying.LoadOrStore(family, true); busy {
		return
	}

	go func() {
		defer chainPinRetrying.Delete(family)
		for try := 0; try < chainPinRetryTries; try++ {
			if try%chainPinStartEvery == 0 {
				chainStartHopBelow(via)
			}
			time.Sleep(chainPinRetryGap)
			if !chainPinnedInterfaceReady(via) {
				continue
			}
			iw.setupMutex.Lock()
			iw.setup(family)
			iw.setupMutex.Unlock()
			log.Printf("Chain: the hop underneath (%s) is here, the tunnel is bound to it", via)
			return
		}
		log.Printf("Chain: the hop underneath never came up, the tunnel stays but carries nothing")
	}()
}

// chainPinRoutesLater installs the host route to the endpoint as soon as the
// pinned adapter shows up, starting the hop underneath in the meantime.
func chainPinRoutesLater(config *conf.Config, cause error) {
	if config == nil {
		return
	}
	via := strings.TrimSpace(config.Interface.PinEndpointVia)
	if via == "" {
		log.Printf("Chain pin route: %v", cause)
		return
	}

	log.Printf("Chain pin route: %v, so the route is pinned once the hop underneath is here", cause)

	go func() {
		for try := 0; try < chainPinRetryTries; try++ {
			if try%chainPinStartEvery == 0 {
				chainStartHopBelow(via)
			}
			time.Sleep(chainPinRetryGap)
			if chainPinnedInterfaceReady(via) {
				chainPinRoutes(config, true)
				return
			}
		}
		log.Printf("Chain pin route: gave up waiting for %s", via)
	}()
}

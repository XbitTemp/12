/* SPDX-License-Identifier: MIT
 *
 * AwgChain pack 51: the chain kill switch lives inside the manager service.
 *
 * Until now the WFP filters were installed by a separate process,
 * awgchain-guard.exe. That worked, but it cost us three problems:
 *
 *   1. The lock appears only after the guard process has started, so there
 *      is a window at raise time with no protection at all.
 *   2. When the manager goes away the guard has to guess whether this was a
 *      deliberate shutdown, so it waits out -orphangrace (120 seconds).
 *      That is the "the internet comes back after two minutes" complaint.
 *   3. It dragged a stop event, a death counter and -mgrpid behind it.
 *
 * The filters belong to a dynamic WFP session, so they live exactly as long
 * as the process that installed them. Installing them from the manager
 * service is therefore both simpler and safer: a manager that crashes frees
 * the machine immediately, and a manager that is alive can lift the lock the
 * moment the tunnel is stopped on purpose.
 *
 * The old guard is kept as a fallback. Create the file
 *
 *   C:\ProgramData\AwgChain\no-inproc-lock
 *
 * and the manager goes back to starting awgchain-guard.exe, with no rebuild.
 */

package manager

import (
	"log"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/windows"

	"github.com/amnezia-vpn/amneziawg-windows/v3/conf"
	"github.com/amnezia-vpn/amneziawg-windows/v3/tunnel/firewall"
)

const chainLockOptOut = "no-inproc-lock"

var (
	chainLockMu    sync.Mutex
	chainLockOn    bool
	chainLockLeaf  string
	chainLockStop  chan struct{}
)

// chainInProcLockDisabled reports the opt-out file that sends us back to the
// separate guard process.
func chainInProcLockDisabled() bool {
	_, err := os.Stat(filepath.Join(chainStateDir(), chainLockOptOut))
	return err == nil
}

func chainLockIsOn() bool {
	chainLockMu.Lock()
	defer chainLockMu.Unlock()
	return chainLockOn
}

func chainParseEndpoint(value string) (net.IP, uint16, bool) {
	host, portText, err := net.SplitHostPort(strings.TrimSpace(value))
	if err != nil {
		return nil, 0, false
	}
	ip := net.ParseIP(host)
	if ip == nil || ip.To4() == nil {
		return nil, 0, false
	}
	port, err := strconv.ParseUint(portText, 10, 16)
	if err != nil {
		return nil, 0, false
	}
	return ip, uint16(port), true
}

func chainLockApps() []string {
	apps := make([]string, 0, 2)
	self, err := os.Executable()
	if err != nil {
		return apps
	}
	apps = append(apps, self)
	neighbour := filepath.Join(filepath.Dir(self), "awgchain.exe")
	if !strings.EqualFold(neighbour, self) {
		if _, err := os.Stat(neighbour); err == nil {
			apps = append(apps, neighbour)
		}
	}
	return apps
}

func chainLockDNS(top string) []net.IP {
	servers := make([]net.IP, 0, 4)
	for _, text := range strings.Split(chainDNSOf(top), ",") {
		ip := net.ParseIP(strings.TrimSpace(text))
		if ip != nil {
			servers = append(servers, ip)
		}
	}
	return servers
}

func chainLockLANs(root string) []net.IPNet {
	via := ""
	if c, err := conf.LoadFromName(root); err == nil {
		via = strings.TrimSpace(c.Interface.PinEndpointVia)
	}
	networks := make([]net.IPNet, 0, 4)
	for _, text := range chainLocalNetworks(via) {
		_, network, err := net.ParseCIDR(text)
		if err == nil && network != nil {
			networks = append(networks, *network)
		}
	}
	return networks
}

// chainArmLockInProc installs the kill switch in this very process. It
// answers true when the chain is protected and the caller must not start the
// guard process, and false when the caller should fall back to the old way.
func chainArmLockInProc(leaf string) bool {
	if !ChainSettingsFor(leaf).KillSwitch {
		log.Printf("[AwgChain] The kill switch is switched off in the settings of %s", leaf)
		chainApplyIPv6For(leaf)
		return true
	}

	if chainInProcLockDisabled() {
		return false
	}
	if chainLockIsOn() {
		return true
	}

	hops := chainHopOrder(leaf)
	if len(hops) < 2 {
		return false
	}
	root := hops[0]
	top := hops[len(hops)-1]

	rootEndpointText, err := chainEndpointOf(root)
	if err != nil {
		log.Printf("[AwgChain] The kill switch cannot read the endpoint of %s: %v", root, err)
		return false
	}
	topEndpointText, err := chainEndpointOf(top)
	if err != nil {
		log.Printf("[AwgChain] The kill switch cannot read the endpoint of %s: %v", top, err)
		return false
	}
	rootIP, rootPort, ok := chainParseEndpoint(rootEndpointText)
	if !ok {
		log.Printf("[AwgChain] The kill switch does not understand the endpoint %q", rootEndpointText)
		return false
	}
	topIP, topPort, ok := chainParseEndpoint(topEndpointText)
	if !ok {
		log.Printf("[AwgChain] The kill switch does not understand the endpoint %q", topEndpointText)
		return false
	}

	rootLUID, ok := chainAdapterLUID(root)
	if !ok {
		log.Printf("[AwgChain] The kill switch waits: the %s adapter is not here yet", root)
		return false
	}
	topLUID, ok := chainAdapterLUID(top)
	if !ok {
		log.Printf("[AwgChain] The kill switch waits: the %s adapter is not here yet", top)
		return false
	}

	apps := chainLockApps()
	if len(apps) == 0 {
		log.Printf("[AwgChain] The kill switch cannot tell which executable to allow")
		return false
	}

	cfg := &firewall.ChainFirewallConfig{
		Hop1LUID:     uint64(rootLUID),
		Hop2LUID:     uint64(topLUID),
		Hop1Endpoint: rootIP,
		Hop1Port:     rootPort,
		Hop2Endpoint: topIP,
		Hop2Port:     topPort,
		DNSServers:   chainLockDNS(top),
		AllowedApps:  apps,
		AllowedLANs:  chainSettingsLANs(root, leaf),
	}

	err = firewall.EnableChainFirewall(cfg)
	if err != nil {
		// A leftover session from an earlier raise is not a reason to start a
		// second guard: close it and try once more.
		firewall.DisableChainFirewall()
		err = firewall.EnableChainFirewall(cfg)
	}
	if err != nil {
		log.Printf("[AwgChain] The kill switch could not be installed inside the manager (%v), falling back to %s", err, chainGuardExeName)
		return false
	}

	stop := make(chan struct{})
	chainLockMu.Lock()
	chainLockOn = true
	chainLockLeaf = leaf
	chainLockStop = stop
	chainLockMu.Unlock()

	log.Printf("[AwgChain] Kill switch armed inside the manager for %s -> %s, no separate guard process", root, top)
	chainApplyIPv6For(leaf)
	go chainLockWatchStopEvent(stop)
	return true
}

// chainDisarmLockInProc lifts the lock. It answers true when there was one.
func chainDisarmLockInProc() bool {
	chainLockMu.Lock()
	on := chainLockOn
	stop := chainLockStop
	chainLockOn = false
	chainLockLeaf = ""
	chainLockStop = nil
	chainLockMu.Unlock()
	if !on {
		return false
	}
	if stop != nil {
		close(stop)
	}
	firewall.DisableChainFirewall()
	log.Printf("[AwgChain] Kill switch lifted, the machine is open again")
	chainDropIPv6Block()
	return true
}

// chainLockWatchStopEvent keeps "awgchain.bat ks off" working: the console
// signals the same event the guard used to listen to.
func chainLockWatchStopEvent(stop chan struct{}) {
	name, err := windows.UTF16PtrFromString(chainGuardStopEventName)
	if err != nil {
		return
	}
	handle, err := windows.CreateEvent(chainStopEventSecurity(), 1, 0, name)
	if handle == 0 {
		if err != nil {
			log.Printf("[AwgChain] The kill switch cannot listen for the stop signal: %v", err)
		}
		return
	}
	defer windows.CloseHandle(handle)
	// A previous run may have left the manual reset event signalled.
	windows.ResetEvent(handle)

	for {
		select {
		case <-stop:
			return
		default:
		}
		state, err := windows.WaitForSingleObject(handle, 1000)
		if err != nil {
			time.Sleep(time.Second)
			continue
		}
		if state == windows.WAIT_OBJECT_0 {
			windows.ResetEvent(handle)
			log.Printf("[AwgChain] The kill switch was asked to stand down")
			chainDisarmLockInProc()
			return
		}
	}
}

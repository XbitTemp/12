//go:build windows

/* AwgChain - patch 10: the chain looks after itself.
 *
 * Everything worked from the interface after patches 8 and 9, but two jobs
 * were still done by hand from awgchain.bat:
 *
 *   awgchain.bat kson    arm the kill switch
 *   awgchain-watch.bat   keep a watchdog running
 *
 * Both now happen inside the manager, which is the one component that always
 * knows when a hop comes up and when it goes down:
 *
 *   the top hop handshakes  -> awgchain-guard.exe is started with arguments
 *                              worked out from the configs themselves
 *   the top hop handshakes  -> a watch goroutine starts
 *   any hop is stopped      -> watch stops, kill switch stands down
 *
 * The watch reads last_handshake_time_sec of every hop over UAPI. When a hop
 * is gone or silent for too long it rebuilds the chain from the bottom up,
 * exactly as the PowerShell watchdog did, but without leaving the kill switch
 * unarmed in between.
 *
 * Opt out by creating this file, which is checked on every arm:
 *
 *   C:\ProgramData\AwgChain\no-autoguard
 *
 * awgchain.bat autoguard on|off|status writes and reads it.
 */

package manager

import (
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/windows"

	"github.com/amnezia-vpn/amneziawg-windows/v3/conf"
	"github.com/amnezia-vpn/amneziawg-windows/v3/tunnel/winipcfg"
)

const (
	chainGuardStopEventName = `Global\AwgChainGuardStop`
	chainGuardExeName       = "awgchain-guard.exe"
	chainWatchInterval      = 5 * time.Second
	chainHandshakeMaxAge    = 180 * time.Second
	chainRepairGrace        = 25 * time.Second
	chainMaxRepairs         = 20
	chainSlowRepairGrace    = 5 * time.Minute
	// How long a hop is given to reach the stopped state before the chain is
	// raised again. Starting a hop that is still shutting down is refused by
	// the manager with "please allow the tunnel to finish activating", which
	// used to cost a whole grace period.
	chainStopWait      = 20 * time.Second
	chainStopPoll      = 200 * time.Millisecond
	chainStartRetries  = 6
	chainStartRetryGap = 3 * time.Second
)

var (
	chainGuardLock    sync.Mutex
	chainGuardArmedBy string
	chainGuardProcess *os.Process
	chainWatchCancel  chan struct{}
)

// chainStateDir is where the opt-out file and the guard log live.
func chainStateDir() string {
	base := os.Getenv("ProgramData")
	if base == "" {
		base = `C:\ProgramData`
	}
	dir := filepath.Join(base, "AwgChain")
	os.MkdirAll(dir, 0o700)
	return dir
}

func chainAutoGuardDisabled() bool {
	_, err := os.Stat(filepath.Join(chainStateDir(), "no-autoguard"))
	return err == nil
}

// chainHopOrder returns the hops of the chain that ends at leaf, bottom hop
// first. A tunnel that is not part of a chain answers with itself alone.
func chainHopOrder(leaf string) []string {
	order := []string{leaf}
	name := leaf
	for i := 0; i < chainMaxDepth; i++ {
		parent := chainParentName(name)
		if parent == "" {
			break
		}
		order = append([]string{parent}, order...)
		name = parent
	}
	return order
}

// chainEndpointOf gives the endpoint of a hop as ip:port, resolving a host
// name if the config carries one.
func chainEndpointOf(name string) (string, error) {
	c, err := conf.LoadFromName(name)
	if err != nil {
		return "", err
	}
	for i := range c.Peers {
		endpoint := c.Peers[i].Endpoint
		if endpoint.IsEmpty() {
			continue
		}
		host := strings.Trim(strings.TrimSpace(endpoint.Host), "[]")
		ip := net.ParseIP(host)
		if ip == nil {
			resolved, err := net.LookupIP(host)
			if err != nil {
				continue
			}
			for _, candidate := range resolved {
				if candidate.To4() != nil {
					ip = candidate
					break
				}
			}
		}
		if ip == nil || ip.To4() == nil {
			continue
		}
		return fmt.Sprintf("%s:%d", ip.String(), endpoint.Port), nil
	}
	return "", fmt.Errorf("no usable IPv4 endpoint in the config of %q", name)
}

// chainDNSOf lists the resolvers of a hop, comma separated for the guard.
func chainDNSOf(name string) string {
	c, err := conf.LoadFromName(name)
	if err != nil {
		return ""
	}
	parts := make([]string, 0, len(c.Interface.DNS))
	for _, server := range c.Interface.DNS {
		parts = append(parts, fmt.Sprint(server))
	}
	return strings.Join(parts, ",")
}

func chainAdapterLUID(name string) (winipcfg.LUID, bool) {
	if strings.TrimSpace(name) == "" {
		return 0, false
	}
	adapters, err := winipcfg.GetAdaptersAddresses(winipcfg.AddressFamily(windows.AF_UNSPEC), winipcfg.GAAFlagDefault)
	if err != nil {
		return 0, false
	}
	for _, adapter := range adapters {
		if strings.EqualFold(adapter.FriendlyName(), strings.TrimSpace(name)) {
			return adapter.LUID, true
		}
	}
	return 0, false
}

// chainLocalNetworks finds the private networks that the given adapter is on,
// so that the kill switch never cuts the machine off from its own LAN. This
// is what keeps a remote desktop session alive while the chain is armed.
func chainLocalNetworks(adapter string) []string {
	result := make([]string, 0, 2)
	luid, ok := chainAdapterLUID(adapter)
	if !ok {
		return result
	}
	rows, err := winipcfg.GetIPForwardTable2(winipcfg.AddressFamily(windows.AF_INET))
	if err != nil {
		return result
	}
	seen := make(map[string]bool, 2)
	for i := range rows {
		if rows[i].InterfaceLUID != luid {
			continue
		}
		if hop := rows[i].NextHop.IP(); hop != nil && !hop.IsUnspecified() {
			continue
		}
		prefix := rows[i].DestinationPrefix.IPNet()
		if prefix.IP == nil || prefix.IP.To4() == nil {
			continue
		}
		ones, bits := prefix.Mask.Size()
		if bits != 32 || ones < 8 || ones > 30 {
			continue
		}
		if !prefix.IP.IsPrivate() {
			continue
		}
		text := prefix.String()
		if seen[text] {
			continue
		}
		seen[text] = true
		result = append(result, text)
	}
	return result
}

// chainArmGuard starts awgchain-guard.exe for the chain ending at leaf.
func (s *ManagerService) chainArmGuard(leaf string) {
	if chainAutoGuardDisabled() {
		log.Printf("[AwgChain] The kill switch is switched off by no-autoguard, leaving it alone")
		return
	}

	chainGuardLock.Lock()
	already := chainGuardProcess != nil
	chainGuardLock.Unlock()
	if already {
		return
	}

	hops := chainHopOrder(leaf)
	if len(hops) < 2 {
		log.Printf("[AwgChain] %s is not part of a chain, so no kill switch", leaf)
		return
	}
	root := hops[0]
	top := hops[len(hops)-1]

	rootEndpoint, err := chainEndpointOf(root)
	if err != nil {
		log.Printf("[AwgChain] Cannot arm the kill switch: %v", err)
		return
	}
	topEndpoint, err := chainEndpointOf(top)
	if err != nil {
		log.Printf("[AwgChain] Cannot arm the kill switch: %v", err)
		return
	}

	self, err := os.Executable()
	if err != nil {
		log.Printf("[AwgChain] Cannot arm the kill switch: %v", err)
		return
	}
	guard := filepath.Join(filepath.Dir(self), chainGuardExeName)
	if _, err := os.Stat(guard); err != nil {
		log.Printf("[AwgChain] %s is missing, so the chain runs without a kill switch", guard)
		return
	}

	args := []string{
		"-hop1if", root,
		"-hop2if", top,
		"-hop1ep", rootEndpoint,
		"-hop2ep", topEndpoint,
		"-allowapp", self,
		"-logfile", filepath.Join(chainStateDir(), "guard-auto-log.txt"),
	}
	if dns := chainDNSOf(top); dns != "" {
		args = append(args, "-dns", dns)
	}
	via := ""
	if c, err := conf.LoadFromName(root); err == nil {
		via = strings.TrimSpace(c.Interface.PinEndpointVia)
	}
	lans := chainLocalNetworks(via)
	if len(lans) > 0 {
		args = append(args, "-lan", strings.Join(lans, ","))
	}

	cmd := exec.Command(guard, args...)
	err = cmd.Start()
	if err != nil {
		log.Printf("[AwgChain] The kill switch would not start: %v", err)
		return
	}

	chainGuardLock.Lock()
	chainGuardProcess = cmd.Process
	chainGuardArmedBy = leaf
	chainGuardLock.Unlock()

	log.Printf("[AwgChain] Kill switch armed for %s -> %s, lan %v, pid %d", root, top, lans, cmd.Process.Pid)

	go func(started *exec.Cmd) {
		started.Wait()
		chainGuardLock.Lock()
		if chainGuardProcess != nil && started.Process != nil && chainGuardProcess.Pid == started.Process.Pid {
			chainGuardProcess = nil
			chainGuardArmedBy = ""
		}
		chainGuardLock.Unlock()
		log.Printf("[AwgChain] The kill switch process has ended")
	}(cmd)
}

func chainSignalGuardStop() error {
	name, err := windows.UTF16PtrFromString(chainGuardStopEventName)
	if err != nil {
		return err
	}
	// Manual reset event. Creating it by name opens the existing one when the
	// guard is already running, which is exactly what we want here.
	handle, err := windows.CreateEvent(nil, 1, 0, name)
	if err != nil && handle == 0 {
		return err
	}
	defer windows.CloseHandle(handle)
	return windows.SetEvent(handle)
}

func chainDisarmGuard() {
	chainGuardLock.Lock()
	process := chainGuardProcess
	chainGuardProcess = nil
	chainGuardArmedBy = ""
	chainGuardLock.Unlock()
	if process == nil {
		return
	}
	err := chainSignalGuardStop()
	if err != nil {
		log.Printf("[AwgChain] Could not ask the kill switch to stand down: %v", err)
	}
	for i := 0; i < 50; i++ {
		time.Sleep(100 * time.Millisecond)
		if !chainProcessAlive(process.Pid) {
			log.Printf("[AwgChain] Kill switch disarmed")
			return
		}
	}
	log.Printf("[AwgChain] The kill switch did not stand down in time, ending it")
	process.Kill()
}

func chainProcessAlive(pid int) bool {
	handle, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, uint32(pid))
	if err != nil {
		return false
	}
	defer windows.CloseHandle(handle)
	var code uint32
	err = windows.GetExitCodeProcess(handle, &code)
	if err != nil {
		return false
	}
	return code == 259 // STILL_ACTIVE
}

// chainHandshakeAge is the age of the freshest handshake of a running hop.
func chainHandshakeAge(c *conf.Config) (time.Duration, bool) {
	best := time.Duration(-1)
	for i := range c.Peers {
		stamp := c.Peers[i].LastHandshakeTime
		if stamp.IsEmpty() {
			continue
		}
		age := time.Since(time.Unix(0, 0).Add(time.Duration(stamp)))
		if best < 0 || age < best {
			best = age
		}
	}
	if best < 0 {
		return 0, false
	}
	return best, true
}

// chainTrouble names the first thing wrong with the chain, or "" when it is
// healthy.
func (s *ManagerService) chainTrouble(leaf string) string {
	for _, name := range chainHopOrder(leaf) {
		state, err := s.State(name)
		if err != nil {
			return fmt.Sprintf("%s cannot be queried: %v", name, err)
		}
		if state != TunnelStarted {
			return fmt.Sprintf("%s is not running", name)
		}
		runtime, err := s.RuntimeConfig(name)
		if err != nil || runtime == nil {
			return fmt.Sprintf("%s does not answer on its pipe", name)
		}
		age, ok := chainHandshakeAge(runtime)
		if !ok {
			return fmt.Sprintf("%s has never handshaken", name)
		}
		if age > chainHandshakeMaxAge {
			return fmt.Sprintf("%s last handshook %d seconds ago", name, int(age.Seconds()))
		}
	}
	return ""
}

// chainRepair drops the chain from the top and raises it again. The kill
// switch deliberately stays armed throughout, so nothing escapes while the
// tunnels are gone.
func (s *ManagerService) chainRepair(leaf string) {
	started := time.Now()
	hops := chainHopOrder(leaf)
	s.chainTearDown(hops)

	for attempt := 1; attempt <= chainStartRetries; attempt++ {
		err := s.Start(leaf)
		if err == nil {
			log.Printf("[AwgChain] Repair: the chain is back up after %d seconds, the kill switch follows the new interfaces by itself", int(time.Since(started).Seconds()))
			return
		}
		log.Printf("[AwgChain] Repair: try %d of %d did not take: %v", attempt, chainStartRetries, err)
		if attempt == chainStartRetries {
			break
		}
		time.Sleep(chainStartRetryGap)
		// A half-raised hop has to be cleared away before the next try.
		s.chainTearDown(hops)
	}
	log.Printf("[AwgChain] Repair: gave up this round after %d seconds, the watch will try again", int(time.Since(started).Seconds()))
}

// chainTearDown stops every hop from the top down and waits until each one
// really is stopped, so the next Start is not refused.
func (s *ManagerService) chainTearDown(hops []string) {
	for i := len(hops) - 1; i >= 0; i-- {
		err := UninstallTunnel(hops[i])
		if err != nil && err != windows.ERROR_SERVICE_DOES_NOT_EXIST {
			log.Printf("[AwgChain] Repair: could not stop %s: %v", hops[i], err)
		}
	}
	for _, name := range hops {
		s.chainWaitStopped(name)
	}
}

func (s *ManagerService) chainWaitStopped(name string) {
	deadline := time.Now().Add(chainStopWait)
	for time.Now().Before(deadline) {
		state, err := s.State(name)
		if err != nil || state == TunnelStopped {
			return
		}
		time.Sleep(chainStopPoll)
	}
	log.Printf("[AwgChain] Repair: %s is taking its time to stop, carrying on anyway", name)
}

func (s *ManagerService) chainWatch(leaf string, stop chan struct{}) {
	log.Printf("[AwgChain] Watching the chain that ends at %s", leaf)
	repairs := 0
	lastRepair := time.Now()
	for {
		select {
		case <-stop:
			log.Printf("[AwgChain] No longer watching the chain")
			return
		case <-time.After(chainWatchInterval):
		}

		reason := s.chainTrouble(leaf)
		if reason == "" {
			// A healthy chain is also the moment to arm a kill switch that is
			// not up yet, for instance because the first try ran before the
			// interfaces existed. Arming twice is harmless.
			s.chainArmGuard(leaf)
			continue
		}
		grace := chainRepairGrace
		if repairs >= chainMaxRepairs {
			grace = chainSlowRepairGrace
		}
		if time.Since(lastRepair) < grace {
			continue
		}
		if repairs == chainMaxRepairs {
			// Never give up and never quietly let go of the kill switch: a
			// chain that cannot be fixed must not turn into plain traffic.
			log.Printf("[AwgChain] The chain is still unwell (%s) after %d repairs, so it is retried every %v from now on, with the kill switch still armed", reason, repairs, chainSlowRepairGrace)
		}
		repairs++
		log.Printf("[AwgChain] The chain needs repair: %s (attempt %d)", reason, repairs)
		s.chainRepair(leaf)
		lastRepair = time.Now()
	}
}

func (s *ManagerService) chainStartWatch(leaf string) {
	chainGuardLock.Lock()
	if chainWatchCancel != nil {
		chainGuardLock.Unlock()
		return
	}
	stop := make(chan struct{})
	chainWatchCancel = stop
	chainGuardLock.Unlock()
	go s.chainWatch(leaf, stop)
}

func chainStopWatch() {
	chainGuardLock.Lock()
	stop := chainWatchCancel
	chainWatchCancel = nil
	chainGuardLock.Unlock()
	if stop != nil {
		close(stop)
	}
}

// chainInstallAndArm replaces the plain InstallTunnel call at the end of
// Start. The top hop of a chain also gets a kill switch and a watch.
func (s *ManagerService) chainInstallAndArm(tunnelName, path string) error {
	err := InstallTunnel(path)
	if err != nil {
		return err
	}
	if !chainHopByName(tunnelName) {
		return nil
	}
	if len(chainChildNames(tunnelName)) != 0 {
		// Not the top hop: whoever rides on this one will arm the chain.
		return nil
	}
	go s.chainArmWhenReady(tunnelName)
	return nil
}

func (s *ManagerService) chainArmWhenReady(leaf string) {
	err := s.chainWaitForHop(leaf)
	if err != nil {
		// A chain that did not come up cleanly still gets a watch, because
		// the watch is the thing that repairs it.
		log.Printf("[AwgChain] %s did not come up cleanly (%v), so the watch takes over", leaf, err)
	} else {
		s.chainArmGuard(leaf)
	}
	s.chainStartWatch(leaf)
}

// chainBeforeStop runs when a tunnel is stopped on purpose. A repair uses
// UninstallTunnel directly and therefore does not come through here, which is
// what keeps the kill switch armed while the chain is being rebuilt.
func (s *ManagerService) chainBeforeStop(tunnelName string) {
	chainGuardLock.Lock()
	armedBy := chainGuardArmedBy
	watching := chainWatchCancel != nil
	chainGuardLock.Unlock()
	if armedBy == "" && !watching {
		return
	}
	involved := false
	if armedBy != "" {
		for _, hop := range chainHopOrder(armedBy) {
			if strings.EqualFold(hop, tunnelName) {
				involved = true
				break
			}
		}
	} else {
		involved = chainHopByName(tunnelName)
	}
	if !involved {
		return
	}
	log.Printf("[AwgChain] %s was asked to stop, so the watch and the kill switch stand down", tunnelName)
	chainStopWatch()
	chainDisarmGuard()
}

//go:build windows

/* AwgChain patch 54 - the window asks the manager about the chain.
 *
 * Everything the chain knows about itself lives in the manager: which hops a
 * chain has, whether they run, and whether the kill switch is armed. The
 * window knew none of that, so the only honest answer was the log or
 * awgchain.bat. One extra IPC call fixes it. The answer carries names and
 * states only, never keys.
 */

package manager

import (
	"encoding/gob"
	"strings"

	"github.com/amnezia-vpn/amneziawg-windows/v3/conf"
)

// ChainStatusMethodType sits far above the upstream method numbers, so a new
// upstream method can never take the same value by accident.
const ChainStatusMethodType MethodType = 100

// ChainHopStatus is one link of the chain.
type ChainHopStatus struct {
	Name   string
	State  TunnelState
	Hidden bool
}

// ChainStatusInfo is the whole picture the panel draws.
type ChainStatusInfo struct {
	Leaf     string
	Hops     []ChainHopStatus
	LockOn   bool
	LockLeaf string
	InProc   bool
}

// chainLockLeafName tells which chain the kill switch is holding.
func chainLockLeafName() string {
	chainLockMu.Lock()
	defer chainLockMu.Unlock()
	return chainLockLeaf
}

// chainPickLeaf finds the visible tunnel of a chain: the one that owns a
// hidden hop. A chain that is not stopped wins over a stopped one.
func (s *ManagerService) chainPickLeaf() string {
	tunnels, err := s.Tunnels()
	if err != nil {
		return ""
	}
	known := make(map[string]bool, len(tunnels))
	for _, t := range tunnels {
		known[strings.ToLower(t.Name)] = true
	}
	best := ""
	for _, t := range tunnels {
		if conf.ChainIsHiddenHopName(t.Name) {
			continue
		}
		if !known[strings.ToLower(conf.ChainHiddenHopName(t.Name))] {
			continue
		}
		if best == "" {
			best = t.Name
		}
		if state, err := s.State(t.Name); err == nil && state != TunnelStopped {
			return t.Name
		}
	}
	return best
}

// ChainStatus is the answer the window gets.
func (s *ManagerService) ChainStatus() ChainStatusInfo {
	info := ChainStatusInfo{
		LockOn:   chainLockIsOn(),
		LockLeaf: chainLockLeafName(),
		InProc:   !chainInProcLockDisabled(),
	}
	leaf := info.LockLeaf
	if leaf == "" {
		leaf = s.chainPickLeaf()
	}
	if leaf == "" {
		return info
	}
	info.Leaf = leaf
	for _, name := range chainHopOrder(leaf) {
		state, err := s.State(name)
		if err != nil {
			state = TunnelUnknown
		}
		info.Hops = append(info.Hops, ChainHopStatus{
			Name:   name,
			State:  state,
			Hidden: conf.ChainIsHiddenHopName(name),
		})
	}
	return info
}

// chainServeStatus is the server side of the call. ipc_server.go calls it from
// its switch, so the patch touches upstream code in exactly one place.
func (s *ManagerService) chainServeStatus(encoder *gob.Encoder) error {
	return encoder.Encode(s.ChainStatus())
}

// IPCClientChainStatus is the client side of the call.
func IPCClientChainStatus() (info ChainStatusInfo, err error) {
	rpcMutex.Lock()
	defer rpcMutex.Unlock()

	err = rpcEncoder.Encode(ChainStatusMethodType)
	if err != nil {
		return
	}
	err = rpcDecoder.Decode(&info)
	return
}

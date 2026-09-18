/* SPDX-License-Identifier: MIT
 *
 * AwgChain pack 55: where the check boxes live.
 *
 * The file is written by the service only, so the interface always asks the
 * manager over the pipe instead of touching it directly.
 */

package manager

import (
	"encoding/json"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-windows/v3/tunnel/firewall"
)

// ChainTunnelSettings is what the three check boxes of one tunnel say.
type ChainTunnelSettings struct {
	KillSwitch bool
	BlockIPv6  bool
	AllowLAN   bool
}

// ChainGlobalSettings is what the Settings tab says about the whole program.
type ChainGlobalSettings struct {
	RaiseOnStart   bool
	RaiseTunnel    string
	LiftLockOnQuit bool
}

type chainSettingsBook struct {
	Global  ChainGlobalSettings
	Tunnels map[string]ChainTunnelSettings
	// Inherited stays true until the user saves the boxes for the first time.
	// While it is true the local network is left open no matter what a stored
	// entry says, so a remote desktop into this machine cannot be cut off by
	// a setting nobody has chosen yet.
	Inherited bool
}

var (
	chainSettingsMu    sync.Mutex
	chainSettingsCache *chainSettingsBook
)

func chainSettingsDefaults() ChainTunnelSettings {
	return ChainTunnelSettings{KillSwitch: true, BlockIPv6: true, AllowLAN: true}
}

func chainSettingsPath() string {
	root := os.Getenv("ProgramData")
	if len(root) == 0 {
		root = "C:\\ProgramData"
	}
	return filepath.Join(root, "AwgChain", "settings.json")
}

func chainSettingsLoadLocked() *chainSettingsBook {
	if chainSettingsCache != nil {
		return chainSettingsCache
	}

	book := &chainSettingsBook{
		Global:    ChainGlobalSettings{LiftLockOnQuit: true},
		Tunnels:   make(map[string]ChainTunnelSettings),
		Inherited: true,
	}

	data, err := os.ReadFile(chainSettingsPath())
	if err == nil {
		stored := &chainSettingsBook{}
		if json.Unmarshal(data, stored) == nil {
			if stored.Tunnels == nil {
				stored.Tunnels = make(map[string]ChainTunnelSettings)
			}
			book = stored
		}
	}

	chainSettingsCache = book
	return book
}

func chainSettingsStoreLocked() error {
	book := chainSettingsCache
	if book == nil {
		return nil
	}

	data, err := json.MarshalIndent(book, "", "  ")
	if err != nil {
		return err
	}

	path := chainSettingsPath()
	err = os.MkdirAll(filepath.Dir(path), os.ModePerm)
	if err != nil {
		return err
	}

	err = os.WriteFile(path, data, 0600)
	if err != nil {
		log.Printf("[AwgChain] The settings could not be written (%v)", err)
		return err
	}

	return nil
}

// ChainSettingsFor returns the boxes of one tunnel, filled in with the
// defaults when nobody has saved anything yet.
func ChainSettingsFor(name string) ChainTunnelSettings {
	chainSettingsMu.Lock()
	defer chainSettingsMu.Unlock()

	book := chainSettingsLoadLocked()
	settings, ok := book.Tunnels[strings.ToLower(name)]
	if !ok {
		return chainSettingsDefaults()
	}
	if book.Inherited {
		settings.AllowLAN = true
	}
	return settings
}

// ChainSettingsSave writes the boxes of one tunnel.
func ChainSettingsSave(name string, settings ChainTunnelSettings) error {
	chainSettingsMu.Lock()
	defer chainSettingsMu.Unlock()

	book := chainSettingsLoadLocked()
	book.Tunnels[strings.ToLower(name)] = settings
	book.Inherited = false
	return chainSettingsStoreLocked()
}

// ChainGlobal returns the settings of the whole program.
func ChainGlobal() ChainGlobalSettings {
	chainSettingsMu.Lock()
	defer chainSettingsMu.Unlock()

	return chainSettingsLoadLocked().Global
}

// ChainGlobalSave writes the settings of the whole program.
func ChainGlobalSave(global ChainGlobalSettings) error {
	chainSettingsMu.Lock()
	defer chainSettingsMu.Unlock()

	book := chainSettingsLoadLocked()
	book.Global = global
	return chainSettingsStoreLocked()
}

// chainSettingsLANs decides which local networks stay reachable behind the
// closed lock. The root tunnel knows the networks, the leaf tunnel carries
// the check box.
func chainSettingsLANs(root, leaf string) []net.IPNet {
	if !ChainSettingsFor(leaf).AllowLAN {
		log.Printf("[AwgChain] The local network stays closed for %s", leaf)
		return nil
	}
	return chainLockLANs(root)
}

// chainApplyIPv6For raises or drops the IPv6 filter for this tunnel.
func chainApplyIPv6For(leaf string) {
	if !ChainSettingsFor(leaf).BlockIPv6 {
		chainDropIPv6Block()
		return
	}

	err := firewall.EnableIPv6Block()
	if err != nil {
		log.Printf("[AwgChain] IPv6 could not be blocked by the filter (%v)", err)
		return
	}
	log.Printf("[AwgChain] IPv6 is blocked by the filter while %s is up", leaf)
}

// chainDropIPv6Block removes the IPv6 filter if it stands.
func chainDropIPv6Block() {
	if !firewall.IPv6BlockIsOn() {
		return
	}
	firewall.DisableIPv6Block()
	log.Printf("[AwgChain] The IPv6 filter is removed")
}

// chainSettingsApplyNow is called right after the boxes are saved. Only the
// IPv6 filter can be changed on a running tunnel; the kill switch and the
// local network are read the next time the chain goes up.
func (s *ManagerService) chainSettingsApplyNow(name string) {
	if !firewall.IPv6BlockIsOn() {
		return
	}
	if !ChainSettingsFor(name).BlockIPv6 {
		chainDropIPv6Block()
	}
}

// chainAutoRaiseOnStart raises the chosen tunnel after the service starts.
// It waits a little so the network stack is up first.
func (s *ManagerService) chainAutoRaiseOnStart() {
	global := ChainGlobal()
	if !global.RaiseOnStart || len(global.RaiseTunnel) == 0 {
		return
	}

	time.Sleep(5 * time.Second)

	err := s.Start(global.RaiseTunnel)
	if err != nil {
		log.Printf("[AwgChain] The tunnel %s could not be raised at start (%v)", global.RaiseTunnel, err)
		return
	}
	log.Printf("[AwgChain] The tunnel %s is raised at start", global.RaiseTunnel)
}

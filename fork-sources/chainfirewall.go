/* SPDX-License-Identifier: MIT
 *
 * AwgChain patch #5: kill switch for a two-hop AmneziaWG chain.
 *
 * This file is purely additive: no upstream file is modified. Every filter
 * lives in its own WFP sublayer created by a *dynamic* session, so the whole
 * rule set disappears as soon as the process that installed it exits (also on
 * a crash or on taskkill). That keeps the machine recoverable.
 *
 * Weights inside our sublayer (higher wins, terminating):
 *   15  permit the hop 1 endpoint for the tunnel binary (any interface)
 *   15  permit the hop 2 endpoint for the tunnel binary, but only when the
 *       packet leaves through the hop 1 interface
 *   14  permit DNS (53/853, UDP+TCP) to the chain resolvers through hop 2
 *   13  block DNS (53/853, UDP+TCP) everywhere else, both families
 *   12  permit everything on the hop 2 interface
 *   11  permit loopback
 *   10  permit DHCPv4 and the configured LAN prefixes
 *    0  block everything else, both families, inbound and outbound
 */

package firewall

import (
	"encoding/binary"
	"errors"
	"net"
	"runtime"
	"unsafe"

	"golang.org/x/sys/windows"
)

// ChainFirewallConfig describes the only traffic allowed to leave the machine
// while the chain is up.
type ChainFirewallConfig struct {
	// LUID of the hop 1 (outer) tunnel interface.
	Hop1LUID uint64
	// LUID of the hop 2 (inner) tunnel interface.
	Hop2LUID uint64
	// Endpoint of hop 1. Reachable over any interface, normally the physical one.
	Hop1Endpoint net.IP
	Hop1Port     uint16
	// Endpoint of hop 2. Reachable only through the hop 1 interface.
	Hop2Endpoint net.IP
	Hop2Port     uint16
	// DNS servers that may be queried, and only through hop 2.
	DNSServers []net.IP
	// Executables allowed to talk to the endpoints above.
	AllowedApps []string
	// Local networks that stay reachable (RDP, the host machine, printers...).
	AllowedLANs []net.IPNet
}

var chainSession uintptr

// EnableChainFirewall installs the chain kill switch. The filters live exactly
// as long as the calling process.
func EnableChainFirewall(cfg *ChainFirewallConfig) error {
	if chainSession != 0 {
		return errors.New("The chain firewall has already been enabled")
	}
	if cfg == nil {
		return errors.New("A chain firewall configuration is required")
	}
	if cfg.Hop1LUID == 0 || cfg.Hop2LUID == 0 {
		return errors.New("Both hop interface LUIDs are required")
	}
	if cfg.Hop1Endpoint.To4() == nil || cfg.Hop2Endpoint.To4() == nil {
		return errors.New("Both hop endpoints must be IPv4 addresses")
	}
	if len(cfg.AllowedApps) == 0 {
		return errors.New("At least one allowed executable is required")
	}

	session, err := createChainWfpSession()
	if err != nil {
		return wrapErr(err)
	}

	hop1LUID := cfg.Hop1LUID
	hop2LUID := cfg.Hop2LUID

	objectInstaller := func(session uintptr) error {
		baseObjects, err := registerChainBaseObjects(session)
		if err != nil {
			return wrapErr(err)
		}

		appIDs, err := appIDsFromFileNames(cfg.AllowedApps)
		if err != nil {
			return wrapErr(err)
		}
		defer freeAppIDs(appIDs)

		err = permitEndpoint(session, baseObjects, 15, appIDs, cfg.Hop1Endpoint, cfg.Hop1Port, 0, "hop 1")
		if err != nil {
			return wrapErr(err)
		}

		err = permitEndpoint(session, baseObjects, 15, appIDs, cfg.Hop2Endpoint, cfg.Hop2Port, hop1LUID, "hop 2 through hop 1")
		if err != nil {
			return wrapErr(err)
		}

		if len(cfg.DNSServers) > 0 {
			err = permitChainDNS(session, baseObjects, 14, cfg.DNSServers, hop2LUID)
			if err != nil {
				return wrapErr(err)
			}
		}

		err = blockDNSPorts(session, baseObjects, 13)
		if err != nil {
			return wrapErr(err)
		}

		err = permitTunInterface(session, baseObjects, 12, hop2LUID)
		if err != nil {
			return wrapErr(err)
		}

		err = permitLoopback(session, baseObjects, 11)
		if err != nil {
			return wrapErr(err)
		}

		err = permitDHCPIPv4(session, baseObjects, 10)
		if err != nil {
			return wrapErr(err)
		}

		if len(cfg.AllowedLANs) > 0 {
			err = permitLANs(session, baseObjects, 10, cfg.AllowedLANs)
			if err != nil {
				return wrapErr(err)
			}
		}

		return blockAll(session, baseObjects, 0)
	}

	err = runTransaction(session, objectInstaller)
	if err != nil {
		fwpmEngineClose0(session)
		return wrapErr(err)
	}

	chainSession = session
	return nil
}

// DisableChainFirewall removes every filter installed by EnableChainFirewall.
func DisableChainFirewall() {
	if chainSession != 0 {
		fwpmEngineClose0(chainSession)
		chainSession = 0
	}
}

func createChainWfpSession() (uintptr, error) {
	sessionDisplayData, err := createWtFwpmDisplayData0("AwgChain", "AwgChain kill switch dynamic session")
	if err != nil {
		return 0, wrapErr(err)
	}

	session := wtFwpmSession0{
		displayData:          *sessionDisplayData,
		flags:                cFWPM_SESSION_FLAG_DYNAMIC,
		txnWaitTimeoutInMSec: windows.INFINITE,
	}

	sessionHandle := uintptr(0)

	err = fwpmEngineOpen0(nil, cRPC_C_AUTHN_WINNT, nil, &session, unsafe.Pointer(&sessionHandle))
	if err != nil {
		return 0, wrapErr(err)
	}

	return sessionHandle, nil
}

func registerChainBaseObjects(session uintptr) (*baseObjects, error) {
	bo := &baseObjects{}
	var err error
	bo.provider, err = windows.GenerateGUID()
	if err != nil {
		return nil, wrapErr(err)
	}
	bo.filters, err = windows.GenerateGUID()
	if err != nil {
		return nil, wrapErr(err)
	}

	{
		displayData, err := createWtFwpmDisplayData0("AwgChain", "AwgChain kill switch provider")
		if err != nil {
			return nil, wrapErr(err)
		}
		provider := wtFwpmProvider0{
			providerKey: bo.provider,
			displayData: *displayData,
		}
		err = fwpmProviderAdd0(session, &provider, 0)
		if err != nil {
			return nil, wrapErr(err)
		}
	}

	{
		displayData, err := createWtFwpmDisplayData0("AwgChain filters", "AwgChain kill switch filters")
		if err != nil {
			return nil, wrapErr(err)
		}
		sublayer := wtFwpmSublayer0{
			subLayerKey: bo.filters,
			displayData: *displayData,
			providerKey: &bo.provider,
			weight:      ^uint16(0),
		}
		err = fwpmSubLayerAdd0(session, &sublayer, 0)
		if err != nil {
			return nil, wrapErr(err)
		}
	}

	return bo, nil
}

func appIDsFromFileNames(paths []string) ([]*wtFwpByteBlob, error) {
	appIDs := make([]*wtFwpByteBlob, 0, len(paths))
	for _, path := range paths {
		pathPtr, err := windows.UTF16PtrFromString(path)
		if err != nil {
			freeAppIDs(appIDs)
			return nil, wrapErr(err)
		}
		var appID *wtFwpByteBlob
		err = fwpmGetAppIdFromFileName0(pathPtr, unsafe.Pointer(&appID))
		if err != nil {
			freeAppIDs(appIDs)
			return nil, wrapErr(err)
		}
		appIDs = append(appIDs, appID)
	}
	return appIDs, nil
}

func freeAppIDs(appIDs []*wtFwpByteBlob) {
	for i := range appIDs {
		if appIDs[i] != nil {
			fwpmFreeMemory0(unsafe.Pointer(&appIDs[i]))
		}
	}
}

type chainLayer struct {
	name string
	key  windows.GUID
}

func chainLayersV4() []chainLayer {
	return []chainLayer{
		{"outbound, IPv4", cFWPM_LAYER_ALE_AUTH_CONNECT_V4},
		{"inbound, IPv4", cFWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V4},
	}
}

func chainLayersBoth() []chainLayer {
	return []chainLayer{
		{"outbound, IPv4", cFWPM_LAYER_ALE_AUTH_CONNECT_V4},
		{"inbound, IPv4", cFWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V4},
		{"outbound, IPv6", cFWPM_LAYER_ALE_AUTH_CONNECT_V6},
		{"inbound, IPv6", cFWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V6},
	}
}

func dnsPortAndProtocolConditions() []wtFwpmFilterCondition0 {
	return []wtFwpmFilterCondition0{
		{
			fieldKey:  cFWPM_CONDITION_IP_REMOTE_PORT,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_UINT16,
				value: uintptr(53),
			},
		},
		// Repeat the condition type for logical OR: DNS over TLS.
		{
			fieldKey:  cFWPM_CONDITION_IP_REMOTE_PORT,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_UINT16,
				value: uintptr(853),
			},
		},
		{
			fieldKey:  cFWPM_CONDITION_IP_PROTOCOL,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_UINT8,
				value: uintptr(cIPPROTO_UDP),
			},
		},
		// Repeat the condition type for logical OR.
		{
			fieldKey:  cFWPM_CONDITION_IP_PROTOCOL,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_UINT8,
				value: uintptr(cIPPROTO_TCP),
			},
		},
	}
}

// permitEndpoint allows the given executables to exchange UDP with a single
// endpoint. When localInterfaceLUID is not zero, the packet must leave through
// that interface.
func permitEndpoint(session uintptr, baseObjects *baseObjects, weight uint8, appIDs []*wtFwpByteBlob, ip net.IP, port uint16, localInterfaceLUID uint64, label string) error {
	ip4 := ip.To4()
	if ip4 == nil {
		return errors.New("Only IPv4 endpoints are supported")
	}
	address := binary.BigEndian.Uint32(ip4)
	luid := localInterfaceLUID

	for _, appID := range appIDs {
		conditions := make([]wtFwpmFilterCondition0, 0, 5)

		conditions = append(conditions, wtFwpmFilterCondition0{
			fieldKey:  cFWPM_CONDITION_ALE_APP_ID,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_BYTE_BLOB_TYPE,
				value: uintptr(unsafe.Pointer(appID)),
			},
		})
		conditions = append(conditions, wtFwpmFilterCondition0{
			fieldKey:  cFWPM_CONDITION_IP_PROTOCOL,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_UINT8,
				value: uintptr(cIPPROTO_UDP),
			},
		})
		conditions = append(conditions, wtFwpmFilterCondition0{
			fieldKey:  cFWPM_CONDITION_IP_REMOTE_ADDRESS,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_UINT32,
				value: uintptr(address),
			},
		})
		conditions = append(conditions, wtFwpmFilterCondition0{
			fieldKey:  cFWPM_CONDITION_IP_REMOTE_PORT,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_UINT16,
				value: uintptr(port),
			},
		})
		if luid != 0 {
			conditions = append(conditions, wtFwpmFilterCondition0{
				fieldKey:  cFWPM_CONDITION_IP_LOCAL_INTERFACE,
				matchType: cFWP_MATCH_EQUAL,
				conditionValue: wtFwpConditionValue0{
					_type: cFWP_UINT64,
					value: uintptr(unsafe.Pointer(&luid)),
				},
			})
		}

		filter := wtFwpmFilter0{
			providerKey:         &baseObjects.provider,
			subLayerKey:         baseObjects.filters,
			weight:              filterWeight(weight),
			numFilterConditions: uint32(len(conditions)),
			filterCondition:     (*wtFwpmFilterCondition0)(unsafe.Pointer(&conditions[0])),
			action: wtFwpmAction0{
				_type: cFWP_ACTION_PERMIT,
			},
		}

		filterID := uint64(0)

		for _, layer := range chainLayersV4() {
			displayData, err := createWtFwpmDisplayData0("Permit "+label+" endpoint ("+layer.name+")", "")
			if err != nil {
				return wrapErr(err)
			}
			filter.displayData = *displayData
			filter.layerKey = layer.key
			err = fwpmFilterAdd0(session, &filter, 0, &filterID)
			if err != nil {
				return wrapErr(err)
			}
		}

		runtime.KeepAlive(conditions)
	}

	runtime.KeepAlive(&luid)
	return nil
}

// permitChainDNS allows DNS to the given servers, but only through hop 2.
func permitChainDNS(session uintptr, baseObjects *baseObjects, weight uint8, servers []net.IP, localInterfaceLUID uint64) error {
	luid := localInterfaceLUID
	conditions := make([]wtFwpmFilterCondition0, 0, 5+len(servers))

	conditions = append(conditions, wtFwpmFilterCondition0{
		fieldKey:  cFWPM_CONDITION_IP_LOCAL_INTERFACE,
		matchType: cFWP_MATCH_EQUAL,
		conditionValue: wtFwpConditionValue0{
			_type: cFWP_UINT64,
			value: uintptr(unsafe.Pointer(&luid)),
		},
	})
	conditions = append(conditions, dnsPortAndProtocolConditions()...)

	serverCount := 0
	for _, ip := range servers {
		ip4 := ip.To4()
		if ip4 == nil {
			continue
		}
		conditions = append(conditions, wtFwpmFilterCondition0{
			fieldKey:  cFWPM_CONDITION_IP_REMOTE_ADDRESS,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_UINT32,
				value: uintptr(binary.BigEndian.Uint32(ip4)),
			},
		})
		serverCount++
	}
	if serverCount == 0 {
		return errors.New("No IPv4 DNS server was given")
	}

	filter := wtFwpmFilter0{
		providerKey:         &baseObjects.provider,
		subLayerKey:         baseObjects.filters,
		weight:              filterWeight(weight),
		numFilterConditions: uint32(len(conditions)),
		filterCondition:     (*wtFwpmFilterCondition0)(unsafe.Pointer(&conditions[0])),
		action: wtFwpmAction0{
			_type: cFWP_ACTION_PERMIT,
		},
	}

	filterID := uint64(0)

	for _, layer := range chainLayersV4() {
		displayData, err := createWtFwpmDisplayData0("Permit chain DNS ("+layer.name+")", "")
		if err != nil {
			return wrapErr(err)
		}
		filter.displayData = *displayData
		filter.layerKey = layer.key
		err = fwpmFilterAdd0(session, &filter, 0, &filterID)
		if err != nil {
			return wrapErr(err)
		}
	}

	runtime.KeepAlive(conditions)
	runtime.KeepAlive(&luid)
	return nil
}

// blockDNSPorts blocks ports 53 and 853 (UDP and TCP) on both families.
func blockDNSPorts(session uintptr, baseObjects *baseObjects, weight uint8) error {
	conditions := dnsPortAndProtocolConditions()

	filter := wtFwpmFilter0{
		providerKey:         &baseObjects.provider,
		subLayerKey:         baseObjects.filters,
		weight:              filterWeight(weight),
		numFilterConditions: uint32(len(conditions)),
		filterCondition:     (*wtFwpmFilterCondition0)(unsafe.Pointer(&conditions[0])),
		action: wtFwpmAction0{
			_type: cFWP_ACTION_BLOCK,
		},
	}

	filterID := uint64(0)

	for _, layer := range chainLayersBoth() {
		displayData, err := createWtFwpmDisplayData0("Block DNS outside the chain ("+layer.name+")", "")
		if err != nil {
			return wrapErr(err)
		}
		filter.displayData = *displayData
		filter.layerKey = layer.key
		err = fwpmFilterAdd0(session, &filter, 0, &filterID)
		if err != nil {
			return wrapErr(err)
		}
	}

	runtime.KeepAlive(conditions)
	return nil
}

// permitLANs keeps the given IPv4 prefixes reachable so that remote desktop,
// the host machine and local devices do not disappear with the kill switch.
func permitLANs(session uintptr, baseObjects *baseObjects, weight uint8, lans []net.IPNet) error {
	masks := make([]wtFwpV4AddrAndMask, 0, len(lans))
	for _, lan := range lans {
		ip4 := lan.IP.To4()
		if ip4 == nil || len(lan.Mask) != net.IPv4len {
			continue
		}
		masks = append(masks, wtFwpV4AddrAndMask{
			addr: binary.BigEndian.Uint32(ip4),
			mask: binary.BigEndian.Uint32(lan.Mask),
		})
	}
	if len(masks) == 0 {
		return nil
	}

	for i := range masks {
		condition := wtFwpmFilterCondition0{
			fieldKey:  cFWPM_CONDITION_IP_REMOTE_ADDRESS,
			matchType: cFWP_MATCH_EQUAL,
			conditionValue: wtFwpConditionValue0{
				_type: cFWP_V4_ADDR_MASK,
				value: uintptr(unsafe.Pointer(&masks[i])),
			},
		}

		filter := wtFwpmFilter0{
			providerKey:         &baseObjects.provider,
			subLayerKey:         baseObjects.filters,
			weight:              filterWeight(weight),
			numFilterConditions: 1,
			filterCondition:     (*wtFwpmFilterCondition0)(unsafe.Pointer(&condition)),
			action: wtFwpmAction0{
				_type: cFWP_ACTION_PERMIT,
			},
		}

		filterID := uint64(0)

		for _, layer := range chainLayersV4() {
			displayData, err := createWtFwpmDisplayData0("Permit local network ("+layer.name+")", "")
			if err != nil {
				return wrapErr(err)
			}
			filter.displayData = *displayData
			filter.layerKey = layer.key
			err = fwpmFilterAdd0(session, &filter, 0, &filterID)
			if err != nil {
				return wrapErr(err)
			}
		}

		runtime.KeepAlive(&condition)
	}

	runtime.KeepAlive(masks)
	return nil
}

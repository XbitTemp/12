//go:build windows

/* AwgChain patch 14 - two configs become one tunnel entry.
 *
 * The pair is named after the visible hop:
 *
 *     warpam           the inner hop, the one the user sees and clicks
 *     warpam-hop1      the outer WARP hop, hidden from the list
 *
 * A second pair becomes warpam1 / warpam1-hop1, a third warpam2 and so on.
 * The old names hop2-amnezia / hop1-warp keep working as a legacy pair.
 */

package conf

import (
	"errors"
	"net"
	"strconv"
	"strings"
)

const (
	ChainPairBase     = "warpam"
	ChainHiddenSuffix = "-hop1"
	ChainLegacyInner  = "hop2-amnezia"
	ChainLegacyOuter  = "hop1-warp"
	ChainHop1MTU      = 1420
	ChainHop2MTU      = 1360
)

// ChainHiddenHopName gives the name of the outer hop that belongs to a
// visible tunnel name.
func ChainHiddenHopName(visible string) string {
	visible = strings.TrimSpace(visible)
	if strings.EqualFold(visible, ChainLegacyInner) {
		return ChainLegacyOuter
	}
	return visible + ChainHiddenSuffix
}

// ChainIsHiddenHopName reports whether a tunnel is the outer hop of a chain,
// which the interface keeps out of the list.
func ChainIsHiddenHopName(name string) bool {
	lower := strings.ToLower(strings.TrimSpace(name))
	return strings.HasSuffix(lower, ChainHiddenSuffix) || strings.HasPrefix(lower, "hop1-")
}

// ChainNextPairName picks warpam, then warpam1, warpam2 ... avoiding every
// name that is already taken.
func ChainNextPairName(taken []string) string {
	used := make(map[string]bool, len(taken)*2)
	for _, name := range taken {
		used[strings.ToLower(strings.TrimSpace(name))] = true
	}
	free := func(candidate string) bool {
		if used[strings.ToLower(candidate)] {
			return false
		}
		return !used[strings.ToLower(ChainHiddenHopName(candidate))]
	}
	if free(ChainPairBase) {
		return ChainPairBase
	}
	for i := 1; i < 1000; i++ {
		candidate := ChainPairBase + strconv.Itoa(i)
		if free(candidate) {
			return candidate
		}
	}
	return ChainPairBase + "-new"
}

// The address ranges Cloudflare hands out for WARP endpoints.
var chainWarpBlocks = []string{
	"162.159.192.0/19",
	"188.114.96.0/20",
	"8.6.112.0/20",
}

// ChainLooksLikeWarp reports whether a config points at Cloudflare WARP.
func ChainLooksLikeWarp(c *Config) bool {
	if c == nil {
		return false
	}
	for i := range c.Peers {
		host := strings.ToLower(strings.TrimSpace(c.Peers[i].Endpoint.Host))
		if host == "" {
			continue
		}
		if strings.Contains(host, "cloudflare") {
			return true
		}
		ip := net.ParseIP(strings.Trim(host, "[]"))
		if ip == nil {
			continue
		}
		for _, block := range chainWarpBlocks {
			_, network, err := net.ParseCIDR(block)
			if err == nil && network.Contains(ip) {
				return true
			}
		}
	}
	// WARP always hands out an address out of 172.16.0.0/12.
	for _, addr := range c.Interface.Addresses {
		four := addr.IP.To4()
		if four != nil && four[0] == 172 && four[1] >= 16 && four[1] <= 31 {
			return true
		}
	}
	return false
}

// ChainSortRoles decides which of two configs is the outer WARP hop.
func ChainSortRoles(a, b *Config) (warp *Config, inner *Config, err error) {
	if a == nil || b == nil {
		return nil, nil, errors.New("нужны два файла конфигурации")
	}
	aWarp := ChainLooksLikeWarp(a)
	bWarp := ChainLooksLikeWarp(b)
	switch {
	case aWarp && !bWarp:
		return a, b, nil
	case bWarp && !aWarp:
		return b, a, nil
	case aWarp && bWarp:
		return nil, nil, errors.New("оба файла похожи на конфиги WARP, внутреннего хопа нет")
	}
	return nil, nil, errors.New("ни один файл не похож на конфиг Cloudflare WARP")
}

// ChainBuild returns the two hop configs of a chain named pairName.
func ChainBuild(warp, inner *Config, outerAlias string, pairName string) (*Config, *Config, error) {
	if warp == nil || inner == nil {
		return nil, nil, errors.New("нужны два файла конфигурации")
	}
	outerAlias = strings.TrimSpace(outerAlias)
	if outerAlias == "" {
		return nil, nil, errors.New("не удалось определить адаптер с выходом в интернет")
	}
	pairName = strings.TrimSpace(pairName)
	if !TunnelNameIsValid(pairName) {
		return nil, nil, errors.New("имя цепочки не подходит: " + pairName)
	}
	hiddenName := ChainHiddenHopName(pairName)
	if !TunnelNameIsValid(hiddenName) {
		return nil, nil, errors.New("имя внешнего хопа не подходит: " + hiddenName)
	}
	if !chainHasEndpoint(warp) {
		return nil, nil, errors.New("в конфиге WARP нет строки Endpoint")
	}
	if !chainHasEndpoint(inner) {
		return nil, nil, errors.New("в конфиге Amnezia нет строки Endpoint")
	}

	hop1 := *warp
	hop1.Name = hiddenName
	hop1.Interface.Addresses = append([]IPCidr(nil), warp.Interface.Addresses...)
	hop1.Interface.TableOff = true
	hop1.Interface.PinEndpointVia = outerAlias
	hop1.Interface.MTU = ChainHop1MTU
	hop1.Interface.DNS = nil
	hop1.Interface.DNSSearch = nil
	hop1.Peers = chainCopyPeers(warp.Peers)

	hop2 := *inner
	hop2.Name = pairName
	hop2.Interface.Addresses = append([]IPCidr(nil), inner.Interface.Addresses...)
	hop2.Interface.TableOff = false
	hop2.Interface.PinEndpointVia = hiddenName
	hop2.Interface.MTU = ChainHop2MTU
	hop2.Interface.DNS = append([]net.IP(nil), inner.Interface.DNS...)
	hop2.Interface.DNSSearch = append([]string(nil), inner.Interface.DNSSearch...)
	if len(hop2.Interface.DNS) == 0 {
		hop2.Interface.DNS = []net.IP{net.IPv4(1, 1, 1, 1), net.IPv4(1, 0, 0, 1)}
	}
	hop2.Peers = chainCopyPeers(inner.Peers)
	for i := range hop2.Peers {
		if chainCoversEverything(hop2.Peers[i].AllowedIPs) {
			hop2.Peers[i].AllowedIPs = chainSplitDefault()
		}
	}

	return &hop1, &hop2, nil
}

func chainHasEndpoint(c *Config) bool {
	for i := range c.Peers {
		if !c.Peers[i].Endpoint.IsEmpty() {
			return true
		}
	}
	return false
}

func chainCopyPeers(peers []Peer) []Peer {
	out := make([]Peer, len(peers))
	for i := range peers {
		out[i] = peers[i]
		out[i].AllowedIPs = append([]IPCidr(nil), peers[i].AllowedIPs...)
		out[i].RxBytes = 0
		out[i].TxBytes = 0
		out[i].LastHandshakeTime = 0
		keepalive := strings.TrimSpace(out[i].PersistentKeepalive)
		if keepalive == "" || keepalive == "0" || keepalive == "off" {
			out[i].PersistentKeepalive = "25"
		}
	}
	return out
}

func chainCoversEverything(ips []IPCidr) bool {
	for _, a := range ips {
		if a.Cidr == 0 && a.IP != nil && a.IP.IsUnspecified() {
			return true
		}
	}
	return false
}

// A pair of halves beats a single default route on every routing table, which
// is how the inner hop takes the traffic away from the outer one.
func chainSplitDefault() []IPCidr {
	return []IPCidr{
		{IP: net.IPv4(0, 0, 0, 0).To4(), Cidr: 1},
		{IP: net.IPv4(128, 0, 0, 0).To4(), Cidr: 1},
	}
}

// ChainSummary describes a built chain, for the confirmation dialog.
func ChainSummary(hop1, hop2 *Config) string {
	nl := string([]byte{10})
	var b strings.Builder
	b.WriteString("Туннель: " + hop2.Name + nl + nl)
	b.WriteString("  1. WARP " + chainEndpointOfConfig(hop1) + nl)
	b.WriteString("     через адаптер " + hop1.Interface.PinEndpointVia + ", MTU 1420" + nl)
	b.WriteString("  2. Amnezia " + chainEndpointOfConfig(hop2) + nl)
	b.WriteString("     внутри WARP, MTU 1360, весь трафик" + nl)
	return b.String()
}

func chainEndpointOfConfig(c *Config) string {
	for i := range c.Peers {
		if !c.Peers[i].Endpoint.IsEmpty() {
			return c.Peers[i].Endpoint.String()
		}
	}
	return "без Endpoint"
}

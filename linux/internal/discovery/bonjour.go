package discovery

import (
	"context"
	"fmt"
	"net"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/grandcat/zeroconf"
	"github.com/hashicorp/mdns"
)

const ServiceType = "_omasend._tcp"

type Found struct {
	ID       string
	Name     string
	Host     string
	Port     int
	Platform string
	Seen     time.Time
}

func Start(ctx context.Context, deviceID, deviceName string, port int, onFound func(Found)) (func(), error) {
	if os.Getenv("OMASEND_NO_DISCOVERY") == "1" {
		return func() {}, nil
	}
	instance := fmt.Sprintf("%s-%s", safeName(deviceName), deviceID[:min(6, len(deviceID))])
	server, err := zeroconf.Register(instance, ServiceType, "local.", port, []string{"v=1", "id=" + deviceID, "name=" + deviceName, "platform=" + runtime.GOOS}, nil)
	if err != nil {
		return nil, err
	}
	go browse(ctx, deviceID, onFound)
	return server.Shutdown, nil
}

// Keep querying after the first result, and resolve split PTR/SRV/TXT/address
// replies. Bonjour frequently sends those records in separate packets.
func browse(ctx context.Context, deviceID string, onFound func(Found)) {
	for ctx.Err() == nil {
		entries := make(chan *mdns.ServiceEntry, 128)
		go func() {
			defer close(entries)
			interfaces, _ := net.Interfaces()
			var queries sync.WaitGroup
			for _, iface := range interfaces {
				if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagMulticast == 0 {
					continue
				}
				addresses, _ := iface.Addrs()
				ipv4Enabled, ipv6Enabled := false, false
				for _, address := range addresses {
					if ip, _, err := net.ParseCIDR(address.String()); err == nil && ip.IsPrivate() {
						if ip.To4() != nil {
							ipv4Enabled = true
						} else {
							ipv6Enabled = true
						}
					}
				}
				if !ipv4Enabled && !ipv6Enabled {
					continue
				}
				queries.Add(1)
				go func(nic net.Interface) {
					defer queries.Done()
					_ = mdns.QueryContext(ctx, &mdns.QueryParam{Service: ServiceType, Domain: "local", Timeout: 3 * time.Second, Entries: entries, Interface: &nic, WantUnicastResponse: true, DisableIPv4: !ipv4Enabled, DisableIPv6: !ipv6Enabled})
				}(iface)
			}
			queries.Wait()
		}()
		for entry := range entries {
			if entry == nil || entry.Port < 1 || entry.Port > 65535 || !strings.HasSuffix(strings.ToLower(entry.Name), ServiceType+".local.") {
				continue
			}
			id, name := txtValue(entry.InfoFields, "id"), txtValue(entry.InfoFields, "name")
			if id == "" || id == deviceID {
				continue
			}
			for _, address := range []net.IP{entry.AddrV4, entry.AddrV6} {
				if !usable(address) {
					continue
				}
				onFound(Found{ID: id, Name: name, Host: address.String(), Port: entry.Port, Platform: txtValue(entry.InfoFields, "platform"), Seen: time.Now()})
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(5 * time.Second):
		}
	}
}

func txtValue(values []string, key string) string {
	prefix := key + "="
	for _, value := range values {
		if strings.HasPrefix(value, prefix) {
			return decodeTXT(strings.TrimPrefix(value, prefix))
		}
	}
	return ""
}

func usable(address net.IP) bool {
	return address != nil && !address.IsLoopback() && !address.IsUnspecified() && !address.IsLinkLocalUnicast()
}

func safeName(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "OmaSend"
	}
	return strings.Map(func(r rune) rune {
		if r == '.' || r == '/' || r == '\\' {
			return '-'
		}
		return r
	}, value)
}

// miekg/dns escapes UTF-8 bytes as decimal \DDD sequences in TXT strings.
func decodeTXT(value string) string {
	var out strings.Builder
	for i := 0; i < len(value); i++ {
		if value[i] == '\\' && i+1 < len(value) {
			if i+3 < len(value) {
				if n, err := strconv.Atoi(value[i+1 : i+4]); err == nil && n >= 0 && n <= 255 {
					out.WriteByte(byte(n))
					i += 3
					continue
				}
			}
			i++
		}
		out.WriteByte(value[i])
	}
	return out.String()
}

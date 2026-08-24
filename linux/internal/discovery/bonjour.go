package discovery

import (
	"context"
	"fmt"
	"net"
	"strings"

	"github.com/grandcat/zeroconf"
)

const ServiceType = "_omasend._tcp"

type Found struct {
	ID   string
	Name string
	Host string
	Port int
}

func Start(ctx context.Context, deviceID, deviceName string, port int, onFound func(Found)) (func(), error) {
	instance := fmt.Sprintf("%s-%s", safeName(deviceName), deviceID[:min(6, len(deviceID))])
	server, err := zeroconf.Register(instance, ServiceType, "local.", port, []string{"v=1", "id=" + deviceID, "name=" + deviceName}, nil)
	if err != nil {
		return nil, err
	}
	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		server.Shutdown()
		return nil, err
	}
	entries := make(chan *zeroconf.ServiceEntry)
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case entry := <-entries:
				if entry == nil {
					continue
				}
				id, name := txtValue(entry.Text, "id"), txtValue(entry.Text, "name")
				if id == "" || id == deviceID {
					continue
				}
				for _, address := range append(entry.AddrIPv4, entry.AddrIPv6...) {
					if !usable(address) {
						continue
					}
					onFound(Found{ID: id, Name: name, Host: address.String(), Port: entry.Port})
					break
				}
			}
		}
	}()
	if err := resolver.Browse(ctx, ServiceType, "local.", entries); err != nil {
		server.Shutdown()
		return nil, err
	}
	return server.Shutdown, nil
}

func txtValue(values []string, key string) string {
	prefix := key + "="
	for _, value := range values {
		if strings.HasPrefix(value, prefix) {
			return strings.TrimPrefix(value, prefix)
		}
	}
	return ""
}

func usable(address net.IP) bool {
	return !address.IsLoopback() && !address.IsUnspecified() && !address.IsLinkLocalUnicast()
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

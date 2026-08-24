package discovery

import (
	"context"
	"encoding/json"
	"net"
	"os/exec"
	"strings"
	"time"
)

type tailStatus struct {
	Peer map[string]tailPeer `json:"Peer"`
}

type tailPeer struct {
	TailscaleIPs []string `json:"TailscaleIPs"`
	Online       bool     `json:"Online"`
}

func TailscaleHosts(ctx context.Context) []string {
	path, err := exec.LookPath("tailscale")
	if err != nil {
		return nil
	}
	commandCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	output, err := exec.CommandContext(commandCtx, path, "status", "--json").Output()
	if err != nil {
		return nil
	}
	var status tailStatus
	if json.Unmarshal(output, &status) != nil {
		return nil
	}
	var result []string
	for _, peer := range status.Peer {
		if !peer.Online {
			continue
		}
		for _, address := range peer.TailscaleIPs {
			ip := net.ParseIP(strings.TrimSpace(address))
			if ip != nil && ip.To4() != nil {
				result = append(result, ip.String())
				break
			}
		}
	}
	return result
}

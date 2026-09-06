package daemon

import (
	"context"
	"errors"
	"net"
	"runtime"
	"sort"
	"time"

	"github.com/Aayush9029/OmaSend/linux/internal/ipc"
	"github.com/Aayush9029/OmaSend/linux/internal/model"
)

// RunBrowser advertises a separate peer without watching the host OS clipboard.
func (d *Daemon) RunBrowser(ctx context.Context) error {
	d.browser = true
	return d.Run(ctx, "")
}

func (d *Daemon) BrowserStatus() model.Status                     { return d.status() }
func (d *Daemon) BrowserHistory() []model.HistoryItem             { return d.store.Snapshot().History }
func (d *Daemon) BrowserItem(id string) (model.HistoryItem, bool) { return d.store.HistoryItem(id) }
func (d *Daemon) BrowserMode(value bool) error {
	response := d.handleIPC(ipc.Request{Action: "lan", Value: &value})
	if !response.OK {
		return errors.New(response.Error)
	}
	return nil
}
func (d *Daemon) BrowserPair(code string) error {
	response := d.handleIPC(ipc.Request{Action: "pair-set", PairingCode: code})
	if !response.OK {
		return errors.New(response.Error)
	}
	return nil
}
func (d *Daemon) BrowserConnect(ctx context.Context, host string, port int) error {
	if port < 1 || port > 65535 || !IsLAN(net.ParseIP(host)) {
		return errors.New("enter a local IP address and port")
	}
	return d.send(ctx, host, port, d.newMessage("hello", ""), true, "Local network")
}

type BrowserResult struct {
	Sent  int `json:"sent"`
	Peers int `json:"peers"`
}

func (d *Daemon) BrowserSend(ctx context.Context, text string) (BrowserResult, error) {
	message := d.newMessage("clipboard", text)
	message.ContentType = "text/plain"
	if len(text) > model.MaxClipboard || !model.ValidClipboard(message) {
		return BrowserResult{}, errors.New("enter text up to 10 MB")
	}
	if _, err := d.store.AddHistory(historyItem(message, d.store.Snapshot().DeviceID)); err != nil {
		return BrowserResult{}, err
	}
	peers := d.activePeers(25 * time.Second)
	result := BrowserResult{Peers: len(peers)}
	for _, p := range peers {
		if d.send(ctx, p.Host, p.Port, message, false, p.Via) == nil {
			result.Sent++
		}
	}
	return result, nil
}

func (d *Daemon) BrowserFile(ctx context.Context, path, name string, size int64) (BrowserResult, error) {
	hash, err := hashFile(path)
	if err != nil {
		return BrowserResult{}, err
	}
	message := d.newMessage("file", "")
	message.ContentType = "application/x-omasend-file"
	message.FileName = name
	message.FileSize = size
	message.FilePath = path
	message.FileSHA256 = hash
	if _, err := d.store.AddHistory(historyItem(message, d.store.Snapshot().DeviceID)); err != nil {
		return BrowserResult{}, err
	}
	peers := d.activePeers(25 * time.Second)
	result := BrowserResult{Peers: len(peers)}
	for _, p := range peers {
		if d.sendFile(ctx, p, message) == nil {
			result.Sent++
		}
	}
	return result, nil
}

// BrowserDevice keeps discovery separate from authenticated connections.
type BrowserDevice struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Platform  string `json:"platform,omitempty"`
	Connected bool   `json:"connected"`
}

func (d *Daemon) BrowserPlatform() string { return runtime.GOOS }
func (d *Daemon) BrowserDevices() []BrowserDevice {
	devices := map[string]BrowserDevice{}
	d.mu.RLock()
	for _, found := range d.candidates {
		if !found.Seen.IsZero() && time.Since(found.Seen) > 5*time.Minute {
			continue
		}
		devices[found.ID] = BrowserDevice{ID: found.ID, Name: found.Name, Platform: found.Platform}
	}
	d.mu.RUnlock()
	for _, peer := range d.activePeers(25 * time.Second) {
		device := devices[peer.ID]
		device.ID = peer.ID
		device.Name = peer.Name
		device.Connected = true
		devices[peer.ID] = device
	}
	result := make([]BrowserDevice, 0, len(devices))
	for _, device := range devices {
		result = append(result, device)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result
}

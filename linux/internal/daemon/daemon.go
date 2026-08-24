package daemon

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/Aayush9029/OmaSend/linux/internal/clipboard"
	"github.com/Aayush9029/OmaSend/linux/internal/config"
	"github.com/Aayush9029/OmaSend/linux/internal/discovery"
	"github.com/Aayush9029/OmaSend/linux/internal/ipc"
	"github.com/Aayush9029/OmaSend/linux/internal/model"
	"github.com/Aayush9029/OmaSend/linux/internal/protocol"
)

type Daemon struct {
	store *config.Store
	clip  *clipboard.Wayland
	port  int

	mu    sync.RWMutex
	peers map[string]model.Peer
}

func New(store *config.Store) *Daemon {
	port := model.DefaultPort
	if value, err := strconv.Atoi(os.Getenv("OMASEND_PORT")); err == nil && value > 0 && value < 65536 {
		port = value
	}
	return &Daemon{store: store, clip: &clipboard.Wayland{}, port: port, peers: map[string]model.Peer{}}
}

func (d *Daemon) Run(ctx context.Context, socketPath string) error {
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", d.port))
	if err != nil {
		return err
	}
	defer listener.Close()
	stop := make(chan struct{})
	defer close(stop)

	go func() { <-ctx.Done(); listener.Close() }()
	go d.accept(ctx, listener)
	go d.clip.Watch(ctx, d.localClipboardChanged)
	go func() { _ = ipc.Serve(socketPath, d.handleIPC, stop) }()

	snapshot := d.store.Snapshot()
	shutdownBonjour, bonjourErr := discovery.Start(ctx, snapshot.DeviceID, snapshot.DeviceName, d.port, func(found discovery.Found) {
		d.upsertPeer(model.Peer{ID: found.ID, Name: found.Name, Host: found.Host, Port: found.Port, Via: "Local network", LastSeen: time.Now()})
		go d.sendHello(ctx, found.Host, found.Port, "Local network")
	})
	if shutdownBonjour != nil {
		defer shutdownBonjour()
	}
	if bonjourErr != nil {
		fmt.Fprintln(os.Stderr, "omasend: Bonjour unavailable:", bonjourErr)
	}

	probeTicker := time.NewTicker(8 * time.Second)
	helloTicker := time.NewTicker(5 * time.Second)
	defer probeTicker.Stop()
	defer helloTicker.Stop()
	d.probeTailscale(ctx)
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-probeTicker.C:
			go d.probeTailscale(ctx)
		case <-helloTicker.C:
			for _, peer := range d.activePeers(2 * time.Minute) {
				go d.sendHello(ctx, peer.Host, peer.Port, peer.Via)
			}
		}
	}
}

func (d *Daemon) accept(ctx context.Context, listener net.Listener) {
	for {
		connection, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			continue
		}
		go d.handleConnection(ctx, connection)
	}
}

func (d *Daemon) handleConnection(ctx context.Context, connection net.Conn) {
	defer connection.Close()
	_ = connection.SetDeadline(time.Now().Add(5 * time.Second))
	frame, err := protocol.ReadFrame(connection)
	if err != nil {
		return
	}
	message, err := protocol.Open(d.store.Snapshot().PairingCode, frame)
	if err != nil {
		return
	}
	if message.OriginID == d.store.Snapshot().DeviceID {
		return
	}
	host, _, _ := net.SplitHostPort(connection.RemoteAddr().String())
	via := "Local network"
	if strings.HasPrefix(host, "100.") {
		via = "Tailscale"
	}
	d.upsertPeer(model.Peer{ID: message.OriginID, Name: message.OriginName, Host: host, Port: d.port, Via: via, LastSeen: time.Now()})
	switch message.Type {
	case "hello":
		reply := d.newMessage("hello_ack", "")
		if sealed, err := protocol.Seal(d.store.Snapshot().PairingCode, reply); err == nil {
			_ = protocol.WriteFrame(connection, sealed)
		}
	case "hello_ack":
		return
	case "clipboard":
		d.receiveClipboard(ctx, message)
	}
}

func (d *Daemon) localClipboardChanged(content clipboard.Content) {
	if (len(content.Text) == 0 && len(content.Data) == 0) || len(content.Text) > model.MaxClipboard || len(content.Data) > model.MaxClipboard {
		return
	}
	message := d.newMessage("clipboard", content.Text)
	message.ContentType = content.ContentType
	if len(content.Data) > 0 {
		message.Data = base64.StdEncoding.EncodeToString(content.Data)
	}
	item := historyItem(message, d.store.Snapshot().DeviceID)
	added, err := d.store.AddHistory(item)
	if err != nil || !added {
		return
	}
	d.broadcast(context.Background(), message)
}

func (d *Daemon) receiveClipboard(ctx context.Context, message model.Message) {
	item := historyItem(message, d.store.Snapshot().DeviceID)
	added, err := d.store.AddHistory(item)
	if err != nil || !added {
		return
	}
	if d.store.Snapshot().AutoCopy {
		writeCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
		defer cancel()
		_ = d.clip.Write(writeCtx, clipboardContent(message))
	}
}

func (d *Daemon) broadcast(ctx context.Context, message model.Message) {
	for _, peer := range d.activePeers(90 * time.Second) {
		peer := peer
		go func() { _ = d.send(ctx, peer.Host, peer.Port, message, false, peer.Via) }()
	}
}

func (d *Daemon) sendHello(ctx context.Context, host string, port int, via string) {
	_ = d.send(ctx, host, port, d.newMessage("hello", ""), true, via)
}

func (d *Daemon) send(ctx context.Context, host string, port int, message model.Message, expectReply bool, via string) error {
	if host == "" || port <= 0 {
		return errors.New("invalid peer")
	}
	sealed, err := protocol.Seal(d.store.Snapshot().PairingCode, message)
	if err != nil {
		return err
	}
	dialer := net.Dialer{Timeout: 2 * time.Second}
	connection, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		return err
	}
	defer connection.Close()
	_ = connection.SetDeadline(time.Now().Add(4 * time.Second))
	if err := protocol.WriteFrame(connection, sealed); err != nil {
		return err
	}
	if !expectReply {
		return nil
	}
	frame, err := protocol.ReadFrame(connection)
	if err != nil {
		return err
	}
	reply, err := protocol.Open(d.store.Snapshot().PairingCode, frame)
	if err != nil || reply.Type != "hello_ack" {
		return errors.New("invalid hello response")
	}
	d.upsertPeer(model.Peer{ID: reply.OriginID, Name: reply.OriginName, Host: host, Port: port, Via: via, LastSeen: time.Now()})
	return nil
}

func (d *Daemon) probeTailscale(ctx context.Context) {
	for _, host := range discovery.TailscaleHosts(ctx) {
		go d.sendHello(ctx, host, d.port, "Tailscale")
	}
}

func (d *Daemon) newMessage(kind, text string) model.Message {
	snapshot := d.store.Snapshot()
	bytes := make([]byte, 16)
	_, _ = rand.Read(bytes)
	return model.NewMessage(kind, hex.EncodeToString(bytes), snapshot.DeviceID, snapshot.DeviceName, text)
}

func (d *Daemon) upsertPeer(peer model.Peer) {
	if peer.ID == "" || peer.ID == d.store.Snapshot().DeviceID {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	existing, ok := d.peers[peer.ID]
	if ok && existing.Via == "Tailscale" && peer.Via != "Tailscale" && time.Since(existing.LastSeen) < 20*time.Second {
		return
	}
	d.peers[peer.ID] = peer
}

func (d *Daemon) activePeers(maxAge time.Duration) []model.Peer {
	d.mu.RLock()
	defer d.mu.RUnlock()
	result := make([]model.Peer, 0, len(d.peers))
	for _, peer := range d.peers {
		if time.Since(peer.LastSeen) <= maxAge {
			result = append(result, peer)
		}
	}
	return result
}

func (d *Daemon) status() model.Status {
	snapshot := d.store.Snapshot()
	peers := d.activePeers(20 * time.Second)
	sort.Slice(peers, func(i, j int) bool { return peers[i].Name < peers[j].Name })
	return model.Status{DeviceID: snapshot.DeviceID, DeviceName: snapshot.DeviceName, AutoCopy: snapshot.AutoCopy, HistorySize: len(snapshot.History), Peers: peers, Port: d.port}
}

func (d *Daemon) handleIPC(request ipc.Request) ipc.Response {
	switch request.Action {
	case "status":
		status := d.status()
		return ipc.Response{OK: true, Status: &status}
	case "history":
		return ipc.Response{OK: true, History: d.store.Snapshot().History}
	case "auto":
		if request.Value == nil {
			return ipc.Response{OK: false, Error: "auto requires a value"}
		}
		if err := d.store.SetAutoCopy(*request.Value); err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		status := d.status()
		return ipc.Response{OK: true, Status: &status}
	case "pair-show":
		return ipc.Response{OK: true, PairingCode: d.store.Snapshot().PairingCode}
	case "pair-set":
		if err := d.store.SetPairingCode(request.PairingCode); err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		d.mu.Lock()
		d.peers = map[string]model.Peer{}
		d.mu.Unlock()
		return ipc.Response{OK: true}
	case "pair-regenerate":
		secret, err := protocol.GenerateSecret()
		if err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		if err := d.store.SetPairingCode(secret); err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		d.mu.Lock()
		d.peers = map[string]model.Peer{}
		d.mu.Unlock()
		return ipc.Response{OK: true, PairingCode: secret}
	case "copy":
		item, ok := d.store.HistoryItem(request.ItemID)
		if !ok {
			return ipc.Response{OK: false, Error: "clipboard item not found"}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		defer cancel()
		data, _ := base64.StdEncoding.DecodeString(item.Data)
		if err := d.clip.Write(ctx, clipboard.Content{ContentType: item.ContentType, Text: item.Text, Data: data}); err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		return ipc.Response{OK: true}
	default:
		return ipc.Response{OK: false, Error: "unknown action"}
	}
}

func historyItem(message model.Message, localID string) model.HistoryItem {
	item := model.HistoryItem{
		ID: message.ID, Text: message.Text, OriginID: message.OriginID,
		OriginName: message.OriginName, CreatedAt: message.CreatedAt,
		IsLocal: message.OriginID == localID, ContentType: message.ContentType, Data: message.Data,
	}
	if item.IsImage() {
		item.Thumbnail = model.ImageThumbnail(item.Data)
	}
	return item
}

func clipboardContent(message model.Message) clipboard.Content {
	data, _ := base64.StdEncoding.DecodeString(message.Data)
	return clipboard.Content{ContentType: message.ContentType, Text: message.Text, Data: data}
}

package daemon

import (
	"context"
	"github.com/Aayush9029/OmaSend/linux/internal/config"
	"github.com/Aayush9029/OmaSend/linux/internal/model"
	"net"
	"path/filepath"
	"testing"
	"time"
)

func testNode(t *testing.T) *Daemon {
	t.Helper()
	store, err := config.Open(filepath.Join(t.TempDir(), "config.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.SetPairingCode("omasend-test-secret-0123456789-abcdef"); err != nil {
		t.Fatal(err)
	}
	d := New(store)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	d.port = listener.Addr().(*net.TCPAddr).Port
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(func() { cancel(); listener.Close() })
	go d.accept(ctx, listener)
	return d
}

func TestThreePeerBroadcast(t *testing.T) {
	a, b, c := testNode(t), testNode(t), testNode(t)
	ctx := context.Background()
	a.sendHello(ctx, "127.0.0.1", b.port, "Test loopback")
	a.sendHello(ctx, "127.0.0.1", c.port, "Test loopback")
	if len(a.status().Peers) != 2 {
		t.Fatal("did not authenticate both peers")
	}
	if b.status().Peers[0].Port != a.port {
		t.Fatal("lost advertised return port")
	}
	message := a.newMessage("clipboard", "fanout")
	a.broadcast(ctx, message)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && (len(b.store.Snapshot().History) != 1 || len(c.store.Snapshot().History) != 1) {
		time.Sleep(10 * time.Millisecond)
	}
	if len(b.store.Snapshot().History) != 1 || len(c.store.Snapshot().History) != 1 {
		t.Fatal("broadcast did not reach both peers")
	}
	a.broadcast(ctx, message)
	time.Sleep(30 * time.Millisecond)
	if len(b.store.Snapshot().History) != 1 || len(c.store.Snapshot().History) != 1 {
		t.Fatal("duplicate inserted")
	}
	if len(a.store.Snapshot().History) != 0 {
		t.Fatal("incoming message was relayed")
	}
}

func TestWrongPairingCodeNotConnected(t *testing.T) {
	a, b := testNode(t), testNode(t)
	if err := b.store.SetPairingCode("a-different-pairing-code-1234567890"); err != nil {
		t.Fatal(err)
	}
	a.sendHello(context.Background(), "127.0.0.1", b.port, "Test loopback")
	if len(a.status().Peers) != 0 || len(b.status().Peers) != 0 {
		t.Fatal("unauthenticated peer connected")
	}
}

func TestExpiredPeerExcluded(t *testing.T) {
	a := testNode(t)
	a.upsertPeer(model.Peer{ID: "expired", Name: "Expired", LastSeen: time.Now().Add(-time.Hour)})
	if len(a.status().Peers) != 0 {
		t.Fatal("expired peer visible")
	}
}

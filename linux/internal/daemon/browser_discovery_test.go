package daemon

import (
	"github.com/Aayush9029/OmaSend/linux/internal/config"
	"github.com/Aayush9029/OmaSend/linux/internal/discovery"
	"github.com/Aayush9029/OmaSend/linux/internal/model"
	"path/filepath"
	"testing"
	"time"
)

func TestBrowserDiscoveryIsNotAuthentication(t *testing.T) {
	store, err := config.Open(filepath.Join(t.TempDir(), "config.json"))
	if err != nil {
		t.Fatal(err)
	}
	d := New(store)
	d.candidates["192.168.1.2:53317"] = discovery.Found{ID: "mac", Name: "MacBook", Platform: "darwin", Seen: time.Now()}
	d.candidates["[fd00::2]:53317"] = discovery.Found{ID: "mac", Name: "MacBook", Platform: "darwin", Seen: time.Now()}
	d.candidates["192.168.1.3:53317"] = discovery.Found{ID: "stale", Name: "Gone", Seen: time.Now().Add(-6 * time.Minute)}
	devices := d.BrowserDevices()
	if len(devices) != 1 || devices[0].ID != "mac" || devices[0].Connected || devices[0].Platform != "darwin" {
		t.Fatalf("unexpected discovery list: %+v", devices)
	}
	d.upsertPeer(model.Peer{ID: "mac", Name: "Authenticated Mac", Host: "192.168.1.2", Port: 53317, LastSeen: time.Now()})
	devices = d.BrowserDevices()
	if len(devices) != 1 || !devices[0].Connected || devices[0].Name != "Authenticated Mac" {
		t.Fatalf("hello status lost: %+v", devices)
	}
}

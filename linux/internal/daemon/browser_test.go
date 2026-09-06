package daemon

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestBrowserBidirectionalFiles(t *testing.T) {
	for _, lan := range []bool{false, true} {
		t.Run(fmt.Sprint("LAN=", lan), func(t *testing.T) {
			t.Setenv("OMASEND_DOWNLOADS", t.TempDir())
			a, b := testNode(t), testNode(t)
			if err := a.store.SetTrustedLAN(lan); err != nil {
				t.Fatal(err)
			}
			if err := b.store.SetTrustedLAN(lan); err != nil {
				t.Fatal(err)
			}
			if lan {
				if err := b.store.SetPairingCode("different-key-01234567890123456789"); err != nil {
					t.Fatal(err)
				}
			}
			ctx := context.Background()
			if err := a.BrowserConnect(ctx, "127.0.0.1", b.port); err != nil {
				t.Fatal(err)
			}
			data := append(bytes.Repeat([]byte("file transfer "), 180000), []byte("end")...)
			source := filepath.Join(t.TempDir(), "source.bin")
			if err := os.WriteFile(source, data, 0600); err != nil {
				t.Fatal(err)
			}
			for _, direction := range []struct {
				sender, receiver *Daemon
				name             string
			}{{a, b, "from-browser.bin"}, {b, a, "from-native.bin"}} {
				result, err := direction.sender.BrowserFile(ctx, source, direction.name, int64(len(data)))
				if err != nil || result.Sent != 1 {
					t.Fatalf("transfer %s: %+v %v", direction.name, result, err)
				}
				history := direction.receiver.BrowserHistory()
				if len(history) == 0 || history[0].FileName != direction.name || history[0].IsLocal {
					t.Fatal("missing remote history")
				}
				got, err := os.ReadFile(history[0].FilePath)
				if err != nil || !bytes.Equal(got, data) {
					t.Fatal("file bytes differ", err)
				}
			}
		})
	}
}

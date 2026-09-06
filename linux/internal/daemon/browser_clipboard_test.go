package daemon

import (
	"context"
	"fmt"
	"testing"
	"time"
)

// Uses the native Linux daemon and web backend over real TCP, in both modes.
func TestWebNativeClipboardCompatibility(t *testing.T) {
	for _, lan := range []bool{false, true} {
		t.Run(fmt.Sprintf("LAN=%v", lan), func(t *testing.T) {
			web, native := testNode(t), testNode(t)
			web.browser = true
			for _, node := range []*Daemon{web, native} {
				if err := node.store.SetTrustedLAN(lan); err != nil {
					t.Fatal(err)
				}
			}
			ctx := context.Background()
			if err := web.BrowserConnect(ctx, "127.0.0.1", native.port); err != nil {
				t.Fatal(err)
			}
			for _, pair := range [][2]*Daemon{{web, native}, {native, web}} {
				text := "Hello from Mac / Linux / web 👋\n日本語 • café"
				result, err := pair[0].BrowserSend(ctx, text)
				if err != nil || result.Sent != 1 {
					t.Fatalf("send: %+v %v", result, err)
				}
				deadline := time.Now().Add(2 * time.Second)
				found := false
				for time.Now().Before(deadline) {
					for _, item := range pair[1].BrowserHistory() {
						if item.Text == text && !item.IsLocal && item.OriginID == pair[0].store.Snapshot().DeviceID {
							found = true
						}
					}
					if found {
						break
					}
					time.Sleep(10 * time.Millisecond)
				}
				if !found {
					t.Fatal("remote Unicode text missing")
				}
			}
			message := native.newMessage("clipboard", "")
			message.ContentType = "image/png"
			message.Data = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
			if err := native.send(ctx, "127.0.0.1", web.port, message, false, "test"); err != nil {
				t.Fatal(err)
			}
			deadline := time.Now().Add(2 * time.Second)
			for time.Now().Before(deadline) {
				if item, ok := web.BrowserItem(message.ID); ok {
					if item.Data != message.Data || item.ContentType != "image/png" || item.IsLocal {
						t.Fatal("image changed in transit")
					}
					return
				}
				time.Sleep(10 * time.Millisecond)
			}
			t.Fatal("native image missing from web history")
		})
	}
}

package web

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime/multipart"
	"net"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Aayush9029/OmaSend/linux/internal/config"
	"github.com/Aayush9029/OmaSend/linux/internal/daemon"
	"github.com/Aayush9029/OmaSend/linux/internal/model"
	"github.com/Aayush9029/OmaSend/linux/internal/protocol"
)

func TestBrowserFlowAndAccessBoundaries(t *testing.T) {
	root := t.TempDir()
	store, err := config.Open(filepath.Join(root, "config.json"))
	if err != nil {
		t.Fatal(err)
	}
	key := store.Snapshot().PairingCode
	d := daemon.New(store)
	handler := New(d, filepath.Join(root, "uploads"), []string{"localhost:53318"})
	request := func(method, path, body, host, origin, remote string, marker bool) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "http://localhost:53318"+path, strings.NewReader(body))
		r.Host = host
		r.RemoteAddr = remote
		r.Header.Set("Content-Type", "application/json")
		if origin != "" {
			r.Header.Set("Origin", origin)
		}
		if marker {
			r.Header.Set("X-OmaSend", "1")
		}
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		return w
	}
	local := func(method, path, body string) *httptest.ResponseRecorder {
		return request(method, path, body, "localhost:53318", "http://localhost:53318", "127.0.0.1:1234", true)
	}
	for _, test := range []struct {
		host, origin, remote string
		marker               bool
	}{
		{"evil.example:53318", "", "127.0.0.1:1234", true},
		{"localhost:53318", "https://evil.example", "127.0.0.1:1234", true},
		{"localhost:53318", "", "8.8.8.8:1234", true},
		{"localhost:53318", "", "127.0.0.1:1234", false},
	} {
		if w := request("POST", "/api/send", `{"text":"evil"}`, test.host, test.origin, test.remote, test.marker); w.Code != 403 {
			t.Fatalf("boundary: %d", w.Code)
		}
	}
	if w := request("POST", "/api/settings", `{"trustedLAN":true}`, "localhost:53318", "", "192.168.1.2:1234", true); w.Code != 403 {
		t.Fatal("remote browser may not change security mode")
	}
	if w := local("GET", "/api/state", ""); strings.Contains(w.Body.String(), key) || !strings.Contains(w.Body.String(), `"trustedLAN":false`) {
		t.Fatal("default mode or secret disclosure")
	}
	if w := local("POST", "/api/settings", `{"trustedLAN":true}`); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	reopened, err := config.Open(filepath.Join(root, "config.json"))
	if err != nil || !reopened.Snapshot().TrustedLAN || reopened.Snapshot().PairingCode != key {
		t.Fatal("mode did not persist or key changed")
	}
	// A real TCP peer receives the browser's text using the public LAN protocol.
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	received := make(chan model.Message, 1)
	go func() {
		c, e := listener.Accept()
		if e != nil {
			return
		}
		defer c.Close()
		_ = c.SetDeadline(time.Now().Add(5 * time.Second))
		frame, e := protocol.ReadFrame(c)
		if e != nil {
			return
		}
		hello, e := protocol.Open("", frame, true)
		if e != nil {
			return
		}
		ack := model.NewMessage("hello_ack", "ack", "test-peer", "Mac simulator", "")
		ack.Port = listener.Addr().(*net.TCPAddr).Port
		frame, _ = protocol.Seal("", ack, true)
		_ = protocol.WriteFrame(c, frame)
		c2, e := listener.Accept()
		if e != nil {
			return
		}
		defer c2.Close()
		_ = c2.SetDeadline(time.Now().Add(5 * time.Second))
		frame, e = protocol.ReadFrame(c2)
		if e != nil {
			return
		}
		message, e := protocol.Open("", frame, true)
		if e == nil && hello.Type == "hello" {
			received <- message
		}
	}()
	if err = d.BrowserConnect(context.Background(), "127.0.0.1", listener.Addr().(*net.TCPAddr).Port); err != nil {
		t.Fatal(err)
	}
	if w := local("POST", "/api/send", `{"text":"browser to native 👋"}`); w.Code != 200 || !strings.Contains(w.Body.String(), `"sent":1`) {
		t.Fatal(w.Body.String())
	}
	select {
	case m := <-received:
		if m.Text != "browser to native 👋" {
			t.Fatal(m)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no TCP delivery")
	}
	if w := local("POST", "/api/settings", `{"trustedLAN":false}`); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if d.BrowserStatus().TrustedLAN || len(d.BrowserStatus().Peers) != 0 {
		t.Fatal("mode switch retained old peers")
	}
	for _, name := range []string{"NUL.txt", "report.txt:payload", "bad.", "normal.txt"} {
		var body bytes.Buffer
		writer := multipart.NewWriter(&body)
		part, _ := writer.CreateFormFile("file", name)
		_, _ = io.WriteString(part, "sample upload")
		_ = writer.Close()
		r := httptest.NewRequest("POST", "http://localhost:53318/api/upload", &body)
		r.RemoteAddr = "127.0.0.1:1234"
		r.Header.Set("X-OmaSend", "1")
		r.Header.Set("Content-Type", writer.FormDataContentType())
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		if name != "normal.txt" {
			if w.Code == 200 {
				t.Fatalf("unsafe filename accepted: %s", name)
			}
			continue
		}
		if w.Code != 200 {
			t.Fatal(w.Body.String())
		}
		item := d.BrowserHistory()[0]
		if w = local("GET", "/api/download?id="+item.ID, ""); w.Code != 200 || w.Body.String() != "sample upload" || !strings.Contains(w.Header().Get("Content-Disposition"), "attachment") {
			t.Fatal("download mismatch")
		}
		w = local("GET", "/api/state", "")
		var state struct{ History []model.HistoryItem }
		if json.Unmarshal(w.Body.Bytes(), &state) != nil || state.History[0].FilePath != "" {
			t.Fatal("local path exposed")
		}
	}
	if w := local("GET", "/api/download?id=../../config.json", ""); w.Code != 404 {
		t.Fatal("arbitrary download")
	}
	for _, ip := range []string{"8.8.8.8", "100.64.1.2", "0.0.0.0", "ff02::1"} {
		if daemon.IsLAN(net.ParseIP(ip)) {
			t.Fatal("non-LAN address allowed", ip)
		}
	}
}

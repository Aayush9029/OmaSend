package protocol

import (
	"bytes"
	"github.com/Aayush9029/OmaSend/linux/internal/model"
	"testing"
)

func TestTrustedLANSeparation(t *testing.T) {
	const key = "test-key-01234567890123456789"
	m := model.NewMessage("clipboard", "lan-1", "web", "Web", "hello 👋")
	m.FilePath = "/private/file"
	frame, err := Seal(key, m, true)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Open("different", frame, true)
	if err != nil || got.Text != m.Text || got.FilePath != "" {
		t.Fatalf("roundtrip: %+v %v", got, err)
	}
	if _, err = Open(key, frame); err == nil {
		t.Fatal("encrypted mode accepted plaintext")
	}
	encrypted, _ := Seal(key, m)
	if _, err = Open(key, encrypted, true); err == nil {
		t.Fatal("LAN mode accepted encrypted frame")
	}
	if !bytes.Contains(frame, []byte("hello")) {
		t.Fatal("LAN frame is not plaintext")
	}
	plain := []byte("OmaSend file chunk")
	chunk, err := SealFileChunk(key, "x", 4096, plain, true)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(chunk, append([]byte{'O', 'S', 'L', '1', 0, 0, 0, 0, 0, 0, 16, 0}, plain...)) {
		t.Fatal("cross-platform chunk layout")
	}
	gotChunk, err := OpenFileChunk("other", "x", 4096, chunk, true)
	if err != nil || !bytes.Equal(gotChunk, plain) {
		t.Fatal("chunk roundtrip")
	}
	if _, err = OpenFileChunk(key, "x", 4096, chunk); err == nil {
		t.Fatal("plaintext accepted as encrypted")
	}
	for _, bad := range [][]byte{chunk[:5], append([]byte("FAIL"), chunk[4:]...), chunk[:12]} {
		if _, err = OpenFileChunk(key, "x", 4096, bad, true); err == nil {
			t.Fatal("invalid chunk accepted")
		}
	}
	if _, err = OpenFileChunk(key, "x", 0, chunk, true); err == nil {
		t.Fatal("offset not checked")
	}
	m.Text = string(bytes.Repeat([]byte{'x'}, model.MaxClipboard+1))
	frame, _ = Seal(key, m, true)
	if _, err = Open(key, frame, true); err == nil {
		t.Fatal("oversized LAN text accepted")
	}
}

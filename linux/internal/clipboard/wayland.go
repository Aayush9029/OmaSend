package clipboard

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"os/exec"
	"strings"
	"sync"
	"time"
)

const maxClipboard = 10 * 1024 * 1024

type Content struct {
	ContentType string
	Text        string
	Data        []byte
}

type Wayland struct {
	mu   sync.Mutex
	last [32]byte
}

func (w *Wayland) Read(ctx context.Context) (Content, error) {
	types, err := exec.CommandContext(ctx, "wl-paste", "--list-types").Output()
	if err != nil {
		return Content{}, err
	}
	typeList := strings.Fields(string(types))
	for _, wanted := range []string{"image/png", "image/jpeg", "image/gif"} {
		if contains(typeList, wanted) {
			output, readErr := exec.CommandContext(ctx, "wl-paste", "--type", wanted).Output()
			if readErr != nil {
				return Content{}, readErr
			}
			if len(output) > maxClipboard {
				return Content{}, errors.New("clipboard image is too large")
			}
			if len(output) == 0 {
				return Content{}, errors.New("clipboard image is empty")
			}
			return Content{ContentType: wanted, Data: output}, nil
		}
	}
	output, err := exec.CommandContext(ctx, "wl-paste", "--no-newline", "--type", "text").Output()
	if err != nil {
		return Content{}, err
	}
	if len(output) > maxClipboard {
		return Content{}, errors.New("clipboard is too large")
	}
	if strings.TrimSpace(string(output)) == "" {
		return Content{}, errors.New("clipboard is empty")
	}
	return Content{ContentType: "text/plain", Text: string(output)}, nil
}

func (w *Wayland) Write(ctx context.Context, content Content) error {
	mime := content.ContentType
	data := content.Data
	if strings.HasPrefix(mime, "text/") || mime == "" {
		mime = "text/plain;charset=utf-8"
		data = []byte(content.Text)
	}
	command := exec.CommandContext(ctx, "wl-copy", "--type", mime)
	command.Stdin = bytes.NewReader(data)
	if err := command.Run(); err != nil {
		return err
	}
	w.mu.Lock()
	w.last = fingerprint(content)
	w.mu.Unlock()
	return nil
}

func (w *Wayland) Watch(ctx context.Context, onChange func(Content)) {
	ticker := time.NewTicker(450 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			readCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
			content, err := w.Read(readCtx)
			cancel()
			if err != nil || (content.Text == "" && len(content.Data) == 0) {
				continue
			}
			hash := fingerprint(content)
			w.mu.Lock()
			changed := hash != w.last
			if changed {
				w.last = hash
			}
			w.mu.Unlock()
			if changed {
				onChange(content)
			}
		}
	}
}

func fingerprint(content Content) [32]byte {
	data := append([]byte(content.ContentType+"\x00"+content.Text), content.Data...)
	return sha256.Sum256(data)
}

func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

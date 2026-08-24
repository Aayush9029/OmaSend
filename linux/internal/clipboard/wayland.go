package clipboard

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const maxClipboard = 10 * 1024 * 1024

type Content struct {
	ContentType  string
	Text         string
	Data         []byte
	FilePath     string
	FileName     string
	FileSize     int64
	FileModified int64
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
	if contains(typeList, "text/uri-list") {
		output, readErr := exec.CommandContext(ctx, "wl-paste", "--no-newline", "--type", "text/uri-list").Output()
		if readErr == nil {
			for _, line := range strings.Split(string(output), "\n") {
				line = strings.TrimSpace(line)
				if line == "" || strings.HasPrefix(line, "#") {
					continue
				}
				parsed, parseErr := url.Parse(line)
				if parseErr != nil || parsed.Scheme != "file" || (parsed.Host != "" && parsed.Host != "localhost") {
					continue
				}
				path := filepath.Clean(parsed.Path)
				info, statErr := os.Stat(path)
				if statErr == nil && info.Mode().IsRegular() && info.Size() > 0 {
					return Content{
						ContentType: "application/x-omasend-file", FilePath: path,
						FileName: info.Name(), FileSize: info.Size(), FileModified: info.ModTime().UnixNano(),
					}, nil
				}
			}
		}
	}
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
	if content.FilePath != "" {
		absolute, err := filepath.Abs(content.FilePath)
		if err != nil {
			return err
		}
		info, err := os.Stat(absolute)
		if err != nil || !info.Mode().IsRegular() {
			return errors.New("clipboard file is unavailable")
		}
		content.ContentType = "application/x-omasend-file"
		content.FilePath = absolute
		content.FileName = info.Name()
		content.FileSize = info.Size()
		content.FileModified = info.ModTime().UnixNano()
		uri := (&url.URL{Scheme: "file", Path: absolute}).String() + "\r\n"
		command := exec.CommandContext(ctx, "wl-copy", "--type", "text/uri-list")
		command.Stdin = strings.NewReader(uri)
		if err := command.Run(); err != nil {
			return err
		}
		w.mu.Lock()
		w.last = fingerprint(content)
		w.mu.Unlock()
		return nil
	}
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
			if err != nil || (content.Text == "" && len(content.Data) == 0 && content.FilePath == "") {
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
	metadata := content.ContentType + "\x00" + content.Text + "\x00" + content.FilePath + "\x00" +
		content.FileName + "\x00" + fmt.Sprintf("%d:%d", content.FileSize, content.FileModified)
	data := append([]byte(metadata), content.Data...)
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

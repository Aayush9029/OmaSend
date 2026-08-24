package ipc

import (
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Aayush9029/OmaSend/linux/internal/model"
)

type Request struct {
	Action      string `json:"action"`
	Value       *bool  `json:"value,omitempty"`
	PairingCode string `json:"pairingCode,omitempty"`
	ItemID      string `json:"itemId,omitempty"`
}

type Response struct {
	OK          bool                `json:"ok"`
	Error       string              `json:"error,omitempty"`
	Status      *model.Status       `json:"status,omitempty"`
	History     []model.HistoryItem `json:"history,omitempty"`
	PairingCode string              `json:"pairingCode,omitempty"`
}

type Handler func(Request) Response

func DefaultSocketPath() string {
	if value := strings.TrimSpace(os.Getenv("OMASEND_SOCKET")); value != "" {
		return value
	}
	root := os.Getenv("XDG_RUNTIME_DIR")
	if root == "" {
		root = filepath.Join(os.TempDir(), "omasend-"+os.Getenv("USER"))
	}
	return filepath.Join(root, "omasend.sock")
}

func Serve(path string, handler Handler, stop <-chan struct{}) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	_ = os.Remove(path)
	listener, err := net.Listen("unix", path)
	if err != nil {
		return err
	}
	defer listener.Close()
	defer os.Remove(path)
	if err := os.Chmod(path, 0600); err != nil {
		return err
	}
	go func() { <-stop; listener.Close() }()
	for {
		connection, err := listener.Accept()
		if err != nil {
			select {
			case <-stop:
				return nil
			default:
				return err
			}
		}
		go func() {
			defer connection.Close()
			_ = connection.SetDeadline(time.Now().Add(5 * time.Second))
			var request Request
			if err := json.NewDecoder(connection).Decode(&request); err != nil {
				_ = json.NewEncoder(connection).Encode(Response{OK: false, Error: "invalid request"})
				return
			}
			_ = json.NewEncoder(connection).Encode(handler(request))
		}()
	}
}

func Call(path string, request Request) (Response, error) {
	connection, err := net.DialTimeout("unix", path, 3*time.Second)
	if err != nil {
		return Response{}, err
	}
	defer connection.Close()
	_ = connection.SetDeadline(time.Now().Add(5 * time.Second))
	if err := json.NewEncoder(connection).Encode(request); err != nil {
		return Response{}, err
	}
	var response Response
	if err := json.NewDecoder(connection).Decode(&response); err != nil {
		return Response{}, err
	}
	if !response.OK {
		return response, errors.New(response.Error)
	}
	return response, nil
}

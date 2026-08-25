package config

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/Aayush9029/OmaSend/linux/internal/model"
	"github.com/Aayush9029/OmaSend/linux/internal/protocol"
)

type Data struct {
	DeviceID    string              `json:"deviceId"`
	DeviceName  string              `json:"deviceName"`
	PairingCode string              `json:"pairingCode"`
	AutoCopy    bool                `json:"autoCopy"`
	History     []model.HistoryItem `json:"history"`
}

type Store struct {
	mu   sync.RWMutex
	path string
	data Data
}

func Open(path string) (*Store, error) {
	store := &Store{path: path}
	bytes, err := os.ReadFile(path)
	if err == nil {
		if err := json.Unmarshal(bytes, &store.data); err != nil {
			return nil, err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if store.data.DeviceID == "" {
		id := make([]byte, 16)
		if _, err := rand.Read(id); err != nil {
			return nil, err
		}
		store.data.DeviceID = hex.EncodeToString(id)
	}
	if store.data.DeviceName == "" {
		name, _ := os.Hostname()
		store.data.DeviceName = friendlyName(name)
	}
	if store.data.PairingCode == "" {
		secret, err := protocol.GenerateSecret()
		if err != nil {
			return nil, err
		}
		store.data.PairingCode = secret
	}
	if store.data.History == nil {
		store.data.History = []model.HistoryItem{}
	}
	for index := range store.data.History {
		item := &store.data.History[index]
		if item.Thumbnail == "" && item.IsFile() {
			item.Thumbnail = model.ImageFileThumbnail(item.FilePath)
		}
	}
	if err := store.saveLocked(); err != nil {
		return nil, err
	}
	return store, nil
}

func DefaultPath() string {
	if value := strings.TrimSpace(os.Getenv("OMASEND_CONFIG")); value != "" {
		return value
	}
	root, err := os.UserConfigDir()
	if err != nil {
		root = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(root, "omasend", "config.json")
}

func (s *Store) Snapshot() Data {
	s.mu.RLock()
	defer s.mu.RUnlock()
	copy := s.data
	copy.History = append([]model.HistoryItem(nil), s.data.History...)
	return copy
}

func (s *Store) SetAutoCopy(value bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.AutoCopy = value
	return s.saveLocked()
}

func (s *Store) SetPairingCode(value string) error {
	value = strings.TrimSpace(value)
	if len(value) < 20 {
		return errors.New("pairing code must contain at least 20 characters")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.PairingCode = value
	return s.saveLocked()
}

func (s *Store) AddHistory(item model.HistoryItem) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, existing := range s.data.History {
		if existing.ID == item.ID {
			return false, nil
		}
	}
	s.data.History = append([]model.HistoryItem{item}, s.data.History...)
	if len(s.data.History) > model.MaxHistory {
		s.data.History = s.data.History[:model.MaxHistory]
	}
	for historyBytes(s.data.History) > model.MaxHistoryBytes && len(s.data.History) > 1 {
		s.data.History = s.data.History[:len(s.data.History)-1]
	}
	return true, s.saveLocked()
}

func historyBytes(items []model.HistoryItem) int {
	total := 0
	for _, item := range items {
		total += item.ApproximateBytes()
	}
	return total
}

func (s *Store) HistoryItem(id string) (model.HistoryItem, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, item := range s.data.History {
		if item.ID == id {
			return item, true
		}
	}
	return model.HistoryItem{}, false
}

func (s *Store) saveLocked() error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0700); err != nil {
		return err
	}
	bytes, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return err
	}
	temporary := s.path + ".tmp"
	if err := os.WriteFile(temporary, append(bytes, '\n'), 0600); err != nil {
		return err
	}
	if err := os.Chmod(temporary, 0600); err != nil {
		return err
	}
	return os.Rename(temporary, s.path)
}

func friendlyName(hostname string) string {
	hostname = strings.TrimSpace(strings.TrimSuffix(hostname, ".local"))
	if hostname == "" {
		return "Linux"
	}
	parts := strings.FieldsFunc(hostname, func(r rune) bool { return r == '-' || r == '_' })
	for index := range parts {
		if parts[index] != "" {
			parts[index] = strings.ToUpper(parts[index][:1]) + parts[index][1:]
		}
	}
	return strings.Join(parts, " ")
}

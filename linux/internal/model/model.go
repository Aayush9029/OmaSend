package model

import "time"

const (
	ProtocolVersion = 1
	DefaultPort     = 53317
	MaxClipboard    = 10 * 1024 * 1024
	MaxFrame        = 14 * 1024 * 1024
	MaxHistory      = 50
	MaxHistoryBytes = 50 * 1024 * 1024
)

type Message struct {
	Version     int    `json:"version"`
	Type        string `json:"type"`
	ID          string `json:"id"`
	OriginID    string `json:"originId"`
	OriginName  string `json:"originName"`
	CreatedAt   int64  `json:"createdAt"`
	Text        string `json:"text,omitempty"`
	ContentType string `json:"contentType,omitempty"`
	Data        string `json:"data,omitempty"`
}

type Envelope struct {
	Version    int    `json:"version"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
}

type HistoryItem struct {
	ID          string `json:"id"`
	Text        string `json:"text"`
	OriginID    string `json:"originId"`
	OriginName  string `json:"originName"`
	CreatedAt   int64  `json:"createdAt"`
	IsLocal     bool   `json:"isLocal"`
	ContentType string `json:"contentType,omitempty"`
	Data        string `json:"data,omitempty"`
	Thumbnail   string `json:"thumbnail,omitempty"`
}

func (item HistoryItem) IsImage() bool {
	return len(item.ContentType) > 6 && item.ContentType[:6] == "image/"
}

func (item HistoryItem) ApproximateBytes() int {
	return len(item.Text) + len(item.Data)*3/4 + len(item.Thumbnail)*3/4
}

type Peer struct {
	ID       string    `json:"id"`
	Name     string    `json:"name"`
	Host     string    `json:"host"`
	Port     int       `json:"port"`
	LastSeen time.Time `json:"lastSeen"`
	Via      string    `json:"via"`
}

type Status struct {
	DeviceID    string `json:"deviceId"`
	DeviceName  string `json:"deviceName"`
	AutoCopy    bool   `json:"autoCopy"`
	PairingCode string `json:"pairingCode,omitempty"`
	HistorySize int    `json:"historySize"`
	Peers       []Peer `json:"peers"`
	Port        int    `json:"port"`
}

func NewMessage(kind, id, originID, originName, text string) Message {
	return Message{
		Version: ProtocolVersion, Type: kind, ID: id, OriginID: originID,
		OriginName: originName, CreatedAt: time.Now().UnixMilli(), Text: text,
	}
}

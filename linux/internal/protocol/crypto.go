package protocol

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/Aayush9029/OmaSend/linux/internal/model"
)

var additionalData = []byte("omasend-v1")

func Seal(secret string, message model.Message) ([]byte, error) {
	gcm, err := makeGCM(secret)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return sealWithNonce(gcm, nonce, message)
}

func SealWithNonce(secret string, nonce []byte, message model.Message) ([]byte, error) {
	gcm, err := makeGCM(secret)
	if err != nil {
		return nil, err
	}
	if len(nonce) != gcm.NonceSize() {
		return nil, fmt.Errorf("nonce must be %d bytes", gcm.NonceSize())
	}
	return sealWithNonce(gcm, nonce, message)
}

func sealWithNonce(gcm cipher.AEAD, nonce []byte, message model.Message) ([]byte, error) {
	plain, err := json.Marshal(message)
	if err != nil {
		return nil, err
	}
	ciphertext := gcm.Seal(nil, nonce, plain, additionalData)
	envelope := model.Envelope{
		Version:    model.ProtocolVersion,
		Nonce:      base64.StdEncoding.EncodeToString(nonce),
		Ciphertext: base64.StdEncoding.EncodeToString(ciphertext),
	}
	return json.Marshal(envelope)
}

func Open(secret string, data []byte) (model.Message, error) {
	var envelope model.Envelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		return model.Message{}, fmt.Errorf("decode envelope: %w", err)
	}
	if envelope.Version != model.ProtocolVersion {
		return model.Message{}, fmt.Errorf("unsupported protocol version %d", envelope.Version)
	}
	nonce, err := base64.StdEncoding.DecodeString(envelope.Nonce)
	if err != nil {
		return model.Message{}, errors.New("invalid nonce")
	}
	ciphertext, err := base64.StdEncoding.DecodeString(envelope.Ciphertext)
	if err != nil {
		return model.Message{}, errors.New("invalid ciphertext")
	}
	gcm, err := makeGCM(secret)
	if err != nil {
		return model.Message{}, err
	}
	plain, err := gcm.Open(nil, nonce, ciphertext, additionalData)
	if err != nil {
		return model.Message{}, errors.New("authentication failed")
	}
	var message model.Message
	if err := json.Unmarshal(plain, &message); err != nil {
		return model.Message{}, errors.New("invalid message")
	}
	if message.Version != model.ProtocolVersion || message.ID == "" || message.OriginID == "" {
		return model.Message{}, errors.New("invalid message fields")
	}
	if len(message.Text) > model.MaxClipboard {
		return model.Message{}, errors.New("clipboard item is too large")
	}
	if message.Data != "" {
		decoded, decodeErr := base64.StdEncoding.DecodeString(message.Data)
		if decodeErr != nil || len(decoded) > model.MaxClipboard {
			return model.Message{}, errors.New("clipboard image is invalid or too large")
		}
	}
	return message, nil
}

func WriteFrame(writer io.Writer, payload []byte) error {
	if len(payload) == 0 || len(payload) > model.MaxFrame {
		return errors.New("invalid frame length")
	}
	var header [4]byte
	binary.BigEndian.PutUint32(header[:], uint32(len(payload)))
	if _, err := writer.Write(header[:]); err != nil {
		return err
	}
	_, err := writer.Write(payload)
	return err
}

func ReadFrame(reader io.Reader) ([]byte, error) {
	var header [4]byte
	if _, err := io.ReadFull(reader, header[:]); err != nil {
		return nil, err
	}
	length := int(binary.BigEndian.Uint32(header[:]))
	if length <= 0 || length > model.MaxFrame {
		return nil, errors.New("invalid frame length")
	}
	payload := make([]byte, length)
	_, err := io.ReadFull(reader, payload)
	return payload, err
}

func GenerateSecret() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func makeGCM(secret string) (cipher.AEAD, error) {
	if len(secret) < 20 {
		return nil, errors.New("pairing code is too short")
	}
	key := sha256.Sum256([]byte(secret))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

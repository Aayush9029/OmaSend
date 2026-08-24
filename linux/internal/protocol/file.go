package protocol

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
)

const FileChunkBytes = 1024 * 1024

var fileAdditionalData = []byte("omasend-file-v1")

func SealFileChunk(secret, transferID string, offset int64, plaintext []byte) ([]byte, error) {
	return sealFileChunk(secret, transferID, offset, plaintext, nil)
}

func SealFileChunkWithNonce(secret, transferID string, offset int64, plaintext, nonce []byte) ([]byte, error) {
	return sealFileChunk(secret, transferID, offset, plaintext, nonce)
}

func sealFileChunk(secret, transferID string, offset int64, plaintext, suppliedNonce []byte) ([]byte, error) {
	if offset < 0 || len(plaintext) == 0 || len(plaintext) > FileChunkBytes {
		return nil, errors.New("invalid file chunk")
	}
	gcm, err := makeGCM(secret)
	if err != nil {
		return nil, err
	}
	nonce := suppliedNonce
	if nonce == nil {
		nonce = make([]byte, gcm.NonceSize())
		if _, err := rand.Read(nonce); err != nil {
			return nil, err
		}
	}
	if len(nonce) != gcm.NonceSize() {
		return nil, errors.New("invalid file chunk nonce")
	}
	offsetBytes := make([]byte, 8)
	binary.BigEndian.PutUint64(offsetBytes, uint64(offset))
	aad := append(append(append([]byte{}, fileAdditionalData...), []byte(transferID)...), offsetBytes...)
	sealed := gcm.Seal(nil, nonce, plaintext, aad)
	payload := make([]byte, 0, len(offsetBytes)+len(nonce)+len(sealed))
	payload = append(payload, offsetBytes...)
	payload = append(payload, nonce...)
	payload = append(payload, sealed...)
	return payload, nil
}

func OpenFileChunk(secret, transferID string, expectedOffset int64, payload []byte) ([]byte, error) {
	if len(payload) <= 8+12+16 {
		return nil, errors.New("invalid file chunk")
	}
	offset := int64(binary.BigEndian.Uint64(payload[:8]))
	if offset != expectedOffset {
		return nil, errors.New("unexpected file chunk offset")
	}
	gcm, err := makeGCM(secret)
	if err != nil {
		return nil, err
	}
	nonce := payload[8 : 8+gcm.NonceSize()]
	offsetBytes := payload[:8]
	aad := append(append(append([]byte{}, fileAdditionalData...), []byte(transferID)...), offsetBytes...)
	plaintext, err := gcm.Open(nil, nonce, payload[8+gcm.NonceSize():], aad)
	if err != nil {
		return nil, errors.New("file chunk authentication failed")
	}
	if len(plaintext) == 0 || len(plaintext) > FileChunkBytes {
		return nil, errors.New("invalid file chunk size")
	}
	return plaintext, nil
}

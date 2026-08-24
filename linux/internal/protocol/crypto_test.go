package protocol

import (
	"encoding/base64"
	"encoding/hex"
	"testing"

	"github.com/Aayush9029/OmaSend/linux/internal/model"
)

const testSecret = "omasend-test-secret-0123456789-abcdef"

func TestRoundTrip(t *testing.T) {
	message := model.Message{Version: 1, Type: "clipboard", ID: "item-1", OriginID: "linux", OriginName: "Framework", CreatedAt: 42, Text: "hello 👋"}
	sealed, err := Seal(testSecret, message)
	if err != nil {
		t.Fatal(err)
	}
	opened, err := Open(testSecret, sealed)
	if err != nil {
		t.Fatal(err)
	}
	if opened != message {
		t.Fatalf("round trip mismatch: %#v", opened)
	}
}

func TestImageRoundTrip(t *testing.T) {
	pixels := []byte{0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a}
	message := model.Message{
		Version: 1, Type: "clipboard", ID: "image-1", OriginID: "linux",
		OriginName: "Framework", CreatedAt: 43, ContentType: "image/png",
		Data: base64.StdEncoding.EncodeToString(pixels),
	}
	sealed, err := Seal(testSecret, message)
	if err != nil {
		t.Fatal(err)
	}
	opened, err := Open(testSecret, sealed)
	if err != nil {
		t.Fatal(err)
	}
	if opened != message {
		t.Fatalf("image round trip mismatch: %#v", opened)
	}
}

func TestFixedInteropVector(t *testing.T) {
	nonce, _ := hex.DecodeString("000102030405060708090a0b")
	message := model.Message{Version: 1, Type: "clipboard", ID: "interop-1", OriginID: "go", OriginName: "Linux", CreatedAt: 1730000000000, Text: "OmaSend interop"}
	sealed, err := SealWithNonce(testSecret, nonce, message)
	if err != nil {
		t.Fatal(err)
	}
	const expected = `{"version":1,"nonce":"AAECAwQFBgcICQoL","ciphertext":"BuLeQaS379eOUMKOqEQkmh/VItWh+DDVCEpm+aX9PgUW+hi7WSjtc1AkBkakzCrnyad5Iu8KDPnYSUCpct+jYu5X8nWbPJzO+zbgXMlzG7ZEigRZlzBagX3AnwmZH1Rk4wQw2kH62UJGHdtVLv43+3dwdsJVa/eQP+4yVhC/tmhANG7kw4iN7bjsz0q3aRHc0z1B+mf++WeF"}`
	if string(sealed) != expected {
		t.Fatalf("interop vector changed:\n%s", sealed)
	}
	if _, err := Open(testSecret, sealed); err != nil {
		t.Fatal(err)
	}
}

func TestWrongSecretRejected(t *testing.T) {
	message := model.NewMessage("hello", "1", "device", "Linux", "")
	sealed, err := Seal(testSecret, message)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Open("another-long-secret-0123456789", sealed); err == nil {
		t.Fatal("expected authentication failure")
	}
}

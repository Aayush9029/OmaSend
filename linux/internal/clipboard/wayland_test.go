package clipboard

import "testing"

func TestTextFingerprintNormalizesMIME(t *testing.T) {
	plain := Content{Text: "hello", ContentType: "text/plain"}
	for _, mime := range []string{"", "text/plain;charset=utf-8"} {
		other := plain
		other.ContentType = mime
		if fingerprint(plain) != fingerprint(other) {
			t.Fatal("text MIME variant would echo")
		}
	}
}

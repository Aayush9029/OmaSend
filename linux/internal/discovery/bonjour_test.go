package discovery

import "testing"

func TestTXTUnicodeAndLiteralBackslash(t *testing.T) {
	for input, want := range map[string]string{`Aayush\226\128\153s MacBook`: "Aayush’s MacBook", `literal\\226`: `literal\226`, "Windows": "Windows"} {
		if got := txtValue([]string{"name=" + input}, "name"); got != want {
			t.Fatalf("%q != %q", got, want)
		}
	}
}

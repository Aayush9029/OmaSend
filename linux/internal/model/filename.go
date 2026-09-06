package model

import "strings"

// SafeFileName is portable, including when the web companion runs on Windows.
func SafeFileName(name string) bool {
	if name == "" || name == "." || name == ".." || len(name) > 200 || strings.ContainsAny(name, "<>:\"/\\|?*") || strings.HasSuffix(name, ".") || strings.HasSuffix(name, " ") {
		return false
	}
	for _, r := range name {
		if r < 32 {
			return false
		}
	}
	stem := strings.ToUpper(strings.Split(name, ".")[0])
	if stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL" {
		return false
	}
	if len(stem) == 4 && (strings.HasPrefix(stem, "COM") || strings.HasPrefix(stem, "LPT")) && stem[3] >= '0' && stem[3] <= '9' {
		return false
	}
	return true
}

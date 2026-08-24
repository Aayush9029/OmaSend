package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"

	"github.com/Aayush9029/OmaSend/linux/internal/config"
	"github.com/Aayush9029/OmaSend/linux/internal/daemon"
	"github.com/Aayush9029/OmaSend/linux/internal/ipc"
)

var version = "dev"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "omasend:", err)
		os.Exit(1)
	}
}

func run(arguments []string) error {
	if len(arguments) == 0 {
		arguments = []string{"status"}
	}
	jsonOutput := removeFlag(&arguments, "--json")
	socket := ipc.DefaultSocketPath()
	switch arguments[0] {
	case "--version", "version":
		fmt.Printf("omasend %s\n", version)
		return nil
	case "--help", "help", "-h":
		printHelp()
		return nil
	case "daemon":
		store, err := config.Open(config.DefaultPath())
		if err != nil {
			return err
		}
		ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer cancel()
		return daemon.New(store).Run(ctx, socket)
	case "status":
		response, err := ipc.Call(socket, ipc.Request{Action: "status"})
		if err != nil {
			return unavailable(err)
		}
		if jsonOutput {
			return printJSON(response.Status)
		}
		status := response.Status
		fmt.Printf("OmaSend on %s\n", status.DeviceName)
		fmt.Printf("  Auto copy: %s\n", onOff(status.AutoCopy))
		fmt.Printf("  Devices:   %d connected\n", len(status.Peers))
		for _, peer := range status.Peers {
			fmt.Printf("    %s via %s\n", peer.Name, peer.Via)
		}
		fmt.Printf("  History:   %d items\n", status.HistorySize)
		return nil
	case "history":
		response, err := ipc.Call(socket, ipc.Request{Action: "history"})
		if err != nil {
			return unavailable(err)
		}
		if jsonOutput {
			return printJSON(response.History)
		}
		for _, item := range response.History {
			preview := strings.ReplaceAll(item.Text, "\n", " ")
			if item.IsImage() {
				preview = "[Image]"
			} else if item.IsFile() {
				preview = "[File] " + item.FileName
			}
			if len([]rune(preview)) > 70 {
				preview = string([]rune(preview)[:67]) + "..."
			}
			fmt.Printf("%s  %-16s %s\n", item.ID, item.OriginName, preview)
		}
		return nil
	case "auto":
		if len(arguments) != 2 || (arguments[1] != "on" && arguments[1] != "off") {
			return errors.New("usage: omasend auto <on|off>")
		}
		value := arguments[1] == "on"
		response, err := ipc.Call(socket, ipc.Request{Action: "auto", Value: &value})
		if err != nil {
			return unavailable(err)
		}
		if jsonOutput {
			return printJSON(response.Status)
		}
		fmt.Println("Auto copy", onOff(value))
		return nil
	case "copy":
		if len(arguments) != 2 {
			return errors.New("usage: omasend copy <item-id>")
		}
		_, err := ipc.Call(socket, ipc.Request{Action: "copy", ItemID: arguments[1]})
		return unavailable(err)
	case "pair":
		return runPair(socket, arguments[1:], jsonOutput)
	default:
		return fmt.Errorf("unknown command %q (try omasend help)", arguments[0])
	}
}

func runPair(socket string, arguments []string, jsonOutput bool) error {
	command := "show"
	if len(arguments) > 0 {
		command = arguments[0]
	}
	switch command {
	case "show", "copy":
		response, err := ipc.Call(socket, ipc.Request{Action: "pair-show"})
		if err != nil {
			return unavailable(err)
		}
		if command == "copy" {
			copyCommand := exec.Command("wl-copy", "--type", "text/plain")
			copyCommand.Stdin = strings.NewReader(response.PairingCode)
			if err := copyCommand.Run(); err != nil {
				return err
			}
			if !jsonOutput {
				fmt.Println("Pairing code copied")
			}
			return nil
		}
		if jsonOutput {
			return printJSON(map[string]string{"pairingCode": response.PairingCode})
		}
		fmt.Println(response.PairingCode)
		return nil
	case "set":
		if len(arguments) != 2 {
			return errors.New("usage: omasend pair set <code>")
		}
		_, err := ipc.Call(socket, ipc.Request{Action: "pair-set", PairingCode: arguments[1]})
		return unavailable(err)
	case "regenerate":
		response, err := ipc.Call(socket, ipc.Request{Action: "pair-regenerate"})
		if err != nil {
			return unavailable(err)
		}
		if jsonOutput {
			return printJSON(map[string]string{"pairingCode": response.PairingCode})
		}
		fmt.Println(response.PairingCode)
		return nil
	default:
		return errors.New("usage: omasend pair <show|copy|set|regenerate>")
	}
}

func unavailable(err error) error {
	if err == nil {
		return nil
	}
	if strings.Contains(err.Error(), "connect") || strings.Contains(err.Error(), "no such file") {
		return errors.New("service is not running")
	}
	return err
}

func removeFlag(arguments *[]string, wanted string) bool {
	result := (*arguments)[:0]
	found := false
	for _, argument := range *arguments {
		if argument == wanted {
			found = true
		} else {
			result = append(result, argument)
		}
	}
	*arguments = result
	return found
}

func printJSON(value any) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	return encoder.Encode(value)
}
func onOff(value bool) string {
	if value {
		return "on"
	}
	return "off"
}

func printHelp() {
	fmt.Print(`OmaSend shares clipboard history between macOS and Omarchy.

Usage:
  omasend status [--json]
  omasend history [--json]
  omasend auto <on|off>
  omasend copy <item-id>
  omasend pair <show|copy|set|regenerate>
  omasend daemon
  omasend version
`)
}

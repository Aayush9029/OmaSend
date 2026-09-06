package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/Aayush9029/OmaSend/linux/internal/config"
	"github.com/Aayush9029/OmaSend/linux/internal/daemon"
	"github.com/Aayush9029/OmaSend/linux/internal/web"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "omasend-web:", err)
		os.Exit(1)
	}
}
func run() error {
	listen := flag.String("listen", "127.0.0.1:53318", "HTTP address; use 0.0.0.0:53318 to allow other LAN browsers (unencrypted HTTP)")
	root, _ := os.UserConfigDir()
	data := flag.String("data", filepath.Join(root, "omasend-web"), "private companion data directory")
	port := flag.Int("port", 53319, "native peer port; separate from the desktop app")
	flag.Parse()
	if *port < 1 || *port > 65535 {
		return fmt.Errorf("invalid peer port")
	}
	store, err := config.Open(filepath.Join(*data, "config.json"))
	if err != nil {
		return err
	}
	_ = os.Setenv("OMASEND_PORT", fmt.Sprint(*port))
	_ = os.Setenv("OMASEND_DOWNLOADS", filepath.Join(*data, "received"))
	node := daemon.New(store)
	listener, err := net.Listen("tcp", *listen)
	if err != nil {
		return err
	}
	defer listener.Close()
	addresses, err := web.Addresses(listener)
	if err != nil {
		return err
	}
	server := web.HTTPServer(*listen, web.New(node, filepath.Join(*data, "uploads"), addresses))
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	done := make(chan error, 2)
	go func() { done <- node.RunBrowser(ctx) }()
	go func() { done <- server.Serve(listener) }()
	fmt.Println("OmaSend Web — open in your browser:")
	for _, a := range addresses {
		fmt.Println(" ", web.URL(a))
	}
	fmt.Println("Sharing mode is encrypted by default. Change mode from the hosting computer's localhost page.")
	select {
	case <-ctx.Done():
	case err = <-done:
	}
	cancel()
	_ = server.Close()
	if err == http.ErrServerClosed {
		return nil
	}
	return err
}

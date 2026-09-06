// Package web serves the local browser companion. It has no cloud dependencies.
package web

import (
	"embed"
	"encoding/base64"
	"encoding/json"
	"errors"
	"github.com/Aayush9029/OmaSend/linux/internal/model"
	"io"
	"io/fs"
	"mime"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Aayush9029/OmaSend/linux/internal/daemon"
)

//go:embed static/*
var assets embed.FS

const MaxUpload = 100 * 1024 * 1024

type Server struct {
	node    *daemon.Daemon
	uploads string
	hosts   map[string]bool
	slots   chan struct{}
}

func New(node *daemon.Daemon, uploads string, addresses []string) http.Handler {
	s := &Server{node: node, uploads: uploads, hosts: map[string]bool{}, slots: make(chan struct{}, 4)}
	for _, a := range addresses {
		s.hosts[strings.ToLower(a)] = true
	}
	static, _ := fs.Sub(assets, "static")
	files := http.FileServer(http.FS(static))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
		if !s.hosts[strings.ToLower(r.Host)] || !daemon.IsLAN(remoteIP(r)) {
			http.Error(w, "Local network access only", http.StatusForbidden)
			return
		}
		if origin := r.Header.Get("Origin"); origin != "" && origin != "http://"+r.Host {
			http.Error(w, "Origin not allowed", http.StatusForbidden)
			return
		}
		if r.Header.Get("Sec-Fetch-Site") == "cross-site" {
			http.Error(w, "Cross-site access is not allowed", http.StatusForbidden)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/api/") {
			if r.Method != http.MethodGet && (r.Method != http.MethodPost || r.Header.Get("X-OmaSend") != "1") {
				http.Error(w, "Request not allowed", http.StatusForbidden)
				return
			}
			s.api(w, r)
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "Method not allowed", 405)
			return
		}
		switch r.URL.Path {
		case "/", "/app.js", "/icons.js", "/style.css":
			files.ServeHTTP(w, r)
		default:
			http.NotFound(w, r)
		}
	})
}

func remoteIP(r *http.Request) net.IP {
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	return net.ParseIP(strings.Split(host, "%")[0])
}
func reply(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(value)
}
func fail(w http.ResponseWriter, err error) { http.Error(w, err.Error(), http.StatusBadRequest) }
func decode(w http.ResponseWriter, r *http.Request, v any) error {
	if kind, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type")); kind != "application/json" {
		return errors.New("JSON required")
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 11*1024*1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(v); err != nil {
		return err
	}
	if decoder.Decode(new(any)) != io.EOF {
		return errors.New("one JSON object required")
	}
	return nil
}
func (s *Server) api(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		switch r.URL.Path {
		case "/api/state":
			items := s.node.BrowserHistory()
			for i := range items {
				items[i].FilePath = ""
				items[i].Data = ""
				items[i].Thumbnail = ""
			}
			reply(w, struct {
				Status  any  `json:"status"`
				History any  `json:"history"`
				Admin   bool `json:"admin"`
			}{s.node.BrowserStatus(), items, remoteIP(r).IsLoopback()})
		case "/api/download":
			s.download(w, r)
		default:
			http.NotFound(w, r)
		}
		return
	}
	select {
	case s.slots <- struct{}{}:
		defer func() { <-s.slots }()
	default:
		http.Error(w, "Busy. Try again shortly.", 429)
		return
	}
	switch r.URL.Path {
	case "/api/send":
		var body struct {
			Text string `json:"text"`
		}
		if err := decode(w, r, &body); err != nil {
			fail(w, err)
			return
		}
		result, err := s.node.BrowserSend(r.Context(), body.Text)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, result)
	case "/api/upload":
		s.upload(w, r)
	case "/api/settings":
		// Only the hosting computer may change pairing or downgrade transport security.
		if !remoteIP(r).IsLoopback() {
			http.Error(w, "Change sharing mode on the hosting computer", 403)
			return
		}
		var body struct {
			TrustedLAN  *bool   `json:"trustedLAN"`
			PairingCode *string `json:"pairingCode"`
		}
		if err := decode(w, r, &body); err != nil {
			fail(w, err)
			return
		}
		if (body.TrustedLAN == nil) == (body.PairingCode == nil) {
			fail(w, errors.New("choose one setting"))
			return
		}
		var err error
		if body.TrustedLAN != nil {
			err = s.node.BrowserMode(*body.TrustedLAN)
		} else {
			err = s.node.BrowserPair(*body.PairingCode)
		}
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, map[string]bool{"ok": true})
	case "/api/connect":
		var body struct {
			Host string `json:"host"`
			Port int    `json:"port"`
		}
		if err := decode(w, r, &body); err != nil {
			fail(w, err)
			return
		}
		if err := s.node.BrowserConnect(r.Context(), body.Host, body.Port); err != nil {
			fail(w, errors.New("Could not connect. Check the address and use the same sharing mode or pairing key."))
			return
		}
		reply(w, map[string]bool{"ok": true})
	default:
		http.NotFound(w, r)
	}
}

func (s *Server) upload(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, MaxUpload+1024*1024)
	reader, err := r.MultipartReader()
	if err != nil {
		fail(w, err)
		return
	}
	part, err := reader.NextPart()
	if err != nil {
		fail(w, err)
		return
	}
	defer part.Close()
	name := part.FileName()
	if !model.SafeFileName(name) {
		fail(w, errors.New("choose a file with a simple filename"))
		return
	}
	if err = os.MkdirAll(s.uploads, 0700); err != nil {
		fail(w, errors.New("cannot save upload"))
		return
	}
	folder, err := os.MkdirTemp(s.uploads, "item-")
	if err != nil {
		fail(w, errors.New("cannot save upload"))
		return
	}
	keep := false
	defer func() {
		if !keep {
			_ = os.RemoveAll(folder)
		}
	}()
	path := filepath.Join(folder, name)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		fail(w, errors.New("cannot save upload"))
		return
	}
	size, err := io.Copy(f, io.LimitReader(part, MaxUpload+1))
	closeErr := f.Close()
	if err != nil || closeErr != nil || size == 0 || size > MaxUpload {
		fail(w, errors.New("choose a nonempty file up to 100 MB"))
		return
	}
	if _, err = reader.NextPart(); err != io.EOF {
		fail(w, errors.New("upload one file at a time"))
		return
	}
	result, err := s.node.BrowserFile(r.Context(), path, name, size)
	if err != nil {
		fail(w, errors.New("could not share file"))
		return
	}
	keep = true
	reply(w, result)
}

func (s *Server) download(w http.ResponseWriter, r *http.Request) {
	item, ok := s.node.BrowserItem(r.URL.Query().Get("id"))
	if !ok {
		http.NotFound(w, r)
		return
	}
	if item.FilePath != "" {
		f, err := os.Open(item.FilePath)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		defer f.Close()
		info, err := f.Stat()
		if err != nil || !info.Mode().IsRegular() {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": item.FileName}))
		http.ServeContent(w, r, item.FileName, info.ModTime(), f)
		return
	}
	if item.Data != "" && (item.ContentType == "image/png" || item.ContentType == "image/jpeg" || item.ContentType == "image/gif") {
		data, err := base64.StdEncoding.DecodeString(item.Data)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", item.ContentType)
		_, _ = w.Write(data)
		return
	}
	http.NotFound(w, r)
}

// Addresses validates the bind address and returns exact allowed HTTP Host values.
func Addresses(listener net.Listener) ([]string, error) {
	host, port, err := net.SplitHostPort(listener.Addr().String())
	if err != nil {
		return nil, err
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return nil, errors.New("bind to a local IP address")
	}
	hosts := []string{}
	add := func(ip net.IP) {
		if daemon.IsLAN(ip) {
			hosts = append(hosts, net.JoinHostPort(ip.String(), port))
		}
	}
	if ip.IsUnspecified() {
		add(net.ParseIP("127.0.0.1"))
		add(net.ParseIP("::1"))
		addresses, err := net.InterfaceAddrs()
		if err != nil {
			return nil, err
		}
		for _, addr := range addresses {
			if n, ok := addr.(*net.IPNet); ok {
				add(n.IP)
			}
		}
	} else {
		add(ip)
	}
	if len(hosts) == 0 {
		return nil, errors.New("bind to localhost or a private LAN address")
	}
	hosts = append(hosts, net.JoinHostPort("localhost", port))
	return hosts, nil
}

func URL(address string) string { return (&url.URL{Scheme: "http", Host: address}).String() }
func HTTPServer(address string, handler http.Handler) *http.Server {
	return &http.Server{Addr: address, Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 5 * time.Minute, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16 * 1024, ErrorLog: nil}
}

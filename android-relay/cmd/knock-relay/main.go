package main

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"sync"
	"time"
)

const version = "0.1.0"

var dnsServers = []string{
	"1.1.1.1:53",
	"8.8.8.8:53",
}

type dohEndpoint struct {
	name string
	ip   string
	host string
	path string
}

var dohEndpoints = []dohEndpoint{
	{name: "cloudflare", ip: "1.1.1.1", host: "cloudflare-dns.com", path: "/dns-query"},
	{name: "google", ip: "8.8.8.8", host: "dns.google", path: "/resolve"},
}

func main() {
	listenAddr := flag.String("listen", "127.0.0.1:18080", "listen address")
	showVersion := flag.Bool("version", false, "print version")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}

	logger := log.New(os.Stdout, "knock-relay ", log.LstdFlags|log.Lmicroseconds)
	listener, err := net.Listen("tcp", *listenAddr)
	if err != nil {
		logger.Fatalf("listen %s: %v", *listenAddr, err)
	}
	defer listener.Close()

	logger.Printf("listening on %s", *listenAddr)
	for {
		conn, err := listener.Accept()
		if err != nil {
			logger.Printf("accept: %v", err)
			continue
		}

		go handleConn(logger, conn)
	}
}

func handleConn(logger *log.Logger, client net.Conn) {
	defer client.Close()

	target, err := readSocks5Connect(client)
	if err != nil {
		logger.Printf("client %s: %v", client.RemoteAddr(), err)
		writeSocks5Reply(client, 0x01)
		return
	}

	remote, err := dialTarget(target)
	if err != nil {
		logger.Printf("connect %s: %v", target, err)
		writeSocks5Reply(client, 0x05)
		return
	}
	defer remote.Close()

	if err := writeSocks5Reply(client, 0x00); err != nil {
		logger.Printf("reply %s: %v", target, err)
		return
	}

	logger.Printf("connect %s", target)
	pipeBoth(client, remote)
}

func dialTarget(target string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(target)
	if err != nil {
		return nil, err
	}

	dialer := net.Dialer{
		Timeout:   30 * time.Second,
		KeepAlive: 30 * time.Second,
	}

	if ip := net.ParseIP(host); ip != nil {
		return dialer.Dial("tcp", target)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	ips, err := lookupHost(ctx, host)
	if err != nil {
		return nil, fmt.Errorf("resolve %s: %w", host, err)
	}
	if len(ips) == 0 {
		return nil, fmt.Errorf("resolve %s: no addresses", host)
	}

	ordered := preferIPv4(ips)
	var lastErr error
	for _, ip := range ordered {
		address := net.JoinHostPort(ip.IP.String(), port)
		conn, err := dialer.DialContext(ctx, "tcp", address)
		if err == nil {
			return conn, nil
		}
		lastErr = err
	}

	if lastErr == nil {
		lastErr = errors.New("no dial attempts made")
	}
	return nil, lastErr
}

func lookupHost(ctx context.Context, host string) ([]net.IPAddr, error) {
	if ips, err := lookupHostDoH(ctx, host); err == nil && len(ips) > 0 {
		return ips, nil
	}

	resolver := androidResolver()
	return resolver.LookupIPAddr(ctx, host)
}

type dohJSONResponse struct {
	Status int `json:"Status"`
	Answer []struct {
		Type int    `json:"type"`
		Data string `json:"data"`
	} `json:"Answer"`
}

func lookupHostDoH(ctx context.Context, host string) ([]net.IPAddr, error) {
	var lastErr error

	for _, endpoint := range dohEndpoints {
		ips, err := lookupHostDoHEndpoint(ctx, endpoint, host)
		if err == nil && len(ips) > 0 {
			return ips, nil
		}
		if err != nil {
			lastErr = err
		}
	}

	if lastErr == nil {
		lastErr = errors.New("no DoH answers")
	}
	return nil, lastErr
}

func lookupHostDoHEndpoint(ctx context.Context, endpoint dohEndpoint, host string) ([]net.IPAddr, error) {
	query := url.Values{}
	query.Set("name", host)
	query.Set("type", "A")

	requestURL := url.URL{
		Scheme:   "https",
		Host:     endpoint.host,
		Path:     endpoint.path,
		RawQuery: query.Encode(),
	}

	dialer := net.Dialer{Timeout: 5 * time.Second}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return dialer.DialContext(ctx, "tcp", net.JoinHostPort(endpoint.ip, "443"))
		},
		TLSClientConfig: &tls.Config{
			ServerName: endpoint.host,
			MinVersion: tls.VersionTLS12,
		},
		ForceAttemptHTTP2: false,
	}
	defer transport.CloseIdleConnections()

	client := &http.Client{
		Transport: transport,
		Timeout:   8 * time.Second,
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Host = endpoint.host
	req.Header.Set("Accept", "application/dns-json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%s DoH request: %w", endpoint.name, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("%s DoH status: %s", endpoint.name, resp.Status)
	}

	var result dohJSONResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("%s DoH decode: %w", endpoint.name, err)
	}
	if result.Status != 0 {
		return nil, fmt.Errorf("%s DoH DNS status: %d", endpoint.name, result.Status)
	}

	ips := make([]net.IPAddr, 0, len(result.Answer))
	for _, answer := range result.Answer {
		if answer.Type != 1 {
			continue
		}
		ip := net.ParseIP(answer.Data)
		if ip == nil || ip.To4() == nil {
			continue
		}
		ips = append(ips, net.IPAddr{IP: ip})
	}
	if len(ips) == 0 {
		return nil, fmt.Errorf("%s DoH returned no A records", endpoint.name)
	}
	return ips, nil
}

func androidResolver() *net.Resolver {
	return &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			dialer := net.Dialer{
				Timeout: 5 * time.Second,
			}

			var lastErr error
			for _, server := range dnsServers {
				conn, err := dialer.DialContext(ctx, network, server)
				if err == nil {
					return conn, nil
				}
				lastErr = err
			}

			if lastErr == nil {
				lastErr = errors.New("no DNS servers configured")
			}
			return nil, lastErr
		},
	}
}

func preferIPv4(ips []net.IPAddr) []net.IPAddr {
	ordered := make([]net.IPAddr, 0, len(ips))
	for _, ip := range ips {
		if ip.IP.To4() != nil {
			ordered = append(ordered, ip)
		}
	}
	for _, ip := range ips {
		if ip.IP.To4() == nil {
			ordered = append(ordered, ip)
		}
	}
	return ordered
}

func readSocks5Connect(conn net.Conn) (string, error) {
	header := make([]byte, 2)
	if _, err := io.ReadFull(conn, header); err != nil {
		return "", err
	}
	if header[0] != 0x05 {
		return "", errors.New("unsupported SOCKS version")
	}

	methods := make([]byte, int(header[1]))
	if _, err := io.ReadFull(conn, methods); err != nil {
		return "", err
	}

	hasNoAuth := false
	for _, method := range methods {
		if method == 0x00 {
			hasNoAuth = true
			break
		}
	}
	if !hasNoAuth {
		conn.Write([]byte{0x05, 0xff})
		return "", errors.New("client does not support no-auth")
	}
	if _, err := conn.Write([]byte{0x05, 0x00}); err != nil {
		return "", err
	}

	req := make([]byte, 4)
	if _, err := io.ReadFull(conn, req); err != nil {
		return "", err
	}
	if req[0] != 0x05 {
		return "", errors.New("invalid request version")
	}
	if req[1] != 0x01 {
		return "", errors.New("only CONNECT is supported")
	}

	host, err := readAddress(conn, req[3])
	if err != nil {
		return "", err
	}

	portBytes := make([]byte, 2)
	if _, err := io.ReadFull(conn, portBytes); err != nil {
		return "", err
	}
	port := int(binary.BigEndian.Uint16(portBytes))

	return net.JoinHostPort(host, strconv.Itoa(port)), nil
}

func readAddress(conn net.Conn, atyp byte) (string, error) {
	switch atyp {
	case 0x01:
		raw := make([]byte, net.IPv4len)
		if _, err := io.ReadFull(conn, raw); err != nil {
			return "", err
		}
		return net.IP(raw).String(), nil
	case 0x03:
		length := make([]byte, 1)
		if _, err := io.ReadFull(conn, length); err != nil {
			return "", err
		}
		raw := make([]byte, int(length[0]))
		if _, err := io.ReadFull(conn, raw); err != nil {
			return "", err
		}
		return string(raw), nil
	case 0x04:
		raw := make([]byte, net.IPv6len)
		if _, err := io.ReadFull(conn, raw); err != nil {
			return "", err
		}
		return net.IP(raw).String(), nil
	default:
		return "", errors.New("unsupported address type")
	}
}

func writeSocks5Reply(conn net.Conn, code byte) error {
	_, err := conn.Write([]byte{0x05, code, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
	return err
}

func pipeBoth(a net.Conn, b net.Conn) {
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		io.Copy(a, b)
		if tcp, ok := a.(*net.TCPConn); ok {
			tcp.CloseWrite()
		}
	}()

	go func() {
		defer wg.Done()
		io.Copy(b, a)
		if tcp, ok := b.(*net.TCPConn); ok {
			tcp.CloseWrite()
		}
	}()

	wg.Wait()
}

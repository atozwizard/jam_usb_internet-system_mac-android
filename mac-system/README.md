# Mac System Mode Skeleton

Purpose: route ordinary Mac app traffic through the Galaxy relay over USB.

Prototype engine candidates:

- `sing-box`
- `tun2socks`

Initial target:

```text
Mac TUN -> SOCKS5 127.0.0.1:18080 -> adb forward -> Android relay -> cellular
```

Stage 3 command target:

```zsh
./jam-usb-internet system --mobile-only
```

Stop target:

```zsh
./jam-usb-internet system-stop
```

Prototype requirements:

- generate config under `~/.jam-usb-internet/`
- require `sudo` only at the TUN boundary
- keep foreground supervision
- restore routes/DNS/processes on exit

Productized path:

- Replace external TUN engine with macOS `NetworkExtension`.
- Use `NEPacketTunnelProvider` for packet flow.
- Keep Android relay transport behind the same high-level interface.


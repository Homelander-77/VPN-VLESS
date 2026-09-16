# VPN-VLESS

A personal learning project for deploying a self-hosted VPN on a VPS using [Xray-core](https://github.com/XTLS/Xray-core) and the VLESS protocol.

The goal of the project is to understand how modern proxy works, how TLS is used at the transport layer and how to configure routing on client side. The repository contains ready-to-use client configuration templates. The instruction for setting VPS and then Xray-core is described below.

>**Disclaimer** This project is created for educational purposes ONLY. Anyone who uses it is responsible for complying with the laws and regulations of their country and the terms of service of of their hosting provider.

## Features

- Self-hosted: no third-party VPN service, full control trafic over the server and data security
- The best way to get fastiest connection 
- Two connection options (just in case):
  - **VLESS + REALITY** over TCP (port 443) with 'xlts-rprx-vision' flow.
  - **VLESS + WebSocket + TLS** (port 8443), required your own domain.
- Split routing: local trafic goes directly, everything goes through the tunnel
- TUN mode on the client, so the whole device uses the connection, not just the browser.

## Repository scructure
| File | Description |
| --- | --- |
| `Config-for-device` | Client config: VLESS + REALITY |
| `ws-path` | Client config: VLESS + WebSocket + TLS |

## Requirements
- VPS with the public IPv4 address (enough to have 1 vCPU and 1 GB RAM).
- Linux on the server (my choice is Debian or Ununtu 24<).
- A client app that supports Xray JSON configs (for example, Happ, v2rayN).
- For the WebSokcet option: a domain name related with server

## Server setup
>**Advice** Buy VPS only on payable platform with your credentials, fake info about you can lead to wrongs things. Also I recommend reading the rules of the company about using provider's trafic, one suspicion and your account will be banned permanently.

### 1. Install Xray
```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```
Main config is located at `/usr/local/xray/config.json`.

### 2. Generate the keys
```bash
xray uuid            # client id
xray x25519          # private and public keys for REALITY
openssl rand -hex 8  # short ID
```
The private key stays on the server. The public key goes into the client config. Client ID uses in both configs, just like short ID.

### 3. Server Config 
The full config is located at `server/config-server-full.json`. Copy it to the server:
```bash
cp server/config-server-full /usr/local/etc/xray/config.json
```
The config has three inbounds:
| Inbound | Port | Description |
| --- | --- | --- |
| VLESS + REALITY | `443` | Main connection, open to the internet |
| VLESS + WebSocket | `127.0.0.1:10000` | Local only, TLS is handled by a reverse proxy (see step 4) |
| Shadowsocks 2022 | `54321` | Additional option, TCP and UDP |

Fill the empty fields:
| Field | Value |
| --- | --- |
| `clients` (REALITY) | client entries with UUID and flow (see below) |
| `clients` (WebSocket) | client entries with UUID, without flow |
| `dest` | a website with TLS 1.3 support, for example `www.nvidia.com:443` |
| `serverNames` | domain names of the `dest` website, for example `["www.nvidia.com"]` |
| `privateKey` | private key from step 2 |
| `shortIds` | short ID from step 2 |
| `password` | Shadowsocks key (see below) |

A client entry looks like this:
```json
"clients": [
  { "id": "YOUR-UUID", "flow": "xtls-rprx-vision", "email": "blabla" }
]
```
The `email` field is just label or tag for the client's name, make it for convenience. The WebSocket indounds uses the same format but without `flow`, because `xtls-rprx-vision` works only over TCP.

For the `2022-blake3-aes-128-gcm` method the password must be 16 byte key in Base64:
```bash
openssl rand -base64 16
```

The routing section blocks connection to private IP ranges (`geoip:private`)/ This way client connot reach the local network of the server.

## 4. Reverse proxy for WebSocket
The WebSocket inbound listen only on `127.0.0.1`, so reverse proxy is needed. It gets a TLS certificate for your local domain and forwards to requests on the `/ws` path to Xray. An example for [Caddy](https://caddyserver.com):
```
your-domain.com:8443 {
    reverse_proxy /ws 127.0.0.1:10000
}
```

Caddy gets the certificate automatically. Port 443 is already used by Xray, so port 80 must be opened for the certificate check.

### Firewall
Open only the ports you need:
```bash
ufw allow 22/tcp      # SSH
ufw allow 80/tcp      # certificate check
ufw allow 443/tcp     # REALITY
ufw allow 8443/tcp    # WebSocket + TLS
ufw allow 54321       # Shadowsocks (TCP and UDP)
ufw enable
```
> Make sure that port 22 (ssh) is allowed before start using ufw, otherwise you will lose access to the server.

### Start the service
Check the clear of config, then start Xray:
```bash
xray run -test -config /usr/local/etc/xray/config.json # In the output you will see OK
systemctl enable --now xray
systemctl status xray
```

Logs can be viewed with `jourbalctl -u xray -f`

##Client setup
Client configs are located in the `client/` dir:
| File | Connection |
| --- | --- |
| `client/config-for-device` | VLESS + REALITY |
| `client/config-ws` | VLESS + WebSocket + TLS |

First of all open the config you need, than fill the empty fields:
 | Field | Value |
   | --- | --- |
   | `address` | IPv4 of the VPS (REALITY) or your domain (WebSocket) |
   | `id` | UUID from the server config |
   | `publicKey` | public key from step 2 (REALITY only) |
   | `serverName` | the same domain as in `serverNames` on the server (REALITY) or your domain (WebSocket) |
   | `shortId` | short ID from the server config (REALITY only) |
   | `Host` | your domain (WebSocket only) |

Remove the `//` (comments), they are not part of the JSON standart. Finally import the config into the client app as raw JSON.

### Shadowsocks
There is no separate config file for Shadowsocks. Most client apps let you add it manually: enter the server IP, port `54321`, method `2022-blake3-aes-128-gcm` and the password from the server config.

## Routing
> In the future wiil be new updates with ready configs.

Both client configs use the same routing rules:
- `.ru`, `.su`, `.рф` domains, Yandex services and Russian IP ranges (`geoip:ru`) → **direct**
- private networks (`geoip:private`) → **direct**
- everything else → **proxy**

This keeps local services fast and reduces the load on the server.

## Notes

- **MTU** is set to `1280` in TUN mode. If some websites load slowly or do not load at all, try a lower value.
- **Fingerprint.** The REALITY config uses `randomized`, the WebSocket config uses `chrome`.
- **Short ID.** The client config contains `0123456789abcdef` as an example. Generate your own value and use it on both sides.
- **Keep secrets private.** Do not commit your UUID, keys, passwords or server address to the repository.

## Useful links

- [Xray-core documentation](https://xtls.github.io/en/)
- [Xray-examples](https://github.com/XTLS/Xray-examples)
- [REALITY](https://github.com/XTLS/REALITY)
- [Caddy documentation](https://caddyserver.com/docs/)

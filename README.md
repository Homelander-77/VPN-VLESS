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

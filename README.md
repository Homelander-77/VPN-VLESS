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


# WaterWall Testing Guide

## Problem Diagnosis from Your Logs

### The Issue
```
WARN  connfd=12 connect error: Transport endpoint is not connected:107
```

**What happened:**
1. [OK] WaterWall client connects successfully to tunnel port
2. [OK] WaterWall server accepts the tunnel connection
3. [ERROR] Server tries to connect to backend service → **BACKEND NOT RUNNING**
4. [ERROR] Connection fails immediately

**Root Cause:** Your WaterWall tunnel is working perfectly! The problem is the **backend service** on the server (the service you're forwarding to) doesn't exist or isn't running.

---

## Solution: Testing Workflow

### Choose the Correct Tunnel Mode

- **`forward` mode**: fixed backend port forward (`TcpListener -> TcpConnector`)
  - Good for SSH/database/single-service forwarding
  - Does **not** provide generic internet proxy access on client by itself
- **`internet` mode**: proxy routing (`ProxyClient -> ... -> ProxyServer -> TcpConnector(dest_context)`)
  - Enables client-side HTTP/SOCKS internet access through the tunnel
  - This is the mode you want when the client must browse/use internet via server egress

### Step 1: On Server (Foreign VPS)

1. **Start a Test Backend Service**
   ```bash
   ./menu.sh
   # Navigate: Waterwall Tunnel → Direct Waterwall tunnel → Server menu
   # Select: Option 6 - Start test backend
   ```

   This will:
   - Parse your WaterWall server config to find the backend port
   - Offer multiple backend options:
     - **HTTP echo server** (best for testing)
     - HTTP file server
     - Netcat echo server
     - Custom command

   Recommended: Choose option 1 (HTTP echo server)

2. **Verify Server Setup**
   ```bash
   ./menu.sh
   # Navigate: Waterwall Tunnel → Direct Waterwall tunnel → Server menu
   # Select: Option 7 - Complete tunnel test
   ```

   This checks:
   - WaterWall service is running [OK]
   - Tunnel port is listening [OK]
   - **Backend service is running** [OK]
   - Backend service is reachable [OK]

### Step 2: On Client (Local VPS)

1. **Test the Complete Tunnel**
   ```bash
   ./menu.sh
   # Navigate: Waterwall Tunnel → Direct Waterwall tunnel → Client menu
   # Select: Option 6 - Complete tunnel test
   ```

   This will:
   - Verify WaterWall client service is running
   - Check local listener is active
   - Test connectivity to server
   - **Send HTTP request through tunnel**
   - Verify response from backend
   - In `internet` mode: verify public IP retrieval through local tunnel port

2. **Successful Test Output:**
   ```
   [OK] WaterWall client service is running
   [OK] WaterWall is listening on 127.0.0.1:<port>
   [OK] Server is reachable
   [OK] Successfully received HTTP response through tunnel!

   [OK] WaterWall tunnel is working correctly!

   === Full Connection Path ===
   Client app → 127.0.0.1:<port> (WaterWall client)
            → <server_ip>:<port> (WaterWall server)
            → Backend service
            → Response back through tunnel
   ```

---

## Understanding the Connection Flow

### Basic TCP Tunnel Architecture

```
┌─────────────┐        ┌─────────────┐        ┌──────────────┐
│   Client    │        │   Server    │        │   Backend    │
│    (VPS)    │        │   (VPS)     │        │   Service    │
└─────────────┘        └─────────────┘        └──────────────┘
      │                       │                       │
      │  1. App connects      │                       │
      │  to local port        │                       │
      │◄──────────────────────┤                       │
      │                       │                       │
      │  2. WaterWall tunnels │                       │
      │  to server            │                       │
      ├──────────────────────►│                       │
      │                       │                       │
      │                       │  3. Server forwards   │
      │                       │  to backend          │
      │                       ├──────────────────────►│
      │                       │                       │
      │                       │  4. Backend responds │
      │                       │◄──────────────────────┤
      │                       │                       │
      │  5. Response tunneled │                       │
      │  back to client       │                       │
      │◄──────────────────────┤                       │
      │                       │                       │
```

**Your Error Occurred at Step 3** - The server couldn't connect to the backend!

---

## New Scripts Added

### 1. `waterwall_start_test_backend.sh`
**Purpose:** Quickly start a test backend service on the server

**Features:**
- Auto-detects backend port from WaterWall config
- Multiple backend types (HTTP, TCP echo, custom)
- Creates an HTTP server that confirms tunnel is working
- Shows backend logs and control commands

**Usage:** Via menu → Server menu → Option 6

### 2. `waterwall_test_tunnel_complete.sh`
**Purpose:** Comprehensive end-to-end tunnel testing

**Features:**
- Auto-detects if running on server or client
- Checks all components (service, ports, connectivity)
- Tests actual data flow through tunnel
- Provides clear diagnostic messages
- Shows full connection path when working

**Usage:**
- Via menu → Server menu → Option 7 (server test)
- Via menu → Client menu → Option 6 (client test)

---

## Manual Testing Commands

If you prefer command-line testing:

### On Server:
```bash
# Start simple HTTP backend on port specified in config
python3 -m http.server <backend_port>

# Or use the test backend script directly
cd scripts
./waterwall_start_test_backend.sh
```

### On Client:
```bash
# Test tunnel with simple HTTP request
curl http://127.0.0.1:<local_port>/

# Test internet through tunnel (internet mode)
curl --proxy http://127.0.0.1:<local_port> https://api.ipify.org
curl --proxy socks5h://127.0.0.1:<local_port> https://api.ipify.org

# Test with netcat
echo "test" | nc 127.0.0.1 <local_port>

# Watch live tunnel activity
journalctl -u waterwall-direct-client -f
```

### On Server (check logs):
```bash
# Watch server logs
journalctl -u waterwall-direct-server -f

# Should see successful connections when backend is running:
# "TcpListener: Accepted FD..."
# "TcpConnector: connection succeed..."
# NO MORE "Transport endpoint is not connected" errors!
```

---

## Troubleshooting

### Still seeing "Transport endpoint is not connected"?

1. **Verify backend is running:**
   ```bash
   ss -ltn | grep <backend_port>
   ```

2. **Test backend directly:**
   ```bash
   curl http://127.0.0.1:<backend_port>/
   # or
   telnet 127.0.0.1 <backend_port>
   ```

3. **Check WaterWall server config:**
   ```bash
   cat ~/waterwall/server/config.json
   ```
   Verify the backend address/port matches your running service

### Connection timing out?

1. **Check UFW firewall:**
   ```bash
   ufw status
   ```
   Make sure tunnel port is open

2. **Verify WaterWall is running:**
   ```bash
   systemctl status waterwall-direct-server
   systemctl status waterwall-direct-client
   ```

---

## Real-World Usage

Once testing is complete, replace the test backend with your actual service:

### Example: SSH Tunnel
```json
// Server config backend:
"address": "127.0.0.1",
"port": 22  // SSH is already running
```

### Example: HTTP Proxy
```json
// Server config backend:
"address": "127.0.0.1",
"port": 8080  // Your proxy service port
```

### Example: Database Forward
```json
// Server config backend:
"address": "127.0.0.1",
"port": 3306  // MySQL, MongoDB, etc.
```

---

## Summary

[OK] **Fixed:**
1. Added ALPN configuration for TLS (when supported in future)
2. Added DNS servers to core.json
3. Added SSH protection to client UFW setup
4. Created comprehensive testing tools

[OK] **Your Config is Correct:**
- Basic TCP tunnel configuration is valid
- Both server and client configs follow WaterWall standards
- Core.json is properly structured

[OK] **Testing Tools Added:**
- Easy backend service setup (HTTP echo server)
- Complete tunnel testing with clear diagnostics
- Automatic configuration parsing
- Full connection path verification

🎯 **Next Steps:**
1. Run the test backend on server (menu option 6)
2. Run complete tunnel test from client (menu option 6)
3. See the "[OK] WaterWall tunnel is working correctly!" message
4. Replace test backend with your actual service

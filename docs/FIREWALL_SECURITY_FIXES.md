# Firewall Security Fixes - Complete Audit and Hardening

## Date: 2024-02-14

## Overview

Comprehensive security audit and hardening of all firewall-related scripts to ensure:
1. UFW is always checked for installation before use
2. SSH ports from sshd_config are ALWAYS protected before enabling firewall
3. SSH rules are NEVER removed when disabling firewall rules
4. Proper error handling and user feedback

## Critical Changes Made

### 1. ssh_proxy_enable_firewall.sh

**ISSUE:** Did not install UFW if missing - just exited with error.

**FIX:**
- Added `ensure_ufw()` function to check and install UFW with user confirmation
- Added `ensure_ssh_ports()` function to detect and protect SSH ports
- Now enables UFW if inactive (with safe defaults)
- Ensures SSH ports are protected BEFORE enabling UFW
- Better error messages and status output

**Lines Changed:** 8-44 (complete rewrite of main function)

### 2. disable_firewall.sh

**CRITICAL ISSUE:** Completely disabled UFW with `ufw disable`, removing ALL firewall protection including SSH access.

**FIX:**
- Changed behavior to ONLY remove paqet-specific rules (paqet-tunnel, paqet-loopback)
- UFW now remains ACTIVE after running this script
- Detects SSH ports from sshd_config and displays protection status
- Separate removal of tunnel rules and loopback rules with counters
- Added clear warning message explaining UFW remains active
- Provides manual command if user wants to completely disable UFW

**Result:** System remains protected, SSH access cannot be locked out

### 3. firewall_rules_disable.sh

**ISSUE:** Pattern-based removal could theoretically conflict with SSH rules.

**FIX:**
- Added `get_ssh_ports()` function to detect all SSH ports from sshd_config
- Enhanced `remove_by_pattern()` to explicitly check each rule before deletion
- NEVER removes rules with comments containing 'ssh' or 'paqet-ssh'
- NEVER removes rules using SSH ports from sshd_config
- Shows warnings when skipping SSH rules
- Better output formatting showing what was removed
- Counts and displays number of rules removed

**Protection Layers:**
1. Comment-based protection (checks for 'ssh' in comments)
2. Port-based protection (checks against sshd_config ports)
3. Pattern-based targeting (only removes tunnel-specific comments)

### 4. ssh_proxy_port_lib.sh

**ENHANCEMENT:** Added extra SSH port protection to remove function.

**FIX:**
- `ssh_proxy_remove_ufw_port_if_active()` now checks if port is in sshd_config
- Refuses to remove any port that matches SSH configuration
- Added warning message when refusing to remove SSH port
- Double protection: comment-based + port-based

**Lines Changed:** 317-337

### 5. enable_firewall.sh (Paqet)

**ENHANCEMENT:** Improved messaging and SSH protection visibility.

**FIX:**
- Added [INFO] tags to all status messages
- Made SSH protection steps more explicit in output
- Added "CRITICAL - prevents lockout" message for SSH rules
- Shows when SSH ports are already open (not just when opening)
- Better summary output at the end showing configuration
- Role-specific summary (server vs client)

## Files Verified as SAFE

The following scripts were audited and confirmed to have proper protections:

### Already Had Proper UFW Installation Checks:
- `enable_firewall_waterwall.sh` ✓
  - Lines 14-39: `ensure_ufw()` function
  - Lines 85-110: `ensure_ssh_rules()` function

- `enable_firewall_icmptunnel.sh` ✓
  - Lines 15-40: `ensure_ufw()` function
  - Lines 72-96: `ensure_ssh_rules()` function

- `waterwall_direct_server_setup.sh` ✓
  - Lines 83-97: UFW installation check with prompt
  - Lines 92-96: SSH port detection and protection

- `waterwall_direct_client_setup.sh` ✓
  - Lines 76-99: UFW check and SSH port protection

- `icmptunnel_server_setup.sh` ✓
  - Lines 84-122: UFW installation and SSH protection

- `icmptunnel_client_setup.sh` ✓
  - Lines 32-76: UFW installation and SSH protection

### Only Remove Tunnel-Specific Rules (Safe):
- `create_server_config.sh`
  - Function: `sync_ufw_tunnel_rule_server()`
  - Only removes rules with comment 'paqet-tunnel'

- `create_client_config.sh`
  - Function: `sync_ufw_tunnel_rule_client()`
  - Only removes rules with comment 'paqet-tunnel'

- `repair_networking_stack.sh`
  - Functions: `sync_ufw_server_rule()`, `sync_ufw_client_rule()`
  - Only removes rules with comment 'paqet-tunnel'

## SSH Protection Strategy

All firewall scripts now follow this protection strategy:

### When Enabling Firewall:
1. Check if UFW is installed
2. If not installed, prompt to install (with confirmation)
3. Set default policies (deny incoming, allow outgoing)
4. **BEFORE enabling UFW:**
   - Detect ALL SSH ports from `/etc/ssh/sshd_config` and `/etc/ssh/sshd_config.d/*.conf`
   - If no custom ports found, use default port 22
   - Add UFW allow rules for EACH SSH port with comment 'paqet-ssh' or 'ssh'
5. Only then enable UFW
6. Display summary of protected SSH ports

### When Removing Firewall Rules:
1. Detect SSH ports from sshd_config
2. Check each rule before deletion for:
   - Comment contains 'ssh' → skip
   - Port matches SSH port → skip
   - Comment matches tunnel-specific pattern → safe to remove
3. Display what was skipped and why
4. Never disable UFW (keeps protection active)

### SSH Port Detection:
All scripts use consistent detection:
```bash
ssh_ports="$(grep -Rsh '^[[:space:]]*Port[[:space:]]\+[0-9]\+' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | \
  awk '{print $2}' | sort -u || true)"
if [ -z "${ssh_ports}" ]; then
  ssh_ports="22"
fi
```

## Rule Comment Conventions

To maintain protection, all scripts follow these comment conventions:

| Comment | Purpose | Protected? |
|---------|---------|------------|
| `paqet-ssh` | Main SSH access rules | YES - Never removed |
| `ssh` | Main SSH access rules (alt) | YES - Never removed |
| `paqet-ssh-proxy` | SSH proxy service port | Only removed by specific scripts |
| `paqet-tunnel` | Paqet tunnel rules | Removed by paqet cleanup |
| `paqet-loopback` | Loopback interface | Removed by paqet cleanup |
| `waterwall-tunnel` | WaterWall tunnel rules | Removed by waterwall cleanup |
| `waterwall-loopback` | Loopback interface | Removed by waterwall cleanup |
| `waterwall-service` | WaterWall service port | Removed by waterwall cleanup |
| `icmptunnel` | ICMP tunnel rules | Removed by icmptunnel cleanup |
| `icmptunnel-socks` | ICMP SOCKS port | Removed by icmptunnel cleanup |

## Testing Recommendations

After these fixes, test the following scenarios:

### Test 1: Enable Firewall Without UFW
```bash
# On fresh VPS without UFW
sudo ~/paqet_tunnel/scripts/enable_firewall.sh server
# Should prompt to install UFW
# Should detect and protect SSH ports
# Should enable UFW successfully
```

### Test 2: Disable Firewall
```bash
sudo ~/paqet_tunnel/scripts/disable_firewall.sh server
# Should remove only paqet rules
# Should keep UFW active
# Should keep SSH rules intact
# SSH should remain accessible
```

### Test 3: Custom SSH Port
```bash
# Set custom SSH port in /etc/ssh/sshd_config
echo "Port 2222" | sudo tee /etc/ssh/sshd_config.d/custom.conf
sudo systemctl restart sshd

# Enable firewall
sudo ~/paqet_tunnel/scripts/enable_firewall_waterwall.sh server
# Should detect port 2222
# Should protect both 22 and 2222
```

### Test 4: SSH Proxy Port Protection
```bash
# Try to remove SSH port via ssh_proxy_disable_firewall.sh
# If proxy port happens to be an SSH port, should refuse
```

### Test 5: Pattern-Based Removal
```bash
sudo ~/paqet_tunnel/scripts/firewall_rules_disable.sh all
# Should remove all tunnel rules
# Should skip and warn about SSH rules
# Should show what was protected
```

## Security Guarantees

After these fixes, the following security guarantees are in place:

1. **SSH Lockout Prevention:** SSH ports from sshd_config are ALWAYS protected before enabling firewall
2. **Rule Removal Safety:** SSH rules can NEVER be removed by tunnel cleanup scripts
3. **UFW Installation:** All scripts check for UFW and offer to install if missing
4. **Firewall Persistence:** Disabling tunnel rules keeps UFW active (doesn't expose system)
5. **Multi-Layer Protection:** Comment-based + port-based + pattern-based rule protection
6. **Clear Feedback:** All scripts show what SSH ports are protected and why

## Backward Compatibility

All changes are backward compatible:
- Existing UFW configurations continue to work
- Existing rule comments are recognized
- Scripts that check UFW status still work
- Menu system continues to function normally

## Files Modified

1. `/scripts/ssh_proxy_enable_firewall.sh` - Added UFW installation and SSH protection
2. `/scripts/disable_firewall.sh` - Changed to preserve UFW and SSH rules
3. `/scripts/firewall_rules_disable.sh` - Added SSH rule protection layer
4. `/scripts/ssh_proxy_port_lib.sh` - Enhanced remove function with SSH port check
5. `/scripts/enable_firewall.sh` - Improved messaging and output

## Verification Steps

To verify all fixes are working:

```bash
# Check all firewall scripts exist and are executable
ls -lh ~/paqet_tunnel/scripts/*firewall*.sh

# Verify SSH port detection works
grep -Rsh '^[[:space:]]*Port' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf

# Check current UFW status
sudo ufw status verbose

# Review UFW rules for SSH protection
sudo ufw status numbered | grep -i ssh
```

## Conclusion

All firewall-related scripts have been audited and hardened. The codebase now has multiple layers of protection against SSH lockout, ensuring that administrators can safely use the firewall management features without risk of losing access to their servers.

**Key Principle:** When in doubt, protect SSH access. It's better to keep an extra firewall rule than to lock out an administrator.

#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== IPTABLES/NFTABLES DIAGNOSTIC ===${NC}"
echo

echo -e "${BLUE}[1/6] Checking iptables version and backend...${NC}"
iptables -V
if iptables -V 2>/dev/null | grep -qi nf_tables; then
  echo -e "${GREEN}[INFO]${NC} Using nftables backend (iptables-nft)"
else
  echo -e "${GREEN}[INFO]${NC} Using legacy iptables backend"
fi
echo

echo -e "${BLUE}[2/6] Checking nftables installation...${NC}"
if command -v nft >/dev/null 2>&1; then
  echo -e "${GREEN}[OK]${NC} nft command available"
  nft --version
else
  echo -e "${RED}[ERROR]${NC} nft command not found"
fi
echo

echo -e "${BLUE}[3/6] Checking current nftables ruleset...${NC}"
if command -v nft >/dev/null 2>&1; then
  echo "Tables:"
  nft list tables 2>/dev/null || echo "  (none or error)"
  echo
  echo "Full ruleset (first 50 lines):"
  nft list ruleset 2>/dev/null | head -50 || echo "  (error)"
else
  echo "  nft not available, skipping"
fi
echo

echo -e "${BLUE}[4/6] Checking iptables NAT table (iptables view)...${NC}"
echo "NAT OUTPUT chain (via iptables):"
iptables -t nat -L OUTPUT -n -v 2>&1 || echo "  Error listing NAT table"
echo

echo -e "${BLUE}[5/6] Testing rule creation...${NC}"
TEST_UID=99999
echo "Adding test rule: iptables -t nat -A OUTPUT -m owner --uid-owner ${TEST_UID} -p udp --dport 53 -j REDIRECT --to-ports 5353"

if iptables -t nat -A OUTPUT -m owner --uid-owner "${TEST_UID}" -p udp --dport 53 -m comment --comment "test-rule" -j REDIRECT --to-ports 5353 2>&1; then
  echo -e "${GREEN}[OK]${NC} iptables command succeeded"
else
  echo -e "${RED}[ERROR]${NC} iptables command failed"
fi

echo
echo "Checking if rule exists (iptables -t nat -S OUTPUT):"
if iptables -t nat -S OUTPUT 2>/dev/null | grep "test-rule"; then
  echo -e "${GREEN}[OK]${NC} Rule found via iptables -S"
else
  echo -e "${RED}[ERROR]${NC} Rule NOT found via iptables -S"
fi

echo
echo "Checking if rule exists (iptables -t nat -L OUTPUT):"
if iptables -t nat -L OUTPUT -n 2>/dev/null | grep "owner UID match ${TEST_UID}"; then
  echo -e "${GREEN}[OK]${NC} Rule found via iptables -L"
else
  echo -e "${RED}[ERROR]${NC} Rule NOT found via iptables -L"
fi

echo
echo "Checking nftables ruleset for test rule:"
if command -v nft >/dev/null 2>&1; then
  if nft list ruleset 2>/dev/null | grep -i "${TEST_UID}"; then
    echo -e "${GREEN}[OK]${NC} Rule found in nftables"
  else
    echo -e "${RED}[ERROR]${NC} Rule NOT found in nftables"
  fi
else
  echo "  nft not available, skipping"
fi

echo
echo "Removing test rule..."
while iptables -t nat -D OUTPUT -m owner --uid-owner "${TEST_UID}" -p udp --dport 53 -m comment --comment "test-rule" -j REDIRECT --to-ports 5353 2>/dev/null; do
  echo "  Removed one instance"
done
echo

echo -e "${BLUE}[6/6] Checking for NAT kernel modules...${NC}"
if lsmod | grep -q nf_nat; then
  echo -e "${GREEN}[OK]${NC} nf_nat module loaded"
else
  echo -e "${YELLOW}[WARN]${NC} nf_nat module not loaded"
fi

if lsmod | grep -q iptable_nat; then
  echo -e "${GREEN}[OK]${NC} iptable_nat module loaded"
else
  echo -e "${YELLOW}[INFO]${NC} iptable_nat module not loaded (expected with nftables backend)"
fi

if lsmod | grep -q nft_nat; then
  echo -e "${GREEN}[OK]${NC} nft_nat module loaded"
else
  echo -e "${YELLOW}[WARN]${NC} nft_nat module not loaded"
fi
echo

echo -e "${BLUE}=== END DIAGNOSTIC ===${NC}"

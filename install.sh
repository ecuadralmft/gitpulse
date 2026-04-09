#!/usr/bin/env bash
set -euo pipefail

KIRO_DIR="${HOME}/.kiro"
MCP_DIR="${KIRO_DIR}/mcp/gitpulse"
MCP_JSON="${KIRO_DIR}/settings/mcp.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔍 Installing GitPulse MCP server..."

# Create target directory
mkdir -p "${MCP_DIR}"

# Copy server files
cp "${SCRIPT_DIR}/mcp/server.py" "${MCP_DIR}/server.py"
cp "${SCRIPT_DIR}/mcp/requirements.txt" "${MCP_DIR}/requirements.txt"

# Set up venv if not exists
if [ ! -d "${MCP_DIR}/.venv" ]; then
  echo "📦 Creating virtual environment..."
  python3 -m venv "${MCP_DIR}/.venv"
fi

echo "📦 Installing dependencies..."
"${MCP_DIR}/.venv/bin/pip" install --quiet -r "${MCP_DIR}/requirements.txt"

# Register in mcp.json
PYTHON_PATH="${MCP_DIR}/.venv/bin/python3"
SERVER_PATH="${MCP_DIR}/server.py"

if [ -f "${MCP_JSON}" ]; then
  # Check if gitpulse already registered
  if grep -q '"gitpulse"' "${MCP_JSON}"; then
    echo "⚡ GitPulse already registered in mcp.json — updating paths..."
    # Use python to update the JSON safely
    python3 -c "
import json, sys
with open('${MCP_JSON}') as f:
    cfg = json.load(f)
cfg['mcpServers']['gitpulse'] = {
    'command': '${PYTHON_PATH}',
    'args': ['${SERVER_PATH}'],
    'env': {}
}
with open('${MCP_JSON}', 'w') as f:
    json.dump(cfg, f, indent=2)
print('  Updated.')
"
  else
    echo "📝 Registering GitPulse in mcp.json..."
    python3 -c "
import json
with open('${MCP_JSON}') as f:
    cfg = json.load(f)
cfg.setdefault('mcpServers', {})['gitpulse'] = {
    'command': '${PYTHON_PATH}',
    'args': ['${SERVER_PATH}'],
    'env': {}
}
with open('${MCP_JSON}', 'w') as f:
    json.dump(cfg, f, indent=2)
print('  Registered.')
"
  fi
else
  echo "📝 Creating mcp.json with GitPulse..."
  mkdir -p "$(dirname "${MCP_JSON}")"
  python3 -c "
import json
cfg = {'mcpServers': {'gitpulse': {
    'command': '${PYTHON_PATH}',
    'args': ['${SERVER_PATH}'],
    'env': {}
}}}
with open('${MCP_JSON}', 'w') as f:
    json.dump(cfg, f, indent=2)
print('  Created.')
"
fi

echo ""
echo "✅ GitPulse installed!"
echo "   Server: ${SERVER_PATH}"
echo "   Python: ${PYTHON_PATH}"
echo ""
echo "Restart Kiro CLI to load the new MCP server."

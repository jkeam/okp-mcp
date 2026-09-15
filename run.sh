#!/bin/bash

# upstream repo: https://github.com/rhel-lightspeed/okp-mcp
# docs: https://docs.redhat.com/en/documentation/red_hat_offline_knowledge_portal/1/install-customize_your_red_hat_offline_knowledge_portal_deployment

set -euo pipefail

ACCESS_KEY_URL="https://access.redhat.com/offline/access/?extIdCarryOver=true&sc_cid=RHCTN1260000484916"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  start        Create the okp pod and start the RHOKP and MCP server containers.
               Requires RHOKP_ACCESS_KEY to be set. Get one at:
               $ACCESS_KEY_URL
  verify solr        Query Solr to check that RHOKP is running and has indexed content.
  verify mcp         Send an MCP initialize request to verify the MCP server is responding.
  integration cursor Show the MCP server config snippet for Cursor.
  stop               Stop the okp pod and all its containers.
  cleanup            Stop and remove the okp pod and all its containers.
  help               Show this help message.
EOF
}

cmd_start() {
  if [ -z "${RHOKP_ACCESS_KEY+x}" ]; then
    echo 'RHOKP_ACCESS_KEY is unset'
    echo "If you need one, go here: $ACCESS_KEY_URL"
    exit 1
  fi

  podman pod create --name okp -p 8983:8983 -p 8000:8000

  podman run -d --pod okp --name redhat-okp \
    -e ACCESS_KEY="${RHOKP_ACCESS_KEY}" \
    -e SOLR_JETTY_HOST=0.0.0.0 \
    registry.redhat.io/offline-knowledge-portal/rhokp-rhel9:latest

  podman run -d --pod okp --name okp-mcp \
    -e MCP_TRANSPORT=streamable-http \
    -e MCP_SOLR_URL=http://localhost:8983 \
    quay.io/redhat-user-workloads/rhel-lightspeed-tenant/rhel-knowledge-bridge

  echo 'Done! Run "$(basename "$0") stop" to stop everything.'
}

cmd_verify_solr() {
  curl -s -4 "http://localhost:8983/solr/portal/select?q=*:*&rows=0" | python3 -m json.tool
}

cmd_verify_mcp() {
  curl -s -4 -N -X POST http://localhost:8000/mcp \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc": "2.0", "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0"}}, "id": 1}'
}

verify_usage() {
  echo "Usage: $(basename "$0") verify <solr|mcp>" >&2
  exit 1
}

cmd_integration_cursor() {
  cat <<'EOF'
Add the following to your Cursor MCP config:

"okp-mcp": {
  "url": "http://localhost:8000/mcp",
  "transport": "streamable-http"
}
EOF
}

integration_usage() {
  echo "Usage: $(basename "$0") integration <cursor>" >&2
  exit 1
}

cmd_stop() {
  podman pod stop okp
}

cmd_cleanup() {
  cmd_stop
  podman pod rm -f okp
}

case "${1:-help}" in
  start)   cmd_start ;;
  verify)
    case "${2:-}" in
      solr) cmd_verify_solr ;;
      mcp)  cmd_verify_mcp ;;
      *)    verify_usage ;;
    esac
    ;;
  integration)
    case "${2:-}" in
      cursor) cmd_integration_cursor ;;
      *)      integration_usage ;;
    esac
    ;;
  stop)    cmd_stop ;;
  cleanup) cmd_cleanup ;;
  help|-h|--help) usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac

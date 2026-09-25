#!/usr/bin/env bash
set -euo pipefail

apt-get update
apt-get install -y curl ca-certificates

private_iface="$(
  ip -o -4 addr show |
  awk '$4 ~ /^192\.168\.56\.110\// {print $2; exit}'
)"

if [ -z "$private_iface" ]; then
  echo "Cannot find interface for 192.168.56.110" >&2
  exit 1
fi

mkdir -p /etc/rancher/k3s

cat > /etc/rancher/k3s/config.yaml <<EOF
node-ip: "192.168.56.110"
advertise-address: "192.168.56.110"
flannel-iface: "${private_iface}"
write-kubeconfig-mode: "0600"
EOF

curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh
INSTALL_K3S_EXEC="server" sh /tmp/install-k3s.sh

systemctl restart k3s

api_ready=false
for attempt in $(seq 1 120); do
  if k3s kubectl get nodes >/dev/null 2>&1; then
    api_ready=true
    break
  fi
  sleep 2
done

if [ "$api_ready" != true ]; then
  echo "Kubernetes API did not become available" >&2
  exit 1
fi

k3s kubectl wait \
  --for=condition=Ready nodes --all --timeout=180s

k3s kubectl apply -f /tmp/configs/

for app in app1 app2 app3; do
  k3s kubectl rollout status \
    "deployment/${app}" --timeout=180s
done
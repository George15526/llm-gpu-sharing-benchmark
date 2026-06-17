#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?Usage: $0 <image>}"

kubectl delete pod vllm-cuda-check --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

kubectl run vllm-cuda-check \
  --image="$IMAGE" \
  --restart=Never \
  --overrides='{
    "spec": {
      "runtimeClassName": "nvidia",
      "containers": [{
        "name": "vllm-cuda-check",
        "image": "'"$IMAGE"'",
        "command": ["bash", "-lc"],
        "args": ["set -x\npython3 - <<PY\nimport numpy as np\nprint(\"numpy\", getattr(np, \"__version__\", \"NO_VERSION\"), hasattr(np, \"ndarray\"))\nimport torch\nprint(\"torch\", torch.__version__)\nprint(\"cuda available\", torch.cuda.is_available())\nprint(\"device count\", torch.cuda.device_count())\nif torch.cuda.device_count() > 0:\n    print(\"device name\", torch.cuda.get_device_name(0))\n    print(\"capability\", torch.cuda.get_device_capability(0))\nPY"],
        "resources": {"limits": {"nvidia.com/gpu": "1"}}
      }]
    }
  }'

echo "[INFO] Waiting for pod to complete"

PHASE="$(kubectl get pod vllm-cuda-check -o jsonpath='{.status.phase}' 2>/dev/null || true)"
echo "[INFO] phase=$PHASE"

for i in $(seq 1 120); do
  PHASE="$(kubectl get pod vllm-cuda-check -o jsonpath='{.status.phase}' 2>/dev/null || true)"

  if [[ "$PHASE" == "Succeeded" || "$PHASE" == "Failed" ]]; then
    echo "[INFO] phase=$PHASE"
    break
  fi

  sleep 2
done

echo "===== POD STATUS ====="
kubectl get pod vllm-cuda-check -o wide || true

echo "===== LOGS ====="
kubectl logs pod/vllm-cuda-check || true

echo "===== DESCRIBE ====="
kubectl describe pod/vllm-cuda-check || true

echo "===== CLEANUP ====="
kubectl delete pod vllm-cuda-check --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true
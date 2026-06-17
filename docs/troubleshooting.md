# Troubleshooting Notes

## vLLM Image Compatibility

| Image | Result |
|---|---|
| latest | NumPy package issue |
| v0.10.1 | CUDA Error 804 |
| v0.9.2 | torch cu128, CUDA Error 804 |
| v0.8.5 | Working, torch cu124 |
| v0.7.3 | libcusparse.so.12 issue |

## CUDA Error 804

Cause: CUDA userspace in the container is newer than the host driver / unsupported forward compatibility on RTX 4070 SUPER.

Solution: use `vllm/vllm-openai:v0.8.5`.

## NVIDIA_VISIBLE_DEVICES=all

Do not manually set this variable in the Pod spec.

## UnexpectedAdmissionError

Possible cause: NVIDIA device plugin reports no healthy GPU devices.

Suggested recovery:

```bash
kubectl delete pod -l app=vllm --grace-period=0 --force
kubectl rollout restart ds/nvidia-device-plugin -n kube-system
sudo systemctl restart kubelet
```

## vLLM KV Cache Error

Possible cause: insufficient memory for cache blocks under multi-Pod GPU sharing.
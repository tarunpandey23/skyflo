# Skyflo.ai Deployment

This document describes the ways you can deploy Skyflo.ai and points to the right guide for each option.

## Deployment types

| Type | Description | Documentation |
|------|-------------|---------------|
| **Kubernetes (Kustomize)** | Deploy to any Kubernetes cluster using manifests and Kustomize. Full control over namespace, replicas, images, and secrets. | [Kubernetes deployment](deployment-kubernetes.md) |
| **Install script** | One-command install from the web (downloads manifests, prompts for LLM config, applies to cluster). | [Install guide](install.md#1-production-deployment) |
| **Helm** | Deploy using a Helm chart. | _Coming soon_ |


## Prerequisites

### Kubernetes (Kustomize or install script)

- A Kubernetes cluster (v1.19+), or a local cluster for testing (see [Local testing](#local-testing) below).
- `kubectl` installed and configured for your cluster.
- For the **install script** only: `gettext` (for `envsubst`) and `curl`.
- At least one LLM provider configured (e.g. OpenAI, Groq, Anthropic). See [install.md](install.md) and [deployment-kubernetes.md#secrets](deployment-kubernetes.md#secrets).

### Helm

- Helm 3.x and `kubectl` with a cluster.  
- _Helm chart and guide coming soon._

## Local testing

For trying Skyflo.ai on your machine without a remote cluster, use one of these to run a local Kubernetes cluster:

| Option | Description |
|--------|-------------|
| **KinD** (Kubernetes in Docker) | Runs Kubernetes inside Docker. Use `kind create cluster` and the config in `deployment/local.kind.yaml`. See [install.md – Local Development with KinD](install.md#2-local-development-with-kind). |
| **Docker Desktop Kubernetes** | Enable Kubernetes in Docker Desktop (Settings → Kubernetes → Enable). Use the same `kubectl apply` or Kustomize steps as for any cluster. |

After the cluster is running, follow [Kubernetes deployment](deployment-kubernetes.md) or the [install script](install.md) to deploy Skyflo.ai.

## Need help?

- [Troubleshooting (Kubernetes)](deployment-kubernetes.md#troubleshooting)
- [Discord community](https://discord.gg/kCFNavMund)

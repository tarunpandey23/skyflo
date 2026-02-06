# Deploy with Helm

Deploy Skyflo.ai to Kubernetes using the Helm chart in `deployment/helm/skyflo/`. The chart mirrors the [Kustomize layout](deployment-kubernetes.md#folder-structure) (cluster, config, network, workload) and exposes **ingress only for the UI**.

**See also:** [Kubernetes deployment (Kustomize)](deployment-kubernetes.md) | [Deployment overview](deployment.md) | [Install script (production)](install.md)

---

## Table of contents

1. [Prerequisites](#prerequisites)
2. [Overview](#overview)
3. [Directory structure](#directory-structure)
4. [Chart metadata (Chart.yaml)](#chart-metadata-chartyaml)
5. [Template helpers](#template-helpers)
6. [Installation](#installation)
7. [Configuration and values reference](#configuration-and-values-reference)
8. [Secrets and ConfigMaps](#secrets-and-configmaps)
9. [Ingress (production)](#ingress-production)
10. [Upgrade and uninstall](#upgrade-and-uninstall)
11. [Testing the chart](#testing-the-chart)
12. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- **Kubernetes** cluster (v1.19+) — e.g. [KinD](deployment.md#local-testing), minikube, or any cloud cluster.
- **Helm 3** installed (`helm version`).
- **kubectl** configured for your cluster.

---

## Overview

The chart deploys:

- **Controller** — Kubernetes operator for SkyfloAI CRs (uses ServiceAccount `skyflo-ai-controller`).
- **Engine** — Core API (LLM, auth, persistence).
- **UI** — Web UI + proxy.
- **Redis** — Cache/session store (StatefulSet).
- **Postgres** — Database (StatefulSet).

Configuration is driven by `values.yaml` (or `-f my-values.yaml` / `--set`). The chart creates Secrets and ConfigMaps from values; workloads reference them by fixed names. **Ingress is only for the UI**; the engine is internal.

---

## Directory structure

```
deployment/helm/skyflo/
├── Chart.yaml              # Chart metadata (name, version, appVersion, maintainers, etc.)
├── values.yaml             # Default values; override with -f or --set
├── .helmignore             # Files ignored when packaging the chart
├── README.md               # Chart overview and quick start
└── templates/
    ├── _helpers.tpl        # Shared template helpers (fullname, labels, version, engineUrl)
    ├── NOTES.txt           # Post-install message (e.g. port-forward instructions)
    │
    ├── cluster/            # Cluster-scoped and namespace-scoped cluster resources
    │   ├── namespace.yaml  # Namespace (optional, when global.createNamespace is true)
    │   ├── crd.yaml        # SkyfloAI CustomResourceDefinition (when global.installCRD is true)
    │   └── rbac.yaml       # Controller + MCP ServiceAccounts, ClusterRoles, ClusterRoleBindings
    │
    ├── config/
    │   ├── configmaps/
    │   │   ├── version-configmap.yaml   # VERSION from global.version
    │   │   ├── engine-configmap.yaml    # Engine env (from engine.config)
    │   │   ├── ui-configmap.yaml        # UI env (from ui.config) + API_URL injected
    │   │   └── mcp-configmap.yaml       # MCP env (from config.mcp)
    │   └── secrets/
    │       ├── postgres-secrets.yaml    # skyflo-postgres-secrets (from postgresSecret)
    │       └── engine-secrets.yaml      # skyflo-engine-secrets (from engine.secret, only keys with values)
    │
    ├── network/service/    # Services (ClusterIP / headless)
    │   ├── redis-headless.yaml
    │   ├── redis.yaml
    │   ├── postgres-headless.yaml
    │   ├── postgres.yaml
    │   ├── engine.yaml
    │   └── ui.yaml
    │
    ├── workload/           # Deployments and StatefulSets
    │   ├── controller.yaml # Uses SA skyflo-ai-controller
    │   ├── redis.yaml
    │   ├── postgres.yaml
    │   ├── engine.yaml
    │   └── ui.yaml
    │
    └── ingress/
        └── ui-ingress.yaml # Ingress for UI only (when ingress.enabled is true)
```

### What each layer does

| Path | Purpose |
|------|--------|
| **cluster/** | Namespace (optional), SkyfloAI CRD, RBAC: controller and MCP ServiceAccounts with ClusterRoles/Bindings. |
| **config/configmaps/** | Non-sensitive env: version, engine config, UI config, MCP config. All keys from values are included. |
| **config/secrets/** | Postgres credentials (all four keys) and engine credentials (only keys with a value). Workloads reference these by name. |
| **network/service/** | Services so pods can reach redis, postgres, engine, and UI. |
| **workload/** | Deployments (controller, engine, ui) and StatefulSets (redis, postgres). |
| **ingress/** | Single Ingress for the UI service; engine is not exposed. |

---

## Chart metadata (Chart.yaml)

| Field | Description |
|-------|-------------|
| `name` | Chart name: `skyflo`. |
| `version` | Chart version (semver); bump when changing templates or defaults. |
| `appVersion` | Application version (e.g. Skyflo `0.5.0`); often used as default image tag. |
| `description` | Short description of the chart. |
| `type` | `application`. |
| `home` | Project URL. |
| `icon` | URL to a PNG or SVG icon. |
| `maintainers` | List of maintainers (name, email, url). |
| `sources` | Source code URLs. |
| `keywords` | Keywords for discovery. |

---

## Template helpers

Defined in `templates/_helpers.tpl` and used across templates:

| Helper | Purpose |
|--------|---------|
| `skyflo.name` | Chart name (from `global.nameOverride` or chart name). |
| `skyflo.fullname` | Resource prefix (from `global.fullnameOverride` or release + name). Default: `skyflo-ai`. |
| `skyflo.chart` | Label value e.g. `skyflo-0.1.0` (chart name + version). |
| `skyflo.labels` | Common labels (chart, selector, version, managed-by). |
| `skyflo.selectorLabels` | Selector labels (app name, instance). |
| `skyflo.version` | App version for ConfigMap and image tags (from `global.version` or appVersion). |
| `skyflo.namespace` | Namespace (from `global.namespace` or release namespace). |
| `skyflo.engineUrl` | Engine API URL: `http://<fullname>-engine:8080/api/v1` (used in UI ConfigMap). |

---

## Installation

### One-command install (creates namespace and installs chart)

From the repo root, run this **single command**. It creates the `skyflo-ai` namespace if it doesn’t exist and installs the chart (no `kubectl` needed):

```bash
helm install skyflo-ai ./deployment/helm/skyflo -n skyflo-ai --create-namespace
```

Ensure required values (e.g. `engine.secret.JWT_SECRET`, one provider API key, `postgresSecret.password`) are set in `values.yaml` or pass them with `--set`. If the namespace already exists from a previous install, omit `--create-namespace` or run `helm uninstall skyflo-ai -n skyflo-ai` first, then the command above again.

### 1. Clone or use the repo

From the Skyflo repo root:

```bash
cd /path/to/skyflo
```

### 2. Set required values

You must provide at least:

- **Engine:** LLM provider and API key, `JWT_SECRET`, and (if using in-cluster Postgres/Redis) leave `POSTGRES_DATABASE_URL` / `REDIS_URL` empty so the chart uses `engine.defaultUrls`.
- **Postgres:** `postgresSecret.password` when using the in-cluster Postgres.

**Minimal install (dev / try-out)** — inline values:

```bash
helm install skyflo-ai ./deployment/helm/skyflo -n skyflo-ai --create-namespace \
  --set global.version=v0.5.0 \
  --set engine.secret.JWT_SECRET="$(openssl rand -base64 32)" \
  --set engine.secret.LLM_MODEL=openai/gpt-4o \
  --set engine.secret.OPENAI_API_KEY=sk-your-openai-key \
  --set postgresSecret.password="$(openssl rand -base64 24)"
```

**Using a custom values file** — recommended:

1. Copy the default values and edit:
   ```bash
   cp deployment/helm/skyflo/values.yaml my-values.yaml
   ```
2. In `my-values.yaml` set at least: `global.version`, `engine.secret.LLM_MODEL`, `engine.secret.OPENAI_API_KEY` (or your provider key), `engine.secret.JWT_SECRET`, `postgresSecret.password`.
3. Install:
   ```bash
   helm install skyflo-ai ./deployment/helm/skyflo -n skyflo-ai --create-namespace -f my-values.yaml
   ```

**Production** — override secrets via `--set` or a values file (avoid committing real keys):

```bash
helm install skyflo-ai ./deployment/helm/skyflo -n skyflo-ai --create-namespace \
  --set postgresSecret.password=YOUR_PG_PASSWORD \
  --set engine.secret.JWT_SECRET="$(openssl rand -base64 32)" \
  --set engine.secret.GROQ_API_KEY=your-groq-key
```

### 3. Check rollout

```bash
kubectl get pods -n skyflo-ai
```

Wait until all pods are `Running` and ready (e.g. `1/1` or `2/2` for UI). Example:

```
NAME                                    READY   STATUS    RESTARTS   AGE
skyflo-ai-controller-xxxxxxxxxx-xxxxx    1/1     Running   0          1m
skyflo-ai-engine-xxxxxxxxxx-xxxxx        1/1     Running   0          1m
skyflo-ai-postgres-0                    1/1     Running   0          1m
skyflo-ai-redis-0                       1/1     Running   0          1m
skyflo-ai-ui-xxxxxxxxxx-xxxxx            2/2     Running   0          1m
```

### 4. Access the UI

**Local (port-forward):**

```bash
kubectl port-forward -n skyflo-ai svc/skyflo-ai-ui 3000:80
```

Open **http://localhost:3000** in your browser.

**Production:** Enable and configure the **UI-only** Ingress (see [Ingress (production)](#ingress-production) below).

---

## Configuration and values reference

Configuration is done via Helm values: `values.yaml`, `-f my-values.yaml`, or `--set`.

### Main values (summary)

| What | Value | Description |
|------|--------|-------------|
| **Global** | `global.version` | App version (e.g. `v0.5.0`). Used in version ConfigMap and as default image tag. |
| **Global** | `global.namespace`, `global.fullnameOverride`, `global.nameOverride` | Namespace and resource naming. |
| **Global** | `global.createNamespace`, `global.installCRD` | Create namespace; install SkyfloAI CRD. |
| **Global** | `global.imagePullSecrets`, `global.imagePullPolicy`, `global.podAnnotations`, `global.podLabels`, `global.nodeSelector`, `global.tolerations`, `global.affinity`, `global.podSecurityContext`, `global.securityContext` | Shared pod and image settings. |
| **Controller** | `controller.replicas`, `controller.image`, `controller.resources` | Scale and image for the Kubernetes controller. |
| **Redis** | `redis.replicas`, `redis.image`, `redis.persistence.size` | Redis StatefulSet. |
| **Postgres** | `postgres.*`, `postgresSecret.*` | Postgres StatefulSet and credentials. |
| **UI** | `ui.replicas`, `ui.image`, `ui.proxyImage`, `ui.config` | UI and proxy images and config. |
| **Engine** | `engine.replicas`, `engine.image`, `engine.config`, `engine.secret` | Engine deployment; chart creates Secret `skyflo-engine-secrets` from `engine.secret`. |
| **Ingress** | `ingress.enabled`, `ingress.hosts`, `ingress.annotations`, `ingress.tls` | **UI-only** Ingress. |

### Engine secrets (required)

The chart creates Secret `skyflo-engine-secrets` from `engine.secret`. **Only keys with a value are added** to the Secret; leave unused provider keys empty in values so they are not included.

**Required for a working deployment:**

| Variable | Description |
|----------|-------------|
| `LLM_MODEL` | Model identifier in `provider/model` form (e.g. `openai/gpt-4o`, `groq/llama-3.3-70b-versatile`). |
| One of the provider API key variables below | Set the key that matches the provider for your `LLM_MODEL`. |
| `JWT_SECRET` | Secret for signing JWTs (e.g. `openssl rand -base64 32`). |
| `POSTGRES_DATABASE_URL` | Postgres connection URL; leave empty to use in-cluster URL from `engine.defaultUrls`. |
| `REDIS_URL` | Redis URL; leave empty to use in-cluster URL from `engine.defaultUrls`. |

**LLM provider API key variables** (set only the one you need for your chosen `LLM_MODEL`):

| Variable | Provider |
|----------|----------|
| `OPENAI_API_KEY` | OpenAI |
| `GROQ_API_KEY` | Groq |
| `ANTHROPIC_API_KEY` | Anthropic |
| `AZURE_API_KEY` | Azure OpenAI |
| `GEMINI_API_KEY` | Google Gemini |
| `COHERE_API_KEY` | Cohere |
| `MISTRAL_API_KEY` | Mistral |
| `ANYSCALE_API_KEY` | Anyscale |
| `OPENROUTER_API_KEY` | OpenRouter |
| `PERPLEXITYAI_API_KEY` | Perplexity |
| `FIREWORKS_AI_API_KEY` | Fireworks AI |
| `TOGETHERAI_API_KEY` | Together AI |
| `DEEPINFRA_API_KEY` | DeepInfra |
| `AI21_API_KEY` | AI21 |
| `NLP_CLOUD_API_KEY` | NLP Cloud |
| `REPLICATE_API_KEY` | Replicate |
| `HF_TOKEN` | Hugging Face |
| `DATABRICKS_TOKEN` | Databricks |
| `CLARIFAI_PAT` | Clarifai |
| `VOYAGE_API_KEY` | Voyage |
| `JINAAI_API_KEY` | Jina AI |
| `ALEPHALPHA_API_KEY` | Aleph Alpha |
| `BASETEN_API_KEY` | Baseten |
| `SAMBANOVA_API_KEY` | SambaNova |
| `FEATHERLESS_AI_API_KEY` | Featherless AI |
| `OLLAMA_API_KEY` | Ollama (self-hosted) |
| `IBM_API_KEY` | IBM / Watsonx |
| `PREDIBASE_API_KEY` | Predibase |
| `NVIDIA_NGC_API_KEY` | NVIDIA NIM |
| `XAI_API_KEY` | xAI |
| `VOLCENGINE_API_KEY` | Volcengine |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock (with AWS_SECRET_ACCESS_KEY, AWS_REGION_NAME) |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock |
| `AWS_REGION_NAME` | AWS Bedrock (e.g. us-west-2) |
| `LLM_HOST` | Optional; self-hosted LLM endpoint URL |

**Recommendation:** Set only the provider key that matches your `LLM_MODEL`, plus `JWT_SECRET`. Leave `POSTGRES_DATABASE_URL` and `REDIS_URL` empty to use `engine.defaultUrls` when using in-cluster Postgres and Redis.

### Detailed values reference

| Section | Key | Type | Default | Description |
|---------|-----|------|---------|-------------|
| **global** | `nameOverride`, `fullnameOverride`, `namespace`, `version` | string | see values.yaml | Naming and app version. |
| **global** | `createNamespace`, `installCRD` | bool | true | Create namespace; install CRD. |
| **global** | `imagePullPolicy`, `imagePullSecrets`, `podAnnotations`, `podLabels`, `nodeSelector`, `tolerations`, `affinity` | object/list | — | Shared pod/image settings. |
| **global** | `podSecurityContext`, `securityContext` | object | runAsNonRoot, drop ALL | Pod and container security context. |
| **controller** | `enabled`, `replicas`, `image`, `resources` | — | — | Controller deployment. |
| **redis** | `enabled`, `replicas`, `image`, `resources`, `persistence.size` | — | — | Redis StatefulSet. |
| **postgres** | `enabled`, `replicas`, `image`, `resources`, `persistence.size` | — | — | Postgres StatefulSet. |
| **postgresSecret** | `user`, `password`, `database`, `port` | string | skyflo, 5432 | Postgres credentials (Secret `skyflo-postgres-secrets`). |
| **ui** | `enabled`, `replicas`, `podSecurityContext`, `image`, `proxyImage`, `service`, `resources`, `config` | — | — | UI and proxy. |
| **engine** | `enabled`, `replicas`, `image`, `service.port`, `secret`, `defaultUrls`, `config`, `integrationsSecretNamespace`, `resources` | — | — | Engine deployment and Secret. |
| **config.mcp** | `APP_NAME`, `APP_DESCRIPTION`, `DEBUG`, `LOG_LEVEL`, retry keys | — | — | MCP ConfigMap (if MCP deployed separately). |
| **ingress** | `enabled`, `className`, `annotations`, `hosts`, `tls` | — | false, [] | UI-only Ingress. |

See `values.yaml` in the chart for every key and default.

### Example: custom values file

```yaml
# my-values.yaml
global:
  version: "v0.5.0"
  namespace: skyflo-ai

controller:
  replicas: 1

engine:
  replicas: 1
  secret:
    LLM_MODEL: "openai/gpt-4o"
    OPENAI_API_KEY: "sk-..."       # set externally or via --set
    JWT_SECRET: "..."              # set externally or via --set
    POSTGRES_DATABASE_URL: ""      # empty = in-cluster
    REDIS_URL: ""                  # empty = in-cluster

postgresSecret:
  password: "changeme-in-production"

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: skyflo.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: skyflo-tls
      hosts:
        - skyflo.example.com
```

Install with:

```bash
helm install skyflo-ai ./deployment/helm/skyflo -n skyflo-ai --create-namespace -f my-values.yaml
```

---

## Secrets and ConfigMaps

### How secrets are created and used

1. **Postgres**  
   When `postgres.enabled` is true, the chart creates Secret **skyflo-postgres-secrets** with keys: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT` from `postgresSecret`. The Postgres StatefulSet uses this Secret via `secretKeyRef`.

2. **Engine**  
   When `engine.enabled` is true, the chart creates Secret **skyflo-engine-secrets**. Only keys under `engine.secret` that have a non-empty value are added. Empty `POSTGRES_DATABASE_URL` and `REDIS_URL` are filled from `engine.defaultUrls`. The Engine deployment uses this Secret via `envFrom`.

### ConfigMaps

| ConfigMap | Source | Used by |
|-----------|--------|--------|
| **skyflo-version** | `global.version` | All workloads (APP_VERSION env). |
| **skyflo-engine-config** | `engine.config` | Engine (envFrom). |
| **skyflo-ui-config** | `ui.config` + chart-injected `API_URL` | UI (envFrom). |
| **skyflo-mcp-config** | `config.mcp` | MCP (if deployed separately). |

All ConfigMap keys listed in values are included.

---

## Ingress (production)

The chart only creates an Ingress for the **UI** service. The engine is used by the UI and is not exposed publicly.

1. Set in values (or `--set`):

   ```yaml
   ingress:
     enabled: true
     className: alb    # or nginx, traefik, etc.
     annotations: {}   # e.g. AWS ALB annotations
     hosts:
       - host: your-domain.com
         paths:
           - path: /
             pathType: Prefix
     tls:
       - secretName: skyflo-tls
         hosts:
           - your-domain.com
   ```

2. Upgrade or install with that values file.

3. Point DNS (e.g. CNAME) at the Ingress address:
   ```bash
   kubectl get ingress -n skyflo-ai
   ```

For an **AWS ALB** example, see [Ingress (production)](deployment-kubernetes.md#ingress-production) in the Kubernetes deployment doc.

---

## Upgrade and uninstall

**Upgrade** to a new version or change config:

```bash
helm upgrade skyflo-ai ./deployment/helm/skyflo -n skyflo-ai -f my-values.yaml
```

If you only change ConfigMaps or Secrets, restart the workloads that use them:

```bash
kubectl rollout restart deployment/skyflo-ai-engine -n skyflo-ai
kubectl rollout restart deployment/skyflo-ai-ui -n skyflo-ai
```

**Uninstall:**

```bash
helm uninstall skyflo-ai -n skyflo-ai
```

To also remove **persistent data** (Redis and Postgres):

```bash
kubectl delete pvc -l app=skyflo-ai-redis -n skyflo-ai
kubectl delete pvc -l app=skyflo-ai-postgres -n skyflo-ai
```

---

## Testing the chart

**Lint and render (no cluster):**

```bash
helm lint deployment/helm/skyflo
helm template skyflo-ai deployment/helm/skyflo -n skyflo-ai
helm template skyflo-ai deployment/helm/skyflo -n skyflo-ai \
  --set engine.secret.JWT_SECRET=test --set engine.secret.GROQ_API_KEY=test-key
```

**Dry-run install (cluster required, no resources created):**

```bash
helm install skyflo-ai ./deployment/helm/skyflo -n skyflo-ai --create-namespace --dry-run \
  --set engine.secret.JWT_SECRET=test \
  --set engine.secret.LLM_MODEL=groq/llama-3.3-70b-versatile \
  --set engine.secret.GROQ_API_KEY=your-key \
  --set postgresSecret.password=test
```

**Real install and verify (e.g. KinD / minikube / Docker Desktop):**

```bash
helm upgrade --install skyflo-ai ./deployment/helm/skyflo -n skyflo-ai --create-namespace \
  -f deployment/helm/skyflo/values.yaml \
  --set engine.secret.JWT_SECRET="$(openssl rand -base64 32)" \
  --set engine.secret.GROQ_API_KEY=your-groq-key \
  --set postgresSecret.password=skyflo

kubectl get pods -n skyflo-ai -w
kubectl get secret,configmap -n skyflo-ai
```

**Access UI and clean up:**

```bash
kubectl port-forward -n skyflo-ai svc/skyflo-ai-ui 3000:80
# Open http://localhost:3000, then Ctrl+C to stop port-forward

helm uninstall skyflo-ai -n skyflo-ai
kubectl delete namespace skyflo-ai   # optional
```

---

## Troubleshooting

### Pods not starting or not ready

1. List pods and check status/events:
   ```bash
   kubectl get pods -n skyflo-ai
   kubectl describe pod <pod-name> -n skyflo-ai
   ```
2. **ImagePullBackOff** — Wrong image name/tag or missing imagePullSecrets. Check `global.imagePullSecrets` and per-service `image.repository` / `image.tag`.
3. **CrashLoopBackOff** — Check logs:
   ```bash
   kubectl logs <pod-name> -n skyflo-ai
   kubectl logs <pod-name> -n skyflo-ai --previous
   ```
4. **Probe failures** — Check `describe` for “Liveness probe failed” or “Readiness probe failed”; adjust probe settings in the workload template if needed.

### Engine or UI: 401 / “Unable to send prompt” / no response from agent

1. **Wrong or missing API key**  
   Ensure the provider key in `engine.secret` matches `LLM_MODEL` (e.g. `LLM_MODEL: groq/llama-...` and `GROQ_API_KEY` set). Only keys with values are in the Secret; confirm your key is present:
   ```bash
   kubectl get secret skyflo-engine-secrets -n skyflo-ai -o jsonpath='{.data}' | jq 'keys'
   ```

2. **Missing JWT_SECRET**  
   Engine needs `JWT_SECRET` for auth. Set it in values or via `--set engine.secret.JWT_SECRET=...`.

3. **Engine logs**  
   ```bash
   kubectl logs deployment/skyflo-ai-engine -n skyflo-ai
   ```
   See [deployment-kubernetes.md — Unable to send prompt](deployment-kubernetes.md#unable-to-send-prompt-or-no-response-from-the-agent) for common causes.

### Database connection errors (engine or postgres)

1. **Postgres not ready**  
   Wait for Postgres: `kubectl get pods -n skyflo-ai -l app=skyflo-ai-postgres`. Ensure `engine.defaultUrls.POSTGRES_DATABASE_URL` matches `postgresSecret` and the Postgres service name (e.g. `skyflo-ai-postgres`).

2. **Wrong credentials**  
   Postgres workload uses Secret **skyflo-postgres-secrets**. Engine uses `POSTGRES_DATABASE_URL` from **skyflo-engine-secrets** (or defaultUrls). Ensure user/password/database in `postgresSecret` match.

3. **Redis**  
   Ensure `REDIS_URL` (or defaultUrls) points at the Redis service (e.g. `redis://skyflo-ai-redis:6379/0`).

### UI not loading or wrong API URL

- **API_URL** is set by the chart to the internal engine URL (`http://<fullname>-engine:8080/api/v1`). If you use a different release name or fullnameOverride, the helper uses that automatically.
- **Port-forward:** `kubectl port-forward -n skyflo-ai svc/skyflo-ai-ui 3000:80` then open http://localhost:3000.
- **Ingress:** Check `kubectl get ingress -n skyflo-ai` and DNS; ensure TLS secret exists if you set `ingress.tls`.

### Helm: “resource already exists” or upgrade conflicts

- Resources are owned by the Helm release. Don’t create the same names (e.g. Secret `skyflo-postgres-secrets`) manually; let the chart create them.

### Viewing rendered manifests

```bash
helm template skyflo-ai ./deployment/helm/skyflo -n skyflo-ai -f my-values.yaml
helm install skyflo-ai ./deployment/helm/skyflo -n skyflo-ai -f my-values.yaml --dry-run --debug
```


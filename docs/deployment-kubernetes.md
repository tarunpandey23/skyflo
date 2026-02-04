# Kubernetes deployment (Kustomize)

Deploy Skyflo.ai to any Kubernetes cluster using the manifests under `deployment/kubernetes/` and Kustomize. You control version, namespace, replicas, and secrets from a single place.

**See also:** [Main deployment overview](deployment.md) | [Production install script](install.md)

---

## Prerequisites

- Kubernetes cluster (v1.19+) — for local testing you can use [KinD](deployment.md#local-testing) or [Docker Desktop Kubernetes](deployment.md#local-testing).
- `kubectl` configured for your cluster.
- (Optional) `kubectl kustomize` or `kubectl apply -k` support.

---

## Folder structure

```
deployment/kubernetes/
├── kustomization.yaml       # Single file to change version, namespace, replicas, images
├── cluster/                 # Cluster-scoped / namespace and RBAC
│   ├── namespace.yaml       # skyflo-ai namespace
│   ├── crd.yaml             # Skyflo CRDs
│   └── rbac.yaml            # ServiceAccount, Role, RoleBinding for controller
├── config/
│   ├── configmaps/          # Non-sensitive configuration
│   │   ├── version-configmap.yaml   # VERSION (e.g. v0.5.0) for APP_VERSION in pods
│   │   ├── engine-configmap.yaml   # Engine app config (MCP_SERVER_URL, JWT_*, LLM_*, etc.)
│   │   ├── mcp-configmap.yaml      # MCP server config
│   │   └── ui-configmap.yaml       # UI config
│   └── secrets/             # Sensitive data — edit before apply
│       ├── engine-secrets.yaml      # LLM API keys, JWT_SECRET, DB/Redis URLs
│       └── postgres-secrets.yaml    # POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, POSTGRES_PORT
├── network/
│   └── service/            # Services
│       ├── redis-headless.yaml
│       ├── redis.yaml
│       ├── postgres-headless.yaml
│       ├── postgres.yaml
│       ├── ui.yaml
│       └── engine.yaml
└── workload/                # Deployments and StatefulSets
    ├── controller.yaml     # Skyflo controller
    ├── redis.yaml          # Redis StatefulSet
    ├── postgres.yaml       # Postgres StatefulSet
    ├── ui.yaml             # UI + proxy
    └── engine.yaml         # Engine API
```

---

## Editing configs, secrets, and other settings

Every resource is defined in a YAML file under `deployment/kubernetes/`. To change anything: edit the right file, then run `kubectl apply -k deployment/kubernetes/` from the repo root to push changes to the cluster. Optionally apply a single file with `kubectl apply -f deployment/kubernetes/<path/to/file>.yaml`.

### Resource-to-file reference

Use this table to find which file defines which resource. Edit that file to change the resource.

| Resource | Kind | File to edit |
|----------|------|--------------|
| **Cluster / namespace** | | |
| `skyflo-ai` namespace | Namespace | `cluster/namespace.yaml` |
| Skyflo CRDs | CustomResourceDefinition | `cluster/crd.yaml` |
| Controller SA, Role, RoleBinding | ServiceAccount, Role, RoleBinding | `cluster/rbac.yaml` |
| **Config** | | |
| `skyflo-version` | ConfigMap | `config/configmaps/version-configmap.yaml` |
| `skyflo-engine-config` | ConfigMap | `config/configmaps/engine-configmap.yaml` |
| `skyflo-mcp-config` | ConfigMap | `config/configmaps/mcp-configmap.yaml` |
| `skyflo-ui-config` | ConfigMap | `config/configmaps/ui-configmap.yaml` |
| **Secrets** | | |
| `skyflo-engine-secrets` | Secret | `config/secrets/engine-secrets.yaml` |
| `skyflo-postgres-secrets` | Secret | `config/secrets/postgres-secrets.yaml` |
| **Services** | | |
| `skyflo-ai-redis-headless` | Service | `network/service/redis-headless.yaml` |
| `skyflo-ai-redis` | Service | `network/service/redis.yaml` |
| `skyflo-ai-postgres-headless` | Service | `network/service/postgres-headless.yaml` |
| `skyflo-ai-postgres` | Service | `network/service/postgres.yaml` |
| `skyflo-ai-ui` | Service | `network/service/ui.yaml` |
| `skyflo-ai-engine` | Service | `network/service/engine.yaml` |
| **Workloads** | | |
| `skyflo-ai-controller` | Deployment | `workload/controller.yaml` |
| `skyflo-ai-redis` | StatefulSet | `workload/redis.yaml` |
| `skyflo-ai-postgres` | StatefulSet | `workload/postgres.yaml` |
| `skyflo-ai-ui` | Deployment | `workload/ui.yaml` |
| `skyflo-ai-engine` | Deployment | `workload/engine.yaml` |
| **Kustomize overrides** | | |
| Namespace, replicas, image tags, labels | — | `kustomization.yaml` |

**Applying changes:** After editing any file, run `kubectl apply -k deployment/kubernetes/` so the cluster matches your files. To apply only one resource: `kubectl apply -f deployment/kubernetes/<path/to/file>.yaml`.

The sections below give more detail for ConfigMaps, Secrets, and other common edits.

### ConfigMaps (non-sensitive config)

**Location:** `config/configmaps/`

| File | Used by | What to edit |
|------|---------|--------------|
| `version-configmap.yaml` | All app pods | `data.VERSION` — keep in sync with image tags in `kustomization.yaml` (e.g. `v0.5.0`). |
| `engine-configmap.yaml` | Engine | `MCP_SERVER_URL`, `LOG_LEVEL`, `JWT_ALGORITHM`, `JWT_ACCESS_TOKEN_EXPIRE_MINUTES`, `JWT_REFRESH_TOKEN_EXPIRE_DAYS`, `LLM_TEMPERATURE`, `LLM_MAX_ITERATIONS`, etc. |
| `mcp-configmap.yaml` | MCP server | MCP-related settings. |
| `ui-configmap.yaml` | UI | UI app configuration. |

**Format:** Under `data:`, each key is a string. Edit in place:

```yaml
data:
  MCP_SERVER_URL: "http://skyflo-ai-mcp:8888/mcp"
  LOG_LEVEL: "INFO"
```

After editing, run `kubectl apply -k deployment/kubernetes/` (or apply only the ConfigMap with `kubectl apply -f config/configmaps/<file>.yaml`). Pods that use the ConfigMap may need a restart to pick up changes: `kubectl rollout restart deployment/skyflo-ai-engine -n skyflo-ai` (and similarly for other workloads).

### Secrets (API keys, passwords)

**Location:** `config/secrets/`

| File | Used by | What to edit |
|------|---------|--------------|
| `engine-secrets.yaml` | Engine | LLM API keys, `LLM_MODEL`, `JWT_SECRET`, `POSTGRES_DATABASE_URL`, `REDIS_URL`. See [Secrets](#secrets) for the full list. |
| `postgres-secrets.yaml` | Postgres | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT`. |

**Format:** Use `stringData:` so values are plain text (no base64). Uncomment only the keys you need; uncommented keys with no value create empty secret entries.

```yaml
stringData:
  # OPENAI_API_KEY: "sk-..."     # leave commented if not using OpenAI
  GROQ_API_KEY: "gsk-your-key"
  LLM_MODEL: "groq/llama-3.3-70b-versatile"
  JWT_SECRET: "your-base64-or-opaque-secret"
  POSTGRES_DATABASE_URL: "postgres://skyflo:yourpassword@skyflo-ai-postgres:5432/skyflo"
  REDIS_URL: "redis://skyflo-ai-redis:6379/0"
```

**Important:** Do not commit real API keys or passwords. Use env vars, a secret manager, or replace placeholders before apply. After editing, run `kubectl apply -k deployment/kubernetes/`.

### kustomization.yaml (namespace, replicas, images, labels)

**Location:** `deployment/kubernetes/kustomization.yaml`

| Section | What to edit |
|---------|--------------|
| `namespace` | Change to deploy into another namespace (e.g. `namespace: my-ns`). |
| `labels` | Add or change labels applied to all resources. |
| `replicas` | Scale workloads: set `count` for each `name` (e.g. `skyflo-ai-engine: 2`). |
| `images` | Set `newTag` for each image to change app version (e.g. `v0.6.0`). Keep `version-configmap.yaml` `VERSION` in sync. |

No need to edit individual workload YAMLs for these; Kustomize applies these overrides when you run `kubectl apply -k deployment/kubernetes/`.

### Workload and service YAMLs (advanced)

**Locations:** `workload/*.yaml`, `network/service/*.yaml`

Edit these only when you need to change something not controlled by Kustomize (e.g. container resources, probes, service ports, extra env vars). Changes to workload or service files are applied with the same command: `kubectl apply -k deployment/kubernetes/`.

### Applying your changes

After editing any of the above:

```bash
kubectl apply -k deployment/kubernetes/
```

If you changed only a ConfigMap or Secret, pods may not reload it automatically; restart the workload that uses it if needed:

```bash
kubectl rollout restart deployment/skyflo-ai-engine -n skyflo-ai
kubectl rollout restart deployment/skyflo-ai-ui -n skyflo-ai
```

---

## Deployment steps

1. **Configure secrets**  
   Edit the files under `config/secrets/` (see [Secrets](#secrets)). Only uncomment and set the API keys and values you need; leaving unused keys uncommented creates empty secret entries.

2. **Optional: adjust `kustomization.yaml`**  
   You can change:
   - `namespace` (default: `skyflo-ai`)
   - `replicas` (per Deployment/StatefulSet)
   - `images[].newTag` (app version)
   - `labels`  
   Keep `config/configmaps/version-configmap.yaml` `VERSION` in sync with the image tags you use.

3. **Apply**  
   From the repo root:
   ```bash
   kubectl apply -k deployment/kubernetes/
   ```

4. **Check rollout**  
   ```bash
   kubectl get pods -n skyflo-ai
   ```

5. **Access the UI (local)**  
   ```bash
   kubectl port-forward -n skyflo-ai svc/skyflo-ai-ui 3000:80
   ```  
   Open `http://localhost:3000`.

For production, configure an [Ingress](#ingress-production).

---

## Managing from `kustomization.yaml`

Everything below is controlled in `deployment/kubernetes/kustomization.yaml`:

| What | Section | Effect |
|------|---------|--------|
| **Namespace** | `namespace: skyflo-ai` | Applied to all resources. Change here to deploy into another namespace. |
| **Labels** | `labels` | Added to all resources and selectors (e.g. `app.kubernetes.io/part-of: skyflo-ai`). |
| **Replicas** | `replicas` | Overrides `spec.replicas` for each listed Deployment/StatefulSet (controller, engine, ui, redis, postgres). |
| **Image tags** | `images` | Replaces container image tags for the listed images. Single place to bump app version. |

When you change app version:

1. Update `images[].newTag` in `kustomization.yaml`.
2. Update `VERSION` in `config/configmaps/version-configmap.yaml` so `APP_VERSION` in pods stays in sync.

No `envsubst` or `export VERSION` is required for the Kustomize flow.

---

## Secrets

Secrets live in `config/secrets/`. **Only include the keys you use.** Uncommented keys with no value become empty secret entries; comment out any provider/key you do not need.

### Engine secrets (`config/secrets/engine-secrets.yaml`)

Used by the **engine** workload. Required for a working deployment:

| Variable | Description |
|----------|-------------|
| `LLM_MODEL` | Model identifier in `provider/model` form (e.g. `openai/gpt-4o`, `groq/llama-3.3-70b-versatile`). |
| One of the provider API key variables below | Depending on which provider you use for `LLM_MODEL`. |
| `JWT_SECRET` | Secret for signing JWTs (e.g. `openssl rand -base64 32`). |
| `POSTGRES_DATABASE_URL` | Postgres connection URL (default in-cluster: `postgres://skyflo:<password>@skyflo-ai-postgres:5432/skyflo`). |
| `REDIS_URL` | Redis URL (default in-cluster: `redis://skyflo-ai-redis:6379/0`). |

**LLM provider API key variables** (uncomment only the one you need for your chosen `LLM_MODEL`):

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

**Recommendation:** Leave all provider keys commented except the one for your chosen `LLM_MODEL`. Set that key and the required `JWT_SECRET`, `POSTGRES_DATABASE_URL`, and `REDIS_URL` (and optionally `LLM_HOST`).

### Postgres secrets (`config/secrets/postgres-secrets.yaml`)

Used by the **postgres** workload. Defaults (change in production):

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_USER` | Postgres user | `skyflo` |
| `POSTGRES_PASSWORD` | Postgres password | Set a strong value in production |
| `POSTGRES_DB` | Database name | `skyflo` |
| `POSTGRES_PORT` | Port | `5432` |

`POSTGRES_DATABASE_URL` in engine-secrets must use the same user, password, host (`skyflo-ai-postgres`), port, and database.

---

## Ingress (production)

To expose the UI over HTTPS and a domain, create an Ingress targeting the Skyflo UI service. The engine is called by the UI from the browser; ensure your Ingress or network allows that.

### Example: AWS ALB Ingress

1. Apply an Ingress that points to the UI service (port 80). Example for AWS ALB:

```yaml
# skyflo-ai-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: skyflo-ai-ingress
  namespace: skyflo-ai
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/subnets: subnet-xxxxx, subnet-yyyyy   # Your subnet IDs
    alb.ingress.kubernetes.io/security-groups: sg-xxxxx             # Your security group ID
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/xxxxx
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80,"HTTPS": 443}]'
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  ingressClassName: alb
  rules:
  - host: your-domain.com
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: skyflo-ai-ui
            port:
              number: 80
```

2. Apply and get the ALB hostname:
   ```bash
   kubectl apply -f skyflo-ai-ingress.yaml
   kubectl get ingress -n skyflo-ai
   ```
3. Point your DNS (e.g. CNAME) to the ALB DNS name.

For other Ingress controllers (nginx, traefik, etc.), use the same idea: Ingress → Service `skyflo-ai-ui` on port 80.

---

## Troubleshooting

1. **Pods not running**  
   ```bash
   kubectl get pods -n skyflo-ai
   kubectl describe pod <pod-name> -n skyflo-ai
   ```
   Check events for scheduling, image pull, or crash reasons.

2. **ImagePullBackOff**  
   Ensure the cluster can pull the images (e.g. `skyfloaiagent/engine:<tag>`). For private registries, configure imagePullSecrets or cluster credentials.

3. **Engine or UI failing / connection errors**  
   - Check that Postgres and Redis are running and that `POSTGRES_DATABASE_URL` and `REDIS_URL` in engine-secrets match the postgres and redis services (e.g. `skyflo-ai-postgres:5432`, `skyflo-ai-redis:6379`).
   - Check engine logs: `kubectl logs deployment/skyflo-ai-engine -n skyflo-ai`.

4. **LLM errors (401, 503, etc.)**  
   - Confirm the API key in `config/secrets/engine-secrets.yaml` matches the provider for `LLM_MODEL`.
   - Ensure only one provider key is set (or the one you intend is correct) and that the key is not commented out or empty.

5. **Blank or invalid secrets**  
   Comment out any unused key in `engine-secrets.yaml` so Kubernetes does not create empty secret entries. Re-apply after editing: `kubectl apply -k deployment/kubernetes/`.

6. **Port-forward for local access**  
   ```bash
   kubectl port-forward -n skyflo-ai svc/skyflo-ai-ui 3000:80
   ```
   Then open `http://localhost:3000`.

---

## Uninstalling

To remove the deployment applied with Kustomize:

```bash
kubectl delete -k deployment/kubernetes/
```

To remove only the namespace and all resources in it:

```bash
kubectl delete namespace skyflo-ai
```

For the install-script flow, use the [uninstall script](install.md#uninstalling) from the docs.

---

## See also

- [Deployment overview](deployment.md)
- [Install guide (script, production, KinD)](install.md)
- [Discord community](https://discord.gg/kCFNavMund)

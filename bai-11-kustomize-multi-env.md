# Bài 11 — Multi-environment với Kustomize

## 🎯 Mục tiêu
- Cấu trúc repo GitOps theo pattern **base + overlays** chuẩn Kustomize.
- Có 3 môi trường (`dev`, `staging`, `prod`) với cấu hình khác nhau từ cùng 1 base.
- Mỗi env = 1 ArgoCD Application riêng, deploy vào namespace riêng.

## 📋 Vì sao Kustomize?
- Native trong `kubectl apply -k` và ArgoCD (không cần plugin).
- Không có template logic phức tạp như Helm — chỉ patch & merge.
- Phù hợp khi config khác nhau ít (image tag, replicas, env vars).

---

## 🛠️ Phần A — Cấu trúc repo

Trong repo `gitops-nginx`, tạo cấu trúc mới:
```
gitops-nginx/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── replicas-patch.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   └── replicas-patch.yaml
    └── prod/
        ├── kustomization.yaml
        └── replicas-patch.yaml
```

### Bước 1. Tạo `base/`
Di chuyển các file Deployment/Service/ConfigMap hiện có vào `base/`. Tạo `base/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app: nginx-demo
```

### Bước 2. Tạo overlay `dev`
File `overlays/dev/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: nginx-dev

resources:
  - ../../base

namePrefix: dev-

patches:
  - path: replicas-patch.yaml

images:
  - name: nginx
    newTag: "1.27"

commonLabels:
  env: dev
```

File `overlays/dev/replicas-patch.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
spec:
  replicas: 1
```

### Bước 3. Tạo overlay `staging`
`overlays/staging/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: nginx-staging
resources:
  - ../../base
namePrefix: stg-
patches:
  - path: replicas-patch.yaml
images:
  - name: nginx
    newTag: "1.27"
commonLabels:
  env: staging
```

`overlays/staging/replicas-patch.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
spec:
  replicas: 2
```

### Bước 4. Tạo overlay `prod`
Tương tự, namespace `nginx-prod`, `namePrefix: prod-`, `replicas: 5`, image tag có thể khác (`1.27-stable`).

### Bước 5. Test local
```powershell
kubectl kustomize overlays/dev
kubectl kustomize overlays/staging
kubectl kustomize overlays/prod
```
→ Xem manifest sinh ra cho từng env, verify khác biệt.

Commit & push.

---

## 🛠️ Phần B — Tạo 3 ArgoCD Application

File `app-nginx-dev.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ngoc25ms/gitops-nginx.git
    targetRevision: HEAD
    path: overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-dev
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

Tương tự `app-nginx-staging.yaml` và `app-nginx-prod.yaml` (đổi `name`, `path`, `namespace`).

> **Tip**: prod nên dùng manual sync. Bỏ block `automated` trong app-nginx-prod.yaml.

Apply cả 3:
```powershell
kubectl apply -f app-nginx-dev.yaml
kubectl apply -f app-nginx-staging.yaml
kubectl apply -f app-nginx-prod.yaml
```

### Verify
```powershell
argocd app list
kubectl get pods -n nginx-dev
kubectl get pods -n nginx-staging
kubectl get pods -n nginx-prod
```
→ Mỗi env có số replicas khác nhau theo overlay.

---

## ✅ Tiêu chí hoàn thành
- [ ] Cấu trúc repo `base/` + `overlays/{dev,staging,prod}` đúng chuẩn Kustomize.
- [ ] 3 Application trong ArgoCD, mỗi cái deploy vào 1 namespace riêng.
- [ ] `kubectl get deployment -n nginx-dev` thấy 1 replica, staging 2, prod 5.
- [ ] Sửa `base/` → cả 3 env cùng cập nhật. Sửa overlay → chỉ env đó cập nhật.

## 💡 Khái niệm rút ra
- **Promotion pattern**: PR cập nhật `overlays/dev` trước → test → cherry-pick sang staging → prod.
- `namePrefix` tránh xung đột tên khi 1 cluster chạy nhiều env.
- `images:` field của Kustomize là cách **chuẩn** để CI bot cập nhật tag (Bài 15, 16 sẽ dùng).
- **Đừng patch `metadata.name`** trong overlay — dùng `namePrefix`/`nameSuffix` thay vì sửa name trực tiếp.
- Có thể dùng `replicas:` field trong kustomization.yaml thay vì patch file riêng:
  ```yaml
  replicas:
    - name: nginx-demo
      count: 5
  ```

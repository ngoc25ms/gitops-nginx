# Bài 12 — Helm chart override theo env

## 🎯 Mục tiêu
- Convert nginx-demo sang **Helm chart**.
- Override values theo env qua ArgoCD `spec.source.helm.values` / `valueFiles`.
- So sánh Helm vs Kustomize: khi nào dùng cái nào.

## 📋 Vì sao Helm?
- Có **template logic** (`if/range/with`) — phù hợp khi config phức tạp.
- Hệ sinh thái chart sẵn (Bitnami, ArtifactHub) — không phải viết lại.
- Versioning & packaging — chart có version riêng, dễ release.

---

## 🛠️ Phần A — Tạo Helm chart

### Bước 1. Cấu trúc
Tạo nhánh mới hoặc folder mới trong repo `gitops-nginx`:
```
gitops-nginx/
└── chart/
    ├── Chart.yaml
    ├── values.yaml
    ├── values-dev.yaml
    ├── values-staging.yaml
    ├── values-prod.yaml
    └── templates/
        ├── deployment.yaml
        ├── service.yaml
        ├── configmap.yaml
        └── _helpers.tpl
```

### Bước 2. `chart/Chart.yaml`
```yaml
apiVersion: v2
name: nginx-demo
description: Nginx demo chart cho ArgoCD
type: application
version: 0.1.0
appVersion: "1.27"
```

### Bước 3. `chart/values.yaml` (mặc định)
```yaml
replicaCount: 1

image:
  repository: nginx
  tag: "1.27"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

content:
  message: "Hello from default values"

resources: {}
```

### Bước 4. `chart/templates/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "nginx-demo.fullname" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "nginx-demo.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "nginx-demo.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
      volumes:
        - name: html
          configMap:
            name: {{ include "nginx-demo.fullname" . }}
```

### Bước 5. `chart/templates/configmap.yaml`
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "nginx-demo.fullname" . }}
data:
  index.html: |
    <h1>{{ .Values.content.message }}</h1>
    <p>Env: {{ .Values.envName | default "default" }}</p>
```

### Bước 6. `chart/templates/service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "nginx-demo.fullname" . }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 80
  selector:
    {{- include "nginx-demo.selectorLabels" . | nindent 4 }}
```

### Bước 7. `chart/templates/_helpers.tpl`
```
{{- define "nginx-demo.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nginx-demo.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "nginx-demo.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
```

### Bước 8. Values theo env

`chart/values-dev.yaml`:
```yaml
envName: dev
replicaCount: 1
image:
  tag: "1.27"
content:
  message: "Hello from DEV"
```

`chart/values-staging.yaml`:
```yaml
envName: staging
replicaCount: 2
image:
  tag: "1.27"
content:
  message: "Hello from STAGING"
```

`chart/values-prod.yaml`:
```yaml
envName: prod
replicaCount: 5
image:
  tag: "1.27"
content:
  message: "Hello from PROD"
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

### Bước 9. Test local
```powershell
helm template demo chart/ -f chart/values-dev.yaml
helm template demo chart/ -f chart/values-prod.yaml
```

Commit & push.

---

## 🛠️ Phần B — Application với Helm

File `app-nginx-helm-dev.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-helm-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ngoc25ms/gitops-nginx.git
    targetRevision: HEAD
    path: chart
    helm:
      releaseName: nginx-dev
      valueFiles:
        - values-dev.yaml
      # Hoặc inline values:
      # values: |
      #   replicaCount: 1
      #   content:
      #     message: "Override inline"
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-helm-dev
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

Tương tự `app-nginx-helm-staging.yaml`, `app-nginx-helm-prod.yaml`.

Apply:
```powershell
kubectl apply -f app-nginx-helm-dev.yaml
kubectl apply -f app-nginx-helm-staging.yaml
kubectl apply -f app-nginx-helm-prod.yaml
```

### Verify
```powershell
kubectl port-forward -n nginx-helm-dev svc/nginx-dev-nginx-demo 9001:80
# mở http://localhost:9001 -> "Hello from DEV"
```

---

## 🛠️ Phần C — Override inline (không cần file)

```yaml
spec:
  source:
    helm:
      parameters:
        - name: replicaCount
          value: "3"
        - name: image.tag
          value: "1.28"
      values: |
        content:
          message: "Override hoan toan"
```

`parameters` (giống `--set`) override field đơn lẻ. `values` (giống `-f`) override block YAML.

---

## ✅ Tiêu chí hoàn thành
- [ ] 3 Application Helm chạy 3 env, message HTML khác nhau.
- [ ] `helm template` local sinh manifest đúng cho từng values.
- [ ] Hiểu khác biệt `valueFiles` vs `values` vs `parameters`.
- [ ] Prod có resource requests/limits khác dev.

## 💡 Khái niệm rút ra

### Helm vs Kustomize
| Tiêu chí | Helm | Kustomize |
|---|---|---|
| Template logic | ✅ if/range/with | ❌ chỉ patch |
| Learning curve | Cao hơn | Thấp |
| Re-use chart bên ngoài | ✅ ArtifactHub | ❌ |
| Debug | Khó (template lỗi khó đọc) | Dễ (`kubectl kustomize`) |
| ArgoCD support | ✅ Native | ✅ Native |
| Khi nào dùng | Chart có sẵn, config phức tạp | Config khác biệt nhỏ giữa env |

### Multi-source application (ArgoCD 2.6+)
Có thể trộn Helm chart từ public registry + values từ Git riêng:
```yaml
spec:
  sources:
    - repoURL: https://charts.bitnami.com/bitnami
      chart: nginx
      targetRevision: 15.0.0
      helm:
        valueFiles:
          - $values/charts/nginx/values-prod.yaml
    - repoURL: https://github.com/ngoc25ms/gitops-nginx.git
      targetRevision: HEAD
      ref: values
```
→ Pattern phổ biến: chart dùng chung, values riêng từng team.

### Cảnh báo
- Helm hooks (`helm.sh/hook`) → ArgoCD map sang sync phase. Đôi khi gây bất ngờ.
- `helm template` không validate CRD → nếu chart cần CRD, ArgoCD sync có thể fail lần đầu. Dùng `ServerSideApply=true` hoặc cài CRD trước.

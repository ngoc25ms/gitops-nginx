# Bài 13 — App-of-Apps Pattern

## 🎯 Mục tiêu
- Hiểu pattern **App-of-Apps**: 1 Application "root" tự sinh ra nhiều Application con.
- Quản lý hàng chục/trăm app bằng cách **commit 1 file**, không phải `kubectl apply` từng cái.
- Là tiền đề cho `ApplicationSet` (Bài 14).

## 📋 Vấn đề
Khi có 20+ app, bạn không muốn phải:
- Vào server chạy `kubectl apply -f` cho từng cái.
- Nhớ app nào đã apply, app nào chưa.
- Onboard người mới phải clone repo + chạy 20 lệnh.

→ **App-of-Apps**: tạo 1 Application "root" trỏ vào folder chứa các YAML Application khác. Khi sync root, ArgoCD tự tạo/cập nhật toàn bộ app con.

---

## 🛠️ Phần A — Tạo repo root

### Bước 1. Tạo repo `gitops-root` (hoặc folder riêng trong `gitops-nginx`)

Cấu trúc:
```
gitops-root/
└── apps/
    ├── nginx-dev.yaml
    ├── nginx-staging.yaml
    ├── nginx-prod.yaml
    ├── guestbook.yaml
    └── monitoring.yaml      # demo
```

Mỗi file là 1 ArgoCD Application (như đã học ở Bài 11).

### Bước 2. `apps/nginx-dev.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-dev
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
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

> `finalizers` quan trọng: khi xoá Application, ArgoCD sẽ xoá cả resource cluster (cascade delete).

Tương tự với staging, prod, guestbook, monitoring.

### Bước 3. Tạo Application **root**

File `app-root.yaml` (apply 1 lần duy nhất):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ngoc25ms/gitops-root.git
    targetRevision: HEAD
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```

Apply:
```powershell
kubectl apply -f app-root.yaml
```

---

## 🛠️ Phần B — Quan sát hành vi

### Bước 4. Verify
```powershell
argocd app list
```
→ Sẽ thấy `root` + tất cả app con (`nginx-dev`, `nginx-staging`, ...).

UI: card `root` chứa cây topology của các Application object. Click 1 app con để vào view chi tiết.

### Bước 5. Test thêm app mới
- Tạo file `apps/redis.yaml` cho 1 chart Redis.
- Commit & push.
- ArgoCD root tự sync → Application `redis` xuất hiện → Redis được deploy.

→ **Không cần chạy `kubectl apply`** — toàn bộ pipeline GitOps.

### Bước 6. Test xoá app
- Xoá `apps/monitoring.yaml`, push.
- Vì root có `prune: true` → Application `monitoring` bị xoá.
- Vì app con có `finalizers` → toàn bộ resource trên cluster bị xoá theo.

---

## 🛠️ Phần C — Cấu trúc nâng cao (multi-tier)

Có thể nest nhiều tầng:
```
root (level 0)
 ├── platform-apps (level 1)     <-- App-of-Apps con
 │   ├── ingress-nginx
 │   ├── cert-manager
 │   └── prometheus
 └── product-apps (level 1)
     ├── nginx-dev
     ├── nginx-staging
     └── nginx-prod
```

Pattern này tách team:
- **Platform team** quản `platform-apps/`.
- **Product team** quản `product-apps/`.
- Cả 2 cùng gắn vào `root` của SRE.

---

## ✅ Tiêu chí hoàn thành
- [ ] Có Application `root` quản ≥3 app con.
- [ ] Thêm file `.yaml` mới vào folder `apps/` → app con tự xuất hiện sau sync root.
- [ ] Xoá file → app con bị prune.
- [ ] UI hiển thị cây phân cấp root → children.

## 💡 Khái niệm rút ra
- **Bootstrap cluster** chỉ bằng 1 lệnh:
  ```powershell
  kubectl apply -f app-root.yaml
  ```
  → từ đó mọi thứ khác tự deploy. Đây là "GitOps day-0".
- App-of-Apps phù hợp khi danh sách app **ít thay đổi cấu trúc** (chủ yếu thêm/xoá file).
- Khi cần sinh app theo pattern (vd "1 app cho mỗi cluster", "1 app cho mỗi PR"), dùng **ApplicationSet** (Bài 14) thay vì viết tay từng file.
- **Tránh circular**: đừng để app `root` deploy chính `app-root.yaml` của nó (self-management) nếu chưa hiểu rõ — dễ gây vòng lặp sync khó debug.

### Pattern thật:
- Repo `infra-gitops` chứa root + platform-apps.
- Repo `<product>-gitops` chứa app product team.
- Bootstrap: chỉ apply 1 root Application thủ công, mọi thứ khác từ Git.

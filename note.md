### Login
```bash
argocd login port-forward `
  --port-forward `
  --port-forward-namespace argocd `
  --username admin `
  --password 'yPe1l6p0g4qA-daq' `
  --insecure `
  --grpc-web
  ```

### Get App
  ```bash
  argocd app list --port-forward --port-forward-namespace argocd
  ```
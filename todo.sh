k3d cluster create my-cluster --port 8888:30080

kubectl create namespace argocd
kubectl create namespace dev

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl apply -f p3/configs/application.yaml -n argocd

kubectl get pods -n dev

curl http://localhost:8888

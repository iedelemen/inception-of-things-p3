k3d cluster create my-cluster --port 8888:30080
	k3d cluster list
	docker ps
	kubectl cluster-info
	
kubectl create namespace argocd
kubectl create namespace dev
	kubectl get namespaces

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl get pods -n argocd -w
	kubectl get all -n argocd

kubectl apply -f p3/configs/application.yaml -n argocd
	kubectl get application -n argocd
	kubectl get pods -n dev
	kubectl get deployment,service -n dev

curl http://localhost:8888


kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443

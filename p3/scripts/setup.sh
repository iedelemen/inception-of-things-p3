#!/bin/bash

# Hata durumunda script'in hemen durmasını sağlar.
set -e
# Pipe içindeki herhangi bir komut hata verirse tüm satırı hatalı sayar.
set -o pipefail

# --- Renk Kodları ve Yardımcı Fonksiyonlar ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${YELLOW}[BİLGİ] $1${NC}"; }
success() { echo -e "${GREEN}[BAŞARILI] $1${NC}"; }
error() { echo -e "${RED}[HATA] $1${NC}"; exit 1; }

# --- Değişkenler ---
CLUSTER_NAME="my-cluster"
ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"
# Script ile aynı dizinde bulunan application.yaml dosyasını kullanacak şekilde ayarlandı.
APP_CONFIG_PATH="p3/configs/application.yaml"
# application.yaml içindeki metadata.name ile eşleşecek şekilde güncellendi.
ARGO_APP_NAME="playground-app-argo"

# --- Temizlik Fonksiyonu ---
cleanup() {
    info "Mevcut k3d cluster'ı siliniyor..."
    k3d cluster delete ${CLUSTER_NAME} --all || true
    success "Temizlik tamamlandı."
}

# Script'e --clean argümanı verilirse sadece temizlik yap ve çık
if [[ "$1" == "--clean" ]]; then
    cleanup
    exit 0
fi

# --- Ana Script ---
info "Kurulum süreci başlıyor..."

# 1. K3d Cluster'ını Oluştur
info "1. K3d cluster'ı oluşturuluyor: ${CLUSTER_NAME}"
# Service manifestindeki nodePort: 30080'i host'taki 8888 portuna yönlendirir.
if ! k3d cluster create ${CLUSTER_NAME} --port "8888:30080@loadbalancer"; then
    error "K3d cluster oluşturulamadı. Docker'ın çalıştığından ve k3d'nin kurulu olduğundan emin olun."
fi
success "K3d cluster'ı başarıyla oluşturuldu."
info "Cluster ile bağlantı kontrol ediliyor..."
kubectl cluster-info

# 2. Namespace'leri Oluştur
info "2. Namespace'ler oluşturuluyor: ${ARGOCD_NAMESPACE} ve ${DEV_NAMESPACE}"
kubectl create namespace ${ARGOCD_NAMESPACE} || true # Zaten varsa hata verme
kubectl create namespace ${DEV_NAMESPACE} || true   # Zaten varsa hata verme
success "Namespace'ler başarıyla oluşturuldu."

# 3. Argo CD'yi Kur ve Hazır Olmasını Bekle
info "3. Argo CD kuruluyor..."
kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Argo CD pod'larının hazır olması bekleniyor... (Bu işlem birkaç dakika sürebilir)"
if ! kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ${ARGOCD_NAMESPACE}; then
    error "Argo CD pod'ları zamanında hazır olmadı. 'kubectl get pods -n ${ARGOCD_NAMESPACE}' komutu ile durumu kontrol edin."
fi
success "Argo CD başarıyla kuruldu ve pod'lar hazır."

# 4. Argo CD Uygulamasını Tanımla
info "4. Argo CD'ye uygulama tanımı gönderiliyor..."
if [ ! -f "${APP_CONFIG_PATH}" ]; then
    error "Uygulama tanım dosyası bulunamadı: ${APP_CONFIG_PATH}"
fi
kubectl apply -f ${APP_CONFIG_PATH} -n ${ARGOCD_NAMESPACE}
success "Argo CD Application nesnesi oluşturuldu: ${ARGO_APP_NAME}"

# 5. AKILLI BEKLEME ADIMI
info "5. Argo CD'nin uygulamayı senkronize etmesi bekleniyor..."
TIMEOUT=300 # 5 dakika bekleme süresi
INTERVAL=10  # Her 10 saniyede bir kontrol et
ELAPSED=0

while true; do
    JSONPATH_SYNC='{.status.sync.status}'
    JSONPATH_HEALTH='{.status.health.status}'

    SYNC_STATUS=$(kubectl get application ${ARGO_APP_NAME} -n ${ARGOCD_NAMESPACE} -o jsonpath="${JSONPATH_SYNC}" 2>/dev/null || echo "NotFound")
    HEALTH_STATUS=$(kubectl get application ${ARGO_APP_NAME} -n ${ARGOCD_NAMESPACE} -o jsonpath="${JSONPATH_HEALTH}" 2>/dev/null || echo "NotFound")

    if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
        success "Argo CD uygulaması başarıyla senkronize oldu (Synced & Healthy)."
        break
    fi

    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        error "Zaman aşımı! Argo CD uygulaması 5 dakika içinde senkronize olamadı. Durum: Sync=${SYNC_STATUS}, Health=${HEALTH_STATUS}"
    fi

    echo -e "   - Bekleniyor... (Mevcut Durum: Sync=${SYNC_STATUS}, Health=${HEALTH_STATUS})"
    sleep ${INTERVAL}
    ELAPSED=$((ELAPSED + INTERVAL))
done

# 6. Son Durum Kontrolü ve Test
info "6. Son durum kontrol ediliyor..."
kubectl get pods,svc -n ${DEV_NAMESPACE}

info "Uygulamaya erişim test ediliyor (http://localhost:8888)..."
# Curl komutu, k3d port yönlendirmesi sayesinde çalışır.
RESPONSE=$(curl --fail --silent --show-error http://localhost:8888)
if [ $? -eq 0 ]; then
    success "Uygulamadan gelen yanıt: ${RESPONSE}"
else
    error "Uygulamaya erişilemedi. Servis veya port yönlendirme hatası olabilir."
fi

info "ArgoCD Arayüzü için: 'kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443' komutunu yeni bir terminalde çalıştırın"
info "Tarayıcınızda https://localhost:8080 adresine giderek ArgoCD arayüzüne erişebilirsiniz"
info "Kullanıcı adı: admin"
info "Argo CD Admin Şifresi: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
success "TÜM KURULUM BAŞARIYLA TAMAMLANDI!"

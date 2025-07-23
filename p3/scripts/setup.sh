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
APP_CONFIG_PATH="p3/confs/application.yaml" # ÖNEMLİ: Bu yolun doğru olduğundan emin olun!

# --- Ana Script ---
info "Kurulum süreci başlıyor..."

# 1. K3d Cluster'ını Oluştur
info "1. K3d cluster'ı oluşturuluyor: ${CLUSTER_NAME}"
if ! k3d cluster create ${CLUSTER_NAME} --port "8888:30080"; then
    error "K3d cluster oluşturulamadı. Docker'ın çalıştığından ve k3d'nin kurulu olduğundan emin olun."
fi
success "K3d cluster'ı başarıyla oluşturuldu."
info "Cluster ile bağlantı kontrol ediliyor..."
kubectl cluster-info

# 2. Namespace'leri Oluştur
info "2. Namespace'ler oluşturuluyor: ${ARGOCD_NAMESPACE} ve ${DEV_NAMESPACE}"
kubectl create namespace ${ARGOCD_NAMESPACE}
kubectl create namespace ${DEV_NAMESPACE}
success "Namespace'ler başarıyla oluşturuldu."

# 3. Argo CD'yi Kur ve Hazır Olmasını Bekle
info "3. Argo CD kuruluyor..."
kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Argo CD pod'larının hazır olması bekleniyor... (Bu işlem birkaç dakika sürebilir)"
# Argo CD sunucusunun Deployment'ı 'available' durumuna gelene kadar bekle.
if ! kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ${ARGOCD_NAMESPACE}; then
    error "Argo CD pod'ları zamanında hazır olmadı. 'kubectl get pods -n ${ARGOCD_NAMESPACE}' komutu ile durumu kontrol edin."
fi
success "Argo CD başarıyla kuruldu ve pod'lar hazır."

# 4. Argo CD Uygulamasını Tanımla ve Senkronizasyonu Bekle
info "4. Argo CD'ye uygulama tanımı gönderiliyor..."
if [ ! -f "${APP_CONFIG_PATH}" ]; then
    error "Uygulama tanım dosyası bulunamadı: ${APP_CONFIG_PATH}"
fi
kubectl apply -f ${APP_CONFIG_PATH} -n ${ARGOCD_NAMESPACE}

info "Argo CD'nin uygulamayı senkronize etmesi ve pod'u başlatması bekleniyor..."
# Argo CD'nin oluşturacağı 'playground-app' Deployment'ı 'available' durumuna gelene kadar bekle.
if ! kubectl wait --for=condition=available --timeout=180s deployment/playground-app -n ${DEV_NAMESPACE}; then
    error "Uygulama pod'u zamanında hazır olmadı. 'kubectl get pods -n ${DEV_NAMESPACE}' komutu ile durumu kontrol edin."
fi
success "Uygulama başarıyla senkronize edildi ve pod çalışıyor."

# 5. Son Durum Kontrolü ve Test
info "5. Son durum kontrol ediliyor..."
kubectl get pods -n ${DEV_NAMESPACE}

info "Uygulamaya erişim test ediliyor (http://localhost:8888)..."
# --fail: HTTP durum kodu 2xx değilse hata verir ve script durur.
# --silent: İlerleme çubuğunu gizler.
# --show-error: Hata durumunda mesajı gösterir.
RESPONSE=$(curl --fail --silent --show-error http://localhost:8888)
if [ $? -eq 0 ]; then
    success "Uygulamadan gelen yanıt: ${RESPONSE}"
else
    error "Uygulamaya erişilemedi. Servis veya port yönlendirme hatası olabilir."
fi

echo ""
success "TÜM KURULUM BAŞARIYLA TAMAMLANDI!"

```

### Script Nasıl Çalıştırılır?

1.  Yukarıdaki kodu `setup.sh` adında bir dosyaya kaydedin.
2.  Dosyaya çalıştırma izni verin:
    ````bash
    chmod +x setup.sh
    ````
3.  Script'i çalıştırın:
    ````bash
    ./setup.sh
    ````

---

### Script'in Teknik Detayları ve Kontrol Mekanizmaları

Bu script'in neden daha "kontrollü" ve güvenilir olduğunu adım adım açıklayalım:

1.  **`set -e` ve `set -o pipefail`**:
    *   **Ne Yapar?**: Script'in en başına eklenen bu satırlar, herhangi bir komutun başarısız olması (sıfırdan farklı bir çıkış kodu döndürmesi) durumunda script'in çalışmasını **anında durdurur**. Bu, bir adım başarısız olduğunda sonraki adımların hatalı bir temel üzerine devam etmesini engeller.

2.  **`k3d cluster create` Kontrolü**:
    *   **Nasıl Kontrol Ediyor?**: Komut bir `if` bloğu içine alınmıştır. Eğer `k3d` komutu herhangi bir sebepten (Docker çalışmıyor, yetki yok vb.) başarısız olursa, `error` fonksiyonu çağrılır, kullanıcıya anlamlı bir hata mesajı gösterilir ve script durur.

3.  **`kubectl wait` (En Önemli Kontrol Mekanizması)**:
    *   **Sorun Ne?**: `kubectl apply` komutu asenkrondur. Komutu çalıştırdığınızda, Kubernetes'e "bu kaynakları oluştur" talebini gönderirsiniz, ancak komut hemen geri döner. Pod'ların imajları indirmesi, başlaması ve `Running` durumuna gelmesi zaman alır.
    *   **Kötü Çözüm**: `sleep 60` gibi bir komutla beklemek. Bu güvenilmezdir çünkü sistemin yüküne göre bu süre yetersiz kalabilir veya gereksiz yere uzun olabilir.
    *   **Doğru Çözüm (`kubectl wait`)**: Bu komut, Kubernetes API'sini sürekli sorgulayarak belirli bir kaynağın istenen duruma gelmesini bekler.
        *   `--for=condition=available`: Bir `Deployment` kaynağının `Available` (Mevcut) koşulunun `true` olmasını bekler. Bu, Deployment'ın yönettiği Pod sayısının istenen sayıya ulaştığı ve hepsinin `Ready` (Hazır) olduğu anlamına gelir.
        *   `--timeout=300s`: Eğer kaynak 300 saniye (5 dakika) içinde istenen duruma gelmezse, komutu başarısız sayar ve script'i durdurur. Bu, sonsuza kadar takılıp kalmayı önler.
    *   **Uygulama**: Script, önce Argo CD'nin kendi sunucusunun (`deployment/argocd-server`) hazır olmasını, ardından Argo CD'nin kurduğu bizim uygulamamızın (`deployment/playground-app`) hazır olmasını bu komutla bekler.

4.  **`curl` ile Nihai Test**:
    *   **Nasıl Kontrol Ediyor?**: `curl` komutu `--fail` parametresi ile çalıştırılır. Eğer sunucudan gelen HTTP yanıt kodu 4xx (örn: 404 Not Found) veya 5xx (örn: 502 Bad Gateway) ise, `curl` komutu başarısız olur. `set -e` sayesinde bu durum script'i durdurur ve size anlamlı bir hata mesajı gösterir. Bu, sadece bir yanıt alıp almadığınızı değil, **başarılı bir yanıt** (`200 OK`) alıp almadığınızı kontrol eder.

Bu yapı, otomasyon scriptleri için en iyi pratikleri kullanarak size hem hızlı hem de son derece güvenilir bir kurulum süreci sunar.

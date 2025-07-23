### Part 3

**Amaç:** Boş bir Docker ortamından başlayarak, GitOps prensiplerine uygun, tam otomatik bir uygulama dağıtım sistemi kurmak.

---

#### 3.1. Cluster'ı Oluştur

**Komut:**
````bash
k3d cluster create my-cluster --port 8888:30080
````

**Bu Komut Ne Yapar?**
Bu komut, `k3d` aracını kullanarak, Docker konteynerları içinde çalışan tam teşekküllü bir Kubernetes cluster'ı oluşturur ve bu cluster'a dışarıdan erişim için bir ağ kuralı tanımlar.

**Teknik Kavramlar ve Süreçler:**
1.  **`k3d`**: K3s'i Docker'da çalıştırmak için tasarlanmış bir yardımcı programdır.
2.  **`K3s`**: CNCF (Cloud Native Computing Foundation) tarafından onaylanmış, hafifletilmiş bir Kubernetes dağıtımıdır. Kaynak tüketimini azaltmak için bazı eski ve nadir kullanılan özellikler çıkarılmış ve veri deposu olarak `etcd` yerine `sqlite` gibi daha basit seçenekler sunulmuştur. Bu, geliştirme ortamları için idealdir.
3.  **`--port 8888:30080`**: Bu bir **port yönlendirme (port mapping)** kuralıdır.
    *   **`8888` (Host Port)**: Bu, komutu çalıştırdığınız ana makinenin (sizin `osboxes` sanal makinenizin) portudur. Dış dünyadan gelen istekler bu porta yapılır.
    *   **`30080` (Container/Node Port)**: Bu, Kubernetes cluster'ı içindeki düğümlerin (Node) üzerinde açılacak olan porttur. Bu port, daha sonra oluşturacağınız `Service` nesnesinde `NodePort` olarak tanımlanacaktır.
    *   **İşleyişi**: Bu kural, Docker'a şunu söyler: "Ana makinenin `8888` portuna gelen herhangi bir TCP bağlantısını, `k3d` tarafından oluşturulan yük dengeleyici (load balancer) konteynerine ilet. Yük dengeleyici de bu trafiği cluster içindeki bir düğümün `30080` portuna yönlendirsin."

**Arka Planda Gerçekleşenler:**
*   `k3d`, `k3d-my-cluster` adında izole bir Docker ağı oluşturur.
*   Bu ağ içinde iki temel Docker konteyneri başlatır:
    1.  `k3d-my-cluster-server-0`: Bu konteyner, K3s sunucusunu çalıştırır. Kubernetes **Kontrol Düzlemi (Control Plane)** bileşenleri (API Server, Scheduler, Controller Manager) burada yaşar.
    2.  `k3d-my-cluster-serverlb`: Bu bir yük dengeleyicidir. `--port` kuralı ile gelen trafiği karşılayan ve onu sunucu düğümüne ileten bir Nginx proxy konteyneridir.
*   `k3d`, yerel makinenizdeki `~/.kube/config` dosyasını otomatik olarak günceller. Bu sayede `kubectl` komutu, yeni oluşturulan bu cluster ile nasıl konuşacağını bilir.

**Doğrulama Komutları:**
*   Cluster'ın `k3d` tarafından tanınıp tanınmadığını kontrol edin:
    ````bash
    k3d cluster list
    ````
    Çıktıda `my-cluster` adında bir cluster görmelisiniz.
*   Çalışan Docker konteynerlarını listeleyin:
    ````bash
    docker ps
    ````
    Çıktıda `k3d-my-cluster-server-0` ve `k3d-my-cluster-serverlb` isimli iki konteyner görmelisiniz.
*   `kubectl`'in cluster ile iletişim kurabildiğini doğrulayın:
    ````bash
    kubectl cluster-info
    ````
    Bu komut, Kubernetes kontrol düzleminin ve CoreDNS'in çalıştığı adresleri göstermelidir.

---

#### 3.2. Namespace'leri Oluştur

**Komutlar:**
````bash
kubectl create namespace argocd
kubectl create namespace dev
````

**Bu Komutlar Ne Yapar?**
Bu komutlar, Kubernetes cluster'ı içinde iki adet mantıksal izolasyon alanı oluşturur.

**Teknik Kavramlar ve Süreçler:**
1.  **`kubectl`**: Kubernetes **API Sunucusu (API Server)** ile iletişim kurmak için kullanılan standart komut satırı aracıdır. Her `kubectl` komutu, API Sunucusuna gönderilen bir HTTP isteğine dönüşür.
2.  **`Namespace`**: Tek bir fiziksel cluster'ı birden çok sanal cluster'a bölmek için kullanılan bir mekanizmadır. Kaynaklar (Pod, Service, Deployment vb.) bir namespace içinde yaşar. Bu, şu faydaları sağlar:
    *   **İsim Çakışmasını Önleme**: `app` adında bir Deployment hem `dev` hem de `production` namespace'inde aynı anda bulunabilir.
    *   **Erişim Kontrolü**: Kullanıcılara veya servislere sadece belirli namespace'ler üzerinde yetki verilebilir (RBAC - Role-Based Access Control).
    *   **Kaynak Kotası**: Her namespace için CPU, hafıza gibi kaynak kullanım limitleri belirlenebilir.
3.  **`argocd` Namespace**: Argo CD sisteminin kendi bileşenlerini barındırmak için kullanılır.
4.  **`dev` Namespace**: Argo CD tarafından yönetilecek olan sizin uygulamanızın kaynaklarını barındırmak için kullanılır.

**Arka Planda Gerçekleşenler:**
*   `kubectl`, API Sunucusuna `argocd` ve `dev` adında iki yeni `Namespace` nesnesi oluşturmak için birer API isteği (POST `/api/v1/namespaces`) gönderir.
*   API Sunucusu bu istekleri doğrular ve yeni nesneleri cluster'ın veri deposuna (K3s'te varsayılan olarak SQLite) kaydeder.

**Doğrulama Komutu:**
*   Cluster'daki tüm namespace'leri listeleyin:
    ````bash
    kubectl get namespaces
    # Kısaltılmış hali: kubectl get ns
    ````
    Çıktıda, varsayılanların yanı sıra `argocd` ve `dev` isimli namespace'leri `Active` durumuyla görmelisiniz.

---

#### 3.3. Argo CD'yi Kur

**Komut:**
````bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
````

**Bu Komut Ne Yapar?**
Bu komut, Argo CD uygulamasını ve onun çalışması için gereken tüm Kubernetes kaynaklarını, `argocd` namespace'i içine kurar.

**Teknik Kavramlar ve Süreçler:**
1.  **`kubectl apply -f [dosya/url]`**: Bu, Kubernetes'te **bildirimsel yapılandırmanın (declarative configuration)** temel komutudur. Belirtilen dosyadaki kaynak tanımlarını okur ve cluster'ın mevcut durumunu bu tanımlara uygun hale getirir. Kaynak yoksa oluşturur, varsa günceller.
2.  **`-n argocd`**: Bu flag, komuta `install.yaml` dosyasındaki tüm kaynakları `argocd` namespace'i içinde oluşturmasını söyler.
3.  **`install.yaml` Dosyasının İçeriği**: Bu dosya, Argo CD'yi oluşturan bir dizi Kubernetes nesne tanımı içerir:
    *   **`Deployment`**: Argo CD'nin sunucusu, denetleyicisi, repo sunucusu gibi farklı mikroservislerini çalıştıran Pod'ları yönetir.
    *   **`Service`**: Argo CD'nin iç servislerinin birbirleriyle iletişim kurmasını sağlar.
    *   **`CustomResourceDefinition (CRD)`**: Bu çok önemlidir. Kubernetes API'sini genişleterek ona yeni kaynak türleri öğretir. Bu kurulum, Kubernetes'e `Application`, `AppProject` gibi Argo CD'ye özgü yeni nesne türlerinin ne anlama geldiğini öğretir. Bu sayede bir sonraki adımda `Application` türünde bir nesne oluşturabileceğiz.

**Arka Planda Gerçekleşenler:**
*   `kubectl`, URL'den `install.yaml` dosyasını indirir.
*   Dosya içindeki her bir kaynak tanımı için API Sunucusuna bir `apply` isteği gönderir.
*   Kubernetes **Denetleyici Yöneticisi (Controller Manager)**, bu yeni `Deployment` nesnelerini görür ve ilgili Pod'ları oluşturmak için harekete geçer. Pod'lar zamanlanır, imajlar çekilir ve konteynerlar başlatılır.

**Doğrulama Komutları:**
*   Argo CD pod'larının durumunu kontrol edin. `-w` (watch) flag'i, durum değişikliklerini canlı olarak izlemenizi sağlar:
    ````bash
    kubectl get pods -n argocd -w
    ````
    Tüm pod'ların durumu `Running` olana kadar bekleyin. (Çıkmak için `Ctrl+C`).
*   `argocd` namespace'indeki tüm kaynakları listeleyin:
    ````bash
    kubectl get all -n argocd
    ````

---

#### 3.4. Argo CD Uygulamasını Tanımla

**Komut:**
````bash
kubectl apply -f p3/confs/application.yaml -n argocd
````

**Bu Komut Ne Yapar?**
Bu komut, Argo CD'ye bir görev atar. Bu görev, belirli bir Git deposunu izlemesi ve o depodaki Kubernetes manifestlerini hedef bir namespace'e senkronize etmesidir.

**Teknik Kavramlar ve Süreçler:**
1.  **`application.yaml`**: Bu, bir önceki adımda CRD ile Kubernetes'e öğrettiğimiz `Application` türünde bir nesne tanımlar. Bu nesne, GitOps akışının yapılandırmasıdır.
    *   `spec.source`: İzlenecek Git deposunun (`repoURL`) ve klasörünün (`path`) bilgisini içerir.
    *   `spec.destination`: Manifestlerin uygulanacağı cluster (`server`) ve namespace (`namespace: dev`) bilgisini içerir.
    *   `spec.syncPolicy.automated`: Bu politika, Argo CD'ye Git'te bir değişiklik tespit ettiğinde, bu değişikliği otomatik olarak cluster'a uygulamasını söyler.

**Arka Planda Gerçekleşenler (GitOps Döngüsü Başlıyor):**
1.  `kubectl`, `application.yaml` dosyasını okur ve `argocd` namespace'inde bir `Application` nesnesi oluşturmak için API Sunucusuna istek gönderir.
2.  `argocd` namespace'inde çalışan **Argo CD Application Controller** pod'u, yeni bir `Application` nesnesinin oluşturulduğunu fark eder.
3.  Controller, bu nesnenin `spec` bölümünü okur ve Git deposu bilgilerini **Argo CD Repo Server** pod'una iletir.
4.  Repo Server, GitHub deponuzu klonlar, `p3/confs` dizinine gider ve içindeki `deployment.yaml` ve `service.yaml` dosyalarını okur.
5.  Application Controller, Repo Server'dan gelen bu "istenen durum" ile `dev` namespace'inin "mevcut durumunu" (şu anda boş) karşılaştırır. Bir uyumsuzluk (`OutOfSync`) tespit eder.
6.  `automated` senkronizasyon politikası aktif olduğu için, Controller bu manifestleri alıp `dev` namespace'ine uygular. Bu, arka planda `kubectl apply -n dev ...` komutunu çalıştırmakla eşdeğerdir.
7.  Sonuç olarak, `dev` namespace'inde `playground-app` Deployment'ı ve `playground-service` Service'i oluşturulur.

**Doğrulama Komutları:**
*   Argo CD'nin uygulamayı nasıl gördüğünü kontrol edin:
    ````bash
    kubectl get application -n argocd
    ````
    Çıktıda `playground-app-argo` uygulamasının `SYNC STATUS`'unun `Synced`, `HEALTH STATUS`'unun ise `Healthy` olduğunu görmelisiniz.
*   Uygulamanızın pod'unun `dev` namespace'inde çalışıp çalışmadığını kontrol edin:
    ````bash
    kubectl get pods -n dev
    ````
*   Uygulamanızın Deployment ve Service'ini kontrol edin:
    ````bash
    kubectl get deployment,service -n dev
    ````
*   **Nihai Test:** Uygulamanıza, en başta oluşturduğunuz port yönlendirme kuralı üzerinden erişin:
    ````bash
    curl http://localhost:8888
    ````
    Çıktıda `{"status":"ok", "message": "v1"}` görmelisiniz. Bu, tüm sistemin uçtan uca doğru çalıştığını kanıtlar.

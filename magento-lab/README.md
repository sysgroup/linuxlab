# Magento Open Source 2.4.9 — testowa VM na Ubuntu 26.04

To samodzielny playbook Ansible dla świeżej, dedykowanej VM testowej. Instaluje
Magento Open Source z publicznego GitHuba, PHP-FPM, nginx, MySQL, OpenSearch,
Composer i cron. Nie tworzy VM ani nie jest wzorcem konfiguracji produkcyjnej.

> Snapshot wersji: **2026-09-24**. Każda liczba niżej opisuje stan sprawdzony
> tego dnia, a nie trwałe znaczenie słowa „latest”. Przed kolejnym wdrożeniem
> porównaj docelowe wydanie z aktualną macierzą Adobe i zaktualizuj kod oraz
> tę tabelę razem.

## Wersje i zgodność

Adobe dla on-premises Magento/Adobe Commerce 2.4.9 testuje Composer 2.10,
OpenSearch 3, MySQL 8.4, PHP 8.5 oraz nginx 1.30. To szeregi zgodności,
natomiast playbook przypina wydania pobierane poza APT i zapisuje faktycznie
zainstalowane wersje w `/etc/magento-lab/versions.txt`.

| Komponent | Konkretna wersja testowanej VM | Stan źródła na 2026-09-24 |
| --- | --- | --- |
| Magento Open Source | `2.4.9`, tag GitHub na commicie `755e34dd689021c5165db9d35ecff74f7dc51527` | `2.4.9` było wydaniem oznaczonym przez GitHub jako Latest. |
| Ubuntu | `26.04 LTS` | Bieżący obraz Ubuntu Server: `26.04.1 LTS`; playbook wymaga dokładnie serii `26.04` x86-64. |
| PHP | runtime `8.5.4`, pakiet `8.5.4-0ubuntu1.3` | Najnowszy opublikowany patch serii PHP 8.5: `8.5.10`; nie jest to to samo co pakiet Ubuntu użyty w VM. |
| MySQL | runtime/pakiet `8.4.11-0ubuntu0.26.04.1` | Magento wymaga szeregu MySQL `8.4`; upstream opublikował `8.4.12`, co nie jest deklaracją wersji pakietu Ubuntu. |
| OpenSearch | `3.8.0`, SHA-512 przypięte w playbooku | `3.8.0` było najnowszym wpisem w oficjalnej historii wydań. |
| Composer | `2.10.3`, SHA-256 `7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6` | `2.10.3` było aktualnym stabilnym wydaniem. |
| nginx | runtime `1.30.5`, pakiet `1.30.5-1~resolute` | stable: `1.30.5`; równolegle mainline: `1.31.6`. Playbook sprawdza serię `1.30`. |
| Kontroler Ansible | Ansible Core `2.21.3` | Wersja użyta do syntax check, lint i testu integracyjnego; [Ansible Core `2.21.4`](https://github.com/ansible/ansible/releases/tag/v2.21.4) było wydaniem Latest producenta. |

Źródła: [macierz Adobe 2.4.9](https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/system-requirements),
[release Magento 2.4.9](https://github.com/magento/magento2/releases/tag/2.4.9),
[PHP releases](https://www.php.net/releases/),
[pakiet PHP Ubuntu 26.04](https://packages.ubuntu.com/resolute/php8.5-cli),
[pakiet MySQL Ubuntu 26.04](https://packages.ubuntu.com/resolute/mysql-server),
[MySQL 8.4.12](https://dev.mysql.com/doc/relnotes/mysql/8.4/en/news-8-4-12.html),
[historia OpenSearch](https://docs.opensearch.org/latest/version-history/),
[Composer 2.10.3](https://github.com/composer/composer/releases/tag/2.10.3),
[nginx downloads](https://nginx.org/en/download.html),
[pakiet nginx dla Ubuntu](https://nginx.org/packages/ubuntu/pool/nginx/n/nginx/) i
[Ubuntu Server](https://ubuntu.com/download/server),
[Ansible Core 2.21.4](https://github.com/ansible/ansible/releases/tag/v2.21.4).

Na 2026-09-24 OpenSearch wymienia w swojej tabeli testowanych systemów Ubuntu
`24.04`, nie `26.04`. Ten zestaw działał funkcjonalnie na osobnej VM Ubuntu
26.04, ale nie należy przedstawiać tego jako certyfikowanej pary producenta.
Zobacz [compatible operating systems](https://docs.opensearch.org/latest/install-and-configure/os-comp/).

## Zakres i wymagania

- Świeża, dedykowana VM Ubuntu 26.04 x86-64. Playbook usuwa domyślny vhost
  nginx i ustawia `default_server`, więc nie wolno stosować go na hoście
  współdzielonym.
- Przetestowany rozmiar VM: 4 vCPU, 16 GiB RAM i 80 GiB dysku. OpenSearch ma
  heap 2 GiB, a PHP `memory_limit=3G`.
- Konto SSH z `sudo` oraz Python 3 na VM. Kontroler wymaga Ansible Core i
  dostępu HTTPS do GitHub, Composer, OpenSearch i `nginx.org`.
- Ustal DNS albo wpis `/etc/hosts` dla `magento_server_name` **przed pierwszym
  uruchomieniem**. Magento zapisuje `magento_base_url` w bazie; zmiana później
  jest świadomą migracją konfiguracji, a nie zadaniem tego playbooka.
- VM musi być izolowana. MySQL i OpenSearch słuchają tylko na loopbackie;
  portu `9200` nie wolno publikować ani tunelować do sieci niezaufanej.

Celowo nie ma Varnisha, Valkeya, RabbitMQ/ActiveMQ ani sample data. To mała
VM do testów zgodności, nie test wydajności ani architektura sklepu
produkcyjnego.

## Uruchomienie

```bash
git clone https://github.com/sysgroup/linuxlab.git
cd linuxlab/magento-lab

cp inventory/local.example.yml inventory/local.yml
# Ustaw ansible_host, ansible_user, magento_server_name i magento_base_url.

ansible-inventory -i inventory/local.yml --graph
ansible-playbook -i inventory/local.yml magento-lab.yml --syntax-check
ansible-playbook -i inventory/local.yml magento-lab.yml
```

Jeżeli grupa ma inną nazwę, użyj `-e target_hosts=nazwa_grupy`. Prywatne
inventory jest ignorowane przez Git; kontrola klucza hosta SSH pozostaje
włączona.

Po udanym pierwszym przebiegu VM przechowuje hasła tylko dla roota:

```bash
sudo cat /etc/magento-lab/secrets/administrator-password
sudo cat /etc/magento-lab/versions.txt
sudo -u magento /srv/magento/bin/magento setup:db:status
sudo -u magento /srv/magento/bin/magento config:show catalog/search/engine
curl -i -H 'Host: magento-lab.example.test' http://127.0.0.1/
```

Drugi przebieg ma być konwergencją. Playbook sprawdza tag i rozwinięty commit
Magento, wersję OpenSearch, serie PHP/MySQL/nginx/Composer, schemat bazy,
konfigurację `opensearch` oraz odpowiedź HTTP 200. Odmawia nadpisania
niepustego katalogu niebędącego checkoutem Git, częściowo wypełnionej bazy
bez `env.php` i utraconego hasła bazy zainstalowanego sklepu.

### Zapis testu

24 września 2026 r. publiczny playbook wykonano na opisanej VM z Ansible Core
`2.21.3`: pełna konwergencja zakończyła się `ok=70 changed=12 failed=0`, a
natychmiastowy drugi przebieg `ok=70 changed=0 failed=0`. Test sprawdził
wersje z tabeli, aktywność `nginx`, `php8.5-fpm`, `mysql`, `opensearch` i
`cron`, loopback dla MySQL/OpenSearch, `setup:db:status`, ustawienie
`catalog/search/engine=opensearch` oraz HTTP 200. Źródło Magento i pierwsza
instalacja VM były uprzednio wykonane tą samą publiczną ścieżką GitHub/tag/
lockfile; ten test nie kasował działającego sklepu tylko po to, by powtórzyć
`setup:install`.

## Magento z GitHub bez kluczy Marketplace

Dokładnie dla publicznego taga Magento Open Source `2.4.9` playbook wykonuje
shallow clone `magento/magento2`, weryfikuje commit i uruchamia:

```bash
composer install --no-dev --no-interaction --no-progress \
  --prefer-source --optimize-autoloader
```

Z dołączonego do taga `composer.lock` instalowane są przypięte zależności,
bez `composer update`. Ta ścieżka nie używa `repo.magento.com`, `auth.json`,
`COMPOSER_AUTH` ani kluczy Adobe Marketplace. Jest inna niż standardowe
`composer create-project --repository-url=https://repo.magento.com/`, które
wymaga poświadczeń Marketplace. Publiczny checkout jest świadomym wyborem dla
tej izolowanej VM testowej, nie uniwersalną receptą dla produkcji lub pakietów
dostępnych wyłącznie przez Adobe.

Porównaj [instrukcję klonowania repozytorium Magento](https://developer.adobe.com/commerce/contributor/guides/install/clone-repository),
[lockfile taga 2.4.9](https://raw.githubusercontent.com/magento/magento2/2.4.9/composer.lock)
i [instalację przez Composer](https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/composer).

## Decyzje bezpieczeństwa

- OpenSearch `3.8.0` ma `plugins.security.disabled: true` wyłącznie dlatego,
  że API wiąże się z `127.0.0.1` w izolowanej VM. Dla środowiska sieciowego
  użyj TLS, uwierzytelniania i dokumentacji
  [OpenSearch Security](https://docs.opensearch.org/latest/security/configuration/disable-enable-security/).
- MySQL wiąże klasyczny oraz X Protocol z loopbackiem. Ustawienie
  `log_bin_trust_function_creators=1` pozwala lokalnemu kontu Magento utworzyć
  triggery podczas `setup:install`, bez nadawania mu `SUPER`. Nie przenoś tej
  decyzji bez analizy do bazy produkcyjnej lub replikowanej.
- Vhost korzysta z dostarczonego przez Magento `nginx.conf.sample`, a nie z
  ręcznie napisanego bloku `location ~ \\.php$`. Dzięki temu zachowuje routing
  front controllera i reguły ochrony Magento. Zobacz
  [konfigurację nginx](https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/prerequisites/web-server/nginx).

## Aktualizacja snapshotu

1. Sprawdź oficjalną macierz dokładnie dla docelowego wydania Magento.
2. Zaktualizuj tag, rozwinięty commit, wersję oraz sumę Composer/OpenSearch w
   jednym commicie.
3. Odtwórz lub sklonuj VM testową; nie wykonuj automatycznie `composer update`.
4. Uruchom pełny playbook, odczytaj `versions.txt` i wpisz rzeczywiste wersje
   oraz nową datę snapshotu do README i artykułu.

## Licencja

Apache License 2.0, zgodnie z [LICENSE](../LICENSE).

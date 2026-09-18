# Pomiar poboru mocy maszyn (`scripts/power-probe.py`)

Skrypt wykrywa i odczytuje wszystkie dostępne w Linuksie źródła pomiaru mocy,
podając przy każdym **zakres pomiaru** - bo to, czy liczba oznacza cały serwer,
czy sam procesor, decyduje o jej wartości.

```bash
# lokalnie
sudo scripts/power-probe.py -i 10

# na zdalnym hoście, bez kopiowania pliku na dysk
ssh <host> "sudo python3 - -i 10" < scripts/power-probe.py

# do monitoringu: jedna linia JSON na pomiar
sudo ./scripts/power-probe.py -i 60 -n 0 --json
```

Skrypt nie ma zewnętrznych zależności (biblioteka standardowa, Python 3.7+),
niczego nie zapisuje i nie zmienia stanu maszyny. Liczniki RAPL i IPMI wymagają
roota.

## Kolejność źródeł

| Źródło | Zakres | Uwagi |
| --- | --- | --- |
| IPMI: czujnik zasilacza (`PS1 Power In`, `PSU1 Input Power`) | cały serwer, z wejścia zasilacza | jedyne źródło mierzące CAŁĄ maszynę |
| IPMI: DCMI `power reading` | cały serwer | wiele płyt zgłasza `deactivated` i zwraca 0 W |
| hwmon `power*_input` / `power*_average` | zależnie od układu (np. `acpi_power_meter`) | baterie pomijamy, liczy je osobne źródło |
| RAPL `psys` | platforma (CPU, pamięć, przetwornice) | laptopy i część desktopów; NIE cały sprzęt |
| RAPL `package-*`, `dram`, `core`, `uncore` | procesor i pamięć | na serwerach zwykle jedyne źródło; dolna granica |
| Bateria (`power_now`) | cała płyta | tylko przy rozładowaniu; na zasilaczu zwraca 0 |

## Co mają nasze maszyny (sprawdzone 2026-09-18)

Przegląd ośmiu maszyn: siedmiu serwerów i jednego laptopa pracującego jako host
maszyn wirtualnych. Nazwy hostów pominięto, liczy się sprzęt.

| Sprzęt | Pomiar całej maszyny | Odczyty (okno 10 s) |
| --- | --- | --- |
| Dell PowerEdge R440, Xeon Silver 4208 | **tak** - czujnik `Pwr Consumption` oraz DCMI | 63 W (czujnik) i 69 W (DCMI); RAPL pakiet 10,8 W, pamięć 1,0 W |
| Płyta Intel S1200BTL, Xeon E3-1220 | **tak** - czujnik `PS1 Power In` | 64-84 W cały serwer; RAPL pakiet 7,0 W |
| Supermicro, Xeon D-1521 (dwie sztuki) | nie | RAPL pakiet 10,3-19,1 W, pamięć 4,8-9,5 W |
| Supermicro, Xeon D-2123IT | nie | RAPL pakiet 30,8 W, pamięć 2,8 W |
| AsRock Rack B550D4U, Ryzen 9 5900X | nie | RAPL pakiet 98,3 W (host obciążony), rdzenie 4,3 W |
| AsRock Rack B650D4U, Ryzen 9 9950X | nie | RAPL pakiet 56,2 W, rdzenie 2,0 W |
| ThinkPad T490 (laptop jako host KVM) | pośrednio | RAPL `psys` 2,6-3,0 W; bateria w trybie rozładowania |

Na maszynach AMD jądro wystawia liczniki pod tą samą nazwą `intel-rapl`, ale
znaczenie domen jest inne: `package-0` obejmuje całe gniazdo (razem
z kontrolerem pamięci i wejściem-wyjściem), a `core` tylko rdzenie - stąd duża
różnica między tymi dwiema liczbami. Zakres przewinięcia licznika też jest inny
(65,5 kJ wobec 262 kJ na Intelu), czyli przy 100 W przewija się co ok. 11 minut;
skrypt to obsługuje.

Wniosek: pobór całego serwera widać tylko tam, gdzie zasilacz jest
oprzyrządowany i kontroler zarządzający wystawia go jako czujnik - w tej próbce
na Dellu (iDRAC) i na płycie Intela. Na żadnym Supermicro z Xeonem D ani na
płytach AsRock Rack z Ryzenem takiego czujnika nie było. Supermicro ma DCMI,
ale zgłasza `Power reading state is: deactivated` i zwraca 0 W; płyty AsRock
Rack zwracają przez DCMI zero. Można spróbować `ipmitool dcmi power activate`,
ale to zapis do kontrolera zarządzającego - na produkcji tylko w oknie
serwisowym.

Gdzie nie ma czujnika, zostają dwie drogi: licznik na gniazdku (mierzy też
straty zasilacza) albo RAPL jako dolna granica. Sam procesor z pamięcią to na
serwerze z Xeonem D-1521 około 24 W, a realny pobór jest wyraźnie wyższy:
wentylatory, dyski, płyta i straty zasilacza są poza licznikiem.

## Pułapka: btop pokazuje watogodziny jako waty

`btop` 1.3.2 liczy „waty” baterii jako `energy_now / 1000000`, czyli wyświetla
zapas energii w Wh z etykietą `W` (na `bm-lab-01` stałe 43,75 = `energy_full`).
W gałęzi głównej projektu poprawiono to na `power_now`. Wartość, która nie
rośnie pod obciążeniem, nie jest pomiarem mocy.

## Testy

`tests/test_power_probe.py` sprawdza bez sprzętu: parsowanie czujników IPMI
(w tym przecinek dziesiętny z polskiej lokalizacji), odczyt i stan DCMI,
przewinięcie licznika energii RAPL oraz odmowę odczytu z baterii, która nie
jest rozładowywana.

# DevOps felvételi feladat megoldásai
---
## 1. A környezet előkészítése
:desktop_computer: A fizikai gép egy **LENOVO ThinkCentre M710q** típusú asztali mini PC:
- CPU: Intel Core i3-6100T @ 3.20 GHz
- RAM: 8 GB
- Tárhely: 250 GB (SSD)

A **list block devices** kimenete:
```
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
nvme0n1     259:0    0 238.5G  0 disk 
├─nvme0n1p1 259:1    0   600M  0 part /boot/efi
├─nvme0n1p2 259:2    0     1G  0 part /boot
├─nvme0n1p3 259:3    0   100G  0 part 
│ ├─ol-root 252:0    0    64G  0 lvm  /
│ ├─ol-swap 252:1    0    16G  0 lvm  [SWAP]
│ └─ol-home 252:2    0    20G  0 lvm  /home
└─nvme0n1p4 259:4    0 136.9G  0 part 
  └─data-vm 252:3    0 136.9G  0 lvm  /data/vm
```
A 4-es partíción külön **volume group**-ot (*data*) és **logical volume**-ot (*vm*) alakítottam ki, ahol a virtuális géphez köthető image-(ek)et tárolom, ami a */data/vm* elérési útra csatolódik fel.

A **KVM** virtualizációhoz szükséges csomagokat **telepítettem**, a **libvirtd** szervizt engedélyeztem és elindítottam.
```
dnf install qemu-kvm libvirt virt-install virt-top bridge-utils
systemctl enable --now libvirtd.service
```
A fentiekhez kapcsolódva létrehoztam a perzisztens **Libvirt storage pool**-t (*debian*) **autostart** opcióval a */data/vm* csatolási pontra.
```
virsh pool-define-as --name debian --type dir --target /data/vm
virsh pool-start debian
virsh pool-autostart debian
```

#### :vertical_traffic_light: Verziókövetés
Egy másik, alhálózatba kapcsolt mini PC-n futó **GitLab**-on, létrehoztam egy külön csoportot (*udemx*) és projektet (*devops-test*), ami SSH-alapú **repository mirroring** segítségével minden *push* esetén továbbítja a tartalmat a jelen **GitHub** *repository*-ba (*udemx-devops-test*).

#### :electric_plug: Hálózati konfiguráció
Azt szeretném elérni, hogy a virtuális gép közvetlenül csatlakozzon a *192.168.1.0/24* **alhálózatomhoz**, azaz:
- a fizikai gép IP címe **192.168.1.20**,
- a virtuális gépé **192.168.1.21** legyen.

Ehhez egy szoftver **bridge**-et állítottam be a fizikai gépen és a **hálózati interfészét** (amin keresztül a hálózathoz csatlakozik) hozzácsatoltam (*enslave*) a *bridge*-hez. Később a virtuális gépet is a *bridge*-hez csatolom.
(*A hálózaton működik egy BIND DNS szerver a 192.168.1.10 címen.*)
```
nmcli con add type bridge autoconnect yes con-name br0 ifname br0
nmcli con modify br0 ipv4.method manual \
  ipv4.addresses 192.168.1.20/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns 192.168.1.10 \
  ipv6.method ignore
nmcli con add type ethernet autoconnect yes con-name bridge-slave-enp0s31f6 \
  ifname enp0s31f6 master br0
nmcli con up bridge-slave-enp0s31f6 && nmcli con up br0 && nmcli con down enp0s31f6
nmcli con delete enp0s31f6
```
---

## 2. Virtuális gép installálása

A telepítés első lépésében elkészítettem a **preseed** konfigurációt a **netboot install**-hoz.
A [:page_facing_up: preseed.cfg](./vm/preseed.cfg) fájlt elérhetővé teszem a *8000*-es porton a *netboot install* számára, amit az alábbi **virsh install** paranccsal futtatok.
(*A `virt install` parancsban csatolom hozzá a virtuális gépet a korábban létrehozott **br0** bridge-hez.*)
```
cd /data/vm/preseed
python3 -m http.server 8000
```

```
virt-install \
  --name udemx-debian \
  --ram 4096 \
  --vcpus 4 \
  --disk pool=debian,size=64,format=qcow2 \
  --os-variant debian11 \
  --location 'http://deb.debian.org/debian/dists/bullseye/main/installer-amd64/' \
  --extra-args 'auto=true priority=critical preseed/url=http://192.168.1.20:8000/udemx-debian.cfg console=ttyS0,115200n8' \
  --network bridge=br0,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --boot useserial=on
```

> [!note]
> A **preseed** konfigurációban a következő dolgokat állítottam be:
> - **Statikus IP cím** (*192.168.1.21*) a virtuális szervernek
> - az `/opt` és `/tmp` könyvtárak részére külön partíció
> - az **SSH** az alapértelmezett (*22*) **port** helyett a *2222* porton hallgatózik
> - **Ansible** telepítve
> - a **root** felhasználó jelszavas SSH bejelentkezése engedélyezve
>
> Hasznos linkek a konfigurációhoz:
> - [example preseed](https://www.debian.org/releases/bullseye/example-preseed.txt)
> - [partman-auto recipe description](https://github.com/xobs/debian-installer/blob/master/doc/devel/partman-auto-recipe.txt)

Az installálás után **autostart**-ra jelölöm a virtuális gépet.
```
virsh autostart udemx-debian
```

---

## 3. Linux beállítása

*A hálózatom BIND DNS szerverének A és PTR rekordjaiba felvettem a **udemx-debian.lan** host-ot, a beállításokat az alábbi fájlok tartalmazzák:*
- [:page_facing_up: 192.168.1.rev](./named/192.168.1.rev)
- [:page_facing_up: lan.zone](./named/lan.zone)

Az **Ansible playbook**-okat a fizikai szerverre másoltam a `/opt/ansible` könyvtárba, az [:page_facing_up: inventory.ini](./ansible/inventory.ini) fájllal együtt.
Az *Ansible* **control node** a host gépem, a **managed node** pedig a virtuális gép.
A továbbiakban a *playbook*-okat mindig a *control node*-on futtatom, és azok a **hosts** paraméterükben meghatározott *node*-on hajtódnak végre.

#### :lock: SSH azonosítás beállítása

A virtuális szervert felveszem az ismert *host*-ok listájára. (*Az **sshpass**-nak a fizikai szerveren rendelkezésre kell állnia.*)
```
ssh-keyscan -p 2222 192.168.1.21 >> ~/.ssh/known_hosts
```

A [:page_facing_up: pem.yml](./ansible/playbooks/pem.yml) *playbook*-ban a **privát kulcsokat**, **SSH publikus kulcsot** és a **HTTPS tanúsítványt** létrehoztam, a publikus kulcsot és a HTTPS kulcs-tanúsítvány párt a virtuális gépre másoltam és engedélyeztem a publikus kulccsal történő azonosítást.
```
cd /opt/ansible
ansible-playbook -i inventory.ini ./playbooks/pem.yml
```

#### :package: Egyéb szolgáltatások

A szükséges **package**-eket a [:page_facing_up: packages.yml](./ansible/playbooks/packages.yml) *playbook*-ban telepítettem.
```
ansible-playbook -i inventory.ini ./playbooks/packages.yml
```

Az **OpenJDK 8**-as verziója a *Debian 11 repository*-ban nem elérhető.
A [:page_facing_up: java8.yml](./ansible/playbooks/java8.yml) *playbook*-ban külső forrásból letöltöttem, kicsomagoltam az `/opt/java` könyvtárba és a `java`, `javac`-t a 8-as verzióra irányítottam.
```
ansible-playbook -i inventory.ini ./playbooks/java8.yml
```

A [:page_facing_up: user.yml](./ansible/playbooks/user.yml) *playbook*-ban a **udemx** felhasználót `/opt/udemx` *home* könyvtárral létrehoztam, a **sudo** csoporthoz hozzáadtam, jelszót állítottam be hozzá.
```
ansible-playbook -i inventory.ini ./playbooks/user.yml
```

A [:page_facing_up: fail2ban.yml](./ansible/playbooks/fail2ban.yml) *playbook*-ban létrehoztam kettő *nginx* és egy *ssh* **jail**-t, majd a szolgáltatást egyelőre leállítottam, mert az *nginx* szerver elindulásáig hiányoznak még az *nginx* logfájlok, ezek nélkül a **fail2ban** sem indítható el.
```
ansible-playbook -i inventory.ini ./playbooks/fail2ban.yml
```

---

## 4. Kiegészítő szolgáltatások telepítése
A [:page_facing_up: docker.yml](./ansible/playbooks/docker.yml) *playbook*-ban telepítettem a **Docker Engine**-t, **Docker Compose**-t és **Docker Buildx**-et egyedi **data root**-ot meghatározva az `/srv/docker` könyvtárban.
Illetve a következő lépésben installált **Docker Registry** URL-jét hozzáadtam az *insecure-registries* kulcshoz a `daemon.json` fájlban.
(*A **hello-world** konténer a `docker run hello-world` paranccsal futtatható.*)
```
ansible-playbook -i inventory.ini ./playbooks/docker.yml
```

A [:page_facing_up: services.yml](./ansible/playbooks/services.yml) *playbook*-ban kialakítottam a környezetet a `docker compose` futtatásához. A szükséges könyvtárakat a perzisztens tárhelyekhez (*MariaDB, Jenkins, Docker Registry, nginx*) létrehoztam, a [:page_facing_up: compose.yml](./docker/compose.yml) és a [:page_facing_up: default.conf](./nginx/default.conf) (*nginx*) fájlokat átmásoltam. A szervizeket a `docker compose up` paranccsal elindítottam, majd az *nginx* logfájlokra váró *fail2ban* szervizt is aktiváltam.
```
ansible-playbook -i inventory.ini ./playbooks/services.yml
```
Az alábbi konténerek indultak el a virtuális gépen:
(az **nginx proxy** a főoldalon - [https://udemx-debian.lan](https://udemx-debian.lan) - *"Hello Udemx!"* szöveggel válaszol, a UI felületeket a táblázatban lévő *domain*-eken szolgáltatja. A **docker-registry** és a **mariadb** konténerek *default* portjai a *host* gép felé nyitva vannak.)

| Konténer neve      | URL                       |
| ---                | ---                       |
| docker-registry    | udemx-debian.lan:5000     |
| docker-registry-ui | registry.udemx-debian.lan |
| jenkins            | jenkins.udemx-debian.lan  |
| mariadb            | udemx-debian.lan:3306     |

A [:page_facing_up: mariadb.yml](./ansible/playbooks/mariadb.yml) *playbook*-ban létrehoztam a `udemx-db` adatbázist, a `udemx` felhasználót és beállítottam a jogosultságait az adatbázishoz, valamint ellenőriztem ezek eredményét.
```
ansible-playbook -i inventory.ini ./playbooks/mariadb.yml
```

A **Git** az operációs rendszerrel együtt települt. A [:page_facing_up: git.yml](./ansible/playbooks/git.yml) *playbook*-ban globálisan az alapértelmezett felhasználót **udemx**-re, az e-mail címet **udemx@udemx.eu**-ra állítottam. Egy *SSH* kulcspárt generáltam, és az `/opt/udemx/.ssh/config` fájlban beállítottam a szükséges konfigurációt.
[:link: udemx-project](https://github.com/Laszlo-Szabo-86/udemx-project/) néven publikus **GitHub** *repository*-t hoztam létre. (*A feladatban privát repository van, azért állítottam publikusra, hogy meg tudjátok nézni.*)
Ezt a *repository*-t fogom használni a [:arrow_down: 6. fejezetben](#6-ci-cd-feladat).
```
ansible-playbook -i inventory.ini ./playbooks/git.yml
```
A *GitHub*-on a **Settings** :arrow_right: **Deploy keys** :arrow_right: **Add deploy key** menüben hozzáadtam az előbb készített publikus kulcsot. (*Allow write access* opció engedélyezve.)
A `git clone github-udemx-project:Laszlo-Szabo-86/udemx-project.git` paranccsal ellenőrizhető, hogy a kapcsolódás sikeres.

---

## 5. Nehezebb feladatok plusz pontokért
Az [:page_facing_up: iptables.yml](./ansible/playbooks/iptables.yml) *playbook*-ban beállítottam, hogy az **INPUT chain** alapértelmezett *policy*-ja a **DROP** legyen, csak a `80`, `443`, `2222`, `3306` és `5000`-es portokon fogad forgalmat a szerver.
```
ansible-playbook -i inventory.ini ./playbooks/iptables.yml
```
A szerveren a beállítás az `iptables -L INPUT -n -v` paranccsal ellenőrizhető.

A [:page_facing_up: scripts.yml](./ansible/playbooks/scripts.yml) *playbook*-ban a kért öt darab szkriptet a virtuális gépre másoltam, futtathatóvá tettem őket, a **mysqldump** szkript esetében a **cron** időzítést beállítottam.
```
ansible-playbook -i inventory.ini ./playbooks/scripts.yml
```
- [:page_facing_up: last-changed-logs.sh](./bash/last-changed-logs.sh)
- [:page_facing_up: last-five.sh](./bash/last-five.sh)
- [:page_facing_up: loadavg-15.sh](./bash/loadavg-15.sh)
- [:page_facing_up: mysqldump.sh](./bash/mysqldump.sh)
- [:page_facing_up: nginx-title.sh](./bash/nginx-title.sh)

**Docker projekt** feladatként a [:arrow_up: 4. fejezetben](#4-kiegészítő-szolgáltatások-telepítése) telepített szolgáltatásokat szeretném a figyelmetekbe ajánlani! **Proxy webszerver**, **adatbázis** is települt. Az adatbázist a kért *stack*-ben ugyan nem használja alkalmazás, de amennyiben közös **docker network**-höz kapcsolódnak a konténerek, úgy a *Docker* belső névfeloldása alapján könnyen megtalálják egymást. Ahogy azt például az *nginx* konfigurációban láthatjátok; így nagyon egyszerű az alkalmazá és adatbázis konténerek összekapcsolása.
- [:page_facing_up: compose.yml](./docker/compose.yml)
- [:page_facing_up: default.conf](./nginx/default.conf) (*nginx*)

A **vim**-ből a `:q!` (*mentés és figyelmeztetés nélkül*), vagy a `:wq` (mentés és kilépés) paranccsal szoktam kilépni.  

---

## 6. CI-CD feladat
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

:vertical_traffic_light: **Verziókövetéshez**, egy másik alhálózatba kapcsolt mini PC-n futó **GitLab**-on, létrehoztam egy külön csoportot (*udemx*) és projektet (*devops-test*), ami SSH-alapú **repository mirroring** segítségével minden *push* esetén továbbítja a tartalmat a jelen **GitHub** *repository*-ba (*udemx-devops-test*).

:electric_plug: A **hálózati konfigurációban** azt szeretném elérni, hogy a virtuális gép közvetlenül csatlakozzon a *192.168.1.0/24* **alhálózatomhoz**, azaz:
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
A [./vm/preseed.cfg :page_facing_up:](./vm/preseed.cfg) fájlt elérhetővé teszem a *8000*-es porton a *netboot install* számára, amit az alábbi **virsh install** paranccsal futtatok.
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
> - az **/opt** és **/tmp** könyvtárak részére külön partíció
>
> Hasznos linkek a preseed konfigurációhoz:
> - [example preseed](https://www.debian.org/releases/bullseye/example-preseed.txt)
> - [partman-auto recipe description](https://github.com/xobs/debian-installer/blob/master/doc/devel/partman-auto-recipe.txt)

Az installálás után **autostart**-ra jelölöm a virtuális gépet.
```
virsh autostart udemx-debian
```
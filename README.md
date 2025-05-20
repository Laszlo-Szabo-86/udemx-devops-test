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
A fentiekhez kapcsolódva létrehoztam a perzisztens **Libvirt storage pool**-t (*debian*) **auto-start** opcióval a */data/vm* csatolási pontra.
```
virsh pool-define-as --name debian --type dir --target /data/vm
virsh pool-start debian
virsh pool-autostart debian
```

:vertical_traffic_light: **Verziókövetéshez**, egy másik alhálózatba kapcsolt mini PC-n futó **GitLab**-on, létrehoztam egy külön csoportot (*udemx*) és projektet (*devops-test*), ami SSH-alapú **repository mirroring** segítségével minden *push* esetén továbbítja a tartalmat a jelen **GitHub** *repository*-ba (*udemx-devops-test*).

---
## 2. Virtuális gép installálása
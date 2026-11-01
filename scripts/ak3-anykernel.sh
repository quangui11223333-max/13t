### AnyKernel3 Ramdisk Mod Script
## 一加 13T (PKX110 / sun / SM8750) —— 自定义内核刷机包
## 骨架来自 osm0sis/AnyKernel3，配置按 GKI + init_boot 设备改写过

### AnyKernel setup
# global properties
properties() { '
kernel.string=@KERNEL_STRING@
do.devicecheck=@DEVICECHECK@
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=@DEVICE1@
device.name2=@DEVICE2@
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
# GKI + init_boot 设备：ramdisk 在 init_boot 里，boot.img 只放 kernel。
# 所以 split_boot（不解 ramdisk）+ flash_boot（不重打包，只替换 kernel 写回）。
split_boot;

# 只替换 kernel image，不碰 dtb（dtbo 单独分区，用 dtbo.img 刷）
flash_boot;
## end boot install

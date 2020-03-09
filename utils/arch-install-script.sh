########################### Get User Input #######################
##################################################################
echo -e "Please enter the desired Hostname"
read HOSTNAME
echo $HOSTNAME

echo -e "Please enter the desired Username"
read USERNAME
echo $USERNAME

########################### Partition management #################
##################################################################

skip_flag=0
cont_flag=0
EFI_Flag="empty"
current_directory=$(pwd)

while [[ $skip_flag != 1 ]]
do
    echo -e "Have the partitions already been set up?\n Type y(es) or n(o): " 
    read APart_Flag
    if [[ ${APart_Flag} == "y" ]] || [[ ${APart_Flag} == "yes" ]] 
    then
        #skip all this shit if already managed     
        skip_flag=1
    elif [[ ${APart_Flag} == "n" ]] || [[ ${APart_Flag} == "no" ]]
    then
        #begin automated partition management
        #####################################
        while [[ $cont_flag != 1 ]]
        do
            echo -e "Do you want to zero the drive?\n Type y(es) or n(o): " 
            read Zero_Flag
            if [[ ${Zero_Flag} == "y" ]] || [[ ${Zero_Flag} == "yes" ]] 
            then
                #zero out the drives in parallel using calculated optimal block sizes
                #####################################################################
                
                dd if=/dev/zero of=/dev/sda status=progress bs=128K &
                dd if=/dev/zero of=/dev/sdb status=progress bs=256K &
                wait

                cont_flag=1

            elif [[ ${Zero_Flag} == "n" ]] || [[ ${Zero_Flag} == "no" ]] 
            then 
                cont_flag=1
            else
                echo "Response not understood, Please try again"
            fi
        done
        cont_flag=0
        echo 'beginning partition creation'
        while [[ $cont_flag!=1 ]]
        do
            # begin partiton creation
            #########################
            while [[ $EFI_Flag == "empty" ]] 
            do
                if [ -d /sys/firmware/efi/efivars ] 
                then
                    echo -e "EFI is supported, Do you want to Set it up?/n Type yes or no: " 
                    read EFI_Flag
                    if [[ "$EFI_Flag" != "yes" && "$EFI_Flag" != "no" ]] 
                    then
                        EFI_Flag="empty"
                    fi
                else
                echo 'EFI is not supported on this system'
                EFI_Flag="no"
                fi
            done

            if [[ "$EFI_Flag" == "no" ]] 
            then
                #Generate MBR partition setup
                #############################
                sfdisk /dev/sda < /arch-install-scripts/build_scripts/partition_setups/mbr_sda.sfdisk
                sfdisk /dev/sdb < /arch-install-scripts/build_scripts/partition_setups/mbr_sdb.sfdisk
                mkswap /dev/sdb2 
                swapon /dev/sdb2
                mount /dev/sda1 /mnt
                mkdir /mnt/home
                mount /dev/sdb1 /mnt/home
                
                rm -r /arch-install-scripts/build_scripts/partition_setups

            elif [[ "$EFI_Flag" == "yes" ]]
            then
                #Generate GPT partition setup
                #############################
                #parted -s -a optimal -- /dev/sda mkpart primary 1MiB -2048s
                echo "coming back to this, not fully developed"
                reboot
            fi
        done
        # end partition creation
        ########################
    skip_flag=1
    #end automated partition management
    ###################################
    else 
        echo "Response not understood, Please try again"
    fi
done

cont_flag=0

########################### Build powerpill ######################
##################################################################

# running makepkg as nobody user
mkdir /home/build
chgrp nobody /home/build
chmod g+ws /home/build
setfacl -m u::rwx,g::rwx /home/build
setfacl -d --set u::rwx,g::rwx,o::- /home/build

#enable color and candy
sed -i '/Color/s/^#//' /etc/pacman.conf
sed -i '/Color/a ILoveCandy' /etc/pacman.conf


#enable multilib repository
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

#set package signing option to require signature. 
sed -i '/\[core\]/a SigLevel\ =\ PackageRequired' /etc/pacman.conf
sed -i '/\[multilib\]/a SigLevel\ =\ PackageRequired' /etc/pacman.conf
sed -i '/\[community\]/a SigLevel\ =\ PackageRequired' /etc/pacman.conf
sed -i '/\[extra\]/a SigLevel\ =\ PackageRequired' /etc/pacman.conf

#enable xyne's repo
echo -e "[xyne-x86_64]\n# A repo for Xyne's own projects: https://xyne.archlinux.ca/projects/\n# Packages for \"any\" architecture.\n# Use this repo only if there is no matching [xyne-*] repo for your architecture.\nSigLevel = Required\nInclude = /etc/pacman.d/xyne-mirrorlist"
echo -e "Server = https://xyne.archlinux.ca/bin/repo.php?file=\nServer = https://xyne.mirrorrepo.com/repos/xyne" /etc/pacman.d/xyne-mirrorlist

pacman -Sy powerpill baurerbill

#cd /home/build
#git clone https://aur.archlinux.org/powerpill.git
#chmod -R g+w powerpill
#cd powerpill
#sudo -u nobody makepkg -sicL --syncdeps
#cd ..
#rm -r powerpill

#git clone  

cd $current_direcory
########################### Begin Install ########################
##################################################################

timedatectl set-ntp true

genfstab -U /mnt >> /mnt/etc/fstab

#creating the base system
source /arch-install-scripts/build_scripts/package_lists/system_base.sh
pacstrap /mnt ${base[*]}

########################## Get User input #######################
#################################################################



######################### Populate pacman hooks #################
#################################################################

echo 'populating hooks'
hooks_location='/mnt/etc/pacman.d/hooks/'

mkdir -p $hooks_location

vga_driver=$(lspci | grep 'vga\|3d\|2d')

for file in $current_directory/pacman_hooks/*.hook; do
  if [[ $file != *"populator"* ]]; then
      base_file=$(echo $(basename "$file") )
      if [[ $base_file != *"nvidia"* ]]; then
        echo $base_file
        cp -i "$current_directory/pacman_hooks/$base_file" "$hooks_location$base_file"
      else
        if [[ $vga_driver = *"Nvidia"* ]]; then
          echo 'Nvidia GPU Detected, populating dkms-based hooks'
          cp -i "pacman_hooks/$base_file" "$hooks_location$base_file"
        fi
      fi
  fi
done

############################ polkit rules ##########################
####################################################################
echo 'populating polkit rules'

rules_location='/mnt/etc/polkit-1/rules.d/'

mkdir -p $rules_location

for file in $current_direcory/polkit_rules/*.rules; do
  if [[ $file != *"populator"* ]]; then
      base_file=$(echo $(basename "$file") )
      cp -i "polkit_rules/$base_file" $rules_location$base_file
  fi
done

###########  Set pacman options  ##################################
###################################################################

#enable color and candy
sed -i '/Color/s/^#//' /mnt/etc/pacman.conf
sed -i '/Color/a ILoveCandy' /mnt/etc/pacman.conf


#enable multilib repository
sed -i "/\[multilib\]/,/Include/"'s/^#//' /mnt/etc/pacman.conf

#set package signing option to require signature. 
sed -i '/\[core\]/a SigLevel\ =\ PackageRequired' /mnt/etc/pacman.conf
sed -i '/\[multilib\]/a SigLevel\ =\ PackageRequired' /mnt/etc/pacman.conf
sed -i '/\[community\]/a SigLevel\ =\ PackageRequired' /mnt/etc/pacman.conf
sed -i '/\[extra\]/a SigLevel\ =\ PackageRequired' /mnt/etc/pacman.conf

########################## setup Network Manager ##################
###################################################################

echo -e '[main]\nwifi.cloned-mac-address=random' >> /mnt/etc/NetworkManager/conf.d/mac_address_randomization.conf
echo -e '[main]\ndhcp=dhclient' >> /mnt/etc/NetworkManager/conf.d/dhcp-client.conf
echo -e '[main]\ndns=dnsmasq' >> /mnt/etc/NetworkManager/conf.d/dns.conf
echo -e '[main]\nrc-manager=resolvconf' >> /mnt/etc/NetworkManager/conf.d/rc-manager.conf
echo -e 'conf-file=/usr/share/dnsmasq/trust-anchors.conf\ndnssec\n' >> /mnt/etc/NetworkManager/dnsmasq.d/dnssec.conf
echo -e 'options="edns0 single-request-reopen"\nnameservers="::1 127.0.0.1"\ndnsmasq_conf=/etc/NetworkManager/dnsmasq.d/dnsmasq-openresolv.conf\ndnsmasq_resolv=/etc/NetworkManager/dnsmasq.d/dnsmasq-resolv.conf' >> /mnt/etc/resolvconf.conf
sed -i '/require_dnssec/s/false/true/' /mnt/etc/dnscrypt-proxy/dnscrypt-proxy.toml

#################### Harden System ##############################
#################################################################

#change default permissions 
chmod 700 /mnt/boot /mnt/etc/{iptables,arptables} #NOTE: DESPERATELY NEED TO MAKE SIMPLE FIREWALLS
sed -i "/umask"'s/^0022/0077//' /mnt/etc/profile

#hide processes from all users not part of proc group
echo -e 'proc\t/proc\tproc\tnosuid,nodev,noexec,hidepid=2,gid=proc\t0\t0' >> /mnt/etc/fstab

# gpasswd -a gdm proc

mkdir -p /mnt/etc/systemd/system/systemd-logind.service.d
echo -e '[Service]\nSupplementaryGroups=proc' >> /mnt/etc/systemd/system/systemd-logind.service.d/hidepid.conf

# change log group to wheel in order to allow notifications
sed -i "/log_group/s/root/wheel/" /mnt/etc/audit/auditd.conf

#firejail apparmor integration, disallow net globally
mkdir -p /mnt/etc/firejail
mv $current_direcory/firejail_profiles/globals.local /mnt/etc/firejail/globals.local

######################################################

#copy necessary files to new root and continue install process
cd arch-install-scripts
cp -r build_scripts systemd_units /mnt
cd ..

#begin install
arch-chroot /mnt mnt/build_scripts/arch-post-chroot.sh
wait $1


######################### Clean up and reboot ####################
##################################################################

umount -a
#unmount all and reboot
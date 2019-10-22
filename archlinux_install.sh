#!/bin/bash

install_device="Not set"
UEFI_BIOS_text=""
ZONE="Asia"
SUBZONE="Shanghai"
country_codes=()
locale_utf8=()

host_name=archlinux
root_password=
user_name=vastpeng
user_password=

UEFI=

MOUNT_POINT="/mnt"

# COLORS {{{
  Bold=$(tput bold)
  Underline=$(tput sgr 0 1)
  Reset=$(tput sgr0)
  # Regular Colors
  Red=$(tput setaf 1)
  Green=$(tput setaf 2)
  Yellow=$(tput setaf 3)
  Blue=$(tput setaf 4)
  Purple=$(tput setaf 5)
  Cyan=$(tput setaf 6)
  White=$(tput setaf 7)
  # Bold
  BRed=${Bold}${Red}
  BGreen=${Bold}${Green}
 BYellow=${Bold}${Yellow}
  BBlue=${Bold}${Blue}
  BPurple=${Bold}${Purple}
  BCyan=${Bold}${Cyan}
  BWhite=${Bold}${White}
#}}}

function print_line() { 
  printf "%$(tput cols)s\n"|tr ' ' '-'
} 
function print_title() {
  clear
  print_line
  echo -e "# ${Bold}$1${Reset}"
  print_line
  echo ""
} 

function print_info() { 
  #Console width number
  T_COLS=`tput cols`
  echo -e "${Bold}$1${Reset}\n" | fold -sw $(( $T_COLS - 18 )) | sed 's/^/\t/'
} 

function print_warning() {
  T_COLS=`tput cols`
  echo -e "${BYellow}$1${Reset}\n" | fold -sw $(( $T_COLS - 1 ))
} 
function print_danger() { 
  T_COLS=`tput cols`
  echo -e "${BRed}$1${Reset}\n" | fold -sw $(( $T_COLS - 1 ))
} 

function contains_element() { 
  #check if an element exist in a string
  for e in "${@:2}"; do [[ $e == $1 ]] && break; done;
} 

function invalid_option() { 
  print_line
  echo "Invalid option. Try another one."
  pause_function
} 

function check_boot_system() { 
    if [[ "$(cat /sys/class/dmi/id/sys_vendor)" == 'Apple Inc.' ]] || [[ "$(cat /sys/class/dmi/id/sys_vendor)" == 'Apple Computer, Inc.' ]]; then
      modprobe -r -q efivars || true  # if MAC
    else
      modprobe -q efivarfs            # all others
    fi
    if [[ -d "/sys/firmware/efi/" ]]; then
      ## Mount efivarfs if it is not already mounted
      if [[ -z $(mount | grep /sys/firmware/efi/efivars) ]]; then
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars
      fi
      UEFI=1
      UEFI_BIOS_text="UEFI detected"
    else
      UEFI=0
      UEFI_BIOS_text="BIOS detected"
    fi
}

# TODO: maybe we need lvm partions?
function format_partions() {
    sgdisk --zap-all ${install_device}
    boot_partion="${install_device}1"
    system_partion="${install_device}2"

    [[ $UEFI -eq 1 ]] && printf "n\n1\n\n+512M\nef00\nw\ny\n" | gdisk ${install_device} && yes | mkfs.fat -F32 ${boot_partion}
    [[ $UEFI -eq 0 ]] && printf "n\n1\n\n+2M\nef02\nw\ny\n" | gdisk ${install_device} && yes | mkfs.ext2 ${boot_partion}

    printf "n\n2\n\n\n8300\nw\ny\n"| gdisk ${install_device}
    yes | mkfs.ext4 ${system_partion}

    mount ${system_partion} /mnt
    [[ $UEFI -eq 1 ]] && mkdir -p /mnt/boot/efi && mount ${boot_partion} /mnt/boot/efi
}

function bootloader_uefi() {
    arch-chroot ${MOUNT_POINT} /bin/bash <<EOF
        pacman -S efibootmgr --noconfirm
        grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
        mkdir /boot/efi/EFI/BOOT
        cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
        echo 'bcf boot add 1 fs0:\EFI\grubx64.efi "My GRUB bootloader" && exit' > /boot/efi/startup.sh
        grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

function bootloader_bios() {
    arch-chroot ${MOUNT_POINT} /bin/bash <<EOF
        grub-install "${install_device}"
        grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

function bootloader_install() {
    case ${UEFI} in 
      1) bootloader_uefi;;
      *) bootloader_bios;;
    esac
}


prompt1="Enter your option: "
prompt2="Enter n° of options (ex: 1 2 3 or 1-3): "

function arch_chroot() {
  arch-chroot $MOUNT_POINT /bin/bash -c "${1}"
}

function read_input_text() {
  if [[ $AUTOMATIC_MODE -eq 1 ]]; then
    OPTION=$2
  else
    read -p "$1 [y/N]: " OPTION
    echo ""
  fi
  OPTION=`echo "$OPTION" | tr '[:upper:]' '[:lower:]'`
}

function read_input_options() { 
  local line
  local packages
  if [[ $AUTOMATIC_MODE -eq 1 ]]; then
    array=("$1")
  else
    read -p "$prompt2" OPTION
    array=("$OPTION")
  fi
  for line in ${array[@]/,/ }; do
    if [[ ${line/-/} != $line ]]; then
      for ((i=${line%-*}; i<=${line#*-}; i++)); do
        packages+=($i);
      done
    else
      packages+=($line)
    fi
  done
  OPTIONS=("${packages[@]}")
} 

function checkbox() { 
    #display [X] or [ ]
    [[ "$1" -eq 1 ]] && echo -e "${BBlue}[${Reset}${Bold}X${BBlue}]${Reset}" || echo -e "${BBlue}[ ${BBlue}]${Reset}";
}

function mainmenu_item() { 
  #if the task is done make sure we get the state
  if  [[ $3 != "" ]] && [[ $3 != "/" ]]; then    
    state="${BGreen}[${Reset}$3${BGreen}]${Reset}"
  else
    state="${BGreen}[${Reset}Not Set${BGreen}]${Reset}"
  fi
  echo -e "$(checkbox "$1") ${Bold}$2${Reset} ${state}"
} 

AUTOMATIC_MODE=0
function pause_function() { 
  print_line
  if [[ $AUTOMATIC_MODE -eq 0 ]]; then
    read -e -sn 1 -p "Press enter to continue..."
  fi
}

ounction set_password() {
  t_
  while true; do
    read -s -p "Password for $1: " password1
    echo
    read -s -p "Confirm the password: " password2
    echo
    if [[ ${password1} == ${password2} ]]; then
      eval $2=${password1}
      break
    fi
    echo "Please try again"
  done 
}

function select_mirrorlist() {
  print_title "MIRRORLIST - https://wiki.dex.php/Mirrors"
  print_info "This option is a guide to selecting and configuring your mirrors, and a listing of current available mirrors."

  local countries_code=("AU" "AT" "BY" "BE" "BR" "BG" "CA" "CL" "CN" "CO" "CZ" "DK" "EE" "FI" "FR" "DE" "GR" "HK" "HU" "ID" "IN" "IR" "IE" "IL" "IT" "JP" "KZ" "KR" "LV" "LU" "MK" "NL" "NC" "NZ" "NO" "PL" "PT" "RO" "RU" "RS" "SG" "SK" "ZA" "ES" "LK" "SE" "CH" "TW" "TR" "UA" "GB" "US" "UZ" "VN")
  local countries_name=("Australia" "Austria" "Belarus" "Belgium" "Brazil" "Bulgaria" "Canada" "Chile" "China" "Colombia" "Czech Republic" "Denmark" "Estonia" "Finland" "France" "Germany" "Greece" "Hong Kong" "Hungary" "Indonesia" "India" "Iran" "Ireland" "Israel" "Italy" "Japan" "Kazakhstan" "Korea" "Latvia" "Luxembourg" "Macedonia" "Netherlands" "New Caledonia" "New Zealand" "Norway" "Poland" "Portugal" "Romania" "Russia" "Serbia" "Singapore" "Slovakia" "South Africa" "Spain" "Sri Lanka" "Sweden" "Switzerland" "Taiwan" "Turkey" "Ukraine" "United Kingdom" "United States" "Uzbekistan" "Viet Nam")
  #`reflector --list-countries | sed 's/[0-9]//g' | sed 's/^/"/g' | sed 's/,.*//g' | sed 's/ *$//g'  | sed 's/$/"/g' | sed -e :a -e '$!N; s/\n/ /; ta'`
  PS3="$prompt1"
  echo "Select your country:"
  select country_name in "${countries_name[@]}" Done; do
    [[ $country_name == Done ]] && break

    if contains_element "$country_name" "${countries_name[@]}"; then
      country_codes=(${countries_code[$(( $REPLY - 1 ))]} ${country_codes[@]})
      echo "Got ${country_name}. Any others?"
    else
      invalid_option
    fi
  done

}

function select_device() {
  devices_list=(`lsblk -d | awk 'NR>1 { print "/dev/" $1 }'`)
  PS3="$prompt1"
  echo -e "Select device to partition:\n"
  select device in "${devices_list[@]}"; do
    if contains_element "${device}" "${devices_list[@]}"; then
      break
    else
      invalid_option
    fi
  done
  install_device=${device}
}

function select_timezone() {
  print_title "HARDWARE CLOCK TIME - https://wiki.archlinux.org/index.php/Internationalization"
  print_info "This is set in /etc/adjtime. Set the hardware clock mode uniformly between your operating systems on the same machine. Otherwise, they will overwrite the time and cause clock shifts (which can cause time drift correction to be miscalibrated)."

  local _zones=(`timedatectl list-timezones | sed 's/\/.*$//' | uniq`)
  PS3="$prompt1"
  echo "Select zone:"
  select ZONE in "${_zones[@]}"; do
    if contains_element "$ZONE" "${_zones[@]}"; then
      local _subzones=(`timedatectl list-timezones | grep ${ZONE} | sed 's/^.*\///'`)
      PS3="$prompt1"
      echo "Select subzone:"
      select SUBZONE in "${_subzones[@]}"; do
        if contains_element "$SUBZONE" "${_subzones[@]}"; then
          break
        else
          invalid_option
        fi
      done
      break
    else
      invalid_option
    fi
  done
}

function select_locale() {
  print_title "LOCALE - https://wiki.archlinux.org/index.php/Locale"
  print_info "Locales are used in Linux to define which language the user uses. As the locales define the character sets being used as well, setting up the correct locale is especially important if the language contains non-ASCII characters."
x
  local _locale_list=(`cat /etc/locale.gen | grep UTF-8 | sed 's/\..*$//' | sed '/@/d' | awk '{print $1}' | uniq | sed 's/#//g'`);
  PS3="$prompt1"
  echo "Select locale:"
  select LOCALE in "${_locale_list[@]}" Done; do
    [[ $LOCALE == Done ]] && break
    if contains_element "$LOCALE" "${_locale_list[@]}"; then
      locale_utf8=("${LOCALE}.UTF-8" ${locale_utf8[@]})
      echo "Got ${LOCALE}. Any others?"
    else
      invalid_option
    fi
  done
}

function set_hostname() {
  read -p "Host name [ex: ${host_name}]: " host_name
}

function set_root_password() {
  set_password root root_password
}

function set_userinfo() {
  local result
  read -p "User name[ex: ${user_name}]: " result
  if [[ ! -z ${result} ]]; then 
    user_name=${result}
  fi
  set_password ${user_name} user_password
}

function configure_mirrorlist() {
  local params=""
  for country in ${country_codes[@]}; do
    params+="country=${country}&"
  done
  url="https://www.archlinux.org/mirrorlist/?${params}protocol=http&protocol=https&ip_version=4&ip_version=6"

  # Get latest mirror list and save to tmpfile
  tmpfile=$(mktemp --suffix=-mirrorlist)
  curl -Lo ${tmpfile} ${url}
  sed -i 's/^#Server/Server/g' ${tmpfile}

  # Backup and replace current mirrorlist file (if new file is non-zero)
  if [[ -s ${tmpfile} ]]; then
   { echo " Backing up the original mirrorlist..."
     mv -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig; } &&
   { echo " Rotating the new list into place..."
     mv -f ${tmpfile} /etc/pacman.d/mirrorlist; }
  else
    echo " Unable to update, could not download list."
  fi

  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.tmp
  rankmirrors /etc/pacman.d/mirrorlist.tmp > /etc/pacman.d/mirrorlist
  rm /etc/pacman.d/mirrorlist.tmp
  chmod +r /etc/pacman.d/mirrorlist
}

function configure_timezone() {
  arch_chroot "ln -sf /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime"
  arch_chroot "sed -i '/#NTP=/d' /etc/systemd/timesyncd.conf"
  arch_chroot "sed -i 's/#Fallback//' /etc/systemd/timesyncd.conf"
  arch_chroot "echo \"FallbackNTP=0.pool.ntp.org 1.pool.ntp.org 0.fr.pool.ntp.org\" >> /etc/systemd/timesyncd.conf"
  arch_chroot "systemctl enable systemd-timesyncd.service"
  arch_chroot "hwclock --systohc --localtime"
}

function configure_locale() {
  LANG=""
  for lang in ${locale_utf8[@]}; do
    LANG+="${lang} "
    arch_chroot "sed -i 's/#\('${lang}'\)/\1/' /etc/locale.gen"
  done
  echo "LANG=${LANG}" > ${MOUNT_POINT}/etc/locale.conf
  arch_chroot "locale-gen"
}

function configure_hostname() {
  echo "$host_name" > ${MOUNT_POINT}/etc/hostname

  arch_chroot "echo '127.0.0.1  localhost >> /etc/hosts'"
  arch_chroot "echo '::1        localhost >> /etc/hosts'"
}

function configure_user() {
  arch_chroot 'echo "root:${root_password}" | chpasswd'
  arch_chroot 'useradd -m -s $(which zsh) -G wheel ${user_name} && echo "${user_name}:${user_password}" | chpasswd'
}

function system_install() {
  configure_mirrorlist
  format_partions

  yes '' | pacstrap -i /mnt base linux linux-firmware grub os-prober git zsh neovim
  yes '' | genfstab -U /mnt >> /mnt/etc/fstab

  configure_timezone
  configure_locale
  configure_hostname
  configure_user
}

function finish(){
  print_title "INSTALL COMPLETED"
  #COPY AUI TO ROOT FOLDER IN THE NEW SYSTEM
  read_input_text "Reboot system"
  if [[ $OPTION == y ]]; then
    umount -R ${MOUNT_POINT}
    reboot
  fi
  exit 0
}


print_title "https://wiki.archlinux.org/index.php/Arch_Install_Scripts"
print_info "The Arch Install Scripts are a set of Bash scripts that simplify Arch installation."
pause_function
check_boot_system
check_list=( 0 0 0 0 0 0 0 )
while true; do
  print_title "ARCHLINUX ULTIMATE INSTALL - https://github.com/vastpeng/aui"
  echo " 1) $(mainmenu_item "${checklist[1]}"  "Select Mirrors"             "${country_codes[*]}" )"
  echo " 2) $(mainmenu_item "${checklist[2]}"  "Select Device"              "${install_device}" )"
  echo " 3) $(mainmenu_item "${checklist[3]}"  "Select Timezone"            "${ZONE}/${SUBZONE}" )"
  echo " 4) $(mainmenu_item "${checklist[4]}"  "Select Locale-UTF8"         "${locale_utf8[*]}" )"
  echo " 5) $(mainmenu_item "${checklist[5]}"  "Configure Hostname"         "${host_name}" )"
  echo " 6) $(mainmenu_item "${checklist[6]}"  "Root password"              "${root_password}" )"
  echo " 7) $(mainmenu_item "${checklist[7]}"  "Set Usesr Info"             "${user_name}/${user_password}" )"
  echo " 8) $(mainmenu_item 1                   "Bootloader"                "${UEFI_BIOS_text}" )"
  echo ""
  echo " i) install"
  echo ""
  read_input_options
  local OPT
  for OPT in ${OPTIONS[@]}; do
    case ${OPT} in
        1) select_mirrorlist && checklist[1]=1;;
        2) select_device && checklist[2]=1;;
        3) select_timezone && checklist[3]=1;;
        4) select_locale && checklist[4]=1;;
        5) set_hostname && checklist[5]=1;;
        6) set_root_password && checklist[6]=1;;
        7) set_userinfo && checklist[7]=1;;
        'i') system_install && finish;;
        *) invalid_option;;
    esac
  done
done



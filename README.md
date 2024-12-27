# Ubuntu Dotfiles 2025

Welcome, stranger! People said the world would end in the year 2000, and here we are, contrary to all expectations. On the other hand, as soon as we passed the cataclysmic year 2000, we imagined that by 2025 we would have clean cities, flying cars, crystal resonance-based technologies, coexistence with other civilizations... here in Brazil we barely have basic sanitation.

This year I celebrate an important milestone: **25 years using Linux**, 20 of which were as my main operating system. A lot has changed, and in the last 10 years I've had to learn to change old habits in order to be more productive. I didn't like all of Linux's developments (like the infamous Systemd), but there are battles we can't win.

In 2024 we will have an Ubuntu LTS. This means that for at least 2 years we will have a system with some predictability to implement our custom configurations. It also means that we will struggle for another 2 years with the broken Nvidia driver, with Wayland, with the constant failures in Pipewire... but that's life.

I learned some new tricks, some more interesting ways to install the system, let's follow them in this post.

## Installing Ubuntu 24.04

This section could also be called **"The Ubuntu that wanted to be an Arch"**. There's one thing I LOVE about Fedora, and that I like less and less with each Ubuntu release: the installer. If there's one thing that makes me angry, it's when the installer doesn't include more advanced options for partitioning, package selection, configurations, etc.

I always have to deal with more advanced partitioning. I dual boot with Windows 11, and I need to use encryption. I like to experiment with modern file systems, such as ZFS and BTRFS. I follow a lot of performance studies, and I've seen problems with LVM.

**Desired Partition Scheme**

| Size    | Mount point | Filesystem           | Path             |
| ------- | ----------- | -------------------- | ---------------- |
| 1 GiB   | /boot       | EXT4                 | /dev/nvme0n1p1   |
| 1 GiB   | /boot/efi   | EFI System Partition | /dev/nvme0n1p2   |
| 250 GiB | Windows     | NTFS                 | /dev/nvme0n1p3   |
| 700 GiB | /           | LUKS (BTRFS)         | /dev/nvme0n1p4   |
| *       | FREE        | UNFORMATTED          | /dev/nvme0n1p5-* |

The BTRFS should have the following sub-volumes:

| Sub-volume | Mount point |
| ---------- | ----------- |
| @          | /           |
| @var       | /var        |
| @home      | /home       |
| @opt       | /opt        |
| @srv       | /srv        |
| @root      | /root       |

Since we require encryption on the system and the layout is based on BTRFS without LVM, there is no support in the installer. This means **we will be the installer**.

1. Boot using Ubuntu (or any other distro with partitioning tools). Create a new GPT partition table and the partitions like the Table 1, above:

```bash

# Get powers!
sudo su -

# Create partitions
cfdisk /dev/nvme0n1  # replace by your device name

# Format partitions
mkfs.ext4 -L boot /dev/nvme0n1p1
mkfs.vfat -F 32 -n EFI /dev/nvme0n1p2
mkfs.ntfs --fast --label WINDOWS /dev/nvme0n1p3
cryptsetup luksFormat --label=cryptlinux /dev/nvme0n1p4
cryptsetup open /dev/nvme0n1p4 cryptlinux
mkfs.btrfs --label cryptlinux /dev/mapper/cryptlinux

# Create subvolumes
cd /mnt
mkdir temp
mount /dev/mapper/cryptlinux /mnt/temp
btrfs subvolume create /mnt/temp/@
btrfs subvolume create /mnt/temp/@var
btrfs subvolume create /mnt/temp/@home
btrfs subvolume create /mnt/temp/@opt
btrfs subvolume create /mnt/temp/@srv
btrfs subvolume create /mnt/temp/@root
umount /mnt/temp

```

2. Install Windows on /dev/nvme0n1p3. Ubuntu and Windows will share the EFI boot partition.

3. Reboot using the LiveCD. Now it is time to mount all partitions and install the system using the Debian Bootstrap tool. 

```bash

# Needed packages
apt update
apt install arch-install-scripts debootstrap vim

# Mount the partitions
cd /mnt
mkdir target
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@ /mnt/target
mkdir /mnt/target/{var,home,opt,srv,root}
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@var /mnt/target/var
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@home /mnt/target/home
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@opt /mnt/target/opt
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@srv /mnt/target/srv
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@root /mnt/target/root

# Mount boot partitions
mkdir -p /mnt/target/boot
mount -o defaults,nosuid,nodev,relatime,errors=remount-ro /dev/nvme0n1p1 /mnt/target/boot
mkdir -p /mnt/target/boot/efi
mount -o defaults,nosuid,nodev,relatime,errors=remount-ro /dev/nvme0n1p2 /mnt/target/boot/efi

# Bootstrap Ubuntu 24.04 from Brazil
debootstrap noble /mnt/target http://br.archive.ubuntu.com/ubuntu

# Prevent some packages from being installed
cat > /mnt/target/etc/apt/preferences.d/ignored-packages <<EOF
Package: snapd cloud-init landscape-common popularity-contest ubuntu-advantage-tools
Pin: release *
Pin-Priority: -1
EOF

# Creating APT repositories
cat > /mnt/target/etc/apt/sources.list <<EOF
deb http://br.archive.ubuntu.com/ubuntu noble           main restricted universe
deb http://br.archive.ubuntu.com/ubuntu noble-security  main restricted universe
deb http://br.archive.ubuntu.com/ubuntu noble-updates   main restricted universe
deb http://br.archive.ubuntu.com/ubuntu noble-backports   main restricted universe
EOF

# Creating an FSTAB
genfstab /mnt/target > /mnt/target/etc/fstab

# Setup LUKS file
echo "cryptlinux /dev/nvme0n1p4 none luks" > /mnt/target/etc/crypttab

# Chroot using Arch scripts
arch-chroot /mnt/target

# Configuring language details
dpkg-reconfigure tzdata
dpkg-reconfigure locales
dpkg-reconfigure keyboard-configuration

# Hostname and hosts
echo "linuxdragon" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.1.1 linuxdragon" >> /etc/hosts

# Installing basic packages
apt update
apt dist-upgrade -y
apt install --no-install-recommends -y \
  linux-{,image-,headers-}generic-hwe-24.04 \
  linux-firmware initramfs-tools efibootmgr firmware-sof-signed intel-microcode \
  cryptsetup btrfs-progs curl wget dmidecode ethtool firewalld fwupd gawk git gnupg htop man \
  needrestart openssh-server patch screen software-properties-common tmux zsh zstd \
  grub-efi-amd64 flatpak gnome-software-plugin-flatpak gdm3 cryptsetup-initramfs \
  plymouth plymouth-theme-spinner ubuntu-desktop-minimal gnome-session gnome-tweaks 

# Bootloader config
# Configurar bootloader
mkdir -p /etc/default/grub.d
echo "GRUB_ENABLE_CRYPTODISK=y" > /etc/default/grub.d/local.cfg
grub-install /dev/nvme0
grub-install /dev/nvme0n1
grub-install /dev/nvme0n1p1
update-grub
update-initramfs -u -k all

# Users
useradd -m wesley \
  -c "Wesley Rodrigues" \
  -G adm,tty,disk,lp,kmem,uucp,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,games,users,utmp \
  -s /bin/zsh

# Password (change, please)
echo "root:12345678" | chpasswd
echo "wesley:12345678" | chpasswd

# Cross your fingers and reboot :)
exit
reboot

```

## Maintenance

Sometimes things will not work as you planned. Most times, I would say.
If you need do recover things, boot using the LiveCD and:

```bash
sudo su -

apt update
apt install arch-install-scripts debootstrap vim -y

cd /mnt
mkdir target

cryptsetup open /dev/nvme0n1p4 cryptlinux

mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@ /mnt/target
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@var /mnt/target/var
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@home /mnt/target/home
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@opt /mnt/target/opt
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@srv /mnt/target/srv
mount /dev/mapper/cryptlinux -o defaults,noatime,autodefrag,compress-force=zstd:1,space_cache=v2,discard=async,subvol=@root /mnt/target/root

mount -o defaults,nosuid,nodev,relatime,errors=remount-ro /dev/nvme0n1p1 /mnt/target/boot
mount -o defaults,nosuid,nodev,relatime,errors=remount-ro /dev/nvme0n1p2 /mnt/target/boot/efi

arch-chroot /mnt/target

```

## Post-Install Tasks

We want a nice desktop environment, with modern features. We will install some tools for achieving this:

- ASDF for managing languages like `python`, `rust`, `go` and `ruby`;
- Rust command line tools replacing `ls`, `top` and `du`;
- Starship for prompt management replacing `oh-my-zsh`;
- LunarVim replacing `vim`, giving super powers to `neovim`;
- Custom prompt and aliases.

This Ubuntu will never have Snap, thanks God. We will use Flatpaks to pump it up.

Let's go. Reboot into your new Ubuntu, open a terminal and:

```bash

# Setup some basic packages
sudo apt install -y autoconf build-essential cmake gfortran libbz2-1.0 libbz2-dev libcurl3-dev libdb-dev libffi-dev libgdbm-dev libgdbm6 libgmp-dev liblzma-dev liblzma5 libncurses5-dev libpcre2-dev libreadline-dev libreadline6-dev libssl-dev libyaml-dev neovim patch python3-dev ruby-build tk tk-dev tklib uuid-dev xorg-dev zlib1g-dev zsh zsh-syntax-highlighting


# If zsh is not your shell...
sudo chsh -s /bin/zsh $(whoami)
zsh


# Install Lazy Git
cd /tmp
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar xf lazygit.tar.gz lazygit
sudo install lazygit -D -t /usr/local/bin/
lazygit --version


# Backup your existing rc files
cd ~
mkdir .old_rc_files
mv .bashrc .bash_history .bash_logout .bash_profile \
    .profile .zshrc .zsh .zsh_history .oh-my-zsh \
    .bash_facilities .zsh_facilities .old_rc_files
mkdir ~/.zsh


# Better suggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh


# Install ASDF
git clone https://github.com/asdf-vm/asdf.git ~/.asdf
source "$HOME/.asdf/asdf.sh"
fpath=(${ASDF_DIR}/completions $fpath)
autoload -Uz compinit && compinit


# Install things with ASDF
asdf plugin add python
asdf plugin add ruby
asdf plugin add rust
asdf plugin add nodejs
asdf plugin add golang
asdf plugin add r

asdf install rust 1.83.0
asdf global rust 1.83.0

asdf install python 3.12.1
asdf global python 3.12.1

asdf install ruby 3.3.6
asdf global ruby 3.3.6

asdf install nodejs 22.12.0
asdf global nodejs 22.12.0

asdf install golang 1.22.10
asdf global golang 1.22.10

asdf install r 4.4.2
asdf global r 4.4.2


# New binary utils
asdf reshim
rehash
cargo install bat exa fd-find procs du-dust starship ytop ripgrep
asdf reshim
rehash


# Lunar VIM :D
LV_BRANCH='release-1.4/neovim-0.9' bash <(curl -s https://raw.githubusercontent.com/LunarVim/LunarVim/release-1.4/neovim-0.9/utils/installer/install.sh)


# Create your new files
cat > ~/.zshrc <<EOF
setopt histignorealldups sharehistory

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e

HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

source "$HOME/.asdf/asdf.sh"
fpath=(${ASDF_DIR}/completions $fpath)
autoload -Uz compinit && compinit

# Autosuggestions
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Path
export PATH=~/.local/bin:$PATH

# Starfish Prompt
eval "$(starship init zsh)"

# Candy time!
alias reload="source ~/.zshrc"
alias editzshrc="vim ~/.zshrc"
alias ls="exa --icons"
alias vim="lvim"

source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF


cat > ~/.config/starship.toml <<EOF
'$schema' = 'https://starship.rs/config-schema.json'


format = """
[┌─](#3366aa)\
[ $username ](bg:#3366aa fg:white bold)\
[  ](bg:#ffaa00 fg:#330066)\
[ $hostname ](bg:#003300 fg:white)\
[ $directory ](bg:#191970 fg:#ffaa00)\
[$python](bg:#dcdcdc fg:green)\
[$ruby](bg:#dcdcdc fg:red)\
[$rlang](bg:#dcdcdc fg:#3366aa)\
[$git_branch$git_status$git_commit](bg:#330066 fg:white)\
$fill \
$jobs
[│](#3366aa) 
[└─](#3366aa)$character
"""


[character]
success_symbol = '[](#3366aa)'
error_symbol = '[](red)'


[directory]
home_symbol = '~'
read_only = ' '
read_only_style	= 'bg:#191970 fg:red'
truncation_length = 5
truncation_symbol = '…/'
truncate_to_repo = false
format = '$path[$read_only]($read_only_style)'


[fill]
symbol = ' '


[git_branch]
format = '  $branch '


[git_commit]
format = ' $tag '
tag_disabled = false
only_detached = false
tag_symbol = '󰓻'


[git_status]
format = '[ $conflicted$staged$modified$renamed$deleted$untracked$stashed$ahead$behind](bg:#330066 fg:#ffaa00 bold)'
conflicted = ' '
staged = '${count} '
modified = '${count}󰙏 '
renamed = '${count} '
deleted = '${count} '
untracked = '${count}? '
stashed = '${count} '
ahead = '${count} '
behind = '${count} '


[hostname]
ssh_only = false
format = '$hostname'
disabled = false


[jobs]
symbol = 'jobs: '
number_threshold = 1
symbol_threshold = 1


[python]
symbol = ''
format = ' ${symbol} ${version}\($virtualenv\) '


[rlang]
symbol = 'R'
format = ' $symbol $version '


[ruby]
symbol = ''
format = ' $symbol $version '


[username]
format = '$user'
show_always = true
EOF


# Reload
source ~/.zshrc

```

## Conclusion (at least for now)

That is it, guys. Then, we have to install Chrome, other browsers, Spotify, other Flatpaks, and customize wallpapers, fonts, etc. There is a long road, but the focus of this article was to work on a solid base with some modern features I was lacking in the previous Ubuntu version. This article will be updated regularly, so, come back in a few weeks, and bye!

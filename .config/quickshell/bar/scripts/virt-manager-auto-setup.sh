#!/bin/bash

# Virt-Manager Auto Setup Script for CachyOS Hyprland
# This script automates the setup of virt-manager with proper networking and display scaling

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        exit 1
    fi
}

# Function to check if we're on CachyOS
check_system() {
    print_status "Checking system compatibility..."
    
    if ! grep -q "CachyOS" /etc/os-release 2>/dev/null; then
        print_warning "This script is designed for CachyOS. Continue anyway? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check if paru or yay is available
    if command -v paru &> /dev/null; then
        PACKAGE_MANAGER="paru"
    elif command -v yay &> /dev/null; then
        PACKAGE_MANAGER="yay"
    else
        print_error "Neither paru nor yay found. Please install one of them first."
        exit 1
    fi
    
    print_success "Using package manager: $PACKAGE_MANAGER"
}

# Function to install packages
install_packages() {
    print_status "Installing virtualization packages..."
    
    # Core packages
    local core_packages=(
        "qemu-base"
        "qemu-desktop"
        "libvirt"
        "edk2-ovmf"
        "virt-manager"
        "virt-viewer"
        "bridge-utils"
        "dnsmasq"
        "qemu-guest-agent"
        "spice"
        "spice-gtk"
        "spice-protocol"
        "libguestfs"
        "guestfs-tools"
    )
    
    # Optional packages
    local optional_packages=(
        "pulseaudio-alsa"
        "spice-vdagent"
        "usbredir"
        "virtio-win"
    )
    
    print_status "Installing core packages..."
    $PACKAGE_MANAGER -S --noconfirm "${core_packages[@]}"
    
    print_status "Installing optional packages..."
    $PACKAGE_MANAGER -S --noconfirm "${optional_packages[@]}"
    
    print_success "All packages installed successfully"
}

# Function to configure libvirt
configure_libvirt() {
    print_status "Configuring libvirt..."
    
    # Start and enable libvirtd
    sudo systemctl start libvirtd
    sudo systemctl enable libvirtd
    
    # Check if default network is already active
    if sudo virsh net-list --active | grep -q "default"; then
        print_status "Default network is already active"
    else
        print_status "Starting default network..."
        sudo virsh net-start default
    fi
    
    # Check if default network is already set to autostart
    if sudo virsh net-list --all | grep "default" | grep -q "autostart"; then
        print_status "Default network is already set to autostart"
    else
        print_status "Setting default network to autostart..."
        sudo virsh net-autostart default
    fi
    
    # Add user to libvirt and kvm groups (only if not already added)
    if ! groups "$USER" | grep -q libvirt; then
        print_status "Adding user to libvirt group..."
        sudo usermod -a -G libvirt "$USER"
    else
        print_status "User is already in libvirt group"
    fi
    
    if ! groups "$USER" | grep -q kvm; then
        print_status "Adding user to kvm group..."
        sudo usermod -a -G kvm "$USER"
    else
        print_status "User is already in kvm group"
    fi
    
    print_success "libvirt configured successfully"
}

# Function to check and load KVM modules
setup_kvm() {
    print_status "Setting up KVM acceleration..."
    
    # Check if KVM is available
    if ! lsmod | grep -q kvm; then
        # Try to load KVM modules
        if grep -q "vmx" /proc/cpuinfo; then
            sudo modprobe kvm_intel
        elif grep -q "svm" /proc/cpuinfo; then
            sudo modprobe kvm_amd
        else
            print_warning "KVM acceleration not available on this system"
            return
        fi
        sudo modprobe kvm
    fi
    
    print_success "KVM acceleration enabled"
}

# Function to create network bridge (optional)
setup_network_bridge() {
    print_status "Setting up network bridge..."
    
    # Check if netctl is being used
    if ! command -v netctl &> /dev/null; then
        print_warning "netctl not found. Skipping bridge setup."
        return
    fi
    
    # Find the main network interface
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [[ -z "$main_interface" ]]; then
        print_warning "Could not determine main network interface. Skipping bridge setup."
        return
    fi
    
    print_status "Found main interface: $main_interface"
    
    # Create bridge configuration
    sudo tee /etc/netctl/bridge0 > /dev/null <<EOF
Description="Bridge connection for virt-manager"
Interface=br0
Connection=bridge
BindsToInterfaces=($main_interface)
IP=dhcp
EOF
    
    # Backup current network configuration
    if [[ -f "/etc/netctl/$main_interface" ]]; then
        sudo cp "/etc/netctl/$main_interface" "/etc/netctl/$main_interface.backup"
    fi
    
    print_warning "Bridge configuration created. You may need to manually switch to it later."
    print_status "To enable bridge: sudo netctl stop $main_interface && sudo netctl start bridge0"
}

# Function to configure Hyprland
configure_hyprland() {
    print_status "Configuring Hyprland for virtual machines..."
    
    local hyprland_config="$HOME/.config/hypr/hyprland.conf"
    local custom_config="$HOME/.config/hyprcustom/custom.conf"
    
    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$hyprland_config")"
    
    # Check if VM configuration already exists in main config
    if [[ -f "$hyprland_config" ]] && grep -q "QT_SCALE_FACTOR_ROUNDING_POLICY" "$hyprland_config"; then
        print_status "VM configuration already exists in main Hyprland config"
        return
    fi
    
    # Check if VM configuration already exists in custom config
    if [[ -f "$custom_config" ]] && grep -q "QT_SCALE_FACTOR_ROUNDING_POLICY" "$custom_config"; then
        print_status "VM configuration already exists in custom config"
        return
    fi
    
    # Check for existing environment variables to avoid conflicts
    local needs_gdk_scale=true
    local needs_xcursor_size=true
    
    if [[ -f "$custom_config" ]] && grep -q "GDK_SCALE" "$custom_config"; then
        print_status "GDK_SCALE already configured in custom.conf"
        needs_gdk_scale=false
    fi
    
    if [[ -f "$custom_config" ]] && grep -q "XCURSOR_SIZE" "$custom_config"; then
        print_status "XCURSOR_SIZE already configured in custom.conf"
        needs_xcursor_size=false
    fi
    
    # Add VM configuration to custom config (preferred) or main config
    local target_config="$custom_config"
    if [[ ! -f "$custom_config" ]]; then
        target_config="$hyprland_config"
        print_status "Adding VM configuration to main Hyprland config"
    else
        print_status "Adding VM configuration to custom.conf"
    fi
    
    # Create custom config directory if needed
    mkdir -p "$(dirname "$target_config")"
    
    # Add VM configuration with conditional variables
    {
        echo ""
        echo "# Virtual machine display scaling"
        echo "env = QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough"
        if [[ "$needs_gdk_scale" == true ]]; then
            echo "env = GDK_SCALE=1"
        fi
        if [[ "$needs_xcursor_size" == true ]]; then
            echo "env = XCURSOR_SIZE=24"
        fi
        echo ""
        echo "# For better VM performance"
        echo "env = QEMU_AUDIO_DRV=pa"
    } >> "$target_config"
    
    print_success "Hyprland configured for virtual machines"
}

# Function to create VM display setup script
create_vm_script() {
    print_status "Creating VM display setup script..."
    
    local script_dir="$HOME/.local/bin"
    local script_path="$script_dir/vm-display-setup.sh"
    
    mkdir -p "$script_dir"
    
    cat > "$script_path" <<'EOF'
#!/bin/bash
# VM Display Setup Script for Hyprland

# Set display scaling for VMs
export GDK_SCALE=1
export QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough

# Launch virt-manager with proper scaling
virt-manager
EOF
    
    chmod +x "$script_path"
    
    print_success "VM display setup script created at $script_path"
}

# Function to create ISO directory and download Arch ISO
setup_iso_directory() {
    print_status "Setting up ISO directory..."
    
    local iso_dir="$HOME/Downloads/iso"
    mkdir -p "$iso_dir"
    
    print_status "Would you like to download the latest Arch ISO? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        print_status "Downloading Arch ISO..."
        cd "$iso_dir"
        
        # Try multiple methods to get the latest Arch ISO
        local iso_url=""
        
        # Method 1: Try the official download page
        iso_url=$(curl -s "https://archlinux.org/download/" | grep -o 'https://[^"]*archlinux-x86_64.iso' | head -n1)
        
        # Method 2: If that fails, try the releases page
        if [[ -z "$iso_url" ]]; then
            iso_url=$(curl -s "https://archlinux.org/releng/releases/" | grep -o 'https://[^"]*archlinux-x86_64.iso' | head -n1)
        fi
        
        # Method 3: Use a known mirror
        if [[ -z "$iso_url" ]]; then
            iso_url="https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso"
        fi
        
        if [[ -n "$iso_url" ]]; then
            print_status "Downloading from: $iso_url"
            if wget -c "$iso_url"; then
                print_success "Arch ISO downloaded to $iso_dir"
            else
                print_warning "Download failed. You can manually download it from:"
                print_status "https://archlinux.org/download/"
                print_status "Or use: paru -S archiso"
            fi
        else
            print_warning "Could not find Arch ISO URL. You can manually download it from:"
            print_status "https://archlinux.org/download/"
            print_status "Or use: paru -S archiso"
        fi
    fi
}

# Function to optimize performance
optimize_performance() {
    print_status "Optimizing performance..."
    
    # Set CPU governor to performance
    if [[ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors" ]]; then
        if grep -q "performance" "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"; then
            echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
            print_success "CPU governor set to performance"
        fi
    fi
    
    # Create performance configuration
    sudo tee /etc/default/cpupower > /dev/null <<EOF
GOVERNOR="performance"
EOF
}



# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    # Check if services are running
    if systemctl is-active --quiet libvirtd; then
        print_success "libvirtd service is running"
    else
        print_error "libvirtd service is not running"
    fi
    
    # Check if user is in libvirt group
    if groups "$USER" | grep -q libvirt; then
        print_success "User is in libvirt group"
    else
        print_warning "User is not in libvirt group. You may need to log out and back in."
    fi
    
    # Check if KVM is available
    if lsmod | grep -q kvm; then
        print_success "KVM acceleration is available"
    else
        print_warning "KVM acceleration is not available"
    fi
    
    # Check if virt-manager is installed
    if command -v virt-manager &> /dev/null; then
        print_success "virt-manager is installed"
    else
        print_error "virt-manager is not installed"
    fi
}

# Function to show next steps
show_next_steps() {
    print_status "Setup complete! Here are your next steps:"
    echo
    echo "1. Log out and log back in to apply group changes"
    echo "2. Launch virt-manager from your application menu or run: $HOME/.local/bin/vm-display-setup.sh"
    echo "3. Configure your first VM with the Arch ISO"
    echo "4. If you created a bridge, switch to it: sudo netctl stop <interface> && sudo netctl start bridge0"
    echo
    echo "For troubleshooting, check the guide at: $HOME/virt-manager-setup-guide.md"
}

# Main execution
main() {
    echo "=========================================="
    echo "Virt-Manager Auto Setup for CachyOS"
    echo "=========================================="
    echo
    
    check_root
    check_system
    
    print_status "Starting automated setup..."
    echo
    
    install_packages
    echo
    
    configure_libvirt
    echo
    
    setup_kvm
    echo
    
    setup_network_bridge
    echo
    
    #configure_hyprland - commented because everything is already setup by default in hyprviz.lua
    #echo
    
    create_vm_script
    echo
    
    setup_iso_directory
    echo
    
    optimize_performance
    echo
    
    verify_installation
    echo
    
    show_next_steps
    echo
    
    print_success "Setup completed successfully!"
}

# Run main function
main "$@" 

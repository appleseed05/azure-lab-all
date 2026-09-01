#cloud-config
package_update: true
package_upgrade: true

packages:
  - xfce4
  - xfce4-goodies
  - xrdp
  - firefox
  - mousepad
  - thunar-archive-plugin
  - gnome-keyring

runcmd:
  # Configure XFCE as default session for XRDP
  - echo "xfce4-session" > /home/${admin_username}/.xsession
  - chown ${admin_username}:${admin_username} /home/${admin_username}/.xsession
  # Add xrdp to group ssl-cert (certificates access)
  - usermod -aG ssl-cert xrdp
  # Enable xrdp when vm start then reboot to apply updates
  - systemctl enable xrdp
  - reboot

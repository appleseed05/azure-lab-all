#cloud-config
package_update: false

write_files:
  - path: /root/nginx-default-site.conf
    owner: root:root
    permissions: '0644'
    content: |
      server {
          listen 80 default_server;
          listen [::]:80 default_server;
          server_name _;

          add_header X-Origin-Server   $server_addr always;
          add_header X-Seen-Client-IP  $remote_addr always;

          location / {
              default_type text/plain;
              return 200 "===== NGINX origin (internal VM) =====\nOrigin server IP      : $server_addr:$server_port\nRequest received from : $remote_addr:$remote_port   \nOriginal client (XFF) : $http_x_forwarded_for\nHost header           : $host\nURI                   : $request_uri\nDate                  : $time_iso8601\n";
          }
      }

runcmd:
  # Wait until egress via VyOS actually works, then install nginx
  - |
    for i in $(seq 1 60); do
      if apt-get update -y; then
        echo "apt-get update OK on attempt $i"
        break
      fi
      echo "apt-get update failed (attempt $i), retrying in 20s..."
      sleep 20
    done
  - DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
  - cp /root/nginx-default-site.conf /etc/nginx/sites-available/default
  - ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  # nginx is already running (started by the package postinst) with the stock
  # config, so `enable --now` would be a no-op: restart to load the new site.
  - systemctl enable nginx
  - nginx -t && systemctl restart nginx

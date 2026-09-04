#cloud-config
# Observability VM: Loki (log store) + Grafana (UI) + Alloy (collector).
#
# It sits in the external subnet but is deliberately NOT in
# local.router_egress_allowed, so it has no direct Internet access - every
# download goes through Tinyproxy on the services VM. That is also why the
# Grafana signing key is fetched with an explicit -x proxy below: runcmd does
# NOT source /etc/environment, so the shell here has no http_proxy of its own.
package_update: false

write_files:
  - path: /etc/apt/apt.conf.d/00-lab-proxy
    owner: root:root
    permissions: '0644'
    content: |
      // Managed by cloud-init (cloud-init-obs.yaml.tpl).
      Acquire::http::Proxy "http://${proxy_ip}:${proxy_port}";
      Acquire::https::Proxy "http://${proxy_ip}:${proxy_port}";

  - path: /etc/chrony/conf.d/10-lab-ntp-client.conf
    owner: root:root
    permissions: '0644'
    content: |
      server ${ntp_ip} iburst

  - path: /root/99-lab-dns.yaml
    owner: root:root
    permissions: '0600'
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4-overrides:
              route-metric: 100
              use-dns: false
            nameservers:
              addresses: [${dns_ip}]
              search: [${dns_zone}]

  # --- Loki: single-binary, filesystem storage -------------------------------
  # schema v13 + tsdb is required for structured metadata, which is what the
  # OTLP ingestion path uses. Bound to loopback: Grafana and Alloy are local,
  # and nothing else should talk to Loki directly.
  - path: /root/loki-config.yml
    owner: root:root
    permissions: '0644'
    content: |
      auth_enabled: false

      server:
        http_listen_address: 127.0.0.1
        http_listen_port: 3100
        grpc_listen_address: 127.0.0.1
        grpc_listen_port: 9096
        log_level: warn

      common:
        instance_addr: 127.0.0.1
        path_prefix: /var/lib/loki
        storage:
          filesystem:
            chunks_directory: /var/lib/loki/chunks
            rules_directory: /var/lib/loki/rules
        replication_factor: 1
        ring:
          instance_addr: 127.0.0.1
          kvstore:
            store: inmemory

      schema_config:
        configs:
          - from: 2020-01-01
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h

      limits_config:
        retention_period: ${loki_retention}
        allow_structured_metadata: true
        volume_enabled: true

      compactor:
        working_directory: /var/lib/loki/compactor
        retention_enabled: true
        delete_request_store: filesystem

      # This VM cannot reach the Internet directly; leaving analytics on just
      # produces periodic failed-connection noise in the journal.
      analytics:
        reporting_enabled: false

  # --- Alloy: syslog in, Loki out --------------------------------------------
  - path: /root/config.alloy
    owner: root:root
    permissions: '0644'
    content: |
      // Syslog receiver for the whole lab: VyOS (kernel firewall + FRR/BGP),
      // and rsyslog/nginx forwarding from the services and application VMs.
      // RFC3164 because that is what VyOS and stock rsyslog emit.
      loki.source.syslog "lab" {
        listener {
          address       = "0.0.0.0:514"
          protocol      = "udp"
          syslog_format = "rfc3164"
          labels        = { job = "syslog" }
        }
        relabel_rules = loki.relabel.syslog_meta.rules
        forward_to    = [loki.write.local.receiver]
      }

      // Promote ONLY low-cardinality syslog fields to Loki labels.
      //
      // Do NOT add SRC/DST/SPT/DPT from the VyOS firewall lines here. Each
      // unique value would create a new Loki stream - thousands of them - and
      // that is the classic way to make Loki fall over. Those fields stay in
      // the log body and get extracted at query time, e.g.
      //   {app="kernel"} |= "FWD-filter-90-D" | pattern "<_>SRC=<src> DST=<dst><_>"
      loki.relabel "syslog_meta" {
        forward_to = []
        rule {
          source_labels = ["__syslog_message_hostname"]
          target_label  = "host"
        }
        rule {
          source_labels = ["__syslog_message_app_name"]
          target_label  = "app"
        }
        rule {
          source_labels = ["__syslog_message_severity"]
          target_label  = "severity"
        }
      }

      loki.write "local" {
        endpoint {
          url = "http://127.0.0.1:3100/loki/api/v1/push"
        }
      }

  # Alloy runs as the unprivileged 'alloy' user, which cannot bind port 514.
  # Grant just that capability rather than moving the lab to a non-standard port.
  - path: /etc/systemd/system/alloy.service.d/10-bind-syslog-port.conf
    owner: root:root
    permissions: '0644'
    content: |
      [Service]
      AmbientCapabilities=CAP_NET_BIND_SERVICE
      CapabilityBoundingSet=CAP_NET_BIND_SERVICE

  # --- Grafana: provision the Loki datasource ---------------------------------
  # A provisioning file, not grafana.ini: grafana.ini is a dpkg conffile and
  # replacing it would fight the package on every upgrade.
  - path: /root/loki-datasource.yaml
    owner: root:root
    permissions: '0644'
    content: |
      apiVersion: 1
      datasources:
        - name: Loki
          type: loki
          # Pinned so the provisioned dashboard can reference it. Safe on a
          # FRESH deploy only: adding a uid to an ALREADY-provisioned
          # datasource makes Grafana fail with "Datasource provisioning error:
          # data source not found" and refuse to start at all (the provisioning
          # module failure cascades into the HTTP server never coming up).
          uid: loki
          access: proxy
          url: http://127.0.0.1:3100
          isDefault: true
          editable: true
          jsonData:
            maxLines: 5000

  # --- Grafana dashboard: provider + the dashboard itself --------------------
  - path: /root/grafana-dashboards.yaml
    owner: root:root
    permissions: '0644'
    content: |
      apiVersion: 1
      providers:
        - name: lab
          orgId: 1
          folder: Lab
          type: file
          disableDeletion: false
          updateIntervalSeconds: 30
          allowUiUpdates: true
          options:
            path: /var/lib/grafana/dashboards

  # "Lab Logs": $host / $app dropdowns + a $search regex box, a stacked volume
  # graph, the log panel, and two firewall-drop breakdowns.
  #
  # NOTE on the LogQL `pattern` stages below: consecutive captures are ILLEGAL
  # ("found consecutive capture '<dst><_>'"), so there must be literal text
  # between them - hence "... DST=<dst> LEN=<_>" rather than "DST=<dst><_>".
  - path: /root/lab-logs.json
    owner: root:root
    permissions: '0644'
    content: |
      {
        "uid": "lab-logs",
        "title": "Lab Logs",
        "tags": [
          "lab",
          "loki"
        ],
        "timezone": "browser",
        "schemaVersion": 39,
        "version": 1,
        "editable": true,
        "refresh": "1m",
        "time": {
          "from": "now-1h",
          "to": "now"
        },
        "templating": {
          "list": [
            {
              "name": "host",
              "label": "Host",
              "type": "query",
              "datasource": {
                "type": "loki",
                "uid": "loki"
              },
              "definition": "label_values(host)",
              "query": {
                "label": "host",
                "refId": "Loki-host"
              },
              "refresh": 1,
              "includeAll": true,
              "allValue": ".*",
              "multi": true,
              "sort": 1,
              "current": {
                "text": [
                  "All"
                ],
                "value": [
                  ".*"
                ]
              },
              "options": [],
              "hide": 0
            },
            {
              "name": "app",
              "label": "App / origin",
              "type": "query",
              "datasource": {
                "type": "loki",
                "uid": "loki"
              },
              "definition": "label_values(app)",
              "query": {
                "label": "app",
                "refId": "Loki-app"
              },
              "refresh": 1,
              "includeAll": true,
              "allValue": ".*",
              "multi": true,
              "sort": 1,
              "current": {
                "text": [
                  "All"
                ],
                "value": [
                  ".*"
                ]
              },
              "options": [],
              "hide": 0
            },
            {
              "name": "search",
              "label": "Search (regex)",
              "type": "textbox",
              "query": "",
              "current": {
                "text": "",
                "value": ""
              },
              "hide": 0,
              "options": []
            }
          ]
        },
        "panels": [
          {
            "id": 1,
            "title": "Log volume by app",
            "type": "timeseries",
            "datasource": {
              "type": "loki",
              "uid": "loki"
            },
            "gridPos": {
              "x": 0,
              "y": 0,
              "w": 24,
              "h": 7
            },
            "targets": [
              {
                "refId": "A",
                "datasource": {
                  "type": "loki",
                  "uid": "loki"
                },
                "expr": "sum by (app) (count_over_time({job=\"syslog\", host=~\"$host\", app=~\"$app\"} |~ \"$search\" [$__interval]))",
                "queryType": "range",
                "legendFormat": "{{app}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "custom": {
                  "drawStyle": "bars",
                  "fillOpacity": 70,
                  "lineWidth": 0,
                  "stacking": {
                    "mode": "normal",
                    "group": "A"
                  }
                }
              },
              "overrides": []
            },
            "options": {
              "legend": {
                "displayMode": "list",
                "placement": "bottom",
                "showLegend": true
              },
              "tooltip": {
                "mode": "multi",
                "sort": "desc"
              }
            }
          },
          {
            "id": 2,
            "title": "Logs",
            "type": "logs",
            "datasource": {
              "type": "loki",
              "uid": "loki"
            },
            "gridPos": {
              "x": 0,
              "y": 7,
              "w": 24,
              "h": 14
            },
            "targets": [
              {
                "refId": "A",
                "datasource": {
                  "type": "loki",
                  "uid": "loki"
                },
                "expr": "{job=\"syslog\", host=~\"$host\", app=~\"$app\"} |~ \"$search\"",
                "queryType": "range"
              }
            ],
            "options": {
              "showTime": true,
              "showLabels": false,
              "showCommonLabels": false,
              "wrapLogMessage": true,
              "prettifyLogMessage": false,
              "enableLogDetails": true,
              "dedupStrategy": "none",
              "sortOrder": "Descending"
            }
          },
          {
            "id": 3,
            "title": "Firewall drops - top destinations",
            "type": "timeseries",
            "datasource": {
              "type": "loki",
              "uid": "loki"
            },
            "gridPos": {
              "x": 0,
              "y": 21,
              "w": 12,
              "h": 8
            },
            "targets": [
              {
                "refId": "A",
                "datasource": {
                  "type": "loki",
                  "uid": "loki"
                },
                "expr": "topk(10, sum by (dst) (count_over_time({app=\"kernel\"} |= \"FWD-filter-90-D\" | pattern \"<_>SRC=<src> DST=<dst> LEN=<_>\" [$__interval])))",
                "queryType": "range",
                "legendFormat": "{{dst}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "custom": {
                  "drawStyle": "bars",
                  "fillOpacity": 70,
                  "lineWidth": 0,
                  "stacking": {
                    "mode": "normal",
                    "group": "A"
                  }
                }
              },
              "overrides": []
            },
            "options": {
              "legend": {
                "displayMode": "list",
                "placement": "bottom",
                "showLegend": true
              },
              "tooltip": {
                "mode": "multi",
                "sort": "desc"
              }
            }
          },
          {
            "id": 4,
            "title": "Firewall drops - by source",
            "type": "timeseries",
            "datasource": {
              "type": "loki",
              "uid": "loki"
            },
            "gridPos": {
              "x": 12,
              "y": 21,
              "w": 12,
              "h": 8
            },
            "targets": [
              {
                "refId": "A",
                "datasource": {
                  "type": "loki",
                  "uid": "loki"
                },
                "expr": "sum by (src) (count_over_time({app=\"kernel\"} |= \"FWD-filter-90-D\" | pattern \"<_>SRC=<src> DST=<dst> LEN=<_>\" [$__interval]))",
                "queryType": "range",
                "legendFormat": "{{src}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "custom": {
                  "drawStyle": "bars",
                  "fillOpacity": 70,
                  "lineWidth": 0,
                  "stacking": {
                    "mode": "normal",
                    "group": "A"
                  }
                }
              },
              "overrides": []
            },
            "options": {
              "legend": {
                "displayMode": "list",
                "placement": "bottom",
                "showLegend": true
              },
              "tooltip": {
                "mode": "multi",
                "sort": "desc"
              }
            }
          }
        ]
      }

runcmd:
  # Wait until apt works through the proxy (see 00-lab-proxy above). Plain
  # `apt-get update` exits 0 even when every mirror is unreachable, so
  # Error-Mode=any is required or this loop breaks on the first attempt.
  - |
    for i in $(seq 1 60); do
      if apt-get update -y -o APT::Update::Error-Mode=any; then
        echo "apt-get update OK on attempt $i"
        break
      fi
      echo "apt-get update failed (attempt $i), proxy not up yet, retrying in 20s..."
      sleep 20
    done
  - DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gpg

  # --- Grafana APT repo -------------------------------------------------------
  # The key fetch needs the proxy passed explicitly: runcmd does not source
  # /etc/environment, so curl would otherwise try to go direct and be dropped
  # by the VyOS egress firewall.
  - install -d -m 0755 /etc/apt/keyrings
  - |
    curl -fsSL -x "http://${proxy_ip}:${proxy_port}" https://apt.grafana.com/gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
  - |
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
      > /etc/apt/sources.list.d/grafana.list
  - apt-get update -y -o APT::Update::Error-Mode=any
  # Unpinned on purpose for a lab. To pin: loki=3.7.7 grafana=13.2.0 alloy=1.19.2-1
  - DEBIAN_FRONTEND=noninteractive apt-get install -y loki grafana alloy

  # --- Loki -------------------------------------------------------------------
  - install -o root -g root -m 0644 /root/loki-config.yml /etc/loki/config.yml
  # Create the state dirs, THEN set ownership - never in one `install` call.
  # The loki package creates the user with primary group 'nogroup'; there is no
  # 'loki' group. `install -g loki` fails with "invalid group", the directories
  # are never created, and Loki then crash-loops on
  #   mkdir /var/lib/loki: permission denied
  # which looks like a config fault but is not. `chown loki:` (trailing colon)
  # uses the user's own primary group, whatever the package chose.
  - install -d -m 0755 /var/lib/loki /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor
  - chown -R loki: /var/lib/loki
  # Loki ships a real config validator - use it before starting.
  - loki -verify-config -config.file=/etc/loki/config.yml
  - systemctl enable loki
  - systemctl restart loki

  # --- Alloy ------------------------------------------------------------------
  - install -o root -g root -m 0644 /root/config.alloy /etc/alloy/config.alloy
  # Expose the Alloy pipeline UI on the lab network (default is loopback only).
  - echo 'CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"' >> /etc/default/alloy
  - systemctl daemon-reload
  # `alloy validate` checks component wiring and arguments, not just syntax -
  # the closest equivalent to named-checkconf. Verified against alloy 1.19.2.
  - alloy validate /etc/alloy/config.alloy
  - systemctl enable alloy
  - systemctl restart alloy

  # --- Grafana ----------------------------------------------------------------
  # Grafana 13 UNBUNDLED the core datasources: the binary ships only
  # alertmanager, cloudwatch, azuremonitor, testdata and graphite. Without the
  # loki plugin, provisioning still registers the datasource in the DB (the API
  # shows it, correctly marked default) but the UI silently omits it from the
  # picker, logging only:
  #   "Could not find plugin definition for data source" datasource_type=loki
  #
  # Grafana installs it itself via preinstall - see GF_PLUGINS_* below. All we
  # need here is the directory it installs into.
  - install -d -o grafana -g grafana -m 0755 /var/lib/grafana/plugins
  - install -o root -g grafana -m 0640 /root/loki-datasource.yaml /etc/grafana/provisioning/datasources/loki.yaml
  # No Internet from this VM: stop Grafana polling for updates/analytics.
  # Grafana MUST have the proxy in its environment. Grafana 13 unbundled the
  # core datasources and preinstalls them from grafana.com at startup; with no
  # egress each attempt blocks ~10s and the HTTP server never comes up (we saw
  # /api/health return 000 with 80+ restarts). With the proxy it pulls loki,
  # prometheus, elasticsearch, tempo etc. itself in seconds.
  # NO_PROXY must include 127.0.0.1 or Grafana's own calls to Loki would be
  # sent to Tinyproxy.
  #
  # PREINSTALL_DISABLED suppresses Grafana's built-in default plugin set, which
  # pulls 18 plugins / ~492 MB (prometheus, elasticsearch, influxdb, mssql,
  # mysql, tempo, jaeger, zipkin ...) of which this lab uses exactly one.
  # NOTE: `preinstall =` being empty in defaults.ini does NOT disable it - the
  # default list is compiled into the binary and only this flag suppresses it.
  # PREINSTALL_SYNC then installs just what we want, and does so BEFORE
  # startup, which is what datasource provisioning needs - the supported
  # alternative to shelling out to `grafana cli`.
  # Result: 61 MB instead of 492 MB. Adding metrics later? Append the id here,
  # e.g. GF_PLUGINS_PREINSTALL_SYNC=loki,grafana-lokiexplore-app,prometheus
  - |
    cat >> /etc/default/grafana-server <<'GFEOF'
    GF_ANALYTICS_REPORTING_ENABLED=false
    GF_ANALYTICS_CHECK_FOR_UPDATES=false
    http_proxy="http://${proxy_ip}:${proxy_port}"
    https_proxy="http://${proxy_ip}:${proxy_port}"
    HTTP_PROXY="http://${proxy_ip}:${proxy_port}"
    HTTPS_PROXY="http://${proxy_ip}:${proxy_port}"
    no_proxy="localhost,127.0.0.1,::1,169.254.169.254,${vnet_cidr},.internal.cloudapp.net,.lan"
    NO_PROXY="localhost,127.0.0.1,::1,169.254.169.254,${vnet_cidr},.internal.cloudapp.net,.lan"
    GF_PLUGINS_PREINSTALL_DISABLED=true
    GF_PLUGINS_PREINSTALL_SYNC=loki,grafana-lokiexplore-app
    GFEOF
  - install -d -o grafana -g grafana -m 0755 /var/lib/grafana/dashboards
  - install -o grafana -g grafana -m 0644 /root/lab-logs.json /var/lib/grafana/dashboards/lab-logs.json
  - install -o root -g grafana -m 0640 /root/grafana-dashboards.yaml /etc/grafana/provisioning/dashboards/lab.yaml
  - systemctl enable grafana-server
  - systemctl restart grafana-server

  # --- Assertions: none of these three ship a post-start self-check -----------
  - |
    sleep 8
    for svc in loki alloy grafana-server; do
      if systemctl is-active --quiet $svc; then
        echo "OK: $svc is running"
      else
        echo "ERROR: $svc failed to start"
        journalctl -u $svc -n 25 --no-pager
      fi
    done
    if curl -s -u admin:admin 'http://127.0.0.1:3000/api/search?type=dash-db' 2>/dev/null | grep -q 'lab-logs'; then
      echo "OK: the Lab Logs dashboard is provisioned"
    else
      echo "ERROR: dashboard not provisioned"
      ls -l /var/lib/grafana/dashboards /etc/grafana/provisioning/dashboards 2>&1
      journalctl -u grafana-server -n 15 --no-pager | grep -i provision
    fi
    if curl -s -u admin:admin http://127.0.0.1:3000/api/frontend/settings 2>/dev/null | grep -q '"type":"loki"'; then
      echo "OK: the Loki datasource is visible to the Grafana frontend"
    else
      echo "ERROR: Loki registered but not in the frontend picker - the 'loki' plugin is probably missing"
      ls /var/lib/grafana/plugins 2>&1
      journalctl -u grafana-server -n 15 --no-pager | grep -i plugin
    fi
    if curl -s -o /dev/null -w '%%{http_code}' http://127.0.0.1:3100/ready | grep -q 200; then
      echo "OK: loki /ready returned 200"
    else
      echo "ERROR: loki is not ready - check /var/lib/loki exists and is owned by the loki user"
      ls -ld /var/lib/loki 2>&1
      journalctl -u loki -n 15 --no-pager
    fi
    if ss -ulnp 2>/dev/null | grep -q ':514'; then
      echo "OK: syslog listener bound on udp/514"
    else
      echo "ERROR: nothing listening on udp/514 - check the CAP_NET_BIND_SERVICE drop-in"
      ss -ulnp 2>/dev/null | head
    fi

  # --- NTP + DNS last (same ordering rule as the other VMs) -------------------
  - sed -i 's|^refclock PHC|#refclock PHC|' /etc/chrony/chrony.conf
  - systemctl restart chrony
  - install -o root -g root -m 0600 /root/99-lab-dns.yaml /etc/netplan/99-lab-dns.yaml
  - netplan generate
  - netplan apply

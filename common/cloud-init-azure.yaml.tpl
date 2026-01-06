#cloud-config
package_update: true
package_upgrade: true

ssh_pwauth: false
disable_root: true

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - wget
  - gpg
  - gnupg
  - lsb-release
  - vim
  - software-properties-common
  - iptables-persistent
  - jq
  - unzip
  - git
  - htop

users:
  - name: ${username}
    gecos: "Application User"
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
%{ for ssh_key in public_ssh_keys ~}
      - ${ssh_key}
%{ endfor ~}
    lock_passwd: true
    groups: sudo, docker

write_files:
  - path: /etc/iptables/rules.v4
    permissions: '0644'
    content: |
      *filter
      :INPUT DROP [0:0]
      :FORWARD DROP [0:0]
      :OUTPUT ACCEPT [0:0]
      :DOCKER - [0:0]
      :DOCKER-USER - [0:0]
      :DOCKER-ISOLATION-STAGE-1 - [0:0]
      :DOCKER-ISOLATION-STAGE-2 - [0:0]
      -A INPUT -i lo -j ACCEPT
      -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 3/min --limit-burst 3 -j ACCEPT
      -A INPUT -p tcp --dport 80 -j ACCEPT
      -A INPUT -p tcp --dport 443 -j ACCEPT
      -A INPUT -p tcp --dport 3000 -j ACCEPT
      -A INPUT -p tcp --dport 5000 -j ACCEPT
      -A INPUT -p tcp --dport 5001 -j ACCEPT
      -A INPUT -p udp --sport 53 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
      -A INPUT -p tcp --sport 53 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
      -A INPUT -i eth0 -s 10.0.0.0/8 -p tcp --dport 2377 -j ACCEPT
      -A INPUT -i eth0 -s 10.0.0.0/8 -p tcp --dport 7946 -j ACCEPT
      -A INPUT -i eth0 -s 10.0.0.0/8 -p udp --dport 7946 -j ACCEPT
      -A INPUT -i eth0 -s 10.0.0.0/8 -p udp --dport 4789 -j ACCEPT
      -A INPUT -i eth0 -p tcp --dport 2377 -j DROP
      -A INPUT -i eth0 -p tcp --dport 7946 -j DROP
      -A INPUT -i eth0 -p udp --dport 7946 -j DROP
      -A INPUT -i eth0 -p udp --dport 4789 -j DROP
      -A FORWARD -i docker0 -j ACCEPT
      -A FORWARD -o docker0 -j ACCEPT
      -A OUTPUT -p udp --dport 53 -j ACCEPT
      -A OUTPUT -p tcp --dport 53 -j ACCEPT
      -A FORWARD -o docker_gwbridge -j DOCKER
      -A FORWARD -i docker_gwbridge -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      -A FORWARD -o docker0 -j DOCKER
      -A FORWARD -i docker0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      -A DOCKER-ISOLATION-STAGE-1 -j RETURN
      -A DOCKER-ISOLATION-STAGE-2 -j RETURN
      -I FORWARD -j DOCKER-ISOLATION-STAGE-1
      -A FORWARD -j DOCKER-USER
      -A FORWARD -j DOCKER
      -A DOCKER-USER -m conntrack --ctstate NEW -m limit --limit 10/sec --limit-burst 20 -j ACCEPT
      -A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
      -A DOCKER-USER -j RETURN
      -A INPUT -p icmp -m limit --limit 1/sec --limit-burst 5 -j ACCEPT
      -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables dropped: " --log-level 7
      -A FORWARD -j DROP
      -A INPUT -j DROP
      COMMIT

  - path: /opt/omis-pc/.env.example
    permissions: '0644'
    content: |
      # Container Registry
      REGISTRY=your-registry.azurecr.io

      # Image Tags
      FE_TAG=latest
      BE_TAG=latest
      CSV_TAG=latest

      # Domain (optional, for Caddy)
      DOMAIN=localhost

      # Database Connection
      DATABASE_URL=postgresql://omispcadmin:password@db-host:5432/omis_pc_db?sslmode=require

      # Application Configuration
      NODE_ENV=production
      STAGE_ENV=development
      BE_PORT=5000
      BE_WS_PORT=5001

      # JWT Configuration
      JWT_SECRET=your-jwt-secret-change-this
      JWT_TOKEN_LIFETIME=24h

      # Frontend URL
      WEB_CLIENT_BASE_URL=http://localhost:3000

      # Backend Service URLs
      API_HEALTH_URL=http://localhost:5000/api/health
      SPRING_BACKEND_BASE_URL=http://csvtomdb:8080

  - path: /opt/omis-pc/docker-compose.yml
    permissions: '0644'
    content: |
      version: '3.8'

      services:
        frontend:
          image: ${REGISTRY}/omis-pc/fe:${FE_TAG:-latest}
          container_name: frontend
          restart: unless-stopped
          ports:
            - "3000:3000"
          env_file:
            - .env
          networks:
            - omis-pc-network

        backend:
          image: ${REGISTRY}/omis-pc/be:${BE_TAG:-latest}
          container_name: backend
          restart: unless-stopped
          ports:
            - "5000:5000"
            - "5001:5001"
          env_file:
            - .env
          networks:
            - omis-pc-network
          depends_on:
            - csvtomdb

        csvtomdb:
          image: ${REGISTRY}/omis-pc/csvtomdb-service:${CSV_TAG:-latest}
          container_name: csvtomdb
          restart: unless-stopped
          expose:
            - "8080"
          env_file:
            - .env
          networks:
            - omis-pc-network

      networks:
        omis-pc-network:
          driver: bridge

  - path: /opt/omis-pc/deploy.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e

      SERVICE=$1
      TAG=$2

      if [ -z "$SERVICE" ] || [ -z "$TAG" ]; then
          echo "Usage: ./deploy.sh <service> <tag>"
          echo "Services: frontend, backend, csvtomdb, all"
          exit 1
      fi

      cd /opt/omis-pc

      if [ "$SERVICE" == "all" ]; then
          docker compose pull
          docker compose up -d
      else
          case $SERVICE in
              frontend) sed -i "s/FE_TAG=.*/FE_TAG=$TAG/" .env ;;
              backend)  sed -i "s/BE_TAG=.*/BE_TAG=$TAG/" .env ;;
              csvtomdb) sed -i "s/CSV_TAG=.*/CSV_TAG=$TAG/" .env ;;
              *)
                  echo "Unknown service: $SERVICE"
                  exit 1
                  ;;
          esac
          docker compose pull $SERVICE
          docker compose up -d --no-deps $SERVICE
      fi

      echo "Deployed $SERVICE:$TAG"
      docker compose ps

runcmd:
  - set -e
  - DOCKER_VERSION=5:27.5.1-1~ubuntu.22.04~jammy

  # Install Docker
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  - chmod a+r /etc/apt/keyrings/docker.asc
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  - apt-get update -y
  - apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-buildx-plugin docker-compose-plugin
  - systemctl start docker
  - systemctl enable docker

  # Apply iptables rules
  - iptables-restore < /etc/iptables/rules.v4

  # Install Azure CLI
  - curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

  # Set ownership of app directory
  - chown -R ${username}:${username} /opt/omis-pc

final_message: "OMIS Product Configurator VM is ready for deployment!"

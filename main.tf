locals {
  server_config = {
    ipv4_address = yandex_compute_instance.server_node.network_interface[0].ip_address
    hostname     = "server.kubernetes.local"
    fqdn         = "server"
    pod_subnet   = "10.200.0.0/24"
  }

  workers_configs = [
    for i in range(var.vm_count) : {
      ipv4_address = yandex_compute_instance.worker_nodes[i].network_interface[0].ip_address
      hostname     = "node-${i+1}.kubernetes.local"
      fqdn         = "node-${i+1}"
      pod_subnet   = "10.200.${i+1}.0/24"
    }
  ]
}


# Сеть и подсеть
resource "yandex_vpc_network" "cluster_network" {
  name = var.network_name
}

resource "yandex_vpc_subnet" "cluster_subnet" {
  name           = var.subnet_name
  zone           = var.zone
  network_id     = yandex_vpc_network.cluster_network.id
  v4_cidr_blocks = [var.subnet_cidr]
}

# Security Group для внутреннего трафика
resource "yandex_vpc_security_group" "internal_sg" {
  name        = "internal-security-group"
  network_id  = yandex_vpc_network.cluster_network.id
  description = "Security group for internal cluster communication"

  ingress {
    protocol       = "ANY"
    description    = "Internal communication"
    v4_cidr_blocks = [var.subnet_cidr]
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outgoing traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group для SSH доступа
resource "yandex_vpc_security_group" "ssh_sg" {
  name        = "ssh-security-group"
  network_id  = yandex_vpc_network.cluster_network.id
  description = "Security group for SSH access"

  ingress {
    protocol       = "TCP"
    description    = "SSH access"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Публичный SSH ключ
resource "yandex_compute_instance" "jump_node" {
  name        = "admin-node"
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = var.jump_node_image_id
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.cluster_subnet.id
    nat       = true
    security_group_ids = [
      yandex_vpc_security_group.internal_sg.id,
      yandex_vpc_security_group.ssh_sg.id
    ]
  }

    metadata = {
        user-data = <<-EOF
        #cloud-config
        users:
            - name: max
              groups: sudo
              shell: /bin/bash
              sudo: ['ALL=(ALL) NOPASSWD:ALL']
              ssh-authorized-keys:
                - ${file(var.ssh_public_key)}

        package_update: true
        package_upgrade: true
        packages:
            - curl
            - wget
            - net-tools
            - htop
            - vim
            - openssl
            - git
        EOF
    }
}

# Серверная нода
resource "yandex_compute_instance" "server_node" {
  name        = "server-node"
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores  = 4
    memory = 8
  }

  boot_disk {
    initialize_params {
      image_id = var.server_node_image_id
      size     = 40
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.cluster_subnet.id
    security_group_ids = [
      yandex_vpc_security_group.internal_sg.id,
      yandex_vpc_security_group.ssh_sg.id
    ]
  }

    metadata = {
        user-data = <<-EOF
        #cloud-config
        users:
            - name: max
              groups: sudo
              shell: /bin/bash
              sudo: ['ALL=(ALL) NOPASSWD:ALL']
              ssh-authorized-keys:
                - ${file(var.ssh_public_key)}
        EOF
    }
}

# Рабочие ноды (создаются в цикле)
resource "yandex_compute_instance" "worker_nodes" {
  count       = var.vm_count
  name        = "worker-node-${count.index + 1}"
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = var.worker_node_image_id
      size     = 30
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.cluster_subnet.id
    security_group_ids = [
      yandex_vpc_security_group.internal_sg.id,
      yandex_vpc_security_group.ssh_sg.id
    ]
  }

    metadata = {
        user-data = <<-EOF
        #cloud-config
        users:
            - name: max
              groups: sudo
              shell: /bin/bash
              sudo: ['ALL=(ALL) NOPASSWD:ALL']
              ssh-authorized-keys:
                - ${file(var.ssh_public_key)}
        EOF
    }
}

# kubernetes-setup.tf

resource "null_resource" "jumpbox_setup" {
  depends_on = [yandex_compute_instance.jump_node]

  triggers = {
    # Перезапускать при изменении IP адреса jump host
    jump_host_ip = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
  }

    connection {
        type        = "ssh"
        user        = "max"
        private_key = file(var.ssh_private_key)
        host        = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
    }

    # Provisioner для выполнения команд на jump host
    provisioner "remote-exec" {
        inline = [
        # Создаем директории
        "sudo mkdir -p /opt/kubernetes/downloads/client",
        "sudo mkdir -p /opt/kubernetes/downloads/cni-plugins", 
        "sudo mkdir -p /opt/kubernetes/downloads/controller",
        "sudo mkdir -p /opt/kubernetes/downloads/worker",
        "sudo chown -R max:max /opt/kubernetes",
        "cd /opt/kubernetes",
        
        # ===== 1. Скачивание всех компонентов =====
        "# Kubernetes компоненты",
        "wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kubectl",
        "wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kube-apiserver",
        "wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kube-controller-manager",
        "wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kube-scheduler",
        "wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kube-proxy",
        "wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kubelet",
        
        "# CRI инструменты",
        "wget -q https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.32.0/crictl-v1.32.0-linux-amd64.tar.gz",
        
        "# Container runtime",
        "wget -q https://github.com/opencontainers/runc/releases/download/v1.3.0-rc.1/runc.amd64",
        "wget -q https://github.com/containerd/containerd/releases/download/v2.1.0-beta.0/containerd-2.1.0-beta.0-linux-amd64.tar.gz",
        
        "# CNI плагины",
        "wget -q https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-amd64-v1.6.2.tgz",
        
        "# etcd",
        "wget -q https://github.com/etcd-io/etcd/releases/download/v3.6.0-rc.3/etcd-v3.6.0-rc.3-linux-amd64.tar.gz",
        
        "# Проверяем что все скачалось",
        "echo '=== Скачанные файлы ==='",
        "ls -la",
        "echo '========================'",
        
        # ===== 2. Распаковка и организация =====
        "# Определяем архитектуру",
        "ARCH=$(dpkg --print-architecture)",
        "echo 'Архитектура: $ARCH'",
        
        "# CRI tools",
        "tar -xzf crictl-v1.32.0-linux-$ARCH.tar.gz -C downloads/worker/",
        
        "# Containerd",
        "tar -xzf containerd-2.1.0-beta.0-linux-$ARCH.tar.gz --strip-components 1 -C downloads/worker/",
        
        "# CNI плагины",
        "tar -xzf cni-plugins-linux-$ARCH-v1.6.2.tgz -C downloads/cni-plugins/",
        
        "# etcd",
        "tar -xzf etcd-v3.6.0-rc.3-linux-$ARCH.tar.gz -C downloads/ \\",
        "  --strip-components 1 \\",
        "  etcd-v3.6.0-rc.3-linux-$ARCH/etcdctl \\",
        "  etcd-v3.6.0-rc.3-linux-$ARCH/etcd",
        
        "# Перемещаем бинарные файлы в соответствующие директории",
        "mv etcdctl downloads/client/",
        "mv kubectl downloads/client/",
        
        "mv etcd downloads/controller/",
        "mv kube-apiserver downloads/controller/",
        "mv kube-controller-manager downloads/controller/",
        "mv kube-scheduler downloads/controller/",
        
        "mv kubelet downloads/worker/",
        "mv kube-proxy downloads/worker/",
        "mv runc.$ARCH downloads/worker/runc",
        
        "# Удаляем архивные файлы",
        "rm -f *.gz *.tgz",
        "echo '=== Очистка архивов завершена ==='",
        
        "# Делаем все бинарные файлы исполняемыми",
        "chmod +x downloads/client/*",
        "chmod +x downloads/cni-plugins/*",
        "chmod +x downloads/controller/*",
        "chmod +x downloads/worker/*",
        
        "# Проверяем результат",
        "echo '=== Итоговая структура директорий ==='",
        "find downloads/ -type f -executable | sort",
        "echo '=== Версии компонентов ==='",
        "downloads/client/kubectl version --client 2>/dev/null | head -2",
        "downloads/controller/etcd --version | head -2",
        "echo 'Настройка завершена!'",

        "echo '=== Настройка kubectl ==='",
        "export PATH=/opt/kubernetes/downloads/client:/opt/kubernetes/downloads/controller:/opt/kubernetes/downloads/worker:$PATH",
        "echo '=== Настройка kubectl завершена ==='",
        "echo $(kubectl version --client)"
        ]
    }
}

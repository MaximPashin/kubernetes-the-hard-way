locals {
  server_config = {
    ipv4_address = yandex_compute_instance.server_node.network_interface[0].ip_address
    hostname     = "server"
    fqdn         = "server.kubernetes.local"
    pod_subnet   = "10.200.0.0/24"
  }

  workers_configs = [
    for i in range(var.vm_count) : {
      ipv4_address = yandex_compute_instance.worker_nodes[i].network_interface[0].ip_address
      hostname     = "node-${i+1}"
      fqdn         = "node-${i+1}.kubernetes.local"
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
            - name: admin
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
            - name: admin
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
            - name: admin
              groups: sudo
              shell: /bin/bash
              sudo: ['ALL=(ALL) NOPASSWD:ALL']
              ssh-authorized-keys:
                - ${file(var.ssh_public_key)}
        EOF
    }
}

resource "null_resource" "local_setup" {
    depends_on = [
        yandex_compute_instance.jump_node,
        yandex_compute_instance.server_node,
        yandex_compute_instance.worker_nodes,
    ]

    # Provisioner для выполнения команд на jump host
    provisioner "local-exec" {
        command = <<-EOT
            # Создаем директории
            mkdir -p ${path.module}/downloads/client
            mkdir -p ${path.module}/downloads/cni-plugins
            mkdir -p ${path.module}/downloads/controller
            mkdir -p ${path.module}/downloads/worker
            cd ${path.module}

            # ===== 1. Скачивание всех компонентов =====
            # Kubernetes компоненты
            wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kubectl
            wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kube-apiserver
            wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kube-controller-manager
            wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kube-scheduler
            wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kube-proxy
            wget -q https://dl.k8s.io/v1.32.3/bin/linux/amd64/kubelet
            
            # CRI инструменты
            wget -q https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.32.0/crictl-v1.32.0-linux-amd64.tar.gz
            
            # Container runtime
            wget -q https://github.com/opencontainers/runc/releases/download/v1.3.0-rc.1/runc.amd64
            wget -q https://github.com/containerd/containerd/releases/download/v2.1.0-beta.0/containerd-2.1.0-beta.0-linux-amd64.tar.gz
            
            # CNI плагины
            wget -q https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-amd64-v1.6.2.tgz
            
            # etcd
            wget -q https://github.com/etcd-io/etcd/releases/download/v3.6.0-rc.3/etcd-v3.6.0-rc.3-linux-amd64.tar.gz
            
            # Проверяем что все скачалось
            echo '=== Скачанные файлы ==='
            ls -la
            echo '========================'
            
            # ===== 2. Распаковка и организация =====
            # Определяем архитектуру
            ARCH=$(dpkg --print-architecture)
            echo 'Архитектура: $ARCH'
            
            # CRI tools
            tar -xzf crictl-v1.32.0-linux-$ARCH.tar.gz -C downloads/worker/
            
            # Containerd
            tar -xzf containerd-2.1.0-beta.0-linux-$ARCH.tar.gz --strip-components 1 -C downloads/worker/
            
            # CNI плагины
            tar -xzf cni-plugins-linux-$ARCH-v1.6.2.tgz -C downloads/cni-plugins/
            
            # etcd
            tar -xzf etcd-v3.6.0-rc.3-linux-$ARCH.tar.gz -C downloads/ \\
              --strip-components 1 \\
              etcd-v3.6.0-rc.3-linux-$ARCH/etcdctl \\
              etcd-v3.6.0-rc.3-linux-$ARCH/etcd
            
            # Перемещаем бинарные файлы в соответствующие директории
            mv etcdctl downloads/client/
            mv kubectl downloads/client/
            
            mv etcd downloads/controller/
            mv kube-apiserver downloads/controller/
            mv kube-controller-manager downloads/controller/
            mv kube-scheduler downloads/controller/
            
            mv kubelet downloads/worker/
            mv kube-proxy downloads/worker/
            mv runc.$ARCH downloads/worker/runc
            
            # Удаляем архивные файлы
            rm -f *.gz *.tgz
            echo '=== Очистка архивов завершена ==='
            
            # Делаем все бинарные файлы исполняемыми
            chmod +x downloads/client/*
            chmod +x downloads/cni-plugins/*
            chmod +x downloads/controller/*
            chmod +x downloads/worker/*
            
            # Проверяем результат
            echo '=== Итоговая структура директорий ==='
            find downloads/ -type f -executable | sort
            echo '=== Версии компонентов ==='
            downloads/client/kubectl version --client 2>/dev/null | head -2
            downloads/controller/etcd --version | head -2
            echo 'Настройка завершена!'

            echo '=== Настройка kubectl ==='
            export PATH=${path.module}/downloads/client:${path.module}/downloads/controller:${path.module}/downloads/worker:$PATH
            echo '=== Настройка kubectl завершена ==='
            kubectl version
        EOT
    }
}

resource "null_resource" "jumpbox_setup" {
    depends_on = [
        yandex_compute_instance.jump_node,
        yandex_compute_instance.server_node,
        yandex_compute_instance.worker_nodes,
    ]

    triggers = {
        # Перезапускать при изменении IP адреса jump host
        jump_host_ip = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
    }

    connection {
        type        = "ssh"
        user        = "admin"
        private_key = file(var.ssh_private_key)
        host        = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
    }

    # Provisioner для выполнения команд на jump host
    provisioner "remote-exec" {
        inline = [
        <<-EOT
        echo '${local.server_config.ipv4_address} ${local.server_config.fqdn} ${local.server_config.hostname}' | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl
        %{ for i in range(var.vm_count) }
        echo '${local.workers_configs[i].ipv4_address} ${local.workers_configs[i].fqdn} ${local.workers_configs[i].hostname}' | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl
        %{ endfor ~}
        sudo systemctl restart cloud-init
        echo '=== Конфигурирование hosts завершена ==='
        sudo cat /etc/hosts
        EOT
        ]
    }
}

resource "null_resource" "server_setup" {
    depends_on = [
        yandex_compute_instance.jump_node,
        yandex_compute_instance.server_node,
        yandex_compute_instance.worker_nodes,
    ]

    triggers = {
        # Перезапускать при изменении IP адреса jump host
        server_host_ip = yandex_compute_instance.server_node.network_interface[0].ip_address
    }

    connection {
        type        = "ssh"
        user        = "admin"
        private_key = file(var.ssh_private_key)
        host        = yandex_compute_instance.server_node.network_interface[0].ip_address
        bastion_host        = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
        bastion_user        = "admin"
        bastion_private_key = file(var.ssh_private_key)
    }

    # Provisioner для выполнения команд на jump host
    provisioner "remote-exec" {
        inline = [
            "echo '=== Начало конфигурирования hostname ==='",
            "sudo sed -i 's/^127.0.1.1.*/127.0.1.1\t${local.server_config.fqdn} ${local.server_config.hostname}/' /etc/cloud/templates/hosts.debian.tmpl",
            "sudo hostnamectl set-hostname ${local.server_config.hostname}",
            "sudo systemctl restart systemd-hostnamed",
            "echo '=== Конфигурирование hostname завершено ==='",
            "echo $(hostname --fqdn)",
            <<-EOT
            echo '${local.server_config.ipv4_address} ${local.server_config.fqdn} ${local.server_config.hostname}' | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl
            %{ for i in range(var.vm_count) }
            echo '${local.workers_configs[i].ipv4_address} ${local.workers_configs[i].fqdn} ${local.workers_configs[i].hostname}' | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl
            %{ endfor ~}
            sudo systemctl restart cloud-init
            echo '=== Конфигурирование hosts завершена ==='
            sudo cat /etc/hosts
            EOT
        ]
    }
}

resource "null_resource" "workers_setup" {
    for_each = { for i, node in yandex_compute_instance.worker_nodes : i => node }

    triggers = {
        # Перезапускать при изменении IP адреса jump host
        server_host_ip = each.value.network_interface[0].ip_address
    }

    depends_on = [
        yandex_compute_instance.jump_node,
        yandex_compute_instance.server_node,
        yandex_compute_instance.worker_nodes,
    ]

    connection {
        type        = "ssh"
        user        = "admin"
        private_key = file(var.ssh_private_key)
        host        = each.value.network_interface[0].ip_address
        bastion_host        = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
        bastion_user        = "admin"
        bastion_private_key = file(var.ssh_private_key)
    }

    # Provisioner для выполнения команд на jump host
    provisioner "remote-exec" {
        inline = [
            "echo '=== Начало конфигурирования hostname ==='",
            "sudo sed -i 's/^127.0.1.1.*/127.0.1.1\t${local.workers_configs[each.key].fqdn} ${local.workers_configs[each.key].hostname}/' /etc/cloud/templates/hosts.debian.tmpl",
            "sudo hostnamectl set-hostname ${local.workers_configs[each.key].hostname}",
            "sudo systemctl restart systemd-hostnamed",
            "echo '=== Конфигурирование hostname завершено ==='",
            "echo $(hostname --fqdn)",
            <<-EOT
            echo '${local.server_config.ipv4_address} ${local.server_config.fqdn} ${local.server_config.hostname}' | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl
            %{ for i in range(var.vm_count) }
            echo '${local.workers_configs[i].ipv4_address} ${local.workers_configs[i].fqdn} ${local.workers_configs[i].hostname}' | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl
            %{ endfor ~}
            sudo systemctl restart cloud-init
            echo '=== Конфигурирование hosts завершена ==='
            sudo cat /etc/hosts
            EOT
        ]
    }
}

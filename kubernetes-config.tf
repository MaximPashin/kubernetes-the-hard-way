resource "null_resource" "k8s_configs" {
    depends_on = [
        local_file.ca_key,
        local_file.ca_cert,
        local_file.cert_certs,
        null_resource.local_download_binaries,
    ]

    # Provisioner для выполнения команд на jump host
    provisioner "local-exec" {
        command = <<-EOT
            export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
            envsubst < ${path.module}/configs/encryption-config.yaml.template > ${path.module}/configs/encryption-config.yaml

            export PATH=${path.module}/downloads/client:${path.module}/downloads/controller:${path.module}/downloads/worker:$PATH
    # nodes kubeconf
            %{ for i in range(var.vm_count) }
            kubectl config set-cluster kubernetes-the-hard-way \
                --certificate-authority=${path.module}/certs/ca.crt \
                --embed-certs=true \
                --server=https://server.kubernetes.local:6443 \
                --kubeconfig=${path.module}/kubeconfigs/node-${i+1}.kubeconfig
            kubectl config set-credentials system:node:node-${i+1} \
                --client-certificate=${path.module}/certs/node-${i+1}.crt \
                --client-key=${path.module}/certs/node-${i+1}.key \
                --embed-certs=true \
                --kubeconfig=${path.module}/kubeconfigs/node-${i+1}.kubeconfig
            kubectl config set-context default \
                --cluster=kubernetes-the-hard-way \
                --user=system:node:node-${i+1} \
                --kubeconfig=${path.module}/kubeconfigs/node-${i+1}.kubeconfig
            kubectl config use-context default \
                --kubeconfig=${path.module}/kubeconfigs/node-${i+1}.kubeconfig
            %{ endfor ~}

    # kube-proxy conf
            kubectl config set-cluster kubernetes-the-hard-way \
                --certificate-authority=${path.module}/certs/ca.crt \
                --embed-certs=true \
                --server=https://server.kubernetes.local:6443 \
                --kubeconfig=${path.module}/kubeconfigs/kube-proxy.kubeconfig
            kubectl config set-credentials system:kube-proxy \
                --client-certificate=${path.module}/certs/kube-proxy.crt \
                --client-key=${path.module}/certs/kube-proxy.key \
                --embed-certs=true \
                --kubeconfig=${path.module}/kubeconfigs/kube-proxy.kubeconfig
            kubectl config set-context default \
                --cluster=kubernetes-the-hard-way \
                --user=system:kube-proxy \
                --kubeconfig=${path.module}/kubeconfigs/kube-proxy.kubeconfig
            kubectl config use-context default \
                --kubeconfig=${path.module}/kubeconfigs/kube-proxy.kubeconfig

    # kube-controller-manager conf
            kubectl config set-cluster kubernetes-the-hard-way \
                --certificate-authority=${path.module}/certs/ca.crt \
                --embed-certs=true \
                --server=https://server.kubernetes.local:6443 \
                --kubeconfig=${path.module}/kubeconfigs/kube-controller-manager.kubeconfig
            kubectl config set-credentials system:kube-controller-manager \
                --client-certificate=${path.module}/certs/kube-controller-manager.crt \
                --client-key=${path.module}/certs/kube-controller-manager.key \
                --embed-certs=true \
                --kubeconfig=${path.module}/kubeconfigs/kube-controller-manager.kubeconfig
            kubectl config set-context default \
                --cluster=kubernetes-the-hard-way \
                --user=system:kube-controller-manager \
                --kubeconfig=${path.module}/kubeconfigs/kube-controller-manager.kubeconfig
            kubectl config use-context default \
                --kubeconfig=${path.module}/kubeconfigs/kube-controller-manager.kubeconfig

    # kube-scheduler conf
            kubectl config set-cluster kubernetes-the-hard-way \
                --certificate-authority=${path.module}/certs/ca.crt \
                --embed-certs=true \
                --server=https://server.kubernetes.local:6443 \
                --kubeconfig=${path.module}/kubeconfigs/kube-scheduler.kubeconfig
            kubectl config set-credentials system:kube-scheduler \
                --client-certificate=${path.module}/certs/kube-scheduler.crt \
                --client-key=${path.module}/certs/kube-scheduler.key \
                --embed-certs=true \
                --kubeconfig=${path.module}/kubeconfigs/kube-scheduler.kubeconfig
            kubectl config set-context default \
                --cluster=kubernetes-the-hard-way \
                --user=system:kube-scheduler \
                --kubeconfig=${path.module}/kubeconfigs/kube-scheduler.kubeconfig
            kubectl config use-context default \
                --kubeconfig=${path.module}/kubeconfigs/kube-scheduler.kubeconfig

    # kube admin conf
            kubectl config set-cluster kubernetes-the-hard-way \
                --certificate-authority=${path.module}/certs/ca.crt \
                --embed-certs=true \
                --server=https://127.0.0.1:6443 \
                --kubeconfig=${path.module}/kubeconfigs/admin.kubeconfig
            kubectl config set-credentials admin \
                --client-certificate=${path.module}/certs/admin.crt \
                --client-key=${path.module}/certs/admin.key \
                --embed-certs=true \
                --kubeconfig=${path.module}/kubeconfigs/admin.kubeconfig
            kubectl config set-context default \
                --cluster=kubernetes-the-hard-way \
                --user=admin \
                --kubeconfig=${path.module}/kubeconfigs/admin.kubeconfig
            kubectl config use-context default \
                --kubeconfig=${path.module}/kubeconfigs/admin.kubeconfig
        EOT
    }
}

resource "null_resource" "copy_kubeconfig_nodes" {
  for_each = { for i, node in yandex_compute_instance.worker_nodes : i => node }

  # Зависимость от создания сертификатов
  depends_on = [
    null_resource.k8s_configs
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

  # Создаем директорию
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /var/lib/kube-proxy",
      "sudo chmod 755 /var/lib/kube-proxy",
      "sudo mkdir -p /var/lib/kubelet",
      "sudo chmod 755 /var/lib/kubelet"
    ]
  }

  provisioner "file" {
    source = "${path.module}/kubeconfigs/kube-proxy.kubeconfig"
    destination = "/tmp/kube-proxy.kubeconfig"
  }

  provisioner "file" {
    source = "${path.module}/kubeconfigs/node-${each.key+1}.kubeconfig"
    destination = "/tmp/kubelet.kubeconfig"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp /tmp/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig",
      "sudo cp /tmp/kubelet.kubeconfig /var/lib/kubelet/kubeconfig",
    ]
  }
}

resource "null_resource" "copy_kubeconfig_server" {
  # Зависимость от создания сертификатов
  depends_on = [
    null_resource.k8s_configs
  ]

  connection {
    type        = "ssh"
    user        = "admin"
    private_key = file(var.ssh_private_key)
    host        = yandex_compute_instance.server_node.network_interface[0].ip_address
    bastion_host        = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
    bastion_user        = "admin"
    bastion_private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source = "${path.module}/configs/encryption-config.yaml"
    destination = "./encryption-config.yaml"
  }

  provisioner "file" {
    source = "${path.module}/kubeconfigs/admin.kubeconfig"
    destination = "./admin.kubeconfig"
  }

  provisioner "file" {
    source = "${path.module}/kubeconfigs/kube-controller-manager.kubeconfig"
    destination = "./kube-controller-manager.kubeconfig"
  }

  provisioner "file" {
    source = "${path.module}/kubeconfigs/kube-scheduler.kubeconfig"
    destination = "./kube-scheduler.kubeconfig"
  }
}

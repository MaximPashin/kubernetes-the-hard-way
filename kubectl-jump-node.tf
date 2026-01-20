resource "null_resource" "copy_kubectl_files_jump_node" {
  # Зависимость от создания сертификатов
  depends_on = [
    yandex_compute_instance.jump_node,
    null_resource.local_download_binaries,
    local_file.cert_certs,
  ]

  connection {
    type        = "ssh"
    user        = "admin"
    private_key = file(var.ssh_private_key)
    host        = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
  }

  provisioner "file" {
    source = "${path.module}/downloads/client/kubectl"
    destination = "./kubectl"
  }

  provisioner "file" {
    source = "${path.module}/certs/ca.crt"
    destination = "./ca.crt"
  }

  provisioner "file" {
    source = "${path.module}/certs/admin.crt"
    destination = "./admin.crt"
  }

  provisioner "file" {
    source = "${path.module}/certs/admin.key"
    destination = "./admin.key"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      sudo mv kubectl /usr/local/bin/
      sudo chmod +x /usr/local/bin/kubectl
      sudo kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=ca.crt \
        --embed-certs=true \
        --server=https://server.kubernetes.local:6443
      sudo kubectl config set-credentials admin \
        --client-certificate=admin.crt \
        --client-key=admin.key
      sudo kubectl config set-context kubernetes-the-hard-way \
        --cluster=kubernetes-the-hard-way \
        --user=admin
      sudo kubectl config use-context kubernetes-the-hard-way
      echo "===Настройка kubectl завершена==="
      sudo kubectl version
      sudo kubectl get nodes
      EOT
    ]
  }
}

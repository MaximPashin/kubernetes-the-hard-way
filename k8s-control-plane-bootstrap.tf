resource "null_resource" "bootstrap_k8s_control_plane" {
  # Зависимость от создания сертификатов
  depends_on = [
    null_resource.local_download_binaries,
    null_resource.copy_certs_server,
    null_resource.copy_kubeconfig_server,
    null_resource.bootstrap_etcd,
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
    source = "${path.module}/downloads/controller/kube-apiserver"
    destination = "./kube-apiserver"
  }

  provisioner "file" {
    source = "${path.module}/downloads/controller/kube-controller-manager"
    destination = "./kube-controller-manager"
  }

  provisioner "file" {
    source = "${path.module}/downloads/controller/kube-scheduler"
    destination = "./kube-scheduler"
  }

  provisioner "file" {
    source = "${path.module}/downloads/client/kubectl"
    destination = "./kubectl"
  }

  provisioner "file" {
    source = "${path.module}/units/kube-apiserver.service"
    destination = "./kube-apiserver.service"
  }

  provisioner "file" {
    source = "${path.module}/units/kube-controller-manager.service"
    destination = "./kube-controller-manager.service"
  }

  provisioner "file" {
    source = "${path.module}/units/kube-scheduler.service"
    destination = "./kube-scheduler.service"
  }

  provisioner "file" {
    source = "${path.module}/configs/kube-scheduler.yaml"
    destination = "./kube-scheduler.yaml"
  }

  provisioner "file" {
    source = "${path.module}/configs/kube-apiserver-to-kubelet.yaml"
    destination = "./kube-apiserver-to-kubelet.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      sudo mkdir -p /etc/kubernetes/config
      sudo mv kube-apiserver \
        kube-controller-manager \
        kube-scheduler kubectl /usr/local/bin/
      sudo mkdir -p /var/lib/kubernetes/
      sudo mv ca.crt ca.key \
        kube-api-server.key kube-api-server.crt \
        service-accounts.key service-accounts.crt \
        encryption-config.yaml /var/lib/kubernetes/
      sudo mv kube-apiserver.service \
        /etc/systemd/system/kube-apiserver.service
      sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/
      sudo mv kube-controller-manager.service /etc/systemd/system/
      sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/
      sudo mv kube-scheduler.yaml /etc/kubernetes/config/
      sudo mv kube-scheduler.service /etc/systemd/system/
      sudo systemctl daemon-reload
      sudo systemctl enable kube-apiserver \
        kube-controller-manager kube-scheduler
      sudo systemctl start kube-apiserver \
        kube-controller-manager kube-scheduler
      until sudo systemctl is-active kube-apiserver >/dev/null 2>&1; do sleep 3; done
      until sudo systemctl is-active kube-controller-manager >/dev/null 2>&1; do sleep 3; done
      until sudo systemctl is-active kube-scheduler >/dev/null 2>&1; do sleep 3; done
      sudo kubectl cluster-info \
        --kubeconfig admin.kubeconfig

      sudo kubectl apply -f kube-apiserver-to-kubelet.yaml \
        --kubeconfig admin.kubeconfig
      EOT
    ]
  }
}

resource "null_resource" "copy_binaries_nodes" {
  for_each = { for i, node in yandex_compute_instance.worker_nodes : i => node }

  # Зависимость от создания сертификатов
  depends_on = [
    yandex_compute_instance.worker_nodes,
    # null_resource.local_download_binaries,
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

  provisioner "local-exec" {
    command = <<-EOT
    sed "s|SUBNET|${local.workers_configs[each.key].pod_subnet}|g" \
        configs/10-bridge.conf > configs/10-bridge-${each.key}.conf
    EOT
  }

  provisioner "file" {
    source = "${path.module}/configs/10-bridge-${each.key}.conf"
    destination = "./10-bridge.conf"
  }

  provisioner "file" {
    source = "${path.module}/configs/kubelet-config.yaml"
    destination = "./kubelet-config.yaml"
  }

  provisioner "file" {
    source = "${path.module}/downloads/worker/"
    destination = "./"
  }

  provisioner "file" {
    source = "${path.module}/downloads/cni-plugins"
    destination = "./"
  }

  provisioner "file" {
    source = "${path.module}/downloads/client/kubectl"
    destination = "./kubectl"
  }

  provisioner "file" {
    source = "${path.module}/configs/99-loopback.conf"
    destination = "./99-loopback.conf"
  }

  provisioner "file" {
    source = "${path.module}/configs/containerd-config.toml"
    destination = "./containerd-config.toml"
  }

  provisioner "file" {
    source = "${path.module}/configs/kube-proxy-config.yaml"
    destination = "./kube-proxy-config.yaml"
  }

  provisioner "file" {
    source = "${path.module}/units/containerd.service"
    destination = "./containerd.service"
  }

  provisioner "file" {
    source = "${path.module}/units/kubelet.service"
    destination = "./kubelet.service"
  }

  provisioner "file" {
    source = "${path.module}/units/kube-proxy.service"
    destination = "./kube-proxy.service"
  }
}

resource "null_resource" "bootstrap_k8s_worker_nodes" {
  for_each = { for i, node in yandex_compute_instance.worker_nodes : i => node }

  # Зависимость от создания сертификатов
  depends_on = [
    null_resource.bootstrap_k8s_control_plane,
    null_resource.copy_kubeconfig_nodes,
    null_resource.copy_binaries_nodes,
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

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      sudo swapoff -a
      sudo mkdir -p /etc/cni/net.d
      sudo mkdir -p /opt/cni/bin
      sudo mkdir -p /var/lib/kubelet
      sudo mkdir -p /var/lib/kube-proxy
      sudo mkdir -p /var/lib/kubernetes
      sudo mkdir -p /var/run/kubernetes
      sudo mv crictl kube-proxy kubelet runc /usr/local/bin/
      sudo mv containerd containerd-shim-runc-v2 containerd-stress /bin/
      sudo mv cni-plugins/* /opt/cni/bin/
      sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/

      sudo chmod +x /usr/local/bin/*
      sudo chmod +x /bin/*
      sudo chmod +x /opt/cni/bin/*
      
      sudo modprobe br-netfilter
      echo "br-netfilter" | sudo tee -a /etc/modules-load.d/modules.conf

      echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf
      echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf
      sudo sysctl -p /etc/sysctl.d/kubernetes.conf

      sudo mkdir -p /etc/containerd/
      sudo mv containerd-config.toml /etc/containerd/config.toml
      sudo mv containerd.service /etc/systemd/system/

      sudo mv kubelet-config.yaml /var/lib/kubelet/
      sudo mv kubelet.service /etc/systemd/system/

      sudo mv kube-proxy-config.yaml /var/lib/kube-proxy/
      sudo mv kube-proxy.service /etc/systemd/system/

      sudo systemctl daemon-reload
      sudo systemctl enable containerd kubelet kube-proxy
      sudo systemctl start containerd kubelet kube-proxy
      EOT
    ]
  }
}

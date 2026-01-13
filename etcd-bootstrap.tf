resource "null_resource" "copy_etcd_files_server" {
  # Зависимость от создания сертификатов
  depends_on = [
    null_resource.local_download_binaries,
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
    source = "${path.module}/downloads/controller/etcd"
    destination = "/tmp/etcd"
  }

  provisioner "file" {
    source = "${path.module}/downloads/client/etcdctl"
    destination = "/tmp/etcdctl"
  }

  provisioner "file" {
    source = "${path.module}/units/etcd.service"
    destination = "/tmp/etcd.service"
  }

  provisioner "remote-exec" {
    inline = [
        "sudo mv /tmp/etcd /tmp/etcdctl /usr/local/bin/",
        "sudo chmod +x /usr/local/bin/*",
        "sudo mkdir -p /etc/etcd",
        "sudo mkdir -p /var/lib/etcd",
        "sudo chmod 700 /var/lib/etcd",
        "sudo cp ca.crt kube-api-server.key kube-api-server.crt /etc/etcd/",
        "sudo mv /tmp/etcd.service /etc/systemd/system/etcd.service",
        "sudo systemctl daemon-reload",
        "sudo systemctl enable etcd",
        "sudo systemctl start etcd",
        "sudo etcdctl member list",
    ]
  }
}

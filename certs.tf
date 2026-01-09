# Генерация CA ключа и сертификата
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem
  subject {
    country      = "US"
    province     = "Washington"
    locality     = "Seattle"
    common_name  = "CA"
  }
  validity_period_hours = 3653 * 24 # 10 лет
  is_ca_certificate     = true
  allowed_uses = [
    "crl_signing",
    "cert_signing",
  ]
}

# Функция для создания сертификатов
locals {
  nodes_certs = { for i in range(var.vm_count) :
    "node-${i+1}" => {
      cn = "system:node:node-${i+1}"
      organization = "system:nodes"
      dns_names = ["node-${i+1}"]
      ip_addresses = ["127.0.0.1"]
      allowed_uses = ["client_auth", "server_auth"]
    }
  }
  k8s_certs = {
    "admin" = {
      cn = "admin"
      organization = "system:masters"
      dns_names = []
      ip_addresses = []
      allowed_uses = ["client_auth"]
    }
    "kube-proxy" = {
      cn = "system:kube-proxy"
      organization = "system:node-proxier"
      dns_names = ["kube-proxy"]
      ip_addresses = ["127.0.0.1"]
      allowed_uses = ["client_auth", "server_auth"]
    }
    "kube-controller-manager" = {
      cn = "system:kube-controller-manager"
      organization = "system:kube-controller-manager"
      dns_names = ["kube-controller-manager"]
      ip_addresses = ["127.0.0.1"]
      allowed_uses = ["client_auth", "server_auth"]
    }
    "kube-scheduler" = {
      cn = "system:kube-scheduler"
      organization = "system:system:kube-scheduler"
      dns_names = ["kube-scheduler"]
      ip_addresses = ["127.0.0.1"]
      allowed_uses = ["client_auth", "server_auth"]
    }
    "kube-api-server" = {
      cn = "kubernetes"
      organization = ""
      dns_names = [
        "kubernetes",
        "kubernetes.default",
        "kubernetes.default.svc",
        "kubernetes.default.svc.cluster",
        "kubernetes.svc.cluster.local",
        "server.kubernetes.local",
        "api-server.kubernetes.local"
      ]
      ip_addresses = ["127.0.0.1", "10.32.0.1"]
      allowed_uses = ["client_auth", "server_auth"]
    }
    "service-accounts" = {
      cn = "service-accounts"
      organization = ""
      dns_names = []
      ip_addresses = []
      allowed_uses = ["client_auth"]
    }
  }
  certs = merge(local.k8s_certs, local.nodes_certs)
}

# Генерация приватных ключей для всех сертификатов
resource "tls_private_key" "certs" {
  for_each = local.certs
  
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Генерация CSR запросов
resource "tls_cert_request" "certs" {
  for_each = local.certs

  private_key_pem = tls_private_key.certs[each.key].private_key_pem
  
  subject {
    country      = "US"
    province     = "Washington"
    locality     = "Seattle"
    common_name  = each.value.cn
    organization = each.value.organization != "" ? each.value.organization : null
  }
  dns_names = each.value.dns_names
  ip_addresses = each.value.ip_addresses
}

# Подписание сертификатов CA
resource "tls_locally_signed_cert" "certs" {
  for_each = local.certs

  cert_request_pem   = tls_cert_request.certs[each.key].cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 3653 * 24

  allowed_uses = each.value.allowed_uses
}

# Локальные файлы для сохранения сертификатов и ключей
resource "local_file" "ca_key" {
  content  = tls_private_key.ca.private_key_pem
  filename = "${path.module}/certs/ca.key"
}

resource "local_file" "ca_cert" {
  content  = tls_self_signed_cert.ca.cert_pem
  filename = "${path.module}/certs/ca.crt"
}

resource "local_file" "cert_keys" {
  for_each = local.certs
  
  content  = tls_private_key.certs[each.key].private_key_pem
  filename = "${path.module}/certs/${each.key}.key"
}

resource "local_file" "cert_certs" {
  for_each = local.certs
  
  content  = tls_locally_signed_cert.certs[each.key].cert_pem
  filename = "${path.module}/certs/${each.key}.crt"
}

# Output значений для использования в других модулях
output "ca_cert_pem" {
  value = tls_self_signed_cert.ca.cert_pem
  sensitive = true
}

output "ca_private_key_pem" {
  value = tls_private_key.ca.private_key_pem
  sensitive = true
}

output "certs" {
  value = {
    for k in keys(local.certs) : k => {
      key  = tls_private_key.certs[k].private_key_pem
      cert = tls_locally_signed_cert.certs[k].cert_pem
    }
  }
  sensitive = true
}

resource "null_resource" "copy_certs_nodes" {
  for_each = { for i, node in yandex_compute_instance.worker_nodes : i => node }

  # Зависимость от создания сертификатов
  depends_on = [
    local_file.ca_key,
    local_file.ca_cert,
    local_file.cert_certs
  ]

  triggers = {
    certs_hash = md5(join("", [
      tls_self_signed_cert.ca.cert_pem,
      tls_private_key.certs["node-${each.key + 1}"].private_key_pem,
    ]))
  }

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
      "sudo mkdir -p /var/lib/kubelet",
      "sudo chmod 755 /var/lib/kubelet"
    ]
  }

  provisioner "file" {
    source = "${path.module}/certs/ca.crt"
    destination = "/tmp/ca.crt"
  }

  provisioner "file" {
    source = "${path.module}/certs/node-${each.key+1}.key"
    destination = "/tmp/kubelet.key"
  }

  provisioner "file" {
    source = "${path.module}/certs/node-${each.key+1}.crt"
    destination = "/tmp/kubelet.crt"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp /tmp/ca.crt /var/lib/kubelet/ca.crt",
      "sudo cp /tmp/kubelet.key /var/lib/kubelet/kubelet.key",
      "sudo cp /tmp/kubelet.crt /var/lib/kubelet/kubelet.crt",
    ]
  }
}

resource "null_resource" "copy_certs_server" {
  # Зависимость от создания сертификатов
  depends_on = [
    local_file.ca_key,
    local_file.ca_cert,
    local_file.cert_certs
  ]

  triggers = {
    certs_hash = md5(join("", [
      tls_self_signed_cert.ca.cert_pem,
      # tls_private_key.certs["admin"].private_key_pem,
      # tls_private_key.certs["kube-proxy"].private_key_pem,
      # tls_private_key.certs["kube-controller-manager"].private_key_pem,
      # tls_private_key.certs["kube-scheduler"].private_key_pem,
      tls_private_key.certs["kube-api-server"].private_key_pem,
      tls_private_key.certs["service-accounts"].private_key_pem,
    ]))
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

  provisioner "file" {
    source = "${path.module}/certs/ca.crt"
    destination = "./ca.crt"
  }

  provisioner "file" {
    source = "${path.module}/certs/ca.key"
    destination = "./ca.key"
  }

  provisioner "file" {
    source = "${path.module}/certs/kube-api-server.crt"
    destination = "./kube-api-server.crt"
  }

  provisioner "file" {
    source = "${path.module}/certs/kube-api-server.key"
    destination = "./kube-api-server.key"
  }

  provisioner "file" {
    source = "${path.module}/certs/service-accounts.crt"
    destination = "./service-accounts.crt"
  }

  provisioner "file" {
    source = "${path.module}/certs/service-accounts.key"
    destination = "./service-accounts.key"
  }
}

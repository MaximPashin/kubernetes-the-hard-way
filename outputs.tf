output "jump_node_external_ip" {
  value = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
}

output "server_node_internal_ip" {
  value = yandex_compute_instance.server_node.network_interface[0].ip_address
}

output "worker_nodes_ips" {
  value = [
    for vm in yandex_compute_instance.worker_nodes : vm.network_interface[0].ip_address
  ]
}

output "cluster_info" {
  value = {
    jump_node_ip   = yandex_compute_instance.jump_node.network_interface[0].nat_ip_address
    server_node_ip  = yandex_compute_instance.server_node.network_interface[0].ip_address
    worker_nodes_ips = [
      for vm in yandex_compute_instance.worker_nodes : vm.network_interface[0].ip_address
    ]
    worker_nodes_count = var.vm_count
  }
}

output "server_node_config" {
  value       = local.server_config
  description = "Конфигурация серверной ноды"
  sensitive   = false
}

output "worker_nodes_config" {
  value       = local.workers_configs
  description = "Конфигурации рабочих нод"
  sensitive   = false
}
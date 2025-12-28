variable "vm_count" {
  description = "Количество рабочих нод"
  type        = number
  default     = 2
}

variable "jump_node_image_id" {
  description = "ID образа для административной ноды"
  type        = string
  default     = "fd8gld4n3e7t7t99puta" # debian-12
}

variable "server_node_image_id" {
  description = "ID образа для сервера"
  type        = string
  default     = "fd8gld4n3e7t7t99puta" # debian-12
}

variable "worker_node_image_id" {
  description = "ID образа для рабочих нод"
  type        = string
  default     = "fd8gld4n3e7t7t99puta" # debian-12
}

variable "zone" {
  description = "Зона доступности"
  type        = string
  default     = "ru-central1-a"
}

variable "network_name" {
  description = "Имя сети"
  type        = string
  default     = "cluster-network"
}

variable "subnet_name" {
  description = "Имя подсети"
  type        = string
  default     = "cluster-subnet"
}

variable "subnet_cidr" {
  description = "CIDR подсети"
  type        = string
  default     = "192.168.10.0/24"
}

variable "ssh_public_key" {
  description = "Публичный SSH ключ"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key" {
  description = "Публичный SSH ключ"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "name" {
  type = string
}

variable "suffix" {
  type = string

  default = "cnpg"
}

variable "cluster_name" {
  type = string

  default = "cluster.local"
}

variable "description" {
  type = string

  default = null
}

variable "timezone" {
  type = string

  default = "UTC"
}

variable "namespace" {
  type = string
}

variable "instances" {
  type = number

  default = 1
}

variable "storage_size" {
  type = string

  default = "1Gi"
}

variable "storage_class" {
  type = string

  default = null
}

variable "username_length" {
  type = number

  default = 16
}

variable "username_special" {
  type = bool

  default = false
}

variable "password_length" {
  type = number

  default = 24
}

variable "password_special" {
  type = bool

  default = false
}

variable "database_username" {
  type    = string

  default = ""
}

variable "post_init_sql" {
  type = list(string)

  default = []
}

variable "enable_superuser_access" {
  type = bool

  default = false
}

variable "enable_pod_monitor" {
  type = bool

  default = true
}

variable "encoding" {
  type = string

  default = "utf8"
}

variable "backup_retention_policy" {
  type = string

  default = "30d"
}

variable "object_storage_backup" {
  type = object({
    enable          = bool
    s3_endpoint_url = string
    access_key      = string
    secret_key      = string
    bucket          = string
    schedule        = optional(string)
  })
}


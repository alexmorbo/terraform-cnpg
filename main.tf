resource "random_string" "database_username" {
  count = var.database_username == "" ? 1 : 0

  special = var.username_special
  length  = var.username_length
}

resource "random_password" "database_password" {
  count = var.database_password == "" ? 1 : 0

  length  = var.password_length
  special = var.password_special
}

resource "random_password" "superuser_password" {
  length  = var.password_length
  special = var.password_special
}

locals {
  labels = {
    "cnpg.io/module" = "${var.name}-${var.suffix}"
  }
}

resource "kubernetes_secret" "cnpg_object_storage_backup_credentials" {
  count = var.object_storage_backup.enable ? 1 : 0

  metadata {
    name      = "${var.name}-${var.suffix}-object-storage-backup-credentials"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    access_key = var.object_storage_backup.access_key
    secret_key = var.object_storage_backup.secret_key
  }
}

locals {
  database_username = var.database_username != "" ? var.database_username : random_string.database_username[0].result
  database_password = var.database_password != "" ? var.database_password : random_password.database_password[0].result

  berman_object_store = var.object_storage_backup.enable ? {
    destinationPath = "s3://${var.object_storage_backup.bucket}/${var.name}${var.object_storage_backup.backup_suffix != null ? var.object_storage_backup.backup_suffix : ""}/"
    endpointURL     = var.object_storage_backup.s3_endpoint_url
    s3Credentials = {
      accessKeyId = {
        name = kubernetes_secret.cnpg_object_storage_backup_credentials[0].metadata[0].name
        key  = "access_key"
      }
      secretAccessKey = {
        name = kubernetes_secret.cnpg_object_storage_backup_credentials[0].metadata[0].name
        key  = "secret_key"
      }
    }
    wal = {
      compression = "gzip"
    }
    data = {
      compression         = "gzip"
      immediateCheckpoint = true
      jobs                = "2"
    }
  } : null
}

resource "kubernetes_secret" "cnpg_auth" {
  type = "kubernetes.io/basic-auth"

  metadata {
    name      = "${var.name}-${var.suffix}-secret"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    username = local.database_username
    password = local.database_password
  }
}

resource "kubernetes_secret" "superuser_auth" {
  metadata {
    name      = "${var.name}-${var.suffix}-superuser-secret"
    namespace = var.namespace
  }

  data = {
    username = "superuser"
    password = random_password.superuser_password.result
  }
}

resource "kubernetes_secret" "cnpg_connection" {
  metadata {
    name      = "${var.name}-${var.suffix}-connection-secret"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    uri = "postgresql://${local.database_username}:${local.database_password}@${var.name}-${var.suffix}-rw.${var.namespace}.svc.${var.cluster_name}:5432/${var.name}"
  }
}

resource "kubernetes_manifest" "cnpg_object_storage_scheduled_backup_job" {
  count = var.object_storage_backup.enable ? 1 : 0

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "ScheduledBackup"
    metadata = {
      name      = "${var.name}-${var.suffix}-object-storage-scheduled-backup"
      namespace = var.namespace
      labels    = local.labels
    }

    spec = {
      schedule = coalesce(try(var.object_storage_backup.schedule, null), "0 0 0 * * *")
      backupOwnerReference = "self"
      cluster = {
        name = "${var.name}-${var.suffix}"
      }
    }
  }
}

resource "kubernetes_manifest" "cnpg" {
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name        = "${var.name}-${var.suffix}"
      namespace   = var.namespace
      labels      = local.labels
      annotations = var.annotations
    }

    spec = {
      instances   = var.instances
      imageName   = "${var.image_registry}/cloudnative-pg/postgresql:${var.postgres_version}"
      description = var.description

      monitoring = {
        enablePodMonitor = var.enable_pod_monitor
      }

      enableSuperuserAccess = var.enable_superuser_access
      superuserSecret = {
        name = kubernetes_secret.superuser_auth.metadata[0].name
      }

      bootstrap = merge(
          var.object_storage_restore.enable ? {
          recovery = {
            database = var.name
            source   = var.object_storage_restore.restore_name
            owner    = local.database_username
            secret = {
              name = kubernetes_secret.cnpg_auth.metadata[0].name
            }
          }
        } : {},
          var.object_storage_restore.enable ? {} : {
          initdb = merge({
            database = var.name
            owner    = local.database_username
            secret = {
              name = kubernetes_secret.cnpg_auth.metadata[0].name
            }
            encoding = var.encoding
          }, length(var.post_init_sql) > 0 ? { postInitSQL = var.post_init_sql } : {})
        }
      )

      externalClusters = var.object_storage_restore.enable ? [
        {
          name = var.object_storage_restore.restore_name
          barmanObjectStore = merge(local.berman_object_store, {
            destinationPath = "s3://${var.object_storage_backup.bucket}/${var.name}${var.object_storage_restore.restore_suffix}/"
          })
        }
      ] : []

      storage = {
        size         = var.storage_size
        storageClass = var.storage_class
      }

      backup = {
        barmanObjectStore = local.berman_object_store
        retentionPolicy   = var.backup_retention_policy
      }
    }
  }

  depends_on = [kubernetes_secret.cnpg_auth, kubernetes_secret.cnpg_connection]
}
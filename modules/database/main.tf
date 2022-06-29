locals {
  port = 5432
}

resource "aws_rds_cluster" "rds" {
  allow_major_version_upgrade         = false
  apply_immediately                   = true
  backtrack_window                    = 0
  backup_retention_period             = 7
  cluster_identifier                  = var.cluster_name
  copy_tags_to_snapshot               = false
  database_name                       = var.database_name
  db_cluster_parameter_group_name     = "default.aurora-postgresql10"
  db_subnet_group_name                = var.subnet_group_name
  enabled_cloudwatch_logs_exports     = []
  engine                              = "aurora-postgresql"
  engine_mode                         = "serverless"
  engine_version                      = "10.18"
  final_snapshot_identifier           = "final-${var.cluster_name}-3a9ffcad"
  global_cluster_identifier           = ""
  iam_database_authentication_enabled = false
  iam_roles                           = []
  kms_key_id                          = var.kms_key_arn
  master_password                     = random_password.master_password.result
  master_username                     = var.username
  port                                = local.port
  skip_final_snapshot                 = true
  storage_encrypted                   = true
  storage_type                        = ""
  tags                                = var.tags
  vpc_security_group_ids = [
    aws_security_group.rds.id
  ]

  scaling_configuration {
    auto_pause               = true
    max_capacity             = 4
    min_capacity             = 2
    seconds_until_auto_pause = 300
    timeout_action           = "ForceApplyCapacityChange"
  }

  timeouts {}

  lifecycle {
    #    ignore_changes = [
    #      replication_source_identifier,
    #      global_cluster_identifier,
    #    ]
  }
}

resource "aws_security_group" "rds" {
  description = "Control traffic to/from RDS Aurora ${var.cluster_name}"
  name_prefix = "${var.cluster_name}-"
  tags = {
    "Name" = var.cluster_name
  }
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "cidr_ingress" {
  cidr_blocks       = var.allowed_cidr_blocks
  description       = "From allowed CIDRs"
  from_port         = local.port
  prefix_list_ids   = []
  protocol          = "tcp"
  security_group_id = aws_security_group.rds.id
  to_port           = local.port
  type              = "ingress"
}


resource "random_id" "snapshot_identifier" {
  keepers = {
    id = var.cluster_name
  }

  byte_length = 4
}

resource "random_password" "master_password" {
  length  = 10
  special = false
}

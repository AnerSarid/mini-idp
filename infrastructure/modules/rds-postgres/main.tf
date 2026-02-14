################################################################################
# Locals
################################################################################

locals {
  prefix = var.environment_name

  common_tags = merge(var.tags, {
    "idp:module" = "rds-postgres"
  })
}

################################################################################
# Master Password
################################################################################

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.prefix}/rds/credentials"
  description = "Master credentials for the ${local.prefix} RDS PostgreSQL instance."

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.master.result
    dbname   = var.db_name
    port     = 5432
    host     = aws_db_instance.this.address
    engine   = "postgres"
  })

  depends_on = [aws_db_instance.this]
}

################################################################################
# DB Subnet Group
################################################################################

resource "aws_db_subnet_group" "this" {
  name       = "${local.prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-db-subnet-group"
  })
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "db" {
  name        = "${local.prefix}-rds-sg"
  description = "Allow inbound PostgreSQL from the application security group."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-rds-sg"
  })
}

resource "aws_security_group_rule" "db_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_id
  security_group_id        = aws_security_group.db.id
  description              = "PostgreSQL from application"
}

resource "aws_security_group_rule" "db_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
  description       = "Allow all outbound"
}

################################################################################
# RDS PostgreSQL Instance
################################################################################

resource "aws_db_instance" "this" {
  identifier = "${local.prefix}-postgres"

  engine         = "postgres"
  engine_version = "16.12"
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = "dbadmin"
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible  = false
  multi_az             = false
  skip_final_snapshot  = true
  deletion_protection  = false
  copy_tags_to_snapshot = true

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-postgres"
  })
}

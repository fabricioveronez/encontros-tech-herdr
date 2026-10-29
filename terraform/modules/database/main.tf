resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.database_subnet_ids
  tags       = { Name = "${var.name}-db" }
}

resource "aws_db_instance" "this" {
  identifier                 = "${var.name}-db"
  engine                     = "postgres"
  engine_version             = var.db_engine_version
  instance_class             = var.db_instance_class
  db_name                    = var.db_name
  username                   = var.db_username
  password                   = random_password.master.result
  port                       = 5432
  allocated_storage          = var.db_allocated_storage
  max_allocated_storage      = var.db_max_allocated_storage
  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [var.database_security_group_id]
  multi_az                   = var.db_multi_az
  storage_encrypted          = true
  publicly_accessible        = false
  backup_retention_period    = var.db_backup_retention_period
  deletion_protection        = var.db_deletion_protection
  skip_final_snapshot        = var.db_skip_final_snapshot
  final_snapshot_identifier  = var.db_skip_final_snapshot ? null : "${var.name}-db-final"
  auto_minor_version_upgrade = true
  tags                       = { Name = "${var.name}-db" }
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = "${var.name}/database-url"
  recovery_window_in_days = var.db_secret_recovery_window_in_days
  tags                    = { Name = "${var.name}-database-url" }
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${var.db_username}:${random_password.master.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}"
}

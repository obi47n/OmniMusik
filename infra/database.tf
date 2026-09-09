# Database.
#
# Postgres on RDS, in the private subnets, reachable only from the application's
# security group. The password is generated here and stored in Secrets Manager --
# never rendered into a variable file, and never in the App Runner configuration in
# plaintext.

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.project}-db" }
}

resource "random_password" "database" {
  length  = 32
  special = false # RDS rejects several punctuation characters in master passwords
}

resource "aws_secretsmanager_secret" "database" {
  name                    = "${var.project}/database"
  description             = "Master credentials for the OmniMusik Postgres instance"
  recovery_window_in_days = 0 # A portfolio stack should be destroyable without a wait
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.database.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "omnimusik"
  username = "omnimusik"
  password = random_password.database.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false

  # Both false deliberately, and both would be true in production. They are off here
  # so the stack stays cheap and can be torn down cleanly.
  multi_az                     = false
  performance_insights_enabled = false

  auto_minor_version_upgrade = true

  tags = { Name = "${var.project}-postgres" }
}

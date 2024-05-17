# Variables
variable "db_user" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_port" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type = string
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Data source to fetch the availability zones
data "aws_availability_zones" "available" {}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Public Subnet Configuration
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# Private Subnet Configuration
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

resource "aws_eip" "nat" {
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "private" {
  allocation_id = aws_eip.nat.id
  subnet_id     = element(aws_subnet.public.*.id, 0)
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.private.id
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id, aws_security_group.scraper_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [aws_security_group.web_lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "scraper_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "web_task" {
  name = "/ecs/web-task"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "scraper_task" {
  name = "/ecs/scraper-task"
  retention_in_days = 7
}

# RDS Instance
resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_parameter_group" "custom_pg" {
  name        = "custom-pg"
  family      = "postgres16"
  description = "Enable SSL for RDS instance."

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "main" {
  identifier              = "miracle-db"
  engine                  = "postgres"
  engine_version          = "16.2"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "postgres"
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]

  # Additional settings
  skip_final_snapshot     = true
  publicly_accessible     = false
  parameter_group_name    = aws_db_parameter_group.custom_pg.name
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "miracle-cluster"
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "web" {
  family                   = "web-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "web-container"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/frontend:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
      environment = [
        {
          name  = "DATABASE_HOST"
          # required workaround to get the hostname without the port
          # https://github.com/hashicorp/terraform/issues/4996
          value = "${element(split(":", aws_db_instance.main.endpoint), 0)}"
        },
        {
          name  = "DATABASE_PASSWORD"
          value = var.db_password
        },
        {
          name  = "DATABASE_NAME"
          value = var.db_name
        },
        {
          name  = "DATABASE_USER"
          value = var.db_user
        },
        {
          name  = "DATABASE_PORT"
          value = var.db_port
        },
        {
          "name": "PGSSLMODE",
          "value": "disable"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web_task.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn
}

resource "aws_ecs_task_definition" "scraper" {
  family                   = "scraper-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "scraper-container"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/webscraper:latest"
      essential = true
      environment = [
        {
          name  = "DATABASE_HOST"
          value = "${element(split(":", aws_db_instance.main.endpoint), 0)}"

        },
        {
          name  = "DATABASE_PASSWORD"
          value = var.db_password
        },
        {
          name  = "DATABASE_NAME"
          value = var.db_name
        },
        {
          name  = "DATABASE_USER"
          value = var.db_user
        },
        {
          name  = "DATABASE_PORT"
          value = var.db_port
        },
        {
          "name": "PGSSLMODE",
          "value": "disable"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.scraper_task.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn
}

# ECS Services
resource "aws_ecs_service" "web" {
  name            = "web-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  load_balancer {
    target_group_arn = aws_lb_target_group.web_tg.arn
    container_name   = "web-container"
    container_port   = 3000
  }
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.web_sg.id]
  }
  depends_on = [
    aws_lb.web_lb,
    aws_lb_target_group.web_tg,
  ]
}

resource "aws_ecs_service" "scraper" {
  name            = "scraper-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.scraper.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.scraper_sg.id]
  }
}

# Load Balancer
resource "aws_lb" "web_lb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_lb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "web_tg" {
  name       = "web-tg"
  port       = 80
  protocol   = "HTTP"
  vpc_id     = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "web_http_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource "aws_security_group" "web_lb_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Output RDS Endpoint
output "rds_endpoint" {
  value = "${element(split(":", aws_db_instance.main.endpoint), 0)}"
}

# Output Load Balancer DNS
output "web_lb_dns" {
  value = aws_lb.web_lb.dns_name
}

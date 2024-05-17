# Variables
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

# RDS Instance
resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = aws_subnet.private[*].id
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
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "miracle-cluster"
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "web" {
  family                   = "web-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "web-container"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/frontend:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
      environment = [
        {
          name  = "DATABASE_HOST"
          value = aws_db_instance.main.endpoint
        },
        {
          name  = "DATABASE_PASSWORD"
          value = var.db_password
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/web-task"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "scraper" {
  family                   = "scraper-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "scraper-container"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/scraper:latest"
      essential = true
      environment = [
        {
          name  = "DATABASE_HOST"
          value = aws_db_instance.main.endpoint
        },
        {
          name  = "DATABASE_PASSWORD"
          value = var.db_password
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/scraper-task"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# ECS Services
resource "aws_ecs_service" "web" {
  name            = "web-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "EC2"
  load_balancer {
    target_group_arn = aws_lb_target_group.web_tg.arn
    container_name   = "web-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.public[*].id
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
  launch_type     = "EC2"
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
  security_groups    = [aws_security_group.web_sg.id]
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

# Output RDS Endpoint
output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

# Output Load Balancer DNS
output "web_lb_dns" {
  value = aws_lb.web_lb.dns_name
}

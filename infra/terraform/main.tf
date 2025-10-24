terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

resource "aws_instance" "validator" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.validator.id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name        = "qubetics-validator"
    Environment = var.environment
  }

  user_data = templatefile("${path.module}/templates/userdata.sh", {
    domain          = var.domain
    allow_ips       = join(",", var.allow_ips)
    docker_tag      = var.docker_tag
    prometheus_port = var.prometheus_port
  })
}

resource "aws_security_group" "validator" {
  name        = "qubetics-validator"
  description = "Qubetics validator node"
  vpc_id      = var.vpc_id

  ingress {
    description = "P2P"
    from_port   = var.p2p_port
    to_port     = var.p2p_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
  }

  ingress {
    description = "Prometheus"
    from_port   = var.prometheus_port
    to_port     = var.prometheus_port
    protocol    = "tcp"
    cidr_blocks = var.monitoring_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "public_ip" {
  description = "Public IP of the validator"
  value       = aws_instance.validator.public_ip
}

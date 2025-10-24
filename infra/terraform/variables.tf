variable "region" {
  type        = string
  description = "AWS region"
}

variable "profile" {
  type        = string
  description = "AWS profile"
  default     = "default"
}

variable "ami_id" {
  type        = string
  description = "Base AMI for validator hosts"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "m6i.large"
}

variable "key_name" {
  type        = string
  description = "SSH key name"
}

variable "subnet_id" {
  type        = string
  description = "Subnet for the validator"
}

variable "vpc_id" {
  type        = string
  description = "VPC identifier"
}

variable "root_volume_size" {
  type        = number
  default     = 200
}

variable "environment" {
  type        = string
  default     = "production"
}

variable "p2p_port" {
  type    = number
  default = 26656
}

variable "prometheus_port" {
  type    = number
  default = 26660
}

variable "admin_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "monitoring_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "domain" {
  type        = string
  description = "Optional RPC domain"
  default     = ""
}

variable "allow_ips" {
  type    = list(string)
  default = []
}

variable "docker_tag" {
  type    = string
  default = "latest"
}

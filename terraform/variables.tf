variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used on all resource names/tags"
  type        = string
  default     = "wiz-exercise"
}

variable "your_name" {
  description = "Your name — written into wizexercise.txt inside the container image"
  type        = string
  default     = "Kenneth Neba"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.42.1.0/24"
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.42.10.0/24", "10.42.11.0/24"]
}

# INTENTIONALLY OLD AMI (>1yr out of date at time of writing — verify/update
# the ami filter below before you build so it stays "1+ year old" relative
# to today, not relative to when this file was written).
variable "mongo_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "mongo_admin_password" {
  description = "Password for the MongoDB app user (pass via TF_VAR or a .tfvars file that is gitignored, never commit it)"
  type        = string
  sensitive   = true
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH access to the Mongo VM"
  type        = string
}

variable "eks_cluster_version" {
  type    = string
  default = "1.33"
}

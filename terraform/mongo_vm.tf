############################################
# INTENTIONALLY OLD AMI
# Pick a base image that is 1+ years old relative to build date.
# Example below pins a specific old Ubuntu 20.04 AMI in us-east-1 —
# replace with a verified old AMI ID for your target region/date.
############################################
data "aws_ami" "old_ubuntu" {
  most_recent = false
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

############################################
# Security Group — SSH open to the world (INTENTIONAL WEAKNESS #1)
# Mongo port only reachable from the EKS node/private subnet CIDRs
############################################
resource "aws_security_group" "mongo_sg" {
  name        = "${var.project_name}-mongo-sg"
  description = "Mongo VM SG - intentionally permissive SSH for exercise"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH open to internet - INTENTIONAL MISCONFIG"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MongoDB - restricted to private (k8s) subnets only"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                  = "${var.project_name}-mongo-sg"
    "wiz-exercise-intentional-exception" = "true"
  }
}

############################################
# IAM Role — overly permissive (INTENTIONAL WEAKNESS #2)
# Grants EC2 broad ability to create/manage other compute resources
############################################
resource "aws_iam_role" "mongo_vm_role" {
  name = "${var.project_name}-mongo-vm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# INTENTIONALLY OVERPRIVILEGED - document this clearly in your presentation
resource "aws_iam_role_policy_attachment" "mongo_vm_overprivileged" {
  role       = aws_iam_role.mongo_vm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "mongo_vm_s3" {
  role       = aws_iam_role.mongo_vm_role.name
  policy_arn = aws_iam_policy.mongo_backup_s3_write.arn
}

resource "aws_iam_instance_profile" "mongo_vm_profile" {
  name = "${var.project_name}-mongo-vm-profile"
  role = aws_iam_role.mongo_vm_role.name
}

############################################
# EC2 instance
############################################
resource "aws_instance" "mongo_vm" {
  ami                         = data.aws_ami.old_ubuntu.id
  instance_type               = var.mongo_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.mongo_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.mongo_vm_profile.name
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/../scripts/mongo_userdata.sh.tpl", {
    mongo_admin_password = var.mongo_admin_password
    backup_bucket        = aws_s3_bucket.mongo_backups.bucket
    aws_region            = var.aws_region
  })

  tags = {
    Name = "${var.project_name}-mongo-vm"
    Note = "Outdated AMI + public SSH + overprivileged role - intentional for Wiz exercise"
  }
}

output "mongo_vm_public_ip" {
  value = aws_instance.mongo_vm.public_ip
}

output "mongo_vm_private_ip" {
  value = aws_instance.mongo_vm.private_ip
}

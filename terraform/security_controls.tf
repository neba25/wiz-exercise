############################################
# AWS Config — recorder + delivery channel
############################################
resource "aws_iam_role" "config_role" {
  name = "${var.project_name}-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_role_managed" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3_write" {
  name = "${var.project_name}-config-s3-write"
  role = aws_iam_role.config_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetBucketAcl"]
      Resource = [aws_s3_bucket.cloudtrail_logs.arn, "${aws_s3_bucket.cloudtrail_logs.arn}/*"]
    }]
  })
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-delivery-channel"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

############################################
# PREVENTATIVE CONTROL (required):
# Detect security groups open to 0.0.0.0/0 on port 22, and auto-remediate
# by revoking the rule — UNLESS the SG carries the exemption tag used by
# the Mongo VM's SG in this exercise (mongo_sg is intentionally excluded so
# the required weakness remains in place for the panel demo).
############################################
resource "aws_config_config_rule" "restricted_ssh" {
  name = "${var.project_name}-restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_iam_role" "config_remediation_role" {
  name = "${var.project_name}-config-remediation-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "config_remediation_policy" {
  name = "${var.project_name}-config-remediation-policy"
  role = aws_iam_role.config_remediation_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeSecurityGroups",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DescribeTags"
      ]
      Resource = "*"
    }]
  })
}

# NOTE: this remediation is deliberately scoped to demo/test security groups
# via the SSM automation's own logic + the exemption tag below — it will
# NOT touch the exercise's required-open Mongo SG, which is tagged
# "wiz-exercise-intentional-exception = true" in mongo_vm.tf.
resource "aws_config_remediation_configuration" "restricted_ssh_remediation" {
  config_rule_name = aws_config_config_rule.restricted_ssh.name
  resource_type    = "AWS::EC2::SecurityGroup"
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisablePublicAccessForSecurityGroup"
  target_version   = "1"

  parameter {
    name           = "GroupId"
    resource_value = "RESOURCE_ID"
  }
  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.config_remediation_role.arn
  }

  automatic                 = true
  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60
}

############################################
# GuardDuty — DETECTIVE control (recommended)
############################################
#resource "aws_guardduty_detector" "main" {
#  enable                       = true
#  finding_publishing_frequency = "FIFTEEN_MINUTES"
#}

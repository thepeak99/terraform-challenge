data "aws_region" "current" {}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  owners = ["amazon"]
}

resource "random_password" "admin_passwords" {
  count = var.vm_count

  length           = 16
  special          = true
  override_special = "_%@"
}

resource "aws_route53_zone" "private" {
  name = "example.internal"

  vpc {
    vpc_id = aws_vpc.example.id
  }
}

resource "aws_route53_record" "instance" {
  count = var.vm_count

  zone_id = aws_route53_zone.private.zone_id
  name    = "vm${count.index}.example.internal"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.vm[count.index].private_ip]
}

resource "aws_security_group" "allow_ping" {
  name        = "allow_ping"
  description = "Allow ICMP echo requests"

  vpc_id = aws_vpc.example.id

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ping"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "vm" {
  count = var.vm_count

  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.vm_flavor
  subnet_id     = aws_subnet.public[count.index % 3].id

  tags = {
    Name = "vm${count.index}"
  }

  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
  vpc_security_group_ids = [aws_security_group.allow_ping.id]

  user_data = <<-EOF
    #!/bin/bash
   
    echo "ec2-user:${random_password.admin_passwords[count.index].result}" | chpasswd

    sleep 120 

    next_vm=vm${(count.index + 1) % var.vm_count}
    my_vm=vm${count.index}

    if ping -c 1 $next_vm.example.internal &> /dev/null; then
      result="Pinging $next_vm from $my_vm: reachable"
    else
      result="Pinging $next_vm from $my_vm: unreachable"
    fi

    aws --region ${data.aws_region.current.name} sqs send-message --queue-url "${aws_sqs_queue.ping_queue.id}" --message-body "$result" --message-group-id ping

    EOF
}

resource "aws_iam_policy" "sqs_send" {
  name        = "example-sqs-send"
  description = "Allows instances to send messages to the FIFO queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.ping_queue.arn
      }
    ]
  })
}

resource "aws_iam_role" "instance_role" {
  name = "example-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sqs_send" {
  policy_arn = aws_iam_policy.sqs_send.arn
  role       = aws_iam_role.instance_role.name
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "example-instance-profile"
  role = aws_iam_role.instance_role.name
}

resource "aws_sqs_queue" "ping_queue" {
  name                        = "ping-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

data "external" "pings" {
  program = ["${path.module}/messages.sh"]

  query = {
    queue = aws_sqs_queue.ping_queue.id
    region = data.aws_region.current.name
  }

  count = var.vm_count

  depends_on=[aws_instance.vm[0]]
}

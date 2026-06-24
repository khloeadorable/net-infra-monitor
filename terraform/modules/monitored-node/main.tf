data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Allow HTTP health checks and restricted SSH for ${var.name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP health endpoint"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (restricted to a single known CIDR)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

# NOTE: heredoc is intentionally unindented (plain <<EOF, not <<-EOF).
# Terraform's `-` strip only removes leading TABS, not spaces, so an
# indented block here would corrupt the embedded Python script's
# whitespace-sensitive syntax. Keep this flush-left.
locals {
  health_server_user_data = <<EOF
#!/bin/bash
dnf install -y python3 || yum install -y python3
cat <<'PY' > /home/ec2-user/health_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok")

HTTPServer(("0.0.0.0", 80), Handler).serve_forever()
PY
nohup python3 /home/ec2-user/health_server.py > /var/log/health_server.log 2>&1 &
EOF
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  user_data              = local.health_server_user_data

  metadata_options {
    http_tokens = "required" # IMDSv2 only — IMDSv1 is a known SSRF-to-credential-theft vector
  }

  tags = merge(var.tags, { Name = var.name })
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# 기본 VPC 가 없는 계정에서도 뜨도록 전용 VPC 를 만든다. 두 서버는 같은 서브넷에 둔다.
resource "aws_vpc" "this" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true

  tags = { Name = "mocou-load-test" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "this" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "mocou-load-test" }
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}

# 접속은 SSM 으로만 한다. 인바운드는 k6 → 앱 8080 하나다.
resource "aws_security_group" "k6" {
  name   = "mocou-load-test-k6"
  vpc_id = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name   = "mocou-load-test-app"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.k6.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 측정 결과를 서버 밖으로 꺼내는 곳. destroy 때 내용과 함께 지운다.
resource "aws_s3_bucket" "results" {
  bucket_prefix = "mocou-load-test-results-"
  force_destroy = true
}

resource "aws_iam_role" "instance" {
  name_prefix = "mocou-load-test-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "results" {
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.results.arn}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "mocou-load-test-"
  role        = aws_iam_role.instance.name
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.this.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
  }

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    repo_url     = var.repo_url
    setup_script = "setup-app.sh"
    setup_args   = ""
  })

  tags = { Name = "mocou-load-test-app" }
}

resource "aws_instance" "k6" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.k6_instance_type
  subnet_id              = aws_subnet.this.id
  vpc_security_group_ids = [aws_security_group.k6.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
  }

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    repo_url     = var.repo_url
    setup_script = "setup-k6.sh"
    setup_args   = aws_instance.app.private_ip
  })

  tags = { Name = "mocou-load-test-k6" }
}

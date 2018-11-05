# Configure the AWS Provider
provider "aws" {
  region  = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

## Resource creation VPC SECTION ####
# This is where the VPC creations will happend #

resource "aws_vpc" "ee_deploy" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags {
    Name = "terraform-aws-vpc"
  }
}

# Define subnets [public]

resource "aws_subnet" "ee_public_subnet" {
  vpc_id                  = "${aws_vpc.ee_deploy.id}"
  cidr_block              = "${var.cidrs["public"]}"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "ee_public_subnet"
  }
}

# Define the private subnet
resource "aws_subnet" "ee_private_subnet" {
  vpc_id                  = "${aws_vpc.ee_deploy.id}"
  cidr_block              = "${var.cidrs["private"]}"
  map_public_ip_on_launch = false
  availability_zone       = "ap-south-1a"

  tags {
    Name = "Private Subnet"
  }
}

# Define the internet gateway
resource "aws_internet_gateway" "ee_gw" {
  vpc_id = "${aws_vpc.ee_deploy.id}"

  tags {
    Name = "VPC EE IGW"
  }
}

# Define a NAT Gateway
resource "aws_eip" "ee_nat" {
  vpc = true
}

resource "aws_nat_gateway" "ee-nat-gw" {
  allocation_id = "${aws_eip.ee_nat.id}"
  subnet_id     = "${aws_subnet.ee_public_subnet.id}"
  depends_on    = ["aws_internet_gateway.ee_gw"]
}

# Define the Public route table
resource "aws_route_table" "web-public-rt" {
  vpc_id = "${aws_vpc.ee_deploy.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.ee_gw.id}"
  }

  tags {
    Name = "Public Subnet RT"
  }
}

# Define the Private route table
resource "aws_route_table" "docker-private-rt" {
  vpc_id = "${aws_vpc.ee_deploy.id}"

  tags {
    Name = "Private route table"
  }
}

resource "aws_route" "private-route" {
  route_table_id         = "${aws_route_table.docker-private-rt.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.ee-nat-gw.id}"
}

# Assign the route table to the public Subnet
resource "aws_route_table_association" "web-public-rt" {
  subnet_id      = "${aws_subnet.ee_public_subnet.id}"
  route_table_id = "${aws_route_table.web-public-rt.id}"
}

# Assing the private route table to the private subnet
resource "aws_route_table_association" "docker-private-rt-association" {
  subnet_id      = "${aws_subnet.ee_private_subnet.id}"
  route_table_id = "${aws_route_table.docker-private-rt.id}"
}

#### END OF VPC CREATION ###

#### SECURITY GROUP CREATION #####A

resource "aws_security_group" "ee_public_sg" {
  name        = "ee_public_securitygroup"
  description = "SG for Public subnet"
  vpc_id      = "${aws_vpc.ee_deploy.id}"

  # ALLOW SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow ssh traffic from all IPs"
  }

  # ALLOW JEKINS traffic
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All Jenkins traffic"
  }

  #ALL HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #ALL HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ee_private_sg" {
  name        = "ee_private_securitygroup"
  description = "SG for Private Security Group"
  vpc_id      = "${aws_vpc.ee_deploy.id}"

  # ALLOW THE VPC SUBNET BLOCK
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = -1
    cidr_blocks     = ["${var.vpc_cidr}"]
    security_groups = ["${aws_security_group.ee_public_sg.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#### INSTANCE CREATIONS #####

resource "aws_instance" "ee_control_host" {
  instance_type               = "${var.control_instance_type}"
  ami                         = "${var.control_ami}"
  associate_public_ip_address = true
  user_data                   = "${file("userdata.sh")}"

  tags {
    Name = "Ansible Control Machin"
  }

  key_name               = "ee_deploy"
  vpc_security_group_ids = ["${aws_security_group.ee_public_sg.id}"]
  subnet_id              = "${aws_subnet.ee_public_subnet.id}"

  provisioner "remote-exec" {
    inline = ["sudo apt update"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${file("./ee_deploy.pem")}"
    }
  }

  provisioner "local-exec" {
    command = <<EOD
cat <<EOF >> aws_hosts
[controlhost]
${aws_instance.ee_control_host.public_ip}
EOF
EOD
  }

  provisioner "local-exec" {
    command = "aws ec2 wait instance-status-ok --instance-ids ${aws_instance.ee_control_host.id} --profile linbynd && ansible-playbook -i aws_hosts --private-key=ee_deploy.pem -u ubuntu site.yml"
  }
}

#### INSTANCE CREATIONS #####

resource "aws_instance" "ee_private_host" {
  instance_type = "${var.private_instance_type}"
  ami           = "${var.private_ami}"
  user_data                   = "${file("private_userdata.sh")}"

  tags {
    Name = "Docker Instance for Java"
  }

  key_name               = "ee_deploy"
  vpc_security_group_ids = ["${aws_security_group.ee_private_sg.id}"]
  subnet_id              = "${aws_subnet.ee_private_subnet.id}"

  provisioner "local-exec" {
    command = <<EOD
cat <<EOF >> aws_hosts
[private]
${aws_instance.ee_private_host.private_ip}
EOF
EOD
  }
}

module "elb_http" {
  source = "terraform-aws-modules/elb/aws"

  name = "petclinic-elb"

  subnets         = ["${aws_subnet.ee_private_subnet.id}"]
  security_groups = ["${aws_security_group.ee_public_sg.id}"]
  internal        = false

  listener = [
    {
      instance_port     = "8080"
      instance_protocol = "HTTP"
      lb_port           = "80"
      lb_protocol       = "HTTP"
    },
  ]

   health_check = [
    {
      target              = "HTTP:80/"
      interval            = 30
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 5
    },
  ]

  // ELB attachments
  number_of_instances = 1
  instances           = ["${aws_instance.ee_private_host.id}"]

  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}

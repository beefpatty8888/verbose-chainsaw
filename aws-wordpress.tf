variable "aws-key-pair" {
  type = string
  default = "jack-ubuntu"
}

provider "aws" {
  profile = "default"
  region  = "us-east-2"
}

## VPC and Subnet Creation ##

## NOTE: AWS generally defines a public subnet as having an Internet Gateway. 
## A private subnet has a NAT Gateway (in a public subnet) or no gateway at all.
## See https://serverfault.com/questions/854475/aws-nat-gateway-in-public-subnet-why

## VPC and subnet address range are using the recommended values in
## https://aws.amazon.com/blogs/containers/optimize-ip-addresses-usage-by-pods-in-your-amazon-eks-cluster/

resource "aws_vpc" "wordpress_vpc" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = "wordpress_vpc"
  }
}

resource "aws_subnet" "wordpress_subnet_priv_a" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = "10.0.48.0/20"
  availability_zone = "us-east-2a"

  tags = {
    Name = "wordpress_subnet_priv_a"
  }
}

resource "aws_subnet" "wordpress_subnet_priv_b" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = "10.0.64.0/20"
  availability_zone = "us-east-2b"

  tags = {
    Name = "wordpress_subnet_priv_b"
  }
}

## NOTE: Public subnets MUST be associated to the application load balancers
## Instances themselves can be on the private subnets.
## SEE: https://stackoverflow.com/questions/54871524/elastic-load-balancer-pointing-at-private-subnet
resource "aws_subnet" "wordpress_subnet_public_a" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = "10.0.0.0/20"
  availability_zone = "us-east-2a"

  tags = {
    Name = "wordpress_subnet_public_a"
  }
}

resource "aws_subnet" "wordpress_subnet_public_b" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = "10.0.16.0/20"
  availability_zone = "us-east-2b"

  tags = {
    Name = "wordpress_subnet_public_b"
  }
}


# This is compatible with ipv6 only
# https://docs.aws.amazon.com/vpc/latest/userguide/egress-only-internet-gateway.html
#resource "aws_egress_only_internet_gateway" "wordpress_egress" {
#  vpc_id = aws_vpc.eks_vpc.id
#
#  tags = {
#    Name = "wordpress_egress"
#  }
#}

resource "aws_internet_gateway" "wordpress_gw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-gw"
  }
}


## Security Groups Creation ##
resource "aws_security_group" "allow_tls_http_lb" {
  name        = "allow-tls-http-lb"
  description = "Allow TLS, HTTP inbound traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "TLS from Anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from Anywhere"
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

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "allow_tls_http_ssh_vpc" {
  name        = "allow-tls-http-ssh"
  description = "Allow TLS, HTTP, SSH inbound traffic from VPC"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "TLS from Application Load Balancer"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    # this specifies resources using the "allow_tls_http_lb" security group to be an allowed source (?)
    security_groups = [aws_security_group.allow_tls_http_lb.id]
  }

  ingress {
    description = "HTTP from Application Load Balancer"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    # this specifies resources using the "allow_tls_http_lb" security group to be an allowed source (?)
    security_groups = [aws_security_group.allow_tls_http_lb.id]
  }

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # this specifies resources using the "allow_tls_http_lb" security group to be an allowed source (?)
    cidr_blocks = [aws_vpc.wordpress_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls_http_ssh_vpc"
  }
}

# For the bastion host
resource "aws_security_group" "allow_ssh_anywhere" {
  name        = "allow-ssh-anywhere"
  description = "Allow SSH inbound traffic from Anywhere"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "SSH from Anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh_anywhere"
  }

}

## Create Route To the Gateway in the VPC Route Table ##
resource "aws_route" "eks_route" {
  route_table_id = aws_vpc.eks_vpc.default_route_table_id
    destination_cidr_block    = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_gw.id
  
}

## Create the Elastic IPs ##
resource "aws_eip" "wordpress_subnet_priv_a_eip" {
  vpc              = true
  public_ipv4_pool = "amazon"
}

resource "aws_eip" "wordpress_subnet_priv_b_eip" {
  vpc              = true
  public_ipv4_pool = "amazon"
}

## Create the NAT Gateways ##

## NOTE: NAT gateways MUST be on the public subnets 
## See: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html#nat-gateway-troubleshooting-no-internet-connection
resource "aws_nat_gateway" "wordpress_subnet_priv_a_gw" {
  allocation_id = aws_eip.eks_subnet_priv_a_eip.id
  subnet_id     = aws_subnet.wordpress_subnet_public_a.id

  tags = {
    Name = "wordpress_subnet_public_a_gw NAT"
    Notes = "NAT gateways MUST be on the public subnets. See: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html#nat-gateway-troubleshooting-no-internet-connection"
  }
}

resource "aws_nat_gateway" "wordpress_subnet_priv_b_gw" {
  allocation_id = aws_eip.wordpress_subnet_priv_b_eip.id
  subnet_id     = aws_subnet.wordpress_subnet_public_b.id

  tags = {
    Name = "wordpress_subnet_public_b_gw NAT"
    Notes = "NAT gateways MUST be on the public subnets. See: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html#nat-gateway-troubleshooting-no-internet-connection"
  }
}

## Create Routes to the NAT Gateways ##
resource "aws_route_table" "wordpress_subnet_priv_a_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress_subnet_priv_a_rt"
  }
}

resource "aws_route_table" "wordpress_subnet_priv_b_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress_subnet_priv_b_rt"
  }
  
}


resource "aws_route" "wordpress_subnet_priv_a_route" {
  route_table_id = aws_route_table.wordpress_subnet_priv_a_rt.id
  destination_cidr_block    = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.wordpress_subnet_priv_a_gw.id
}

resource "aws_route" "wordpress_subnet_priv_b_route" {
  route_table_id = aws_route_table.wordpress_subnet_priv_b_rt.id
  destination_cidr_block    = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.wordpress_subnet_priv_b_gw.id
}

# NOTE: If the route tables are not explicitly associated with a subnet
# the VPC main route table is used.
resource "aws_route_table_association" "wordpress_subnet_priv_a_route_table_association" {
  subnet_id     = aws_subnet.wordpress_subnet_priv_a.id
  route_table_id = aws_route_table.wordpress_subnet_priv_a_rt.id
}

resource "aws_route_table_association" "wordpress_subnet_priv_b_route_table_association" {
  subnet_id     = aws_subnet.wordpress_subnet_priv_b.id
  route_table_id = aws_route_table.wordpress_subnet_priv_b_rt.id
}


## Bastion Host Creation ##

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_configuration#using-with-autoscaling-groups
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# https://harshitdawar.medium.com/launching-a-vpc-with-public-private-subnet-nat-gateway-in-aws-using-terraform-99950c671ce9
resource "aws_instance" "bastion_host" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.aws-key-pair
  associate_public_ip_address = true
  subnet_id   = aws_subnet.wordpress_subnet_public_b.id
  vpc_security_group_ids = [aws_security_group.allow_ssh_anywhere.id]

  tags = {
    Name = "Bastion Host"
  }
}

## Wordpress EC2 Instance Creation ##

resource "aws_instance" "wordpress_host_a" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.aws-key-pair
  associate_public_ip_address = true
  subnet_id   = aws_subnet.wordpress_subnet_priv_a.id
  vpc_security_group_ids = [aws_security_group.allow_tls_http_ssh_vpc.id]

  tags = {
    Name = "Wordpress Host A"
  }
}

esource "aws_instance" "wordpress_host_b" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.aws-key-pair
  associate_public_ip_address = true
  subnet_id   = aws_subnet.wordpress_subnet_priv_b.id
  vpc_security_group_ids = [aws_security_group.allow_tls_http_ssh_vpc.id]

  tags = {
    Name = "Wordpress Host B"
  }
}



## Wordpress EFS Instance Creation ##


## Wordpress RDS Instance Creation ##

# ─────────────────────────────────────────────────────────────
#  VPC
# ─────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for private DNS names and VPC endpoints

  tags = { Name = "${var.project}-vpc" }
}

# ─────────────────────────────────────────────────────────────
#  Subnets - one public and one private per AZ.
#  cidrsubnet() derives each block from the VPC CIDR, so changing
#  vpc_cidr re-derives everything instead of needing 4 edits.
#    cidrsubnet("10.20.0.0/16", 8, 1)  => 10.20.1.0/24
#    cidrsubnet("10.20.0.0/16", 8, 11) => 10.20.11.0/24
# ─────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  for_each = toset(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, index(var.availability_zones, each.key) + 1)
  availability_zone       = "${var.aws_region}${each.key}"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "private" {
  for_each = toset(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(var.availability_zones, each.key) + 11)
  availability_zone = "${var.aws_region}${each.key}"

  tags = { Name = "${var.project}-private-${each.key}", Tier = "private" }
}

# ─────────────────────────────────────────────────────────────
#  Internet Gateway + routing.
#  A subnet is "public" ONLY because its route table sends
#  0.0.0.0/0 to an IGW - there is no public flag.
# ─────────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private route table with NO 0.0.0.0/0 route: these subnets have no path to
# the internet at all. Production would add a NAT Gateway here for outbound
# access - omitted deliberately because NAT is billed hourly plus per-GB and is
# the line item that most often surprises people.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

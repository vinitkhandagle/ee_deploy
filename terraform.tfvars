aws_profile = "linbynd"
aws_region = "ap-south-1"
vpc_cidr = "172.20.0.0/16"
cidrs   = {
    public = "172.20.0.0/24"
    private = "172.20.1.0/24"
}

control_instance_type = "t2.medium"
control_ami = "ami-0c6c52d7cf1004825"
private_instance_type = "t2.medium"
private_ami = "ami-0c6c52d7cf1004825"


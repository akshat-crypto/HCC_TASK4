provider aws {
    region = "ap-south-1"
    profile = "derek"
}

#CREATING THE VPC 
resource "aws_vpc" "t4vpc" {
    cidr_block = "192.168.0.0/16"
    enable_dns_hostnames = "true"
    tags = {
        Name = "t4vpc"
    }
}

#CREATING TWO DIFFERENT LABS OR SUBNET IN THE VPC

#THIS ONE IS FOR THE PUBLIC SUBNET
resource "aws_subnet" "t4sub1" {
    vpc_id = "${aws_vpc.t4vpc.id}"
    cidr_block = "192.168.3.0/24"
    availability_zone = "ap-south-1b"
    map_public_ip_on_launch  = "true"
    tags = {
        Name = "t4sub1"
    }
}

#THIS ONE IS FOR THE PRIVATE SUBNET
resource "aws_subnet" "t4sub2" {
    vpc_id = "${aws_vpc.t4vpc.id}"
    cidr_block = "192.168.4.0/24"
    availability_zone = "ap-south-1a"
    tags = {
        Name = "t4sub2"
    }
}

#THIS IS FOR CREATING THE INTERNET GATEWAY
resource "aws_internet_gateway" "t4igw1" {
    vpc_id = "${aws_vpc.t4vpc.id}"
    tags = {
        Name = "t4igw1"
    }
}

#THIS IS FOR CREATING THE ROUTING TABLE
resource "aws_route_table" "t4rt1" {
    vpc_id = "${aws_vpc.t4vpc.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.t4igw1.id}"  
    }
}

#ATTACHING ROUTE TABLE TO THE SUBNET CREATED
resource "aws_route_table_association" "attachrt" {
    subnet_id = "${aws_subnet.t4sub1.id}"
    route_table_id = "${aws_route_table.t4rt1.id}"
}

#CREATING THE ELASTIC IP FOR THE NAT GATEWAY

resource "aws_eip" "eipngw" {
  depends_on = [ aws_instance.wpinst , aws_instance.mysqlinst , aws_instance.bhinst ]
   vpc      = true
}

#CREATE THE NAT GATEWAY 
resource "aws_nat_gateway" "t4ngw1" {
    depends_on = [ aws_eip.eipngw ]
    allocation_id = aws_eip.eipngw.id
    subnet_id     = aws_subnet.t4sub1.id
    tags = {
       Name = "t4ngw1"
    }
}

#CREATING THE ROUTE TABLE FOR THE NAT GATEWAY

resource "aws_route_table" "t4rt2" {
    depends_on = [ aws_nat_gateway.t4ngw1 ]
    vpc_id = "${aws_vpc.t4vpc.id}"
    
    route {
        cidr_block = "0.0.0.0/0" 
        gateway_id = "${aws_nat_gateway.t4ngw1.id}"
    }
}

#ATTACHING THE ROUTE TABLE
resource "aws_route_table_association" "attachrt2" {
  depends_on = [ aws_route_table.t4rt2 ]
  subnet_id      = "${aws_subnet.t4sub2.id}"
  route_table_id = "${aws_route_table.t4rt2.id}"
}

#CREATING SECURITY GROUPS FOR SUBNET 1 AND 2
#SECURITY GROUP FOR WORDPRESS INSTANCES
resource "aws_security_group" "sg1"{
    name = "allow_tcp_wp"
    description = "Allow tcp and ssh to the instances launched"
    vpc_id = "${aws_vpc.t4vpc.id}"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }

   egress {
   from_port   = 0
   to_port     = 0
   protocol    = "-1"
   cidr_blocks = ["0.0.0.0/0"]
   }

   tags = {
       Name = "sg1"
   }
}

#SECURITY GROUP FOR MYSQL INSTANCES
resource "aws_security_group" "sg2" {
    name = "allow_tcp_mysql"
    description = "allow only the traffic from the wordpress instances to connect"
    vpc_id = "${aws_vpc.t4vpc.id}"
    
    ingress {
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        //cidr_blocks = ["0.0.0.0/0"]
        security_groups = ["${aws_security_group.sg1.id}"]
    }
    
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        //cidr_blocks = ["0.0.0.0/0"]
        security_groups = ["${aws_security_group.sg3.id}"]
    }

    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }
    
    tags = {
        Name = "sg2"
    }
}

#SECURITY GROUP FOR BASTION HOST
resource "aws_security_group" "sg3" {
  description = "allow the instance to connect through mysql and provides intrnet for update"
  name        = "allow_ssh_bh"
  vpc_id      = aws_vpc.t4vpc.id


ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0"]
  }
egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
    Name = "sg3"
  }
}


#TAKING INPUT FOR THE KEY VARIABLE
variable "insert_key_var" {
     type = string
}

#LAUNCHING THE INSTANCES USING THESE SECURITY GROUPS
#LAUNCHING WORDPRESS INSTANCE IN SUBNET1
resource "aws_instance" "wpinst" {
    depends_on = [
        aws_instance.bhinst
    ]
    ami = "ami-00bfa9443b339fa43"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.t4sub1.id}"
    vpc_security_group_ids = ["${aws_security_group.sg1.id}"]
    key_name = "${var.insert_key_var}"
    tags = {
        Name = "wprhel8"
    }
}


#CHANGING THE WORDPRESS CONFIGURATION FIE
resource "null_resource" "connecting_ip_wp" {
      depends_on = [
             aws_instance.wpinst
      ]
	  connection  {
          type = "ssh"
          user = "ec2-user"
          private_key = file("C:/Users/Akshat/Desktop/${var.insert_key_var}.pem")
          host = aws_instance.wpinst.public_ip
      }
      
      provisioner  "remote-exec" {
          inline = [
              "sudo sed -i 's+serverip+${aws_instance.mysqlinst.private_ip}+g' /var/www/html/wordpress/wp-config-sample.php",
              "sudo systemctl restart httpd"
        ]
      }
}


#LAUNCHING MYSQL INSTANCE IN SUBNET2
resource "aws_instance" "mysqlinst" {
    depends_on = [
        aws_security_group.sg2
    ]
    ami = "ami-0325719afa9dd7b73"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.t4sub2.id}"
    vpc_security_group_ids = ["${aws_security_group.sg2.id}"]
    key_name = "${var.insert_key_var}"
    tags = {
        Name = "mysqlrhel8"
    }
}

/*
*/
#LAUNCHING BASTION HOST INSTANCE IN SUBNET1
resource "aws_instance" "bhinst" {
    depends_on = [
        aws_instance.mysqlinst
    ]
    ami = "ami-033c3795a9fea5dd8"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.t4sub1.id}"
    vpc_security_group_ids = ["${aws_security_group.sg3.id}"]
    key_name = "${var.insert_key_var}"
    tags = {
        Name = "bhrhel8"
    }
}

resource "null_resource" "connecting_ip_bastionhost" {
      depends_on = [
             aws_instance.bhinst
      ]
	  connection  {
          type = "ssh"
          user = "ec2-user"
          private_key = file("C:/Users/Akshat/Desktop/${var.insert_key_var}.pem")
          host = aws_instance.bhinst.public_ip
      }
      
      provisioner  "remote-exec" {
          inline = [
              "sudo sed -i 's+127.0.0.1+${aws_instance.mysqlinst.private_ip}+g' /etc/my.cnf",
              "sudo sed -i 's+appserverip+${aws_instance.wpinst.private_ip}+g' /commands/commands.txt",
              "sudo mysql -uroot  < /commands/commands.txt",
              "sudo systemctl restart mysqld.service"
        ]
      }
}


/*
"sudo su - root",
"cd /",
"ssh -l ec2-user -i ukey1.pem ${aws_instance.mysqlinst.public_ip}",
"sudo su - root",
#RUNNING CHROME FROM THE BASE WINDOWS
resource "null_resource" "runchrome" {
    depends_on = [
        aws_instance.bhinst
    ]
    provisioner "local-exec" {
        command = "start chrome ${aws_instance.wpinst.public_dns}"
    }
}
*/
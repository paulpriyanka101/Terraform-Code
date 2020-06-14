provider "aws" {
  region = "ap-south-1"
  profile = "admin"
}

# Create key-pair for EC2:

resource "tls_private_key" "webserver_key" {
	algorithm = "RSA"
	rsa_bits = 4096
}
resource "local_file" "private_key" {
	content = tls_private_key.webserver_key.private_key_pem
	filename = "webserver.pem"
	file_permission = 0400
}
resource "aws_key_pair" "webserver_key" {
	key_name = "webserver"
	public_key = tls_private_key.webserver_key.public_key_openssh
}

# Create SG for ec2 and allow port 22 and 80:

resource "aws_security_group" "websg" {
	name = "websg"
	description = "my webserver sg"
ingress {
	description = "ssh"
	cidr_blocks = ["0.0.0.0/0"]
	from_port = 22
	to_port = 22
	protocol = "tcp"
  }
ingress {
	description = "http"
	cidr_blocks = ["0.0.0.0/0"]
	from_port = 80
	to_port = 80
	protocol = "tcp"
  }
ingress {
	description = "ping-icmp"
	from_port = -1
	to_port = -1
	protocol = "icmp"
	cidr_blocks = ["0.0.0.0/0"]
  }
egress {
	from_port = 0
	to_port = 0
	protocol = "-1"
	cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch EC2 instance:

resource "aws_instance" "web" {
	ami = "ami-0447a12f28fddb066"
	instance_type = "t2.micro" 
	key_name = aws_key_pair.webserver_key.key_name
	security_groups = ["websg"]

	connection {
		type = "ssh"
		user = "ec2-user"
		private_key = tls_private_key.webserver_key.private_key_pem
		host = aws_instance.web.public_ip
	}

	provisioner "remote-exec" {
		inline = [
    	"sudo yum install httpd php git -y",
    	"sudo systemctl start httpd",
    	"sudo systemctl enable httpd"
		]
	}

	tags = {
		name = "Webserver-1"
	}
}

# Launch EBS volume and attach it to EC2:

resource "aws_ebs_volume" "datavol" {
	availability_zone = aws_instance.web.availability_zone
	size = 1
	tags = {
		name = "web-data" 
	}
}

resource "aws_volume_attachment" "datavol_attach" {
	device_name = "/dev/sdc"
	volume_id = "${aws_ebs_volume.datavol.id}"
	instance_id = "${aws_instance.web.id}"
	force_detach = true
}

output "weserver_ip" {
	value = aws_instance.web.public_ip
}

resource "null_resource" "nullremote1" {
	depends_on = [
	aws_volume_attachment.datavol_attach
	]

connection {
	type = "ssh"
	user = "ec2-user"
	private_key = tls_private_key.webserver_key.private_key_pem
	host = aws_instance.web.public_ip
} 

provisioner "remote-exec" {
	inline = [
		"sudo mkfs.ext4 /dev/xvdc",
		"sudo mount /dev/xvdc /var/www/html",
		"sudo rm -rf /var/www/html*",
		"sudo git clone https://github.com/paulpriyanka101/Terraform-Code.git /var/www/html/"
	]
  }
}

resource "aws_ebs_snapshot" "webdata_snapshot" {
  volume_id = "${aws_ebs_volume.datavol.id}"

  tags = {
    Name = "WebServer_snap"
  }
}

resource "null_resource" "nullremote2" {
        depends_on = [
        null_resource.nullremote1,
        ]
}

resource "null_resource" "nulllocal1" {
	depends_on = [
	null_resource.nullremote1,
	]
provisioner "local-exec" {
	command = "open  http://${aws_instance.web.public_ip}"
  }
}

# Create S3 bucket and store image from gihub:

resource "aws_s3_bucket" "image-bucket" {
	bucket = "webserver-1-image-bucket"
	acl = "public-read"

provisioner "local-exec" {
	command = "git clone https://github.com/paulpriyanka101/Terraform-Code.git /Users/priyanka/Desktop/tera-code/auto-infra/webserver-iamge"
  }

provisioner "local-exec" {
        when        =   destroy
        command     =   "echo Y | rmdir /s /Users/priyanka/Desktop/tera-code/auto-infra/webserver-image"
    }
}

resource "aws_s3_bucket_object" "image_upload" {
	bucket = aws_s3_bucket.image-bucket.bucket
	key = "Multi-cloud.jpg"
	source = "/Users/priyanka/Desktop/tera-code/auto-infra/webserver-image/Multi-cloud.jpg"
	acl = "public-read"
}

# Crate Cloud Front and use the URL to open the complete WebSite:

variable "var1" {default = "S3-"}
locals {
    s3_origin_id = "${var.var1}${aws_s3_bucket.image-bucket.bucket}"
    image_url = "${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image-upload.key}"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
    }
enabled             = true
origin {
        domain_name = aws_s3_bucket.image-bucket.bucket_domain_name
        origin_id   = local.s3_origin_id
    }
restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }
viewer_certificate {
        cloudfront_default_certificate = true
    }

connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.web.public_ip
        port    = 22
        private_key = tls_private_key.webserver_key.private_key_pem
    }

provisioner "remote-exec" {
        inline  = [
            # "sudo su << \"EOF\" \n echo \"<img src='${self.domain_name}'>\" >> /var/www/html/test.html \n \"EOF\""
            "sudo su << EOF",
            "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.image_upload.key}'>\" >> /var/www/html/test.html",
            "EOF"
        ]
    }
}

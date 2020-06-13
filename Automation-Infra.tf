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

resource "null_resource" "nulllocal1" {
	depends_on = [
	null_resource.nullremote1,
	]
provisioner "local-exec" {
	command = "open  http://52.66.249.194/php-code.php"
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

# Create Cloudfront distribution
resource "aws_cloudfront_distribution" "cf_dist" {
    origin {
        domain_name = "static-image-bucket.s3.amazonaws.com"
        origin_id = "S3-static-image-bucket"
 
        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
    }
    
    enabled = true
    

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-static-image-bucket"

        # Forward all query strings, cookies and headers
        forwarded_values {
            query_string = false

            cookies {
                forward = "none"
            }    
        }

        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }

    # Restricts who is able to access this content
    restrictions {
        geo_restriction {
            # type of restriction, blacklist, whitelist or none
            restriction_type = "none"
        }
    }

    # SSL certificate for the service.
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}

provider "aws" {
		region  = "ap-south-1"
		profile = "admin"
}

resource "aws_key_pair" "key-name" {
  key_name   = "hola"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCtq/HITmyH+I+CpXO8raRgN9T3U1u2rKKEKAjSIe5C3pdYyAuhzzseYG4T8Jh63g1GWPdRgc7Z/gcyzaWWG/IutiW9KaXll4NuVoSZH+nkzN7ZE2tFaVYorknzHsa7KHeKtwgDmLIxicF3p8dlzoiXY5PFqVqxUuYMFRjX++zpxb8nJJfpIma1BCSYQBXEFtlqFKLXwYdQmMX9uJyjFHqBs3ZbgWeymyAi1MKvvKrZf9J43CrNOWZ+64W3LrO3dJPcjNH6LxogO5bzFkk6K1bssqVjfA7oZ0fhfdSeLfhOObt/YVd+z7TzsCJMIZ22dBbhrAwJOBb/7YfY7wJ8y6G2tg7GGxe4cTe9EjDkGq0XicQVBWG0jjUAiHiQEfvgXWzmPUTWkkbs6yiUwhYZ3AcAHJRNMt0x7A9oS+Cgj2qSR4uv8sA+kMTSYFdWD8TTu4r0YZFhVxHRf8hdFe8u8eUKtTxTqo/OWODYI/HSwik+J3CI1R9N9bxyhEt+OE1ZgbM= key-name"
}

resource "aws_security_group" "websg" {
  name         = "websg"
  description  = "My Security Group"
  
  # allow ingress of port 22
  ingress {
    cidr_blocks = ["0.0.0.0/0"]  
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  } 
  
  # allow ingress of port 80
  ingress {
    cidr_blocks = ["0.0.0.0/0"]  
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }
}

resource "aws_instance" "myweb" {
	ami = "ami-052c08d70def0ac62"
	availability_zone = "ap-south-1a"
	instance_type = "t2.micro"
	key_name = "hola"
	security_groups = [ "websg" ]

	tags = {
		name = "webserver-1"
	}
}

#creating and attaching ebs volume

resource "aws_ebs_volume" "data-vol" {
 availability_zone = "ap-south-1a"
 size = 1
 tags = {
        Name = "data-volume"
 }

}

resource "aws_volume_attachment" "vol_att" {
 device_name = "/dev/sdc"
 volume_id = "${aws_ebs_volume.data-vol.id}"
 instance_id = "${aws_instance.myweb.id}"
}

resource "aws_ebs_snapshot" "webdata_snapshot" {
  volume_id = "${aws_ebs_volume.data-vol.id}"

  tags = {
    Name = "WebServer_snap"
  }
}

resource "aws_s3_bucket" "b" {
  bucket = "static-image-bucket"
  acl    = "public-read"
  
  tags   = {
    names = "static-image-bucket"
  }	 
}

resource "aws_s3_bucket_object" "upload-file" {
bucket = "static-image-bucket"
key = "cloudimage"
source = "/Users/priyanka/Desktop/Multi-cloud.jpg"
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